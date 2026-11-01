import Foundation

public enum HooksStatus: String, Sendable, Equatable {
    case installed, partial, notInstalled
}

public enum HooksInstallerError: Error, Equatable, CustomStringConvertible {
    case unreadableSettings(String)
    public var description: String {
        switch self {
        case .unreadableSettings(let why): return "Claude settings.json is not valid JSON (\(why)); Meridian left it untouched."
        }
    }
}

/// Merges Meridian's hook entries into Claude Code's settings.json, preserving everything else.
public struct HooksInstaller {
    /// Events Meridian listens to. No matcher is set, so each fires for every tool / notification type.
    public static let events = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Elicitation", "ElicitationResult",
        "Notification", "Stop", "StopFailure", "SubagentStop", "SessionEnd",
    ]

    public let settingsURL: URL
    public let scriptURL: URL
    public var backupURL: URL { settingsURL.appendingPathExtension("meridian-backup") }

    public init(settingsURL: URL = HooksInstaller.defaultSettingsURL, scriptURL: URL) {
        self.settingsURL = settingsURL
        self.scriptURL = scriptURL
    }

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The command string Claude runs: the absolute script path, single-quoted only if it needs quoting.
    public var command: String {
        let p = scriptURL.path
        let safe = p.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "/._-+".unicodeScalars.contains($0) }
        return safe ? p : "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: status

    public func status() -> HooksStatus {
        guard let root = try? readSettings() else { return .notInstalled }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let present = Self.events.filter { containsOurs(hooks[$0]) }.count
        if present == 0 { return .notInstalled }
        return present == Self.events.count ? .installed : .partial
    }

    // MARK: install / uninstall

    /// Returns true when the file changed.
    @discardableResult
    public func install() throws -> Bool {
        var root = try readSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in Self.events where !containsOurs(hooks[event]) {
            var groups = hooks[event] as? [Any] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 5] as [String: Any]]] as [String: Any])
            hooks[event] = groups
            changed = true
        }
        guard changed else { return false }
        root["hooks"] = hooks
        try write(root)
        return true
    }

    /// Removes only entries whose command points at our script. Returns true when the file changed.
    @discardableResult
    public func uninstall() throws -> Bool {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return false }
        var root = try readSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return false }
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            for g in groups {
                guard var group = g as? [String: Any], let handlers = group["hooks"] as? [Any] else { kept.append(g); continue }
                let remaining = handlers.filter { !isOurs($0) }
                if remaining.count == handlers.count { kept.append(g); continue }
                changed = true
                if !remaining.isEmpty { group["hooks"] = remaining; kept.append(group) }
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        guard changed else { return false }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try write(root)
        return true
    }

    // MARK: helpers

    private func isOurs(_ handler: Any) -> Bool {
        guard let h = handler as? [String: Any], let c = h["command"] as? String else { return false }
        return c.contains(scriptURL.path)
    }

    private func containsOurs(_ value: Any?) -> Bool {
        guard let groups = value as? [Any] else { return false }
        for g in groups {
            if let group = g as? [String: Any], let handlers = group["hooks"] as? [Any], handlers.contains(where: isOurs) { return true }
        }
        return false
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return [:] }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HooksInstallerError.unreadableSettings("top level is not an object")
            }
            return obj
        } catch let e as HooksInstallerError {
            throw e
        } catch {
            throw HooksInstallerError.unreadableSettings(error.localizedDescription)
        }
    }

    private func write(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            try Data(contentsOf: settingsURL).write(to: backupURL, options: .atomic)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic)
    }
}
