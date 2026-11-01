import Foundation
import MeridianKit
import MeridianSensors

enum Commands {
    /// Rates and power are deltas, so a one-shot snapshot takes a baseline, waits briefly, then samples again.
    static func snapshot() async {
        let source = LiveTelemetrySource()
        _ = try? await source.sample()
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard let snapshot = try? await source.sample() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) { print(String(decoding: data, as: UTF8.self)) }
    }

    static func watch(count: Int?) async {
        let source = LiveTelemetrySource()
        var n = 0
        while count == nil || n < count! {
            if let s = try? await source.sample() { print(line(for: s)); fflush(stdout) }
            n += 1
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private static func line(for s: TelemetrySnapshot) -> String {
        var parts: [String] = []
        if let c = s.cpu { parts.append("cpu \(pct(c.total)) (u \(pct(c.user)) s \(pct(c.system)))") }
        if let m = s.memory { parts.append("mem \(pct(m.usedFraction)) \(m.pressure.rawValue)") }
        if let g = s.gpu?.utilization { parts.append("gpu \(pct(g))") }
        if let n = s.network { parts.append("net \(n.interfaceName ?? "-") down \(Format.rate(n.rxBytesPerSec)) up \(Format.rate(n.txBytesPerSec))") }
        if let d = s.bootDisk { parts.append("disk r \(Format.rate(d.readBytesPerSec)) w \(Format.rate(d.writeBytesPerSec))") }
        if let b = s.battery, b.isPresent {
            parts.append("bat \(pct(b.level))\(b.isCharging ? "+" : "")\(b.watts.map { String(format: " %.1fW", $0) } ?? "")")
        }
        if let t = s.thermal {
            if let cpu = t.cpuCelsius { parts.append(String(format: "cpuT %.0fC", cpu)) }
            if let hot = t.hottestCelsius { parts.append(String(format: "max %.0fC", hot)) }
            parts.append("therm \(t.pressure.rawValue)")
        }
        if let p = s.power {
            if p.source == "unavailable" { parts.append("power n/a") }
            else {
                var w = "power \(p.source)"
                if let v = p.cpuWatts { w += String(format: " cpu %.1fW", v) }
                if let v = p.gpuWatts { w += String(format: " gpu %.1fW", v) }
                if let v = p.totalWatts { w += String(format: " tot %.1fW", v) }
                parts.append(w)
            }
        }
        if let top = s.processes.first { parts.append("top \(top.name) \(pct(top.cpuFraction))") }
        return parts.joined(separator: " | ")
    }

    private static func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    static func sensors() {
        let readings = SensorProbe.temperatures()
        if readings.isEmpty { print("no temperature sensors available"); return }
        print(pad("SOURCE", 7) + pad("GROUP", 9) + pad("TEMP", 8) + pad("ID", 34) + "NAME")
        for r in readings.sorted(by: { ($0.group.rawValue, $0.id) < ($1.group.rawValue, $1.id) }) {
            let source = r.id.hasPrefix("hid:") ? "hid" : "smc"
            print(pad(source, 7) + pad(r.group.rawValue, 9) + pad(String(format: "%.1fC", r.celsius), 8) + pad(r.id, 34) + r.name)
        }
        print("\n\(readings.count) sensors")
    }

    static func smcKeys() {
        let keys = SensorProbe.dumpSMC()
        if keys.isEmpty { print("AppleSMC not available"); return }
        print(pad("KEY", 6) + pad("TYPE", 6) + pad("SIZE", 5) + pad("VALUE", 14) + pad("RAW", 40) + "NAME")
        for k in keys {
            let value = k.value.map { String(format: "%g", $0) } ?? k.text ?? "-"
            print(pad(k.key, 6) + pad(k.type, 6) + pad(String(k.size), 5) + pad(value, 14) + pad(k.rawHex, 40) + (k.name == k.key ? "" : k.name))
        }
    }

    private struct Contribution: Codable {
        var tool = "meridianctl contribute"
        var format = 1
        var chip: String
        var model: String
        var macOS: String
        var isAppleSilicon: Bool
        var hid: [HIDSensorDump]
        var smc: [SMCKeyDump]
    }

    /// Hostname and other identifying fields are deliberately left out so the file is safe to attach to a public PR.
    static func contribute(arguments: [String]) {
        let info = SensorProbe.systemInfo()
        let slug = info.chipName.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        var path = ("~/Desktop/meridian-sensors-\(slug).json" as NSString).expandingTildeInPath
        if let i = arguments.firstIndex(of: "--out"), i + 1 < arguments.count {
            path = (arguments[i + 1] as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                path = (path as NSString).appendingPathComponent("meridian-sensors-\(slug).json")
            }
        }
        let payload = Contribution(chip: info.chipName, model: info.modelIdentifier, macOS: info.macOSVersion,
                                   isAppleSilicon: info.isAppleSilicon, hid: SensorProbe.dumpHID(), smc: SensorProbe.dumpSMC())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(payload).write(to: URL(fileURLWithPath: path))
            print("wrote \(path): \(payload.hid.count) HID sensors, \(payload.smc.count) SMC keys")
            print("Open a pull request adding it under docs/sensor-maps/ (see docs/SENSORS.md).")
        } catch {
            FileHandle.standardError.write(Data("could not write \(path): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s + " " : s + String(repeating: " ", count: width - s.count)
    }
}
