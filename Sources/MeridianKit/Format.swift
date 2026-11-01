import Foundation

public enum TemperatureUnit: String, Sendable, Codable, CaseIterable {
    case celsius, fahrenheit
}

/// Every number the user sees goes through here so the notch, the card and the menu bar agree.
public enum Format {
    /// Decimal units, as Finder and Activity Monitor show them.
    public static func bytes(_ bytes: UInt64, decimals: Int? = nil) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let places = decimals ?? (unit == 0 ? 0 : (value < 10 ? 1 : 0))
        return "\(trim(value, places)) \(units[unit])"
    }

    public static func bytes(_ bytes: Double) -> String { Self.bytes(UInt64(max(0, bytes))) }

    public static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1000 { return "\(Int(bytesPerSec)) B/s" }
        let units = ["KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec / 1000
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return "\(trim(value, value < 10 ? 1 : 0)) \(units[unit])"
    }

    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        "\(trim(fraction * 100, decimals))%"
    }

    /// Percent of a multi-core budget: a process at 3.2 cores on an 8-core Mac is 40%.
    public static func percent(_ cores: Double, of coreCount: Int) -> String {
        guard coreCount > 0 else { return percent(cores) }
        return percent(cores / Double(coreCount))
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit, decimals: Int = 0) -> String {
        switch unit {
        case .celsius: return "\(trim(celsius, decimals))°"
        case .fahrenheit: return "\(trim(celsius * 9 / 5 + 32, decimals))°"
        }
    }

    public static func temperatureWithUnit(_ celsius: Double, unit: TemperatureUnit) -> String {
        temperature(celsius, unit: unit) + (unit == .celsius ? "C" : "F")
    }

    public static func watts(_ w: Double) -> String {
        w < 10 ? "\(trim(w, 1)) W" : "\(trim(w, 0)) W"
    }

    public static func rpm(_ rpm: Double) -> String { "\(Int(rpm.rounded())) rpm" }

    public static func frequency(_ mhz: Double) -> String {
        mhz >= 1000 ? "\(trim(mhz / 1000, 2)) GHz" : "\(Int(mhz)) MHz"
    }

    /// "1h 12m", "48m", "under a minute".
    public static func minutes(_ minutes: Int) -> String {
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Compact countdown for the notch: "1:20", "12:04", "1:02:33".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.towardZero))
        let sign = total < 0 ? "-" : ""
        let t = abs(total)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%@%d:%02d:%02d", sign, h, m, s) }
        return String(format: "%@%d:%02d", sign, m, s)
    }

    /// Relative phrasing for the card: "in 1m 20s", "now", "2m ago".
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let delta = date.timeIntervalSince(now)
        if abs(delta) < 30 { return "now" }
        let t = Int(abs(delta))
        let text: String
        if t < 3600 {
            let m = t / 60, s = t % 60
            text = m == 0 ? "\(s)s" : (s == 0 || m >= 10 ? "\(m)m" : "\(m)m \(s)s")
        } else if t < 86_400 {
            let h = t / 3600, m = (t % 3600) / 60
            text = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        } else {
            text = "\(t / 86_400)d"
        }
        return delta > 0 ? "in \(text)" : "\(text) ago"
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        let d = t / 86_400, h = (t % 86_400) / 3600, m = (t % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func trim(_ value: Double, _ decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", value)
        return s == "-0" ? "0" : s
    }
}
