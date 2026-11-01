import CMeridian
import Foundation
import IOKit

/// One decoded SMC key as returned by `SMCConnection.read`.
public struct SMCKeyValue: Sendable, Equatable {
    public var key: String
    public var type: String
    public var bytes: [UInt8]
    public var value: Double? { SMCDecoder.decode(type: type, bytes: bytes) }
    public var text: String? { SMCDecoder.text(type: type, bytes: bytes) }
}

/// A connection to the AppleSMC user client. Thread-safe; every call is serialized by a lock because the
/// struct method shares one driver-side buffer.
public final class SMCConnection: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var infoCache: [UInt32: (size: UInt32, type: UInt32)] = [:]

    /// Nil when the SMC is not present (VM) or cannot be opened.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS, connection != 0 else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.size
        let kr = IOConnectCallStructMethod(connection, UInt32(kMeridianSMCUserClientSelector),
                                           &input, MemoryLayout<SMCParamStruct>.size, &output, &outSize)
        // result 0 = ok, 0x84 = key not found. Anything else is treated as a miss.
        guard kr == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    private func keyInfo(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        if let cached = infoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(kMeridianSMCReadKeyInfo)
        guard let out = call(input), out.keyInfo.dataSize > 0 else { return nil }
        let info = (out.keyInfo.dataSize, out.keyInfo.dataType)
        infoCache[key] = info
        return info
    }

    public func read(_ key: String) -> SMCKeyValue? {
        lock.lock(); defer { lock.unlock() }
        return readLocked(FourCC.encode(key))
    }

    private func readLocked(_ code: UInt32) -> SMCKeyValue? {
        guard let info = keyInfo(code) else { return nil }
        var input = SMCParamStruct()
        input.key = code
        input.keyInfo.dataSize = info.size
        input.data8 = UInt8(kMeridianSMCReadBytes)
        guard var out = call(input) else { return nil }
        let size = min(Int(info.size), 32)
        let bytes = withUnsafeMutablePointer(to: &out) { p in Array(UnsafeBufferPointer(start: meridian_smc_bytes(p), count: size)) }
        return SMCKeyValue(key: FourCC.decode(code), type: FourCC.decode(info.type), bytes: bytes)
    }

    /// Number of keys the SMC exposes ("#KEY").
    public func keyCount() -> Int {
        guard let v = read("#KEY"), let n = v.value else { return 0 }
        return Int(n)
    }

    /// The name of the key at `index`.
    public func key(at index: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        var input = SMCParamStruct()
        input.data8 = UInt8(kMeridianSMCReadKeyByIndex)
        input.data32 = UInt32(index)
        guard let out = call(input) else { return nil }
        return FourCC.decode(out.key)
    }

    /// Every key name, in index order. Enumerating is slow-ish (one call per key), so callers cache it.
    public func allKeys() -> [String] {
        let count = keyCount()
        return (0..<count).compactMap { key(at: $0) }
    }
}
