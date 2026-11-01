import Foundation

/// BEST EFFORT, read-only. Codex CLI writes rollout files to ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl while it
/// runs. A file modified in the last 30 s is shown as "working". There is no needs-you or done signal for Codex.
public struct CodexMonitor {
    public static let activeWindow: TimeInterval = 30
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    public var isAvailable: Bool { FileManager.default.fileExists(atPath: root.path) }

    public func scan(now: Date = Date()) -> [AgentSession] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        var sessions: [AgentSession] = []
        for back in 0...1 { // today and yesterday cover a run that crosses midnight; avoids walking the whole history
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      now.timeIntervalSince(m) <= Self.activeWindow else { continue }
                let cwd = Self.cwd(inRollout: f)
                sessions.append(AgentSession(
                    id: "codex-" + f.deletingPathExtension().lastPathComponent,
                    name: cwd.map { SessionTracker.displayName(cwd: $0) } ?? "Codex",
                    cwd: cwd, state: .working, source: .codex, lastEventAt: m, startedAt: m,
                    turnStartedAt: m, lastToolName: "Codex"))
            }
        }
        return sessions
    }

    /// The first rollout line is a session_meta record that carries the working directory.
    static func cwd(inRollout url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 16 * 1024),
              let nl = data.firstIndex(of: 0x0A) ?? Optional(data.endIndex),
              let obj = (try? JSONSerialization.jsonObject(with: data[data.startIndex..<nl])) as? [String: Any] else { return nil }
        let payload = obj["payload"] as? [String: Any]
        return (payload?["cwd"] as? String) ?? (obj["cwd"] as? String)
    }
}
