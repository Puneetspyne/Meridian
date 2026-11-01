import Foundation
import MeridianKit

/// Names and groups for sensors. HID products are named by Apple (for example "PMU tdie3"); SMC keys are
/// four-character codes. Both are mapped here so the UI shows words and groups without knowing either scheme.
public enum SensorCatalog {
    // MARK: HID

    /// Heuristic grouping by product name, case-insensitive. Order matters: the first match wins.
    public static func group(forSensorName name: String) -> SensorGroup {
        let n = name.lowercased()
        if n.contains("cpu") || n.contains("pacc") || n.contains("eacc") || n.contains("tdie") || n.contains("soc") { return .cpu }
        if n.contains("gpu") { return .gpu }
        if n.contains("dram") || n.contains("memory") { return .memory }
        if n.contains("battery") || n.contains("gas gauge") { return .battery }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        return .system
    }

    /// Readable label for an Apple silicon HID product name. Unknown shapes pass through unchanged.
    public static func friendlyName(forHIDName name: String) -> String {
        func number(after prefix: String) -> String? {
            guard name.hasPrefix(prefix) else { return nil }
            let digits = name.dropFirst(prefix.count).filter(\.isNumber)
            return digits.isEmpty ? nil : String(digits)
        }
        // M2-generation chips expose two PMUs ("PMU" and "PMU2"), each with numbered die and device sensors.
        if let n = number(after: "PMU tdie") { return "SoC die \(n)" }
        if let n = number(after: "PMU tdev") { return "SoC device \(n)" }
        if let n = number(after: "PMU2 tdie") { return "SoC die \(n) (PMU2)" }
        if let n = number(after: "PMU2 tdev") { return "SoC device \(n) (PMU2)" }
        if let n = number(after: "pACC MTR Temp Sensor") { return "Performance core \(n)" }
        if let n = number(after: "eACC MTR Temp Sensor") { return "Efficiency core \(n)" }
        if let n = number(after: "GPU MTR Temp Sensor") { return "GPU \(n)" }
        if let n = number(after: "SOC MTR Temp Sensor") { return "SoC \(n)" }
        if let n = number(after: "NAND CH") { return "SSD channel \(n)" }
        if name.lowercased().contains("gas gauge") { return "Battery" }
        return name
    }

    // MARK: SMC

    /// Group by key prefix. Case matters on purpose: `Tg` is an Apple silicon GPU die, `TG` an Intel GPU.
    public static func group(forSMCKey key: String) -> SensorGroup {
        let p = String(key.prefix(2))
        switch p {
        case "Tp", "TC", "Te": return .cpu
        case "Tg", "TG": return .gpu
        case "Tm", "TM": return .memory
        case "TB": return .battery
        case "TH": return .storage
        default: return .system
        }
    }

    /// Friendly name for well-known keys; otherwise a descriptive fallback for known prefixes; otherwise the raw key.
    public static func name(forSMCKey key: String) -> String {
        name(forSMCKey: key, appleSilicon: isAppleSilicon)
    }

    static let isAppleSilicon = (Sysctl.int32("hw.optional.arm64") ?? 0) == 1

    /// Intel temperature names ("Palm Rest", "Heatpipe 1") describe Intel sensor placement. The same keys exist
    /// on Apple silicon with different meaning, so those names apply on Intel only.
    static func name(forSMCKey key: String, appleSilicon: Bool) -> String {
        if let known = common[key] { return known }
        if !appleSilicon, let known = intelTemperatures[key] { return known }
        let suffix = String(key.dropFirst(2))
        switch String(key.prefix(2)) {
        case "Tp", "Te": return "CPU core (\(key))"
        case "TC": return "CPU (\(key))"
        case "Tg", "TG": return "GPU (\(key))"
        case "Tm", "TM": return "Memory (\(key))"
        case "TB": return "Battery (\(key))"
        case "TW", "Tw": return "Wi-Fi (\(key))"
        case "TL": return "Display (\(key))"
        default: _ = suffix; return key
        }
    }

    /// Well-known keys, written from public SMC key lists. Intel entries are long established; Apple silicon
    /// sensors vary per chip, so only the stable power and fan keys are named here. Contribute more with
    /// `meridianctl contribute`.
    static let intelTemperatures: [String: String] = [
        "TA0P": "Ambient", "TA1P": "Ambient 2", "Ta0P": "Airflow Left",
        "TC0D": "CPU Die", "TC0E": "CPU Die (E)", "TC0F": "CPU Die (F)", "TC0H": "CPU Heatsink", "TC0P": "CPU Proximity",
        "TC1C": "CPU Core 1", "TC2C": "CPU Core 2", "TC3C": "CPU Core 3", "TC4C": "CPU Core 4",
        "TC5C": "CPU Core 5", "TC6C": "CPU Core 6", "TC7C": "CPU Core 7", "TC8C": "CPU Core 8",
        "TCGC": "CPU Graphics", "TCSA": "CPU System Agent", "TCXC": "CPU PECI", "TCXc": "CPU PECI",
        "TG0D": "GPU Die", "TG0H": "GPU Heatsink", "TG0P": "GPU Proximity", "TG1D": "GPU 2 Die", "TG1H": "GPU 2 Heatsink",
        "TH0A": "SSD A", "TH0B": "SSD B", "TH0P": "Storage Proximity", "TH0F": "Storage F", "TH0V": "Storage V",
        "TM0P": "Memory Proximity", "TM0S": "Memory Slot 1", "TM1S": "Memory Slot 2",
        "TN0D": "Northbridge Die", "TN0H": "Northbridge Heatsink", "TN0P": "Northbridge Proximity",
        "TB0T": "Battery 1", "TB1T": "Battery 2", "TB2T": "Battery 3",
        "TTLD": "Thunderbolt Left", "TTRD": "Thunderbolt Right",
        "Th0H": "Heatpipe 1", "Th1H": "Heatpipe 2", "Th2H": "Heatpipe 3",
        "Ts0P": "Palm Rest", "Ts0S": "Palm Rest 2", "Ts1P": "Palm Rest 3", "Ts1S": "Palm Rest 4",
        "TL0P": "Display", "TW0P": "Wi-Fi", "TPCD": "PCH Die", "Tp0P": "Power Supply Proximity",
    ]

    static let common: [String: String] = [
        // Fans
        "FNum": "Fan Count", "F0Ac": "Fan 1 Speed", "F1Ac": "Fan 2 Speed",
        // Power and electrical
        "PSTR": "System Total Power", "PDTR": "DC In Power", "PPBR": "Battery Power", "PC0C": "CPU Core Power",
        "PCPC": "CPU Package Power", "PCPG": "CPU Package GPU Power", "PCTR": "CPU Total Power", "PG0C": "GPU Power",
        "PCPT": "CPU Power", "PHPC": "Heatsink Power", "PM0R": "Memory Power",
        "VD0R": "DC In Voltage", "ID0R": "DC In Current",
        // Counts
        "#KEY": "Key Count",
    ]
}
