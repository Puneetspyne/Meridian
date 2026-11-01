import Foundation

/// One sampled picture of the machine. Every section is optional so a source can publish
/// what it has: a sandboxed test, an Intel Mac without IOReport, or a VM without sensors.
public struct TelemetrySnapshot: Sendable, Codable, Equatable {
    public var timestamp: Date
    public var cpu: CPUMetrics?
    public var memory: MemoryMetrics?
    public var gpu: GPUMetrics?
    public var disks: [DiskMetrics]
    public var network: NetworkMetrics?
    public var battery: BatteryMetrics?
    public var thermal: ThermalMetrics?
    public var power: PowerMetrics?
    public var processes: [ProcessMetrics]
    public var system: SystemInfo?

    public init(
        timestamp: Date = Date(),
        cpu: CPUMetrics? = nil,
        memory: MemoryMetrics? = nil,
        gpu: GPUMetrics? = nil,
        disks: [DiskMetrics] = [],
        network: NetworkMetrics? = nil,
        battery: BatteryMetrics? = nil,
        thermal: ThermalMetrics? = nil,
        power: PowerMetrics? = nil,
        processes: [ProcessMetrics] = [],
        system: SystemInfo? = nil
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.disks = disks
        self.network = network
        self.battery = battery
        self.thermal = thermal
        self.power = power
        self.processes = processes
        self.system = system
    }

    public static let empty = TelemetrySnapshot(timestamp: Date(timeIntervalSince1970: 0))

    /// The boot volume, or the first disk when the source could not tell.
    public var bootDisk: DiskMetrics? { disks.first(where: \.isBoot) ?? disks.first }
}

// MARK: - CPU

public struct CPUMetrics: Sendable, Codable, Equatable {
    /// Fractions in 0...1 across all cores.
    public var total: Double
    public var user: Double
    public var system: Double
    /// Per-core busy fraction in 0...1, ordered as the kernel reports them.
    public var perCore: [Double]
    /// Apple silicon splits cores into efficiency and performance clusters. Both are 0 on Intel.
    public var efficiencyCoreCount: Int
    public var performanceCoreCount: Int
    /// 1, 5 and 15 minute load averages.
    public var loadAverage: [Double]
    public var frequencyMHz: Double?
    public var uptime: TimeInterval

    public init(total: Double, user: Double, system: Double, perCore: [Double],
                efficiencyCoreCount: Int = 0, performanceCoreCount: Int = 0,
                loadAverage: [Double] = [], frequencyMHz: Double? = nil, uptime: TimeInterval = 0) {
        self.total = total
        self.user = user
        self.system = system
        self.perCore = perCore
        self.efficiencyCoreCount = efficiencyCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.loadAverage = loadAverage
        self.frequencyMHz = frequencyMHz
        self.uptime = uptime
    }

    public var coreCount: Int { perCore.count }
    /// Efficiency cores come first in the kernel's ordering on Apple silicon.
    public var efficiencyCores: ArraySlice<Double> { perCore.prefix(efficiencyCoreCount) }
    public var performanceCores: ArraySlice<Double> { perCore.dropFirst(efficiencyCoreCount) }
}

// MARK: - Memory

public enum MemoryPressure: String, Sendable, Codable, Equatable, Comparable {
    case normal, warning, critical
    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool { lhs.rank < rhs.rank }
    private var rank: Int { switch self { case .normal: 0; case .warning: 1; case .critical: 2 } }
}

public struct MemoryMetrics: Sendable, Codable, Equatable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var freeBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: MemoryPressure

    public init(totalBytes: UInt64, usedBytes: UInt64, appBytes: UInt64 = 0, wiredBytes: UInt64 = 0,
                compressedBytes: UInt64 = 0, cachedBytes: UInt64 = 0, freeBytes: UInt64 = 0,
                swapUsedBytes: UInt64 = 0, swapTotalBytes: UInt64 = 0, pressure: MemoryPressure = .normal) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
    }

    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

// MARK: - GPU

public struct GPUMetrics: Sendable, Codable, Equatable {
    public var name: String
    /// Device utilisation 0...1 when the driver reports it.
    public var utilization: Double?
    public var memoryUsedBytes: UInt64?
    public var frequencyMHz: Double?
    public var coreCount: Int?

    public init(name: String, utilization: Double? = nil, memoryUsedBytes: UInt64? = nil,
                frequencyMHz: Double? = nil, coreCount: Int? = nil) {
        self.name = name
        self.utilization = utilization
        self.memoryUsedBytes = memoryUsedBytes
        self.frequencyMHz = frequencyMHz
        self.coreCount = coreCount
    }
}

// MARK: - Disks

public struct DiskMetrics: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var mountPoint: String
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public var isInternal: Bool
    public var isBoot: Bool

    public init(id: String, name: String, mountPoint: String, totalBytes: UInt64, freeBytes: UInt64,
                readBytesPerSec: Double = 0, writeBytesPerSec: Double = 0, isInternal: Bool = true, isBoot: Bool = false) {
        self.id = id
        self.name = name
        self.mountPoint = mountPoint
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.isInternal = isInternal
        self.isBoot = isBoot
    }

    public var usedBytes: UInt64 { totalBytes >= freeBytes ? totalBytes - freeBytes : 0 }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
    public var freeFraction: Double { 1 - usedFraction }
}

// MARK: - Network

public struct NetworkMetrics: Sendable, Codable, Equatable {
    public var rxBytesPerSec: Double
    public var txBytesPerSec: Double
    public var interfaceName: String?
    public var isConnected: Bool
    public var localIP: String?
    public var publicIP: String?
    public var wifiSSID: String?
    public var linkSpeedMbps: Double?

    public init(rxBytesPerSec: Double, txBytesPerSec: Double, interfaceName: String? = nil, isConnected: Bool = true,
                localIP: String? = nil, publicIP: String? = nil, wifiSSID: String? = nil, linkSpeedMbps: Double? = nil) {
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
        self.interfaceName = interfaceName
        self.isConnected = isConnected
        self.localIP = localIP
        self.publicIP = publicIP
        self.wifiSSID = wifiSSID
        self.linkSpeedMbps = linkSpeedMbps
    }
}

// MARK: - Battery

public struct BatteryMetrics: Sendable, Codable, Equatable {
    public var isPresent: Bool
    /// 0...1
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool
    /// Minutes to empty while discharging, minutes to full while charging. Nil while the system is still estimating.
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    /// Current max capacity over design capacity, 0...1.
    public var healthFraction: Double?
    public var temperatureC: Double?
    /// Positive while charging, negative while discharging.
    public var watts: Double?
    public var adapterWatts: Double?

    public init(isPresent: Bool, level: Double, isCharging: Bool, isPluggedIn: Bool, isFullyCharged: Bool = false,
                minutesRemaining: Int? = nil, cycleCount: Int? = nil, healthFraction: Double? = nil,
                temperatureC: Double? = nil, watts: Double? = nil, adapterWatts: Double? = nil) {
        self.isPresent = isPresent
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.healthFraction = healthFraction
        self.temperatureC = temperatureC
        self.watts = watts
        self.adapterWatts = adapterWatts
    }
}

// MARK: - Thermal

public enum SensorGroup: String, Sendable, Codable, CaseIterable {
    case cpu, gpu, memory, battery, storage, system, other
}

public struct TemperatureReading: Sendable, Codable, Equatable, Identifiable {
    /// The raw SMC or HID key, stable across launches.
    public var id: String
    public var name: String
    public var celsius: Double
    public var group: SensorGroup

    public init(id: String, name: String, celsius: Double, group: SensorGroup) {
        self.id = id
        self.name = name
        self.celsius = celsius
        self.group = group
    }
}

public struct FanReading: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var rpm: Double
    public var minRPM: Double?
    public var maxRPM: Double?
    public var targetRPM: Double?

    public init(id: String, name: String, rpm: Double, minRPM: Double? = nil, maxRPM: Double? = nil, targetRPM: Double? = nil) {
        self.id = id
        self.name = name
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
    }

    /// 0...1 within the fan's range when the range is known.
    public var fraction: Double? {
        guard let minRPM, let maxRPM, maxRPM > minRPM else { return nil }
        return min(1, max(0, (rpm - minRPM) / (maxRPM - minRPM)))
    }
}

public enum ThermalPressure: String, Sendable, Codable, Equatable, Comparable {
    case nominal, fair, serious, critical
    public static func < (lhs: ThermalPressure, rhs: ThermalPressure) -> Bool { lhs.rank < rhs.rank }
    private var rank: Int { switch self { case .nominal: 0; case .fair: 1; case .serious: 2; case .critical: 3 } }
}

public struct ThermalMetrics: Sendable, Codable, Equatable {
    public var sensors: [TemperatureReading]
    public var fans: [FanReading]
    public var pressure: ThermalPressure

    public init(sensors: [TemperatureReading], fans: [FanReading] = [], pressure: ThermalPressure = .nominal) {
        self.sensors = sensors
        self.fans = fans
        self.pressure = pressure
    }

    public func average(of group: SensorGroup) -> Double? {
        let values = sensors.filter { $0.group == group }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public func hottest(in group: SensorGroup) -> TemperatureReading? {
        sensors.filter { $0.group == group }.max(by: { $0.celsius < $1.celsius })
    }

    public var cpuCelsius: Double? { average(of: .cpu) }
    public var gpuCelsius: Double? { average(of: .gpu) }
    public var hottestCelsius: Double? { sensors.map(\.celsius).max() }
}

// MARK: - Power

public struct PowerMetrics: Sendable, Codable, Equatable {
    public var cpuWatts: Double?
    public var gpuWatts: Double?
    public var aneWatts: Double?
    public var totalWatts: Double?
    /// "ioreport", "smc" or "unavailable". Shown in the card so a user knows why a number is missing.
    public var source: String

    public init(cpuWatts: Double? = nil, gpuWatts: Double? = nil, aneWatts: Double? = nil, totalWatts: Double? = nil, source: String = "unavailable") {
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
        self.totalWatts = totalWatts
        self.source = source
    }
}

// MARK: - Processes

public struct ProcessMetrics: Sendable, Codable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var bundleIdentifier: String?
    /// 0...1 of one core, so a process may exceed 1 on multicore Macs.
    public var cpuFraction: Double
    public var memoryBytes: UInt64

    public init(pid: Int32, name: String, bundleIdentifier: String? = nil, cpuFraction: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.cpuFraction = cpuFraction
        self.memoryBytes = memoryBytes
    }
}

// MARK: - System

public struct SystemInfo: Sendable, Codable, Equatable {
    public var chipName: String
    public var modelIdentifier: String
    public var macOSVersion: String
    public var hostName: String
    public var hasNotch: Bool
    public var isAppleSilicon: Bool

    public init(chipName: String, modelIdentifier: String, macOSVersion: String, hostName: String, hasNotch: Bool, isAppleSilicon: Bool) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.macOSVersion = macOSVersion
        self.hostName = hostName
        self.hasNotch = hasNotch
        self.isAppleSilicon = isAppleSilicon
    }
}

// MARK: - Source

/// Anything that can produce a snapshot: the live machine, a replayed fixture, or the mock used for design work.
public protocol TelemetrySource: Sendable {
    func sample() async throws -> TelemetrySnapshot
}
