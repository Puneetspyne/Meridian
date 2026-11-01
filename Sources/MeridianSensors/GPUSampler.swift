import Foundation
import MeridianKit

/// GPU utilisation from the accelerator's PerformanceStatistics. Works unprivileged on Apple silicon and Intel.
final class GPUSampler {
    func sample() -> GPUMetrics? {
        var best: [String: Any]?
        IORegistry.forEachService("IOAccelerator") { _, props in
            // Prefer the service that actually publishes statistics when a Mac has several GPUs.
            if props["PerformanceStatistics"] is [String: Any], best == nil { best = props }
        }
        guard let props = best else { return nil }

        let stats = props["PerformanceStatistics"] as? [String: Any] ?? [:]
        let percent = stats.double("Device Utilization %") ?? stats.double("GPU Activity(%)")

        var name = (props["model"] as? String)
        if name == nil, let data = props["model"] as? Data { name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
        let resolved = name ?? Sysctl.string("machdep.cpu.brand_string") ?? "GPU"

        return GPUMetrics(
            name: resolved,
            utilization: percent.map { min(1, max(0, $0 / 100)) },
            memoryUsedBytes: stats.uint64("In use system memory") ?? stats.uint64("vramUsedBytes"),
            frequencyMHz: nil,
            coreCount: props.int("gpu-core-count")
        )
    }
}
