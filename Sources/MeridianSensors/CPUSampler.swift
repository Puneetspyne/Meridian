import Foundation
import MeridianKit

/// CPU load from per-core tick deltas. Needs two calls to produce rates; the first returns zeros.
final class CPUSampler {
    private var previous: [[UInt32]]?

    /// Core cluster sizes never change at runtime, so read them once.
    private let performanceCores = Int(Sysctl.int32("hw.perflevel0.logicalcpu") ?? 0)
    private let efficiencyCores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 0)

    func sample() -> CPUMetrics? {
        guard let ticks = Self.readTicks() else { return nil }
        defer { previous = ticks }

        var perCore = [Double](repeating: 0, count: ticks.count)
        var totalDelta: UInt64 = 0, userDelta: UInt64 = 0, systemDelta: UInt64 = 0

        if let previous, previous.count == ticks.count {
            for i in ticks.indices {
                // Tick counters are 32-bit and wrap; wrapping subtraction keeps the delta right across a wrap.
                let user = UInt64(ticks[i][0] &- previous[i][0])
                let sys = UInt64(ticks[i][1] &- previous[i][1])
                let idle = UInt64(ticks[i][2] &- previous[i][2])
                let nice = UInt64(ticks[i][3] &- previous[i][3])
                let busy = user + sys + nice
                let all = busy + idle
                perCore[i] = all == 0 ? 0 : Double(busy) / Double(all)
                totalDelta += all
                userDelta += user + nice
                systemDelta += sys
            }
        }

        let total = totalDelta == 0 ? 0 : Double(userDelta + systemDelta) / Double(totalDelta)
        let user = totalDelta == 0 ? 0 : Double(userDelta) / Double(totalDelta)
        let system = totalDelta == 0 ? 0 : Double(systemDelta) / Double(totalDelta)

        var load = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&load, 3)

        return CPUMetrics(
            total: total, user: user, system: system, perCore: perCore,
            efficiencyCoreCount: efficiencyCores, performanceCoreCount: performanceCores,
            loadAverage: loadCount == 3 ? load : [],
            frequencyMHz: nil, // Apple silicon exposes no cheap, unprivileged cluster frequency.
            uptime: Self.uptime()
        )
    }

    static func uptime() -> TimeInterval {
        guard let boot = Sysctl.timeval("kern.boottime") else { return 0 }
        let bootDate = Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - bootDate)
    }

    /// [user, system, idle, nice] per logical core.
    private static func readTicks() -> [[UInt32]]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            (0..<stride).map { state in UInt32(bitPattern: info[core * stride + state]) }
        }
    }
}
