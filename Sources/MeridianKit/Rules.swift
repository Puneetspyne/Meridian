import Foundation

/// User-tunable thresholds. Defaults follow what a laptop owner actually worries about, not what a datacentre would.
public struct Thresholds: Sendable, Codable, Equatable {
    public var cpuSustainedFraction: Double = 0.85
    public var cpuSustainedSeconds: TimeInterval = 60
    public var memoryWarningPressure: MemoryPressure = .warning
    public var diskFreeWarningFraction: Double = 0.10
    public var diskFreeCriticalFraction: Double = 0.05
    public var diskFreeCriticalBytes: UInt64 = 10_000_000_000
    public var batteryWarningLevel: Double = 0.20
    public var batteryCriticalLevel: Double = 0.10
    public var batteryCriticalMinutes: Int = 15
    public var cpuTempWarningC: Double = 90
    public var cpuTempCriticalC: Double = 100
    public var fanWarningFraction: Double = 0.90
    public var thermalPressureWarning: ThermalPressure = .serious

    public init() {}
    public static let `default` = Thresholds()
}

/// Turns raw telemetry into signals. Stateful because "sustained" conditions need memory between samples.
public struct RuleEngine: Sendable {
    public var thresholds: Thresholds
    private var cpuHighSince: Date?

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public mutating func evaluate(_ s: TelemetrySnapshot, now: Date = Date()) -> [Signal] {
        var out: [Signal] = []
        out += evaluateCPU(s, now: now)
        out += evaluateThermal(s, now: now)
        out += evaluateMemory(s, now: now)
        out += evaluateDisks(s, now: now)
        out += evaluateBattery(s, now: now)
        return out
    }

    // MARK: Individual rules

    private mutating func evaluateCPU(_ s: TelemetrySnapshot, now: Date) -> [Signal] {
        guard let cpu = s.cpu else { return [] }
        if cpu.total >= thresholds.cpuSustainedFraction {
            if cpuHighSince == nil { cpuHighSince = now }
        } else {
            cpuHighSince = nil
        }
        let percent = Format.percent(cpu.total)
        let culprit = s.processes.max(by: { $0.cpuFraction < $1.cpuFraction })
        if let since = cpuHighSince, now.timeIntervalSince(since) >= thresholds.cpuSustainedSeconds {
            let detail = culprit.map { "\($0.name) is using \(Format.percent($0.cpuFraction, of: cpu.coreCount)) of the CPU" }
            return [Signal(id: "rule.cpu.sustained", kind: .cpu, attention: .warning,
                           title: "CPU \(percent)", detail: detail ?? "Sustained high load",
                           symbol: "cpu", progress: cpu.total, value: percent, priority: 40, tint: .amber)]
        }
        // Ambient: always available, calm.
        return [Signal(id: "ambient.cpu", kind: .cpu, attention: .calm, title: "CPU",
                       detail: culprit.map { "\($0.name) on top" }, symbol: "cpu",
                       progress: cpu.total, value: percent, priority: 10, tint: .neutral)]
    }

    private func evaluateThermal(_ s: TelemetrySnapshot, now: Date) -> [Signal] {
        guard let thermal = s.thermal else { return [] }
        var out: [Signal] = []
        if let cpuC = thermal.hottest(in: .cpu)?.celsius ?? thermal.hottestCelsius {
            let value = Format.temperature(cpuC, unit: .celsius)
            if cpuC >= thresholds.cpuTempCriticalC || thermal.pressure == .critical {
                out.append(Signal(id: "rule.thermal.critical", kind: .thermal, attention: .critical,
                                  title: "Running hot", detail: "CPU at \(value). macOS is throttling.",
                                  symbol: "flame.fill", progress: min(1, cpuC / 110), value: value, priority: 90, tint: .red))
            } else if cpuC >= thresholds.cpuTempWarningC || thermal.pressure >= thresholds.thermalPressureWarning {
                out.append(Signal(id: "rule.thermal.warning", kind: .thermal, attention: .warning,
                                  title: "Getting warm", detail: "CPU at \(value)",
                                  symbol: "thermometer.medium", progress: min(1, cpuC / 110), value: value, priority: 60, tint: .amber))
            } else {
                out.append(Signal(id: "ambient.thermal", kind: .thermal, attention: .calm, title: "Temp",
                                  detail: thermal.fans.first.map { "Fan \(Int($0.rpm)) rpm" },
                                  symbol: "thermometer.medium", progress: min(1, cpuC / 110), value: value, priority: 9, tint: .neutral))
            }
        }
        if let fan = thermal.fans.compactMap({ f -> (FanReading, Double)? in f.fraction.map { (f, $0) } }).max(by: { $0.1 < $1.1 }),
           fan.1 >= thresholds.fanWarningFraction {
            out.append(Signal(id: "rule.fan.high", kind: .thermal, attention: .info,
                              title: "Fans at \(Format.percent(fan.1))", detail: "\(fan.0.name) \(Int(fan.0.rpm)) rpm",
                              symbol: "fan.fill", progress: fan.1, value: "\(Int(fan.0.rpm))", priority: 30, tint: .amber))
        }
        return out
    }

    private func evaluateMemory(_ s: TelemetrySnapshot, now: Date) -> [Signal] {
        guard let mem = s.memory else { return [] }
        let value = Format.percent(mem.usedFraction)
        switch mem.pressure {
        case .critical:
            return [Signal(id: "rule.memory.critical", kind: .memory, attention: .critical, title: "Memory full",
                           detail: "Swap \(Format.bytes(mem.swapUsedBytes)) · pressure critical",
                           symbol: "memorychip.fill", progress: mem.usedFraction, value: value, priority: 85, tint: .red)]
        case .warning where thresholds.memoryWarningPressure <= .warning:
            return [Signal(id: "rule.memory.warning", kind: .memory, attention: .warning, title: "Memory pressure",
                           detail: "Swap \(Format.bytes(mem.swapUsedBytes)) in use",
                           symbol: "memorychip", progress: mem.usedFraction, value: value, priority: 55, tint: .amber)]
        default:
            return [Signal(id: "ambient.memory", kind: .memory, attention: .calm, title: "Memory",
                           detail: "\(Format.bytes(mem.usedBytes)) of \(Format.bytes(mem.totalBytes))",
                           symbol: "memorychip", progress: mem.usedFraction, value: value, priority: 8, tint: .neutral)]
        }
    }

    private func evaluateDisks(_ s: TelemetrySnapshot, now: Date) -> [Signal] {
        var out: [Signal] = []
        for disk in s.disks where disk.isInternal || disk.isBoot {
            let free = Format.bytes(disk.freeBytes)
            if disk.freeFraction <= thresholds.diskFreeCriticalFraction || disk.freeBytes <= thresholds.diskFreeCriticalBytes {
                out.append(Signal(id: "rule.disk.critical.\(disk.id)", kind: .disk, attention: .critical,
                                  title: "Disk almost full", detail: "\(free) left on \(disk.name)",
                                  symbol: "internaldrive.fill", progress: disk.usedFraction, value: free, priority: 80, tint: .red))
            } else if disk.freeFraction <= thresholds.diskFreeWarningFraction {
                out.append(Signal(id: "rule.disk.warning.\(disk.id)", kind: .disk, attention: .warning,
                                  title: "Disk filling up", detail: "\(free) left on \(disk.name)",
                                  symbol: "internaldrive", progress: disk.usedFraction, value: free, priority: 50, tint: .amber))
            }
        }
        if out.isEmpty, let boot = s.bootDisk {
            out.append(Signal(id: "ambient.disk", kind: .disk, attention: .calm, title: "Disk",
                              detail: "\(Format.bytes(boot.freeBytes)) free",
                              symbol: "internaldrive", progress: boot.usedFraction, value: Format.percent(boot.usedFraction), priority: 7, tint: .neutral))
        }
        return out
    }

    private func evaluateBattery(_ s: TelemetrySnapshot, now: Date) -> [Signal] {
        guard let b = s.battery, b.isPresent else { return [] }
        let percent = Format.percent(b.level)
        if !b.isPluggedIn {
            let remaining = b.minutesRemaining.map { Format.minutes($0) }
            if b.level <= thresholds.batteryCriticalLevel || (b.minutesRemaining ?? .max) <= thresholds.batteryCriticalMinutes {
                return [Signal(id: "rule.battery.critical", kind: .battery, attention: .critical, title: "Battery \(percent)",
                               detail: remaining.map { "\($0) left. Plug in." } ?? "Plug in soon.",
                               symbol: "battery.0percent", progress: b.level, value: percent, priority: 95, tint: .red)]
            }
            if b.level <= thresholds.batteryWarningLevel {
                return [Signal(id: "rule.battery.warning", kind: .battery, attention: .warning, title: "Battery \(percent)",
                               detail: remaining.map { "\($0) left" }, symbol: "battery.25percent",
                               progress: b.level, value: percent, priority: 65, tint: .amber)]
            }
        }
        let symbol: String
        let detail: String?
        if b.isFullyCharged { symbol = "battery.100percent.bolt"; detail = "Fully charged" }
        else if b.isCharging { symbol = "battery.75percent.bolt"; detail = b.minutesRemaining.map { "\(Format.minutes($0)) to full" } ?? "Charging" }
        else { symbol = "battery.75percent"; detail = b.minutesRemaining.map { "\(Format.minutes($0)) left" } }
        return [Signal(id: "ambient.battery", kind: .battery, attention: .calm, title: "Battery", detail: detail,
                       symbol: symbol, progress: b.level, value: percent, priority: 6, tint: b.isCharging ? .green : .neutral)]
    }
}
