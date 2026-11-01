import Foundation
import MeridianKit

/// Coding-agent sessions as signals. Claude Code via opt-in hooks; Codex CLI best effort, read-only.
///
/// Nothing is written to ~/.claude until the user opts in (the settings UI posts `meridian.agents.install`).
@MainActor
public final class AgentsProvider: SignalProvider {
    public static let installNotification = Notification.Name("meridian.agents.install")

    public let providerID = "agents"
    public private(set) var signals: [Signal] = []
    /// All visible sessions (including dimmed idle ones) for the UI strip.
    public private(set) var sessions: [AgentSession] = []
    public var onChange: (@MainActor () -> Void)?

    private var settings: ModuleSettings
    private let supportDirectory: URL
    private let installer: HooksInstaller
    private let reader: EventReader
    private let codex: CodexMonitor
    private var tracker = SessionTracker()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var started = false
    private var tick = 0
    private var codexSessions: [AgentSession] = []

    public init(settings: ModuleSettings, supportDirectory: URL? = nil, claudeSettingsURL: URL? = nil, codex: CodexMonitor = CodexMonitor()) {
        self.settings = settings
        let dir = supportDirectory ?? Paths.supportDirectory
        self.supportDirectory = dir
        let script = dir.appendingPathComponent("hooks").appendingPathComponent(HookScript.fileName)
        self.installer = HooksInstaller(settingsURL: claudeSettingsURL ?? HooksInstaller.defaultSettingsURL, scriptURL: script)
        self.reader = EventReader(url: dir.appendingPathComponent(HookScript.eventsFileName))
        self.codex = codex
    }

    public var hooksStatus: HooksStatus { installer.status() }

    /// Enabled by the setting, and by hooks (or a Codex sessions folder to read).
    public var isActive: Bool {
        settings.agentsEnabled && (hooksStatus != .notInstalled || codex.isAvailable)
    }

    // MARK: SignalProvider

    public func start() {
        started = true
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: Self.installNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { try? self?.installHooks() }
            }
        }
        reconfigure()
    }

    public func stop() {
        started = false
        timer?.invalidate(); timer = nil
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
    }

    public func apply(_ settings: ModuleSettings) {
        self.settings = settings
        if started { reconfigure() }
    }

    // MARK: user actions

    public func dismiss(sessionID: String) {
        tracker.dismiss(sessionID)
        codexSessions.removeAll { $0.id == sessionID }
        refresh()
    }

    /// Writes the hook script and merges the entries into ~/.claude/settings.json (backup first).
    public func installHooks() throws {
        try HookScript.write(toDirectory: supportDirectory.appendingPathComponent("hooks"))
        try installer.install()
        if started { reconfigure() }
    }

    /// Removes only Meridian's entries. The script and event log stay on disk; see docs/AGENTS.md.
    public func uninstallHooks() throws {
        try installer.uninstall()
        if started { reconfigure() }
    }

    // MARK: engine

    private func reconfigure() {
        timer?.invalidate(); timer = nil
        guard isActive else {
            tracker = SessionTracker(); codexSessions = []
            publish(sessions: [], now: Date())
            return
        }
        loadNameOverrides()
        pollEvents()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollEvents() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func loadNameOverrides() {
        let url = supportDirectory.appendingPathComponent("agent-names.json")
        if let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: String].self, from: data) {
            tracker.nameOverrides = map
        }
    }

    private func pollEvents() {
        let now = Date()
        tick += 1
        for e in reader.poll() { tracker.apply(e) }
        reader.rotateIfNeeded()
        if tick % 60 == 0 { tracker.prune(now: now); loadNameOverrides() }
        if tick % 2 == 0 || codexSessions.isEmpty && tick == 1 { codexSessions = codex.scan(now: now) }
        refresh(now: now)
    }

    private func refresh(now: Date = Date()) {
        var all = tracker.sessions(now: now)
        let known = Set(all.map(\.id))
        all += codexSessions.filter { !known.contains($0.id) && now.timeIntervalSince($0.lastEventAt) <= CodexMonitor.activeWindow }
        publish(sessions: all, now: now)
    }

    private func publish(sessions new: [AgentSession], now: Date) {
        let newSignals = AgentSignals.signals(for: new, now: now)
        let changed = newSignals != signals || new != sessions
        sessions = new
        signals = newSignals
        if changed { onChange?() }
    }
}
