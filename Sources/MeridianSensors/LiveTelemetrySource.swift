import Foundation
import MeridianKit

/// Samples the live machine. All IOKit and Mach work runs on one private serial queue, so `sample()` never
/// blocks the caller's actor and the delta-based samplers always see calls in order.
public struct LiveTelemetrySource: TelemetrySource {
    private let engine: SensorEngine

    public init() {
        engine = SensorEngine()
        engine.warmUp()
    }

    public func sample() async throws -> TelemetrySnapshot {
        await withCheckedContinuation { continuation in
            engine.queue.async { continuation.resume(returning: engine.sampleNow()) }
        }
    }
}

/// Owns every sampler and its between-call state. Each sampler is independent and fails soft.
final class SensorEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.meridian.sensors", qos: .utility)

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let disks = DiskSampler()
    private let network = NetworkSampler()
    private let battery = BatterySampler()
    private let hid = HIDTemperatureSampler()
    private let smc = SMCSampler()
    private let power: PowerSampler
    private let processes = ProcessSampler()
    private let system = SystemInfoSampler.read()

    init() {
        power = PowerSampler(smc: smc)
    }

    /// Takes the baseline for every delta-based sampler off the caller's thread, so the first real sample has rates.
    func warmUp() {
        queue.async { _ = self.sampleNow() }
    }

    /// Must run on `queue`. The two slowest samplers (HID events and SMC round trips) do not share state, so they
    /// run alongside the rest and the whole pass costs about as much as the slower of the two.
    func sampleNow() -> TelemetrySnapshot {
        let group = DispatchGroup()
        let hidBox = Box<[TemperatureReading]>([])
        let smcBox = Box<([TemperatureReading], [FanReading])>(([], []))
        let side = DispatchQueue.global(qos: .utility)
        side.async(group: group) { hidBox.value = self.hid.sample() }
        side.async(group: group) { smcBox.value = (self.smc.temperatures(), self.smc.fans()) }

        let cpuMetrics = cpu.sample()
        let memoryMetrics = memory.sample()
        let gpuMetrics = gpu.sample()
        let diskMetrics = disks.sample()
        let networkMetrics = network.sample()
        let batteryMetrics = battery.sample()
        let processMetrics = processes.sample()
        group.wait()

        var sensors = hidBox.value
        let known = Set(sensors.map(\.id))
        sensors += smcBox.value.0.filter { !known.contains($0.id) }
        let thermal = ThermalMetrics(sensors: sensors, fans: smcBox.value.1, pressure: ThermalSampler.pressure())

        // Power reads PSTR through the SMC, so it runs after the side work to avoid contending for the SMC lock.
        let powerMetrics = power.sample()

        return TelemetrySnapshot(
            timestamp: Date(), cpu: cpuMetrics, memory: memoryMetrics, gpu: gpuMetrics, disks: diskMetrics,
            network: networkMetrics, battery: batteryMetrics, thermal: thermal, power: powerMetrics,
            processes: processMetrics, system: system)
    }
}

/// A mutable cell handed to concurrent closures; each box is written by exactly one of them.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
