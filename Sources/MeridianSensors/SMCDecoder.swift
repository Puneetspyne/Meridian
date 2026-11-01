import Foundation

/// Decoders for the SMC's data types. Pure functions so they can be tested with byte fixtures.
///
/// Multi-byte integers and fixed-point values are big-endian. `flt` and `ioft` are little-endian because the
/// Apple silicon SMC returns them in host order.
public enum SMCDecoder {
    public static func decode(type rawType: String, bytes: [UInt8]) -> Double? {
        let type = rawType.trimmingCharacters(in: .whitespaces)
        switch type {
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "ui8":
            return bytes.first.map { Double($0) }
        case "ui16":
            return bigEndian(bytes, width: 2).map { Double($0) }
        case "ui32":
            return bigEndian(bytes, width: 4).map { Double($0) }
        case "ui64":
            return bigEndian(bytes, width: 8).map { Double($0) }
        case "si8":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "si16":
            return bigEndian(bytes, width: 2).map { Double(Int16(bitPattern: UInt16($0))) }
        case "si32":
            return bigEndian(bytes, width: 4).map { Double(Int32(bitPattern: UInt32($0))) }
        case "ioft":
            // 48.16 fixed point: used for fan speeds on recent machines.
            guard bytes.count >= 8 else { return nil }
            var raw: UInt64 = 0
            for i in (0..<8).reversed() { raw = (raw << 8) | UInt64(bytes[i]) }
            return Double(raw) / 65536
        case "flag":
            return bytes.first.map { $0 != 0 ? 1 : 0 }
        default:
            return fixedPoint(type: type, bytes: bytes)
        }
    }

    /// `fpXY` is unsigned and `spXY` signed 16-bit; the last hex digit is the number of fractional bits
    /// (sp78 = 8, fpe2 = 2, fp1f = 15).
    private static func fixedPoint(type: String, bytes: [UInt8]) -> Double? {
        guard type.count == 4, bytes.count >= 2,
              let fractionBits = Int(String(type.last!), radix: 16) else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let divisor = Double(1 << fractionBits)
        if type.hasPrefix("fp") { return Double(raw) / divisor }
        if type.hasPrefix("sp") { return Double(Int16(bitPattern: raw)) / divisor }
        return nil
    }

    /// `ch8*` and `{fds`-style character data, trimmed of padding and control bytes.
    public static func text(type rawType: String, bytes: [UInt8]) -> String? {
        let type = rawType.trimmingCharacters(in: .whitespaces)
        guard type.hasPrefix("ch8") || type == "{fds" else { return nil }
        // `{fds` (fan descriptor) carries 4 header bytes before the 12-byte name.
        let body = type == "{fds" ? Array(bytes.dropFirst(4)) : bytes
        let printable = body.prefix(while: { $0 != 0 })
        let s = String(decoding: printable, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func bigEndian(_ bytes: [UInt8], width: Int) -> UInt64? {
        guard bytes.count >= width else { return nil }
        return bytes.prefix(width).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
