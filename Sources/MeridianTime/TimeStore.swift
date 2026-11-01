import Foundation

/// Everything the time module persists.
public struct TimeState: Codable, Equatable, Sendable {
    public var version = 1
    public var timers: [TimerItem] = []
    public var countdowns: [Countdown] = []
    public var stopwatch: Stopwatch?
    public var todos: [TodoItem] = []

    public init() {}
}

/// JSON persistence at `<directory>/time.json`, written atomically. The directory is injectable for tests.
public struct TimeStore: Sendable {
    public let fileURL: URL

    /// - Parameter directory: where `time.json` lives. Defaults to `Paths.supportDirectory`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("time.json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    /// An empty state when the file is missing or unreadable (a corrupt file must never block launch).
    public func load() -> TimeState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? Self.decoder.decode(TimeState.self, from: data) else { return TimeState() }
        return state
    }

    public func save(_ state: TimeState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
