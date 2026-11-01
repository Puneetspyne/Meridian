import Foundation

/// One parsed line of claude-events.jsonl. Only the fields Meridian needs; tool inputs are deliberately dropped.
public struct AgentEvent: Equatable, Sendable {
    public var ts: Date
    public var name: String
    public var sessionID: String
    public var cwd: String?
    public var message: String?
    public var notificationType: String?
    public var toolName: String?

    public init(ts: Date, name: String, sessionID: String, cwd: String? = nil, message: String? = nil,
                notificationType: String? = nil, toolName: String? = nil) {
        self.ts = ts; self.name = name; self.sessionID = sessionID; self.cwd = cwd
        self.message = message; self.notificationType = notificationType; self.toolName = toolName
    }

    /// Tolerant: returns nil for malformed JSON or lines without a session id.
    public static func parse(line: String) -> AgentEvent? {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let payload = root["payload"] as? [String: Any] ?? [:]
        guard let sid = payload["session_id"] as? String, !sid.isEmpty else { return nil }
        let name = (root["event"] as? String) ?? (payload["hook_event_name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let ts = (root["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        func str(_ k: String) -> String? { (payload[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return AgentEvent(ts: Date(timeIntervalSince1970: ts), name: name, sessionID: sid, cwd: str("cwd"),
                          message: str("message"), notificationType: str("notification_type"), toolName: str("tool_name"))
    }
}
