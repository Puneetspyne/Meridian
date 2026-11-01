import Foundation
import IOKit
import MeridianKit

/// Mounted volumes with capacity from getmntinfo and throughput from IOBlockStorageDriver counters.
///
/// APFS volumes share one container, so throughput cannot be attributed per volume. The boot disk gets the
/// summed internal-drive rate; an external volume gets the rate of the physical drive it sits on, matched by BSD name.
final class DiskSampler {
    private struct Counters { var read: UInt64; var write: UInt64 }
    private var previous: [String: Counters] = [:]
    private var previousTime: TimeInterval?

    private static let realFilesystems: Set<String> = ["apfs", "hfs", "exfat", "msdos", "ntfs", "ufs", "udf"]

    func sample() -> [DiskMetrics] {
        let now = ProcessInfo.processInfo.systemUptime
        let drives = Self.readDrives()
        var rates: [String: (read: Double, write: Double)] = [:]
        if let previousTime, now > previousTime {
            let dt = now - previousTime
            for (key, counters) in drives {
                guard let old = previous[key], counters.read >= old.read, counters.write >= old.write else { continue }
                rates[key] = (Double(counters.read - old.read) / dt, Double(counters.write - old.write) / dt)
            }
        }
        previous = drives
        previousTime = now

        var disks: [DiskMetrics] = []
        for volume in Self.mountedVolumes() {
            let url = URL(fileURLWithPath: volume.mountPoint)
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                             .volumeAvailableCapacityKey, .volumeIsInternalKey]
            let values = try? url.resourceValues(forKeys: keys)
            let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
            guard total > 0 else { continue }
            let free: UInt64
            if let important = values?.volumeAvailableCapacityForImportantUsage {
                free = UInt64(max(0, important)) // Matches Finder, which counts purgeable space as free.
            } else {
                free = UInt64(max(0, values?.volumeAvailableCapacity ?? 0))
            }
            let isBoot = volume.mountPoint == "/"
            let isInternal = values?.volumeIsInternal ?? isBoot
            let key = isBoot || isInternal ? "internal" : Self.wholeDiskName(volume.device)
            let rate = (isBoot || (!isInternal)) ? rates[key] : nil
            disks.append(DiskMetrics(
                id: volume.device, name: values?.volumeName ?? (volume.mountPoint as NSString).lastPathComponent,
                mountPoint: volume.mountPoint, totalBytes: total, freeBytes: min(free, total),
                readBytesPerSec: rate?.read ?? 0, writeBytesPerSec: rate?.write ?? 0,
                isInternal: isInternal, isBoot: isBoot))
        }
        // Boot disk first so UI that takes `disks.first` shows the right one.
        return disks.sorted { ($0.isBoot ? 0 : 1, $0.mountPoint) < ($1.isBoot ? 0 : 1, $1.mountPoint) }
    }

    private struct Volume { var device: String; var mountPoint: String }

    private static func mountedVolumes() -> [Volume] {
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        guard count > 0, let list else { return [] }
        var result: [Volume] = []
        for i in 0..<Int(count) {
            var fs = list[i]
            let type = withUnsafePointer(to: &fs.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) } }
            let mount = withUnsafePointer(to: &fs.f_mntonname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            let device = withUnsafePointer(to: &fs.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            guard realFilesystems.contains(type) else { continue }
            let hidden = fs.f_flags & UInt32(MNT_DONTBROWSE) != 0
            // "/" is the sealed system snapshot and is flagged hidden on some releases; it is still the boot disk.
            if hidden && mount != "/" { continue }
            result.append(Volume(device: device, mountPoint: mount))
        }
        return result
    }

    /// "/dev/disk4s2" -> "disk4"
    static func wholeDiskName(_ device: String) -> String {
        let name = device.replacingOccurrences(of: "/dev/", with: "")
        guard name.hasPrefix("disk") else { return name }
        let digits = name.dropFirst(4).prefix(while: \.isNumber)
        return "disk" + digits
    }

    /// Cumulative byte counters: all internal drives summed under "internal", each external drive under its BSD name.
    private static func readDrives() -> [String: Counters] {
        var result: [String: Counters] = [:]
        IORegistry.forEachService("IOBlockStorageDriver") { entry, props in
            guard let stats = props["Statistics"] as? [String: Any],
                  let read = stats.uint64("Bytes (Read)"), let write = stats.uint64("Bytes (Write)") else { return }
            let location = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "Physical Interconnect Location" as CFString, kCFAllocatorDefault,
                                                           IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
            if location == "External" {
                var bsd: String?
                IORegistry.forEachDescendant(of: entry) { _, media in
                    if bsd == nil, media["Whole"] as? Bool == true, let name = media["BSD Name"] as? String { bsd = name }
                }
                if let bsd { result[bsd] = Counters(read: read, write: write) }
            } else {
                let old = result["internal"] ?? Counters(read: 0, write: 0)
                result["internal"] = Counters(read: old.read + read, write: old.write + write)
            }
        }
        return result
    }
}
