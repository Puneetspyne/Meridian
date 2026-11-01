import Foundation
import MeridianKit

/// Temperatures, fans and total system power from the SMC. The key list is enumerated once; each sample then
/// reads only the temperature keys, which is a handful of microsecond-scale calls.
public final class SMCSampler: @unchecked Sendable {
    public let connection: SMCConnection?
    private var activeKeys: [String]?
    private var strikes = 0
    private var fanKeys: [(index: Int, name: String?)]?
    private let lock = NSLock()

    public init(connection: SMCConnection? = SMCConnection()) {
        self.connection = connection
    }

    private static let temperatureTypes: Set<String> = ["flt", "sp78", "sp87", "sp96", "spa5", "spb4", "sp69", "fpe2"]

    /// Walks all ~1600 keys once (about 0.4 s) and keeps the "T" keys that decode to a sane temperature right now.
    /// Each SMC read is a round trip to the SMC firmware, so every later tick reads only this short list.
    /// Keys that report the exact same float as an earlier key in their group are aliases of one sensor
    /// (Th04/Th05 on M2) and are dropped, which removes a fifth of the reads for no loss of information.
    private func discover(_ connection: SMCConnection) -> [String] {
        var live: [String] = []
        var seen = Set<String>()
        for key in connection.allKeys() where key.hasPrefix("T") {
            guard let r = reading(raw: connection.read(key), key: key) else { continue }
            let signature = "\(r.group.rawValue)/\(r.celsius)"
            if seen.insert(signature).inserted { live.append(key) }
        }
        return live
    }

    private func reading(raw: SMCKeyValue?, key: String) -> TemperatureReading? {
        guard let raw, let c = raw.value, c > 0, c <= 130,
              Self.temperatureTypes.contains(raw.type.trimmingCharacters(in: .whitespaces)) else { return nil }
        return TemperatureReading(id: key, name: SensorCatalog.name(forSMCKey: key), celsius: c,
                                  group: SensorCatalog.group(forSMCKey: key))
    }

    /// Never rescans the key list per sample. It is rediscovered only after three consecutive passes where
    /// most reads fail outright (the SMC connection went stale, for example after sleep).
    public func temperatures() -> [TemperatureReading] {
        lock.lock(); defer { lock.unlock() }
        guard let connection else { return [] }
        if activeKeys == nil { activeKeys = discover(connection) }
        var readings: [TemperatureReading] = []
        var failed = 0
        for key in activeKeys ?? [] {
            let raw = connection.read(key)
            if raw == nil { failed += 1; continue }
            if let r = reading(raw: raw, key: key) { readings.append(r) }
        }
        let total = activeKeys?.count ?? 0
        strikes = (total > 0 && failed * 2 > total) ? strikes + 1 : 0
        if strikes >= 3 { activeKeys = nil; strikes = 0 }
        return readings
    }

    public func fans() -> [FanReading] {
        lock.lock(); defer { lock.unlock() }
        guard let connection else { return [] }
        if fanKeys == nil {
            let count = Int(connection.read("FNum")?.value ?? 0)
            fanKeys = (0..<min(max(count, 0), 8)).map { ($0, connection.read("F\($0)ID")?.text) }
        }
        return (fanKeys ?? []).compactMap { fan in
            let i = fan.index
            guard let rpm = connection.read("F\(i)Ac")?.value, rpm >= 0 else { return nil }
            return FanReading(id: "F\(i)", name: fan.name ?? "Fan \(i + 1)", rpm: rpm,
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
