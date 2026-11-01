import Foundation
import Testing
import MeridianKit
@testable import MeridianAgents

// MARK: helpers

func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-agents-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@discardableResult
func runHook(script: URL, stdin: String, arg: String? = nil, env: [String: String] = [:]) throws -> (out: String, status: Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [script.path] + (arg.map { [$0] } ?? [])
    var e = ProcessInfo.processInfo.environment; e.merge(env) { $1 }
    p.environment = e
    let inp = Pipe(), out = Pipe()
    p.standardInput = inp; p.standardOutput = out
    try p.run()
    inp.fileHandleForWriting.write(Data(stdin.utf8)); try inp.fileHandleForWriting.close()
    p.waitUntilExit()
    return (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "", p.terminationStatus)
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func ev(_ name: String, _ sid: String = "s1", at: TimeInterval = 0, cwd: String? = "/Users/me/my-portfolio/", message: String? = nil,
        type: String? = nil, tool: String? = nil) -> AgentEvent {
    AgentEvent(ts: t0.addingTimeInterval(at), name: name, sessionID: sid, cwd: cwd, message: message, notificationType: type, toolName: tool)
}

// MARK: hook script

@Suite struct HookScriptTests {
    func payloadOf(_ dir: URL, line: Int = 0) throws -> [String: Any] {
        let text = try String(contentsOf: dir.appendingPathComponent("claude-events.jsonl"), encoding: .utf8)
        let lines = text.split(separator: "\n")
        let obj = try #require(JSONSerialization.jsonObject(with: Data(lines[line].utf8)) as? [String: Any])
        return try #require(obj["payload"] as? [String: Any])
    }

    @Test func appendsLineSilentlyAndExitsZero() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try HookScript.write(toDirectory: dir.appendingPathComponent("hooks"))
        let payload = #"{"session_id":"abc-1","cwd":"/tmp/x y","hook_event_name":"Stop","stop_hook_active":false}"#
        let r = try runHook(script: script, stdin: payload + "\n")
        #expect(r.out.isEmpty)
        #expect(r.status == 0)
        let text = try String(contentsOf: dir.appendingPathComponent("claude-events.jsonl"), encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 1)
        let obj = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(obj["event"] as? String == "Stop")
        #expect((obj["ts"] as? Double ?? 0) > 1_700_000_000)
        let pl = try #require(obj["payload"] as? [String: Any])
        #expect(pl["session_id"] as? String == "abc-1" && pl["stop_hook_active"] as? Bool == false)
        let parsed = try #require(AgentEvent.parse(line: String(lines[0])))
        #expect(parsed.name == "Stop" && parsed.cwd == "/tmp/x y")
    }

    @Test func storesOnlyIdentifierFields() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try HookScript.write(toDirectory: dir.appendingPathComponent("hooks"))
        let secret = "SECRET-PROMPT-TEXT"
        try runHook(script: script, stdin: #"{"session_id":"s9","transcript_path":"/Users/me/.claude/projects/x/s9.jsonl","cwd":"/r/app","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"\#(secret) \"cwd\":\"/evil\" tool_name"}"#)
        try runHook(script: script, stdin: #"{"session_id":"s9","cwd":"/r/app","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo SECRET-CMD"},"tool_response":{"stdout":"SECRET-OUT"},"tool_use_id":"t1"}"#)
        try runHook(script: script, stdin: #"{"session_id":"s9","cwd":"/r/app","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"SECRET-REPLY"}"#)
        let text = try String(contentsOf: dir.appendingPathComponent("claude-events.jsonl"), encoding: .utf8)
        for needle in [secret, "SECRET-CMD", "SECRET-OUT", "SECRET-REPLY", "transcript", "/evil", "prompt", "tool_input"] {
            #expect(!text.contains(needle), "leaked \(needle)")
        }
        #expect(Set(try payloadOf(dir, line: 0).keys) == ["session_id", "hook_event_name", "cwd"])
        let post = try payloadOf(dir, line: 1)
        #expect(Set(post.keys) == ["session_id", "hook_event_name", "cwd", "tool_name"] && post["tool_name"] as? String == "Bash")
        let stop = try payloadOf(dir, line: 2)
        #expect(stop["stop_hook_active"] as? Bool == true && stop["message"] == nil)
    }

    @Test func notificationKeepsMessageTruncatedTo200() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try HookScript.write(toDirectory: dir.appendingPathComponent("hooks"))
        // 1: escaped quotes inside a short message
        try runHook(script: script, stdin: #"{"session_id":"n1","cwd":"/p","hook_event_name":"Notification","message":"Claude needs your permission to use \"Bash\"","notification_type":"permission_prompt"}"#)
        // 2: long message
        let long = String(repeating: "a", count: 300)
        try runHook(script: script, stdin: #"{"session_id":"n1","hook_event_name":"Notification","message":"\#(long)"}"#)
        // 3: cut lands in the middle of a backslash escape and of a \u escape
        let edge = String(repeating: "b", count: 199) + #"\n tail"#
        try runHook(script: script, stdin: #"{"session_id":"n1","hook_event_name":"Notification","message":"\#(edge)"}"#)
        let edgeU = String(repeating: "c", count: 197) + #"\u00e9 tail"#
        try runHook(script: script, stdin: #"{"session_id":"n1","hook_event_name":"Notification","message":"\#(edgeU)"}"#)
        // 5: non-ASCII near the cut
        let uni = String(repeating: "é", count: 250)
        try runHook(script: script, stdin: #"{"session_id":"n1","hook_event_name":"Notification","message":"\#(uni)"}"#)

        let m1 = try payloadOf(dir, line: 0)
        #expect(m1["message"] as? String == #"Claude needs your permission to use "Bash""#)
        #expect(m1["notification_type"] as? String == "permission_prompt")
        #expect((try payloadOf(dir, line: 1)["message"] as? String)?.count == 200)
        #expect((try payloadOf(dir, line: 2)["message"] as? String)?.count == 199)   // parsed fine, dangling "\" dropped
        #expect((try payloadOf(dir, line: 3)["message"] as? String)?.count == 197)   // partial \u escape dropped
        let m5 = try #require(try payloadOf(dir, line: 4)["message"] as? String)
        #expect(m5.count <= 200 && m5.hasPrefix("éé"))
        // every stored line still parses as an AgentEvent
        let lines = try String(contentsOf: dir.appendingPathComponent("claude-events.jsonl"), encoding: .utf8).split(separator: "\n")
        #expect(lines.allSatisfy { AgentEvent.parse(line: String($0)) != nil })
    }

    @Test func handlesMultilineAndEmptyInput() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try HookScript.write(toDirectory: dir.appendingPathComponent("hooks"))
        try runHook(script: script, stdin: "{\n \"session_id\":\"m1\",\n \"hook_event_name\":\"Notification\", \"message\":\"a \\\"q\\\" b\"\n}")
        let r = try runHook(script: script, stdin: "")
        #expect(r.status == 0 && r.out.isEmpty)
        let lines = try String(contentsOf: dir.appendingPathComponent("claude-events.jsonl"), encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        let e = try #require(AgentEvent.parse(line: String(lines[0])))
        #expect(e.sessionID == "m1" && e.message == #"a "q" b"#)
        #expect(AgentEvent.parse(line: String(lines[1])) == nil) // no session id: tolerated, dropped
    }

    @Test func exitsZeroEvenWhenLogIsUnwritable() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try HookScript.write(toDirectory: dir.appendingPathComponent("hooks"))
        let r = try runHook(script: script, stdin: #"{"session_id":"a"}"#, env: ["MERIDIAN_EVENTS_FILE": "/nonexistent-dir/x.jsonl"])
        #expect(r.status == 0 && r.out.isEmpty)
    }
}

// MARK: installer

@Suite struct HooksInstallerTests {
    func fixture(_ dir: URL) throws -> (HooksInstaller, URL) {
        let settings = dir.appendingPathComponent("settings.json")
        let existing = #"""
        {"model":"opus","permissions":{"allow":["Bash(ls)"]},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard.sh"}]}],
                  "Stop":[{"hooks":[{"type":"command","command":"say done"}]}],
                  "SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}
        """#
        try existing.write(to: settings, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("Application Support/hooks/claude-hook.sh")
        return (HooksInstaller(settingsURL: settings, scriptURL: script), settings)
    }

    func load(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func mergePreservesEverythingAndIsIdempotent() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (inst, settings) = try fixture(dir)
        let original = try Data(contentsOf: settings)
        #expect(inst.status() == .notInstalled)
        #expect(try inst.install())
        #expect(inst.status() == .installed)
        #expect(try Data(contentsOf: inst.backupURL) == original)

        let root = try load(settings)
        #expect(root["model"] as? String == "opus")
        #expect((root["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(hooks["SessionStart"] != nil)
        #expect((hooks["PreToolUse"] as? [Any])?.count == 2)
        #expect((hooks["Stop"] as? [Any])?.count == 2)
        for e in HooksInstaller.events { #expect(hooks[e] != nil) }
        let group = try #require((hooks["UserPromptSubmit"] as? [[String: Any]])?.first)
        let h = try #require((group["hooks"] as? [[String: Any]])?.first)
        #expect(h["type"] as? String == "command" && h["timeout"] as? Int == 5)
        #expect(h["command"] as? String == "'\(inst.scriptURL.path)'") // path has a space, so it is quoted
        #expect(group["matcher"] == nil)

        let afterFirst = try Data(contentsOf: settings)
        #expect(try inst.install() == false)
        #expect(try Data(contentsOf: settings) == afterFirst)
        // sorted keys, pretty printed
        let text = String(decoding: afterFirst, as: UTF8.self)
        #expect(text.contains("\n  \"hooks\""))
        #expect(try #require(text.range(of: "\"hooks\"")).lowerBound < #require(text.range(of: "\"model\"")).lowerBound)
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (inst, settings) = try fixture(dir)
        try inst.install()
        #expect(try inst.uninstall())
        #expect(inst.status() == .notInstalled)
        let hooks = try #require(load(settings)["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["PreToolUse", "Stop", "SessionStart"])
        #expect((hooks["Stop"] as? [Any])?.count == 1)
        #expect(try inst.uninstall() == false)
    }

    @Test func partialStatusAndMissingFileAndInvalidJSON() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("s.json")
        let inst = HooksInstaller(settingsURL: settings, scriptURL: dir.appendingPathComponent("h/claude-hook.sh"))
        #expect(inst.status() == .notInstalled)
        try inst.install()                         // creates the file
        var root = try load(settings)
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop"); root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: settings)
        #expect(inst.status() == .partial)
        try inst.install()
        #expect(inst.status() == .installed)
        // uninstall on a file that only had our hooks drops the hooks key
        try inst.uninstall()
        #expect(try load(settings)["hooks"] == nil)

        try "{ not json".write(to: settings, atomically: true, encoding: .utf8)
        #expect(throws: HooksInstallerError.self) { try inst.install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ not json")
    }
}

// MARK: tracker

@Suite struct SessionTrackerTests {
    @Test func promptToolStopCycle() {
        var t = SessionTracker()
        t.apply(ev("UserPromptSubmit", at: 0))
        var s = t.sessions(now: t0.addingTimeInterval(1))
        #expect(s.count == 1 && s[0].state == .working && s[0].name == "my-portfolio" && s[0].turnStartedAt == t0)
        #expect(s[0].actionURL?.absoluteString == "claude://resume?session=s1")
        t.apply(ev("PreToolUse", at: 5, tool: "Bash"))
        t.apply(ev("PostToolUse", at: 8, tool: "Bash"))
        t.apply(ev("SubagentStop", at: 9))
        s = t.sessions(now: t0.addingTimeInterval(10))
        #expect(s[0].state == .working && s[0].lastToolName == "Bash")
        t.apply(ev("Stop", at: 192))
        s = t.sessions(now: t0.addingTimeInterval(193))
        #expect(s[0].state == .done && s[0].lastTurnDuration == 192)
    }

    @Test func needsYouAndClearing() {
        var t = SessionTracker()
        t.apply(ev("UserPromptSubmit", at: 0))
        t.apply(ev("PreToolUse", at: 2, tool: "Bash"))
        t.apply(ev("Notification", at: 3, message: "Claude needs your permission to use Bash", type: "permission_prompt"))
        var s = t.sessions(now: t0.addingTimeInterval(4))
        #expect(s[0].state == .needsYou && s[0].needsReason == "Claude needs your permission to use Bash" && s[0].needsSince == t0.addingTimeInterval(3))
        t.apply(ev("PreToolUse", at: 5, tool: "Read"))     // does not clear
        #expect(t.sessions(now: t0.addingTimeInterval(6))[0].state == .needsYou)
        t.apply(ev("Notification", at: 7, message: "Claude is waiting for your input"))
        #expect(t.sessions(now: t0.addingTimeInterval(8))[0].needsSince == t0.addingTimeInterval(3)) // not reset
        t.apply(ev("PostToolUse", at: 20, tool: "Bash"))
        s = t.sessions(now: t0.addingTimeInterval(21))
        #expect(s[0].state == .working && s[0].needsReason == nil)

        t.apply(ev("Notification", at: 22, message: "Authenticated successfully"))  // unrelated
        #expect(t.sessions(now: t0.addingTimeInterval(23))[0].state == .working)
        t.apply(ev("PermissionRequest", at: 24, tool: "Edit"))
        #expect(t.sessions(now: t0.addingTimeInterval(25))[0].needsReason == "Needs permission to use Edit")
        t.apply(ev("Stop", at: 30))
        #expect(t.sessions(now: t0.addingTimeInterval(31))[0].state == .done)
        t.apply(ev("Elicitation", at: 32, message: "Pick one"))
        #expect(t.sessions(now: t0.addingTimeInterval(33))[0].state == .needsYou)
        t.apply(ev("UserPromptSubmit", at: 40))
        #expect(t.sessions(now: t0.addingTimeInterval(41))[0].state == .working)
    }

    @Test func stalenessAndDoneExpiryAndDismiss() {
        var t = SessionTracker()
        t.apply(ev("UserPromptSubmit", "w", at: 0))
        #expect(t.sessions(now: t0.addingTimeInterval(89))[0].state == .working)
        #expect(t.sessions(now: t0.addingTimeInterval(91))[0].state == .idle)
        t.apply(ev("PostToolUse", "w", at: 100))
        #expect(t.sessions(now: t0.addingTimeInterval(101))[0].state == .working)

        t.apply(ev("Stop", "d", at: 0, cwd: "/a/b"))
        #expect(t.sessions(now: t0.addingTimeInterval(599)).contains { $0.id == "d" })
        #expect(!t.sessions(now: t0.addingTimeInterval(601)).contains { $0.id == "d" })

        t.apply(ev("Stop", "e", at: 1000, cwd: "/a/c"))
        t.dismiss("e")
        #expect(!t.sessions(now: t0.addingTimeInterval(1001)).contains { $0.id == "e" })
        t.apply(ev("UserPromptSubmit", "e", at: 1002, cwd: "/a/c"))
        #expect(t.sessions(now: t0.addingTimeInterval(1003)).contains { $0.id == "e" })

        t.apply(ev("SessionEnd", "e", at: 1004))
        #expect(!t.sessions(now: t0.addingTimeInterval(1005)).contains { $0.id == "e" })
    }

    @Test func namesAndOverrides() {
        #expect(SessionTracker.displayName(cwd: "/Users/me/proj///") == "proj")
        #expect(SessionTracker.displayName(cwd: "/") == "Claude")
        #expect(SessionTracker.displayName(cwd: nil) == "Claude")
        var t = SessionTracker()
        t.nameOverrides = ["s1": "Docs rewrite"]
        t.apply(ev("UserPromptSubmit", at: 0))
        #expect(t.sessions(now: t0)[0].name == "Docs rewrite")
    }

    @Test func orderingNeedsYouFirst() {
        var t = SessionTracker()
        t.apply(ev("UserPromptSubmit", "a", at: 10))
        t.apply(ev("Notification", "b", at: 5, message: "needs your permission"))
        #expect(t.sessions(now: t0.addingTimeInterval(11)).map(\.id) == ["b", "a"])
    }
}

// MARK: reader

@Suite struct EventReaderTests {
    func line(_ sid: String, _ event: String = "Stop") -> String {
        #"{"ts": 1800000000, "event": "\#(event)", "payload": {"session_id": "\#(sid)", "cwd": "/p"}}"# + "\n"
    }
    func append(_ s: String, to url: URL) throws {
        if let h = try? FileHandle(forWritingTo: url) { try h.seekToEnd(); try h.write(contentsOf: Data(s.utf8)); try h.close() }
        else { try s.write(to: url, atomically: false, encoding: .utf8) }
    }

    @Test func offsetsPartialLinesMalformedAndTruncation() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("e.jsonl")
        let r = EventReader(url: url)
        #expect(r.poll().isEmpty)                         // missing file
        try append(line("a") + "garbage{\n", to: url)
        var got = r.poll()
        #expect(got.map(\.sessionID) == ["a"] && r.malformedLineCount == 1)
        #expect(r.poll().isEmpty)                         // nothing new
        let half = line("b")
        try append(String(half.prefix(20)), to: url)
        #expect(r.poll().isEmpty)                         // partial line waits
        try append(String(half.dropFirst(20)) + line("c"), to: url)
        got = r.poll()
        #expect(got.map(\.sessionID) == ["b", "c"])
        // truncation: file shrinks below offset
        try (line("z")).write(to: url, atomically: false, encoding: .utf8)
        #expect(r.poll().map(\.sessionID) == ["z"])
    }

    @Test func rotationReplacesFile() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("e.jsonl")
        let r = EventReader(url: url)
        r.rotationLimit = 100
        try append(String(repeating: line("a"), count: 3), to: url)
        #expect(r.poll().count == 3)
        #expect(r.rotateIfNeeded())
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("1").path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try append(line("n"), to: url)
        #expect(r.poll().map(\.sessionID) == ["n"])
        // replaced by a file at least as large (new inode)
        try FileManager.default.removeItem(at: url)
        try append(line("p") + line("q"), to: url)
        #expect(r.poll().map(\.sessionID) == ["p", "q"])
    }
}

// MARK: signals + provider

@Suite struct AgentSignalTests {
    @Test func mapping() {
        var t = SessionTracker()
        t.apply(ev("UserPromptSubmit", "w", at: 0, cwd: "/x/work"))
        t.apply(ev("PreToolUse", "w", at: 50, cwd: "/x/work", tool: "Edit"))
        t.apply(ev("Notification", "n", at: 10, cwd: "/x/need", message: "Claude needs your permission to use Bash"))
        t.apply(ev("UserPromptSubmit", "d", at: -142, cwd: "/x/fin"))
        t.apply(ev("Stop", "d", at: 50, cwd: "/x/fin"))
        t.apply(ev("UserPromptSubmit", "i", at: -500, cwd: "/x/stale"))
        let now = t0.addingTimeInterval(100)
        let sigs = AgentSignals.signals(for: t.sessions(now: now), now: now)
        let by = Dictionary(uniqueKeysWithValues: sigs.map { ($0.id, $0) })
        #expect(by["agents.session.i"] == nil)            // idle is not a signal

        let n = try! #require(by["agents.session.n"])
        #expect(n.attention == .warning && n.title == "need needs you" && n.detail == "Claude needs your permission to use Bash")
        #expect(n.value == "1:30" && n.priority == 70 && n.tint == .violet && n.kind == .agent && n.symbol == "sparkles")
        let w = try! #require(by["agents.session.w"])
        #expect(w.attention == .info && w.title == "work" && w.detail == "Working · Edit" && w.value == "1:40" && w.priority == 25 && w.progress == nil)
        let d = try! #require(by["agents.session.d"])
        #expect(d.attention == .info && d.title == "fin done" && d.detail == "Took 3m 12s" && d.priority == 15 && d.tint == .green)
        // 60 s later the done signal turns calm
        let later = t0.addingTimeInterval(50 + 61)
        let calm = AgentSignals.signals(for: t.sessions(now: later), now: later).first { $0.id == "agents.session.d" }
        #expect(calm?.attention == .calm)
        #expect(UrgencyRanker.top(sigs)?.id == "agents.session.n")
    }

    @Test func durationFormatting() {
        #expect(AgentSignals.duration(45) == "45s")
        #expect(AgentSignals.duration(192) == "3m 12s")
        #expect(AgentSignals.duration(3900) == "1h 5m")
    }

    @Test func codexScanBestEffort() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = dir.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let fresh = day.appendingPathComponent("rollout-1.jsonl"), old = day.appendingPathComponent("rollout-2.jsonl")
        try #"{"type":"session_meta","payload":{"cwd":"/Users/me/api"}}"#.appending("\n{}\n").write(to: fresh, atomically: true, encoding: .utf8)
        try "{}\n".write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: old.path)
        let found = CodexMonitor(root: dir).scan(now: now)
        #expect(found.count == 1 && found[0].name == "api" && found[0].state == .working && found[0].source == .codex)
        #expect(found[0].actionURL == nil)
    }

    @MainActor @Test func providerEndToEnd() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let settingsURL = dir.appendingPathComponent("claude/settings.json")
        var ms = ModuleSettings(); ms.agentsEnabled = true
        let p = AgentsProvider(settings: ms, supportDirectory: dir, claudeSettingsURL: settingsURL,
                               codex: CodexMonitor(root: dir.appendingPathComponent("nocodex")))
        var changes = 0
        p.onChange = { changes += 1 }
        p.start()
        #expect(p.providerID == "agents" && p.signals.isEmpty && !p.isActive && p.hooksStatus == .notInstalled)
        try p.installHooks()
        #expect(p.hooksStatus == .installed && p.isActive)
        #expect(FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("hooks/claude-hook.sh").path))

        let script = dir.appendingPathComponent("hooks/claude-hook.sh")
        try runHook(script: script, stdin: #"{"session_id":"live","cwd":"/r/app","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}"#)
        p.apply(ms) // reconfigure -> immediate poll
        #expect(p.signals.first?.id == "agents.session.live" && p.signals.first?.attention == .warning)
        #expect(changes > 0)
        p.dismiss(sessionID: "live")
        #expect(p.sessions.isEmpty)

        ms.agentsEnabled = false
        p.apply(ms)
        #expect(p.signals.isEmpty)
        p.stop()
        try p.uninstallHooks()
        #expect(p.hooksStatus == .notInstalled)
    }
}
