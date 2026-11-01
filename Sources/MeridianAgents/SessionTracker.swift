import Foundation

public enum AgentState: String, Sendable, Equatable {
    case working, needsYou, done
    /// A working session with no event for 90 s. Derived at read time; shown dimmed, never a signal.
    case idle
}

public enum AgentSource: String, Sendable, Equatable {
    case claudeCode
    /// Best effort: inferred from rollout file modification times only.
    case codex
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cwd: String?
    public var state: AgentState
    public var source: AgentSource = .claudeCode
    public var lastEventAt: Date
    public var startedAt: Date
    public var turnStartedAt: Date?
    public var lastToolName: String?
    public var needsReason: String?
    public var needsSince: Date?
    public var doneAt: Date?
    /// Length of the last finished turn.
    public var lastTurnDuration: TimeInterval?
    public var dismissed = false

    /// Deep link into the Claude desktop app. If it is not installed the UI shows `cwd` instead.
    public var actionURL: URL? {
        guard source == .claudeCode else { return nil }
        return URL(string: "claude://resume?session=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)")
    }
}

/// Pure state machine: feed it events with their own timestamps, ask it for sessions at a given `now`.
public struct SessionTracker: Sendable {
    public static let idleAfter: TimeInterval = 90
    public static let doneLifetime: TimeInterval = 600
    /// Sessions that never sent SessionEnd (killed terminal) are dropped after this long without events.
    public static let maxAge: TimeInterval = 6 * 3600

    /// Title overrides keyed by session id, full cwd, or last path component.
    public var nameOverrides: [String: String] = [:]
    private var store: [String: AgentSession] = [:]

    public init() {}

    public static func displayName(cwd: String?) -> String {
        guard var c = cwd else { return "Claude" }
        while c.count > 1, c.hasSuffix("/") { c.removeLast() }
        let last = c.split(separator: "/").last.map(String.init) ?? ""
        return last.isEmpty ? "Claude" : last
    }

    /// Notification messages and types that mean the user must act.
    public static func notificationNeedsUser(message: String?, type: String?) -> Bool {
        if let t = type, ["permission_prompt", "idle_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"].contains(t) {
            return true
        }
        let m = (message ?? "").lowercased()
        return ["permission", "needs your", "waiting for your input", "idle"].contains { m.contains($0) }
    }

    public mutating func apply(_ e: AgentEvent) {
        if e.name == "SessionEnd" { store.removeValue(forKey: e.sessionID); return }

        let known = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
                     "Elicitation", "ElicitationResult", "Notification", "Stop", "StopFailure", "SubagentStop"]
        guard known.contains(e.name) else { return }

        var s = store[e.sessionID] ?? AgentSession(
            id: e.sessionID, name: "", cwd: e.cwd, state: .working, lastEventAt: e.ts, startedAt: e.ts)
        if let cwd = e.cwd { s.cwd = cwd }
        s.name = resolveName(id: e.sessionID, cwd: s.cwd)
        s.lastEventAt = max(s.lastEventAt, e.ts)

        func startTurnIfNeeded() {
            if s.state == .done || s.turnStartedAt == nil { s.turnStartedAt = e.ts }
        }
        func clearNeeds() { s.needsReason = nil; s.needsSince = nil }
        func needsYou(_ reason: String) {
            if s.state != .needsYou { s.needsSince = e.ts }
            s.state = .needsYou
            s.needsReason = reason
            s.doneAt = nil
        }

        switch e.name {
        case "UserPromptSubmit":
            s.state = .working; s.turnStartedAt = e.ts; s.doneAt = nil; clearNeeds()
        case "PreToolUse":
            if let t = e.toolName { s.lastToolName = t }
            if s.state != .needsYou { startTurnIfNeeded(); s.state = .working; s.doneAt = nil }
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied", "ElicitationResult":
            if let t = e.toolName { s.lastToolName = t }
            startTurnIfNeeded(); s.state = .working; s.doneAt = nil; clearNeeds()
        case "PermissionRequest":
            if let t = e.toolName { s.lastToolName = t }
            needsYou(e.toolName.map { "Needs permission to use \($0)" } ?? "Needs your permission")
        case "Elicitation":
            needsYou(e.message ?? "Needs your input")
        case "Notification":
            if Self.notificationNeedsUser(message: e.message, type: e.notificationType) {
                needsYou(e.message ?? "Needs your attention")
            }
        case "Stop", "StopFailure":
            if let start = s.turnStartedAt { s.lastTurnDuration = max(0, e.ts.timeIntervalSince(start)) }
            s.state = .done; s.doneAt = e.ts; clearNeeds()
        default: // SubagentStop: liveness only
            break
        }
        if e.name != "SubagentStop", e.name != "Notification" || s.state == .needsYou { s.dismissed = false }
        store[e.sessionID] = s
    }

    public mutating func dismiss(_ id: String) { store[id]?.dismissed = true }

    public mutating func prune(now: Date) {
        store = store.filter { now.timeIntervalSince($0.value.lastEventAt) <= Self.maxAge }
    }

    /// Visible sessions at `now`: idle derived, expired and dismissed done sessions removed. Needs-you first, then recency.
    public func sessions(now: Date) -> [AgentSession] {
        var out: [AgentSession] = []
        for var s in store.values {
            if now.timeIntervalSince(s.lastEventAt) > Self.maxAge { continue }
            if s.dismissed { continue }
            switch s.state {
            case .done:
                if let d = s.doneAt, now.timeIntervalSince(d) > Self.doneLifetime { continue }
            case .working:
                if now.timeIntervalSince(s.lastEventAt) > Self.idleAfter { s.state = .idle }
            default: break
            }
            out.append(s)
        }
        func rank(_ s: AgentSession) -> Int { switch s.state { case .needsYou: 0; case .working: 1; case .done: 2; case .idle: 3 } }
        return out.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : ($0.lastEventAt, $0.id) > ($1.lastEventAt, $1.id) }
    }

    private func resolveName(id: String, cwd: String?) -> String {
        if let n = nameOverrides[id] { return n }
        if let cwd, let n = nameOverrides[cwd] { return n }
        let base = Self.displayName(cwd: cwd)
        return nameOverrides[base] ?? base
    }
}
