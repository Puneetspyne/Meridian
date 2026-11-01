import Darwin
import Foundation
import MeridianKit

/// Top processes by CPU, from per-pid rusage deltas. Names and bundle ids are resolved only for the few that make the cut,
/// because proc_pidpath and plist reads are far more expensive than the rusage call.
final class ProcessSampler {
    private struct Previous { var cpuNanos: UInt64; var time: TimeInterval }
    private var previous: [Int32: Previous] = [:]
    private var bundleIDs: [String: String?] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()
    private let limit: Int

    init(limit: Int = 8) { self.limit = limit }

    private struct Row { var pid: Int32; var cpu: Double; var memory: UInt64 }

    func sample() -> [ProcessMetrics] {
        let now = ProcessInfo.processInfo.systemUptime
        let pids = Self.allPIDs()
        var next: [Int32: Previous] = [:]
        next.reserveCapacity(pids.count)
        var rows: [Row] = []
        rows.reserveCapacity(pids.count)

        for pid in pids {
            guard let usage = Self.rusage(pid) else { continue }
            // Mach absolute ticks to nanoseconds; on Apple silicon the ratio is not 1:1.
            let nanos = (usage.ri_user_time &+ usage.ri_system_time) &* timebase.numer / timebase.denom
            next[pid] = Previous(cpuNanos: nanos, time: now)
            var fraction = 0.0
            if let old = previous[pid], now > old.time, nanos >= old.cpuNanos { // nanos < old means the pid was reused
                fraction = Double(nanos - old.cpuNanos) / 1e9 / (now - old.time)
            }
            rows.append(Row(pid: pid, cpu: fraction, memory: usage.ri_phys_footprint))
        }
        previous = next

        // Memory breaks ties so the very first call (no deltas yet) still returns something meaningful.
        let top = rows.sorted { ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }.prefix(limit)
        return top.map { row in
            let (name, bundle) = resolveIdentity(pid: row.pid)
            return ProcessMetrics(pid: row.pid, name: name, bundleIdentifier: bundle, cpuFraction: row.cpu, memoryBytes: row.memory)
        }
    }

    private static func allPIDs() -> [Int32] {
        // libproc's wrapper returns a pid count (not bytes); pad the buffer because processes spawn between calls.
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private static func rusage(_ pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? info : nil
    }

    private func resolveIdentity(pid: Int32) -> (String, String?) {
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        var name = String(cString: nameBuffer)
        if pid == 0 && name.isEmpty { name = "kernel_task" }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { return (name.isEmpty ? "pid \(pid)" : name, nil) }
        let path = String(cString: pathBuffer)
        // Outermost bundle, so "Google Chrome Helper" reads as "Google Chrome".
        guard let appRange = path.range(of: ".app/") else { return (name.isEmpty ? (path as NSString).lastPathComponent : name, nil) }
        let bundlePath = String(path[..<appRange.lowerBound]) + ".app"
        let appName = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
        if bundleIDs[bundlePath] == nil { bundleIDs[bundlePath] = .some(Bundle(path: bundlePath)?.bundleIdentifier) }
        return (appName, bundleIDs[bundlePath] ?? nil)
    }
}
