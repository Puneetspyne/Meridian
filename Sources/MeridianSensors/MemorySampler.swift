import Foundation
import MeridianKit

/// Memory in Activity Monitor's terms so the numbers match what users see there.
/// used = app + wired + compressed, where app = internal pages minus purgeable.
/// cached = file-backed (external) pages plus purgeable ("Cached Files").
final class MemorySampler {
    private let totalBytes = Sysctl.uint64("hw.memsize") ?? 0

    func sample() -> MemoryMetrics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        let page = UInt64(pageSize)

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + purgeable) * page
        // vm_stat reports free without speculative pages, which are really reclaimable cache.
        let freePages = UInt64(stats.free_count)
        let speculative = UInt64(stats.speculative_count)
        let free = (freePages > speculative ? freePages - speculative : 0) * page

        var swapUsed: UInt64 = 0, swapTotal: UInt64 = 0
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }

        return MemoryMetrics(
            totalBytes: totalBytes,
            usedBytes: app + wired + compressed,
            appBytes: app, wiredBytes: wired, compressedBytes: compressed,
            cachedBytes: cached, freeBytes: free,
            swapUsedBytes: swapUsed, swapTotalBytes: swapTotal,
            pressure: Self.pressure()
        )
    }

    static func pressure() -> MemoryPressure {
        switch Sysctl.int32("kern.memorystatus_vm_pressure_level") {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }
}
