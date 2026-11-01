import Foundation
import MeridianKit

/// How often each expensive sampler refreshes. Between refreshes `sample()` returns the sampler's last result.
/// CPU, memory, network, disk rates and battery are cheap and run on every call.
public struct SamplingTiers: Sendable, Equatable {
    public var gpu: TimeInterval
    public var temperatures: TimeInterval
    public var power: TimeInterval
    public var processes: TimeInterval

    public init(gpu: TimeInterval = 2, temperatures: TimeInterval = 3, power: TimeInterval = 2, processes: TimeInterval = 3) {
        self.gpu = gpu
        self.temperatures = temperatures
        self.power = power
        self.processes = processes
    }

    public static let `default` = SamplingTiers()
    /// Every sampler on every call: tests and one-shot tools.
    public static let everyCall = SamplingTiers(gpu: 0, temperatures: 0, power: 0, processes: 0)
}

/// Samples the live machine. All IOKit and Mach work runs on one private serial queue, so `sample()` never
/// blocks the caller's actor and the delta-based samplers always see calls in order.
public struct LiveTelemetrySource: TelemetrySource {
    private let engine: SensorEngine

    public init(tiers: SamplingTiers = .default) {
        engine = SensorEngine(tiers: tiers)
        engine.warmUp()
    }

    public func sample() async throws -> TelemetrySnapshot {
        await withCheckedContinuation { continuation in
            engine.queue.async { continuation.resume(returning: engine.sampleNow()) }
        }
    }
}

/// Caches a sampler's last value and re-runs it only when its interval has elapsed.
private struct Tiered<T> {
    let interval: TimeInterval
    var value: T
    var lastRun: TimeInterval?

    init(interval: TimeInterval, initial: T) { self.interval = interval; value = initial }

    func isDue(_ now: TimeInterval) -> Bool {
        guard let lastRun else { return true }
        // 50 ms of slack so a 1 Hz caller with timer jitter does not skip every other refresh of a 2 s tier.
        return now - lastRun >= interval - 0.05
    }

    mutating func markRun(_ now: TimeInterval, _ new: T) { value = new; lastRun = now }
}

/// Owns every sampler and its between-call state. Each sampler is independent and fails soft.
final class SensorEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.meridian.sensors", qos: .utility)

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disks = DiskSampler()
    private let network = NetworkSampler()
    private let battery = BatterySampler()
    private let gpu = GPUSampler()
    private let hid = HIDTemperatureSampler()
    private let smc = SMCSampler()
    private let power: PowerSampler
    private let processes = ProcessSampler()
    private let system = SystemInfoSampler.read()

    private var gpuTier: Tiered<GPUMetrics?>
    private var thermalTier: Tiered<[TemperatureReading]>
    private var fansTier = [FanReading]()
    private var powerTier: Tiered<PowerMetrics?>
    private var processTier: Tiered<[ProcessMetrics]>

    init(tiers: SamplingTiers) {
        power = PowerSampler(smc: smc)
        gpuTier = Tiered(interval: tiers.gpu, initial: nil)
        thermalTier = Tiered(interval: tiers.temperatures, initial: [])
        powerTier = Tiered(interval: tiers.power, initial: nil)
        processTier = Tiered(interval: tiers.processes, initial: [])
    }

    /// Takes the baseline for every delta-based sampler off the caller's thread (and pays the one-time SMC key
    /// discovery there), so the first real sample has rates.
    func warmUp() {
        queue.async { _ = self.sampleNow() }
    }

    /// Must run on `queue`. Temperatures run HID and SMC in parallel because they share no state.
    func sampleNow() -> TelemetrySnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let group = DispatchGroup()
        let hidBox = Box<[TemperatureReading]>([])
        let smcBox = Box<([TemperatureReading], [FanReading])>(([], []))
        let thermalDue = thermalTier.isDue(now)
        if thermalDue {
            let side = DispatchQueue.global(qos: .utility)
            side.async(group: group) { hidBox.value = self.hid.sample() }
            side.async(group: group) { smcBox.value = (self.smc.temperatures(), self.smc.fans()) }
        }

        let cpuMetrics = cpu.sample()
        let memoryMetrics = memory.sample()
        let diskMetrics = disks.sample()
        let networkMetrics = network.sample()
        let batteryMetrics = battery.sample()
        if gpuTier.isDue(now) { gpuTier.markRun(now, gpu.sample()) }
        if processTier.isDue(now) { processTier.markRun(now, processes.sample()) }
        group.wait()

        if thermalDue {
            var sensors = hidBox.value
            let known = Set(sensors.map(\.id))
            sensors += smcBox.value.0.filter { !known.contains($0.id) }
            thermalTier.markRun(now, sensors)
            fansTier = smcBox.value.1
        }
        // Power reads PSTR through the SMC, so it runs after the side work to avoid contending for the SMC lock.
        if powerTier.isDue(now) { powerTier.markRun(now, power.sample()) }

        return TelemetrySnapshot(
            timestamp: Date(), cpu: cpuMetrics, memory: memoryMetrics, gpu: gpuTier.value, disks: diskMetrics,
            network: networkMetrics, battery: batteryMetrics,
            thermal: ThermalMetrics(sensors: thermalTier.value, fans: fansTier, pressure: ThermalSampler.pressure()),
            power: powerTier.value, processes: processTier.value, system: system)
    }
}

/// A mutable cell handed to concurrent closures; each box is written by exactly one of them.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
