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
    private var identities: [Int32: (name: String, bundle: String?)] = [:]
    private let ownPID = getpid()
    /// Raw rows resolved to names before aggregation. Large enough that a multi-process app (browser helpers)
    /// is summed from all of its heavy children, small enough that proc_pidpath stays a few dozen calls.
    private let candidateCount = 64

    /// Walks every pid, so callers run it on a slow tier (the engine uses 3 s) and reuse the result between runs.
    func sample() -> [ProcessMetrics] {
        let now = ProcessInfo.processInfo.systemUptime
        let pids = Self.allPIDs()
        var next: [Int32: Previous] = [:]
        next.reserveCapacity(pids.count)
        var rows: [Row] = []
        rows.reserveCapacity(pids.count)

        for pid in pids where pid != ownPID {
            guard let usage = Self.rusage(pid) else { continue }
            // Mach absolute ticks to nanoseconds; on Apple silicon the ratio is not 1:1.
            let nanos = (usage.ri_user_time &+ usage.ri_system_time) &* timebase.numer / timebase.denom
            next[pid] = Previous(cpuNanos: nanos, time: now)
            var fraction = 0.0
            if let old = previous[pid], now > old.time {
                if nanos >= old.cpuNanos { fraction = Double(nanos - old.cpuNanos) / 1e9 / (now - old.time) }
                else { identities[pid] = nil } // counter went backwards: the pid was reused by another process
            }
            rows.append(Row(pid: pid, cpu: fraction, memory: usage.ri_phys_footprint))
        }
        previous = next
        identities = identities.filter { next[$0.key] != nil }

        // Memory breaks ties so the very first run (no deltas yet) still returns something meaningful.
        let candidates = rows.sorted { ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }.prefix(candidateCount)

        // Aggregate by resolved name so "Claude" and its helpers read as one row; keep the heaviest member's pid.
        var byName: [String: (row: ProcessMetrics, heaviest: Double)] = [:]
        for row in candidates {
            let (name, bundle) = identity(pid: row.pid)
            if var entry = byName[name] {
                entry.row.cpuFraction += row.cpu
                entry.row.memoryBytes += row.memory
                if row.cpu > entry.heaviest {
                    entry.row.pid = row.pid; entry.heaviest = row.cpu
                    if let bundle { entry.row.bundleIdentifier = bundle }
                }
                byName[name] = entry
            } else {
                byName[name] = (ProcessMetrics(pid: row.pid, name: name, bundleIdentifier: bundle, cpuFraction: row.cpu, memoryBytes: row.memory), row.cpu)
            }
        }
        return byName.values.map(\.row)
            .sorted { ($0.cpuFraction, $0.memoryBytes) > ($1.cpuFraction, $1.memoryBytes) }
            .prefix(limit).map { $0 }
    }

    private func identity(pid: Int32) -> (String, String?) {
        if let cached = identities[pid] { return cached }
        let resolved = resolveIdentity(pid: pid)
        identities[pid] = resolved
        return resolved
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
