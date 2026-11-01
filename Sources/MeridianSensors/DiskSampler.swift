import Foundation
import IOKit
import MeridianKit

/// Mounted volumes with capacity from getmntinfo and throughput from IOBlockStorageDriver counters.
///
/// APFS volumes share one container, so throughput cannot be attributed per volume. The boot disk gets the
/// summed internal-drive rate; an external volume gets the rate of the physical drive it sits on, matched by BSD name.
///
/// Cost control: the registry walk, the drive classification and the capacity queries are the expensive parts and
/// change rarely, so they are cached. Each tick only calls getmntinfo (to notice mounts) and reads one registry
/// property per cached drive.
final class DiskSampler {
    private struct Counters { var read: UInt64; var write: UInt64 }
    private struct Drive { var entry: io_registry_entry_t; var key: String }
    private struct Volume {
        var device: String, mountPoint: String, name: String, total: UInt64, isInternal: Bool, isBoot: Bool
        var free: UInt64 = 0
    }

    private var previous: [String: Counters] = [:]
    private var previousTime: TimeInterval?
    private var drives: [Drive] = []
    private var drivesLoadedAt: TimeInterval = -.infinity
    private var volumes: [Volume] = []
    private var mountSignature = ""
    private var freeLoadedAt: TimeInterval = -.infinity

    private static let realFilesystems: Set<String> = ["apfs", "hfs", "exfat", "msdos", "ntfs", "ufs", "udf"]
    private static let driveRefresh: TimeInterval = 30
    private static let freeRefresh: TimeInterval = 10

    deinit { drives.forEach { IOObjectRelease($0.entry) } }

    func sample() -> [DiskMetrics] {
        let now = ProcessInfo.processInfo.systemUptime

        let mounts = Self.mountedVolumes()
        let signature = mounts.map { $0.device + "@" + $0.mountPoint }.joined(separator: "|")
        if signature != mountSignature {
            mountSignature = signature
            volumes = mounts.compactMap(Self.describe)
            freeLoadedAt = -.infinity
            drivesLoadedAt = -.infinity // a new volume may be a new drive
        }
        if now - freeLoadedAt >= Self.freeRefresh {
            freeLoadedAt = now
            for i in volumes.indices { volumes[i].free = Self.freeBytes(volumes[i].mountPoint) ?? volumes[i].free }
        }
        if now - drivesLoadedAt >= Self.driveRefresh { reloadDrives(); drivesLoadedAt = now }

        let counters = readCounters()
        var rates: [String: (read: Double, write: Double)] = [:]
        if let previousTime, now > previousTime {
            let dt = now - previousTime
            for (key, c) in counters {
                guard let old = previous[key], c.read >= old.read, c.write >= old.write else { continue }
                rates[key] = (Double(c.read - old.read) / dt, Double(c.write - old.write) / dt)
            }
        }
        previous = counters
        previousTime = now

        let disks = volumes.map { v -> DiskMetrics in
            let key = v.isBoot || v.isInternal ? "internal" : Self.wholeDiskName(v.device)
            let rate = (v.isBoot || !v.isInternal) ? rates[key] : nil
            return DiskMetrics(id: v.device, name: v.name, mountPoint: v.mountPoint, totalBytes: v.total, freeBytes: min(v.free, v.total),
                               readBytesPerSec: rate?.read ?? 0, writeBytesPerSec: rate?.write ?? 0,
                               isInternal: v.isInternal, isBoot: v.isBoot)
        }
        // Boot disk first so UI that takes `disks.first` shows the right one.
        return disks.sorted { ($0.isBoot ? 0 : 1, $0.mountPoint) < ($1.isBoot ? 0 : 1, $1.mountPoint) }
    }

    // MARK: Volumes

    private struct Mount { var device: String; var mountPoint: String }

    private static func mountedVolumes() -> [Mount] {
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        guard count > 0, let list else { return [] }
        var result: [Mount] = []
        for i in 0..<Int(count) {
            var fs = list[i]
            let type = withUnsafePointer(to: &fs.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) } }
            let mount = withUnsafePointer(to: &fs.f_mntonname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            let device = withUnsafePointer(to: &fs.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            guard realFilesystems.contains(type) else { continue }
            let hidden = fs.f_flags & UInt32(MNT_DONTBROWSE) != 0
            // "/" is the sealed system snapshot and is flagged hidden on some releases; it is still the boot disk.
            if hidden && mount != "/" { continue }
            result.append(Mount(device: device, mountPoint: mount))
        }
        return result
    }

    private static func describe(_ mount: Mount) -> Volume? {
        let url = URL(fileURLWithPath: mount.mountPoint)
        let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeIsInternalKey])
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
        guard total > 0 else { return nil }
        let isBoot = mount.mountPoint == "/"
        return Volume(device: mount.device, mountPoint: mount.mountPoint,
                      name: values?.volumeName ?? (mount.mountPoint as NSString).lastPathComponent,
                      total: total, isInternal: values?.volumeIsInternal ?? isBoot, isBoot: isBoot)
    }

    private static func freeBytes(_ mountPoint: String) -> UInt64? {
        let values = try? URL(fileURLWithPath: mountPoint).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        // "Important usage" matches Finder, which counts purgeable space as free.
        if let important = values?.volumeAvailableCapacityForImportantUsage { return UInt64(max(0, important)) }
        return values?.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
    }

    /// "/dev/disk4s2" -> "disk4"
    static func wholeDiskName(_ device: String) -> String {
        let name = device.replacingOccurrences(of: "/dev/", with: "")
        guard name.hasPrefix("disk") else { return name }
        let digits = name.dropFirst(4).prefix(while: \.isNumber)
        return "disk" + digits
    }

    // MARK: Drives

    /// Enumerates storage drivers and classifies each once. Internal drives share the key "internal"; each external
    /// drive is keyed by its BSD name. Entries stay retained so a tick can read one property without walking the registry.
    private func reloadDrives() {
        drives.forEach { IOObjectRelease($0.entry) }
        drives = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            let location = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "Physical Interconnect Location" as CFString, kCFAllocatorDefault,
                                                           IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
            if location == "External" {
                var bsd: String?
                IORegistry.forEachDescendant(of: entry) { _, media in
                    if bsd == nil, media["Whole"] as? Bool == true, let name = media["BSD Name"] as? String { bsd = name }
                }
                if let bsd { drives.append(Drive(entry: entry, key: bsd)); continue }
                IOObjectRelease(entry)
            } else {
                drives.append(Drive(entry: entry, key: "internal"))
            }
        }
    }

    /// Cumulative byte counters, internal drives summed.
    private func readCounters() -> [String: Counters] {
        var result: [String: Counters] = [:]
        for drive in drives {
            guard let stats = IORegistryEntryCreateCFProperty(drive.entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let read = stats.uint64("Bytes (Read)"), let write = stats.uint64("Bytes (Write)") else { continue }
            let old = result[drive.key] ?? Counters(read: 0, write: 0)
            result[drive.key] = Counters(read: old.read + read, write: old.write + write)
        }
        return result
    }
}
