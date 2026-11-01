import Foundation

/// Deterministic, smoothly varying fake telemetry for design work, snapshots and CI.
/// Pass a `scenario` to force a state the real machine rarely shows while you are designing for it.
public struct MockTelemetrySource: TelemetrySource {
    public enum Scenario: String, Sendable, CaseIterable {
        case calm, busy, hot, lowBattery, diskFull, charging
    }

    public var scenario: Scenario
    public var start: Date

    public init(scenario: Scenario = .calm, start: Date = Date()) {
        self.scenario = scenario
        self.start = start
    }

    public func sample() async throws -> TelemetrySnapshot {
        snapshot(at: Date())
    }

    /// Pure function of time so snapshot tests are reproducible.
    public func snapshot(at now: Date) -> TelemetrySnapshot {
        let t = now.timeIntervalSince(start)
        func wave(_ period: Double, _ phase: Double = 0) -> Double { (sin(t / period * 2 * .pi + phase) + 1) / 2 }

        let baseCPU: Double
        switch scenario {
        case .busy, .hot: baseCPU = 0.88 + 0.10 * wave(7)
        default: baseCPU = 0.12 + 0.18 * wave(11)
        }
        let perCore: [Double] = (0..<8).map { i in
            let eff = i < 4
            let spread = eff ? 0.6 : 1.25
            return min(1, max(0, baseCPU * spread * (0.7 + 0.6 * wave(5 + Double(i), Double(i)))))
        }
        let cpu = CPUMetrics(total: baseCPU, user: baseCPU * 0.7, system: baseCPU * 0.3, perCore: perCore,
                             efficiencyCoreCount: 4, performanceCoreCount: 4,
                             loadAverage: [baseCPU * 8, baseCPU * 7, baseCPU * 6], frequencyMHz: 2400 + 1000 * baseCPU,
                             uptime: 3 * 86_400 + 4 * 3600 + t)

        let total: UInt64 = 24_000_000_000
        let usedFrac = scenario == .busy ? 0.86 : 0.58 + 0.06 * wave(23)
        let memory = MemoryMetrics(totalBytes: total, usedBytes: UInt64(Double(total) * usedFrac),
                                   appBytes: UInt64(Double(total) * usedFrac * 0.6), wiredBytes: 3_100_000_000,
                                   compressedBytes: UInt64(Double(total) * usedFrac * 0.15), cachedBytes: 4_200_000_000,
                                   freeBytes: UInt64(Double(total) * (1 - usedFrac)),
                                   swapUsedBytes: scenario == .busy ? 2_300_000_000 : 0, swapTotalBytes: 4_000_000_000,
                                   pressure: scenario == .busy ? .warning : .normal)

        let gpu = GPUMetrics(name: "Apple M2", utilization: scenario == .hot ? 0.9 : 0.08 + 0.2 * wave(9), coreCount: 10)

        let diskFree: Double = scenario == .diskFull ? 0.03 : 0.42
        let disks = [DiskMetrics(id: "disk3s1", name: "Macintosh HD", mountPoint: "/", totalBytes: 994_000_000_000,
                                 freeBytes: UInt64(994_000_000_000 * diskFree),
                                 readBytesPerSec: 2_400_000 * wave(3), writeBytesPerSec: 900_000 * wave(4, 1),
                                 isInternal: true, isBoot: true)]

        let network = NetworkMetrics(rxBytesPerSec: 180_000 + 4_200_000 * pow(wave(13), 3),
                                     txBytesPerSec: 40_000 + 600_000 * pow(wave(17, 2), 3),
                                     interfaceName: "en0", isConnected: true, localIP: "192.168.1.24",
                                     publicIP: "203.0.113.7", wifiSSID: "Home", linkSpeedMbps: 866)

        let battery: BatteryMetrics
        switch scenario {
        case .lowBattery:
            battery = BatteryMetrics(isPresent: true, level: 0.08, isCharging: false, isPluggedIn: false,
                                     minutesRemaining: 12, cycleCount: 212, healthFraction: 0.91, temperatureC: 31, watts: -9.4)
        case .charging:
            battery = BatteryMetrics(isPresent: true, level: 0.64, isCharging: true, isPluggedIn: true,
                                     minutesRemaining: 48, cycleCount: 212, healthFraction: 0.91, temperatureC: 33, watts: 42, adapterWatts: 67)
        default:
            battery = BatteryMetrics(isPresent: true, level: 0.78, isCharging: false, isPluggedIn: false,
                                     minutesRemaining: 6 * 60 + 12, cycleCount: 212, healthFraction: 0.91, temperatureC: 30, watts: -7.1)
        }

        let cpuTemp: Double = scenario == .hot ? 96 + 6 * wave(5) : 44 + 10 * wave(19) + 20 * baseCPU
        let sensors = [
            TemperatureReading(id: "Tp01", name: "CPU performance core 1", celsius: cpuTemp, group: .cpu),
            TemperatureReading(id: "Tp05", name: "CPU performance core 2", celsius: cpuTemp - 2, group: .cpu),
            TemperatureReading(id: "Tp09", name: "CPU efficiency core 1", celsius: cpuTemp - 8, group: .cpu),
            TemperatureReading(id: "Tg05", name: "GPU 1", celsius: cpuTemp - 6, group: .gpu),
            TemperatureReading(id: "Tm02", name: "Memory 1", celsius: 38 + 4 * wave(29), group: .memory),
            TemperatureReading(id: "TB1T", name: "Battery", celsius: 31, group: .battery),
            TemperatureReading(id: "TH0x", name: "SSD", celsius: 36 + 3 * wave(31), group: .storage),
        ]
        let fans = [FanReading(id: "F0", name: "Fan", rpm: scenario == .hot ? 6_800 : 1_800 + 1_200 * baseCPU, minRPM: 1_200, maxRPM: 7_200)]
        let thermal = ThermalMetrics(sensors: sensors, fans: fans, pressure: scenario == .hot ? .serious : .nominal)

        let power = PowerMetrics(cpuWatts: 1.2 + 18 * baseCPU, gpuWatts: 0.3 + 12 * (gpu.utilization ?? 0),
                                 aneWatts: 0.02, totalWatts: 2 + 30 * baseCPU, source: "mock")

        let processes = [
            ProcessMetrics(pid: 4821, name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", cpuFraction: 3.1 * baseCPU, memoryBytes: 2_900_000_000),
            ProcessMetrics(pid: 3310, name: "Safari", bundleIdentifier: "com.apple.Safari", cpuFraction: 0.6 * baseCPU, memoryBytes: 1_400_000_000),
            ProcessMetrics(pid: 912, name: "WindowServer", cpuFraction: 0.3, memoryBytes: 620_000_000),
            ProcessMetrics(pid: 5120, name: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", cpuFraction: 0.25 * baseCPU, memoryBytes: 980_000_000),
            ProcessMetrics(pid: 77, name: "kernel_task", cpuFraction: 0.18, memoryBytes: 2_100_000_000),
        ]

        let system = SystemInfo(chipName: "Apple M2", modelIdentifier: "Mac14,2", macOSVersion: "26.5.1",
                                hostName: "Meridian", hasNotch: true, isAppleSilicon: true)

        return TelemetrySnapshot(timestamp: now, cpu: cpu, memory: memory, gpu: gpu, disks: disks, network: network,
                                battery: battery, thermal: thermal, power: power, processes: processes, system: system)
    }
}
