import Foundation
import MeridianKit

/// Pure mapping from sessions to the shared Signal vocabulary.
public enum AgentSignals {
    public static func duration(_ seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded())
        if t < 60 { return "\(t)s" }
        if t < 3600 { return "\(t / 60)m \(t % 60)s" }
        return "\(t / 3600)h \((t % 3600) / 60)m"
    }

    public static func signals(for sessions: [AgentSession], now: Date) -> [Signal] {
        sessions.compactMap { s in
            let id = "agents.session.\(s.id)"
            let url = s.actionURL
            let actionTitle = url == nil ? nil : "Open in Claude"
            switch s.state {
            case .idle:
                return nil
            case .needsYou:
                let since = s.needsSince ?? s.lastEventAt
                return Signal(id: id, kind: .agent, attention: .warning, title: "\(s.name) needs you", detail: s.needsReason,
                              symbol: "sparkles", value: Format.countdown(max(0, now.timeIntervalSince(since))),
                              createdAt: since, priority: 70, tint: .violet, actionURL: url, actionTitle: actionTitle)
            case .working:
                let start = s.turnStartedAt ?? s.startedAt
                let tool = s.lastToolName.map { " · \($0)" } ?? ""
                let note = s.source == .codex ? " (best effort)" : ""
                return Signal(id: id, kind: .agent, attention: .info, title: s.name, detail: "Working\(tool)\(note)",
                              symbol: "sparkles", value: Format.countdown(max(0, now.timeIntervalSince(start))),
                              createdAt: start, priority: s.source == .codex ? 20 : 25, tint: .violet,
                              actionURL: url, actionTitle: actionTitle)
            case .done:
                let at = s.doneAt ?? s.lastEventAt
                let fresh = now.timeIntervalSince(at) < 60
                return Signal(id: id, kind: .agent, attention: fresh ? .info : .calm, title: "\(s.name) done",
                              detail: s.lastTurnDuration.map { "Took \(duration($0))" } ?? "Finished",
                              symbol: "checkmark.circle.fill", createdAt: at, priority: 15, tint: .green,
                              actionURL: url, actionTitle: actionTitle)
            }
        }
    }
}
