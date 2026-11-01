import Foundation
import MeridianKit

/// Temperatures, fans and total system power from the SMC. The key list is enumerated once; each sample then
/// reads only the temperature keys, which is a handful of microsecond-scale calls.
public final class SMCSampler: @unchecked Sendable {
    public let connection: SMCConnection?
    private var temperatureKeys: [String]?
    private var activeKeys: [String] = []
    private var passes = 0
    private var fanCount: Int?
    private let lock = NSLock()

    public init(connection: SMCConnection? = SMCConnection()) {
        self.connection = connection
    }

    private func loadTemperatureKeys() -> [String] {
        if let temperatureKeys { return temperatureKeys }
        let keys = (connection?.allKeys() ?? []).filter { $0.hasPrefix("T") }
        temperatureKeys = keys
        return keys
    }

    /// Each SMC read costs a round trip to the SMC firmware (about a quarter of a millisecond on M2), and roughly
    /// a third of the "T" keys never yield a usable temperature. A full pass finds the live ones; the following
    /// samples read only those, and a full pass repeats every few minutes in case a sensor wakes up.
    public func temperatures() -> [TemperatureReading] {
        lock.lock(); defer { lock.unlock() }
        guard let connection else { return [] }
        let fullPass = passes % 120 == 0
        passes += 1
        var readings: [TemperatureReading] = []
        for key in fullPass ? loadTemperatureKeys() : activeKeys {
            guard let raw = connection.read(key), let c = raw.value, c > 0, c <= 130 else { continue }
            // Only temperature-shaped types: a "T" key holding something else must not show as degrees.
            guard ["flt", "sp78", "sp87", "sp96", "spa5", "spb4", "sp69", "fpe2"].contains(raw.type.trimmingCharacters(in: .whitespaces)) else { continue }
            readings.append(TemperatureReading(id: key, name: SensorCatalog.name(forSMCKey: key), celsius: c,
                                               group: SensorCatalog.group(forSMCKey: key)))
        }
        if fullPass { activeKeys = readings.map(\.id) }
        return readings
    }

    public func fans() -> [FanReading] {
        lock.lock(); defer { lock.unlock() }
        guard let connection else { return [] }
        if fanCount == nil { fanCount = Int(connection.read("FNum")?.value ?? 0) }
        guard let count = fanCount, count > 0 else { return [] }
        return (0..<min(count, 8)).compactMap { i in
            guard let rpm = connection.read("F\(i)Ac")?.value, rpm >= 0 else { return nil }
            let name = connection.read("F\(i)ID")?.text ?? "Fan \(i + 1)"
            return FanReading(id: "F\(i)", name: name, rpm: rpm,
                              minRPM: connection.read("F\(i)Mn")?.value,
                              maxRPM: connection.read("F\(i)Mx")?.value,
                              targetRPM: connection.read("F\(i)Tg")?.value)
        }
    }

    /// System total power in watts when the machine exposes PSTR.
    public func systemWatts() -> Double? {
        guard let connection, let w = connection.read("PSTR")?.value, w >= 0, w < 1000 else { return nil }
        return w
    }
}
