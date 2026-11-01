import Foundation

/// Tails claude-events.jsonl. Remembers a byte offset, only consumes complete lines, survives truncation and
/// rotation (file shrinks or is replaced), and skips malformed lines.
public final class EventReader {
    public let url: URL
    public private(set) var offset: UInt64 = 0
    public private(set) var malformedLineCount = 0
    private var fileID: UInt64?
    /// Rotate (move to `.1`) once the file is larger than this after a read.
    public var rotationLimit: UInt64 = 5 * 1024 * 1024
    private let maxChunk = 16 * 1024 * 1024

    public init(url: URL) { self.url = url }

    /// Reads everything appended since the last call.
    public func poll() -> [AgentEvent] {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            offset = 0; fileID = nil
            return []
        }
        let id = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        if let prev = fileID, let id, prev != id { offset = 0 }   // replaced
        fileID = id
        if size < offset { offset = 0 }                            // truncated
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: min(Int(size - offset), maxChunk)), !data.isEmpty else { return [] }
            // Only complete lines; a partial trailing line waits for the next poll.
            guard let lastNL = data.lastIndex(of: 0x0A) else {
                return []
            }
            let complete = data[data.startIndex...lastNL]
            offset += UInt64(complete.count)
            var events: [AgentEvent] = []
            for raw in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                // Lenient decode: a multi-byte character cut by the script's truncation must not drop the whole event.
                guard let e = AgentEvent.parse(line: String(decoding: raw, as: UTF8.self)) else {
                    malformedLineCount += 1
                    continue
                }
                events.append(e)
            }
            return events
        } catch {
            return []
        }
    }

    /// Call after `poll()`: moves an oversized, fully-read file aside so the log cannot grow without bound.
    @discardableResult
    public func rotateIfNeeded() -> Bool {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.uint64Value > rotationLimit, offset >= size.uint64Value else { return false }
        let old = url.appendingPathExtension("1")
        try? fm.removeItem(at: old)
        guard (try? fm.moveItem(at: url, to: old)) != nil else { return false }
        offset = 0; fileID = nil
        return true
    }
}
