import Foundation
import MeridianKit

/// One SMC key with everything needed to understand it, for `meridianctl smc-keys` and `contribute`.
public struct SMCKeyDump: Sendable, Codable, Equatable {
    public var key: String
    public var type: String
    public var size: Int
    public var rawHex: String
    public var value: Double?
    public var text: String?
    public var name: String
    public var group: SensorGroup
}

/// One HID temperature sensor as the kernel names it.
public struct HIDSensorDump: Sendable, Codable, Equatable {
    public var product: String
    public var celsius: Double
    public var name: String
    public var group: SensorGroup
}

/// Diagnostics for contributors. Not used by the app's 1 Hz path.
public enum SensorProbe {
    public static func dumpSMC() -> [SMCKeyDump] {
        guard let smc = SMCConnection() else { return [] }
        return smc.allKeys().compactMap { key in
            guard let v = smc.read(key) else { return nil }
            return SMCKeyDump(key: key, type: v.type, size: v.bytes.count,
                              rawHex: v.bytes.map { String(format: "%02x", $0) }.joined(separator: " "),
                              value: v.value, text: v.text,
                              name: SensorCatalog.name(forSMCKey: key), group: SensorCatalog.group(forSMCKey: key))
        }
    }

    public static func dumpHID() -> [HIDSensorDump] {
        HIDTemperatureSampler().readRaw().map {
            HIDSensorDump(product: $0.name, celsius: $0.celsius, name: SensorCatalog.friendlyName(forHIDName: $0.name),
                          group: SensorCatalog.group(forSensorName: $0.name))
        }
    }

    /// Every temperature the app would show, HID first then SMC, de-duplicated by id.
    public static func temperatures() -> [TemperatureReading] {
        var all = HIDTemperatureSampler().sample()
        let known = Set(all.map(\.id))
        all += SMCSampler().temperatures().filter { !known.contains($0.id) }
        return all
    }

    public static func systemInfo() -> SystemInfo { SystemInfoSampler.read() }
}
