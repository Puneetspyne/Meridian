import SwiftUI
import MeridianKit
import MeridianTime
import MeridianAgents

// MARK: - Shared bits

struct IconButton: View {
    var symbol: String
    var label: String
    var tint: Color = Design.Color.textSecondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct StripDivider: View {
    var body: some View { Rectangle().fill(Design.Color.hairline).frame(height: 1).padding(.horizontal, 12) }
}

private struct JoinButton: View {
    var title: String
    var spoken: String
    var url: URL
    var body: some View {
        Button { openURL(url) } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Design.Color.tint(.blue)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Time

/// Meeting, timers, countdowns, stopwatch, world clocks and quick add. Wired to `TimeProvider` when the app has one;
/// without it (the snapshot renderer) the same strip is drawn read-only from signals.
struct TimeStrip: View {
    let model: AppModel

    @State private var quickOpen = false
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.meridianKeyboard) private var keyboard
    @Environment(\.meridianSnapshot) private var snapshot

    init(model: AppModel) {
        self.model = model
        _text = State(initialValue: CardCommands.shared.quickAddPrefill ?? "")
    }

    static func entries(in signals: [Signal]) -> [Signal] {
        let kinds: Set<SignalKind> = [.meeting, .countdown, .timer, .stopwatch]
        return signals.filter { kinds.contains($0.kind) }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }
    static func clocks(in signals: [Signal]) -> [Signal] { signals.filter { $0.kind == .clock } }

    private var provider: TimeProvider? { model.provider(TimeProvider.self) }

    var body: some View {
        // Provider mutations call `onChange`, which republishes `model.signals`; reading it here is what refreshes us.
        let signals = model.signals
        VStack(spacing: 0) {
            if let provider {
                header
                if quickOpen { quickAdd(provider) }
                content(provider, signals: signals)
            } else {
                fallback(signals)
            }
        }
        .frame(maxWidth: .infinity)
        .meridianSurface(radius: Design.Radius.tile)
        .onChange(of: CardCommands.shared.quickAddPending, initial: true) { _, pending in
            if pending { CardCommands.shared.quickAddPending = false; setQuick(true) }
        }
        .onDisappear { if quickOpen { keyboard(false) } }
    }

    // MARK: Header and quick add

    private var header: some View {
        HStack {
            Text("Time").font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary)
            Spacer()
            IconButton(symbol: quickOpen ? "xmark" : "plus", label: quickOpen ? "Close quick add" : "Quick add timer, countdown or to-do") {
                setQuick(!quickOpen)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(height: 34)
    }

    private func setQuick(_ on: Bool) {
        quickOpen = on
        keyboard(on)
        if on {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
            }
        } else {
            focused = false
            text = ""
        }
    }

    private func quickAdd(_ provider: TimeProvider) -> some View {
        let parsed = QuickParse.parse(text, now: Date(), calendar: .current)
        let preview = Self.preview(parsed)
        return VStack(alignment: .leading, spacing: 4) {
            field
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                .onSubmit {
                    if provider.add(parsed: parsed) { setQuick(false) }
                }
                .accessibilityLabel("Quick add")
            if !text.isEmpty {
                Text(preview.text)
                    .font(Design.Font.caption)
                    .foregroundStyle(preview.valid ? Design.Color.tint(.teal) : Design.Color.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// ImageRenderer cannot draw a text field, so snapshots show the text as a label.
    @ViewBuilder private var field: some View {
        if snapshot {
            Text(text).font(.system(size: 13)).foregroundStyle(Design.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("25m focus, 6pm standup, every day 9am", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Design.Color.textPrimary)
                .focused($focused)
        }
    }

    /// "Timer · Focus · 25 min", the line shown under the field as you type.
    static func preview(_ parsed: QuickParse.Parsed) -> (text: String, valid: Bool) {
        switch parsed {
        case let .timer(name, seconds):
            let label = seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0
                ? Format.minutes(Int(seconds / 60)).replacingOccurrences(of: "m", with: " min") : Format.countdown(seconds)
            return ("Timer \u{00B7} \(name.isEmpty ? "Timer" : name) \u{00B7} \(label)", true)
        case let .countdown(name, fireAt, rule):
            let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
            var s = "Countdown \u{00B7} \(name.isEmpty ? "Countdown" : name) \u{00B7} \(f.string(from: fireAt))"
            if rule.isRepeating { s += " \u{00B7} \(rule.label)" }
            return (s, true)
        case .stopwatch: return ("Stopwatch", true)
        case let .todo(text): return ("To-do \u{00B7} \(text)", true)
        case let .invalid(reason): return (reason, false)
        }
    }

    // MARK: Provider content

    @ViewBuilder private func content(_ provider: TimeProvider, signals: [Signal]) -> some View {
        let meeting = signals.first { $0.kind == .meeting }
        let clocks = provider.worldClocks
        if let meeting { StripDivider(); meetingRow(meeting) }
        ForEach(provider.timers) { t in StripDivider(); timerRow(t, provider) }
        ForEach(provider.countdowns) { c in StripDivider(); countdownRow(c, provider) }
        if let sw = provider.stopwatch { StripDivider(); stopwatchRow(sw, provider) }
        if !clocks.isEmpty {
            StripDivider()
            HStack(spacing: 0) {
                ForEach(clocks.prefix(3)) { c in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.cityName == c.abbreviation ? c.abbreviation : c.cityName)
                            .font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
                        Num(c.time, size: 15, weight: .medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(c.cityName) \(c.time)")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        if meeting == nil, provider.timers.isEmpty, provider.countdowns.isEmpty, provider.stopwatch == nil, clocks.isEmpty {
            Text("Nothing scheduled").font(Design.Font.body).foregroundStyle(Design.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 12)
        }
    }

    private func rowFrame<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { c() }.padding(.horizontal, 12).frame(height: 44)
    }

    private func titleBlock(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
            if let detail { Text(detail).font(Design.Font.caption).foregroundStyle(Design.Color.textSecondary).lineLimit(1) }
        }
    }

    private func meetingRow(_ s: Signal) -> some View {
        rowFrame {
            Image(systemName: s.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Design.Color.tint(s.tint)).frame(width: 18)
            titleBlock(s.title, s.detail)
            Spacer(minLength: 6)
            if s.isLiveCountdown { SignalValue(signal: s, font: Design.Font.number(13, weight: .medium)) }
            if let url = s.actionURL, let title = s.actionTitle { JoinButton(title: title, spoken: "\(title) \(s.title)", url: url) }
        }
        .accessibilityElement(children: .contain)
    }

    private func timerRow(_ t: TimerItem, _ p: TimeProvider) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let finished = t.isFinished(at: ctx.date)
            let remaining = t.remaining(at: ctx.date)
            rowFrame {
                Image(systemName: "timer").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(finished ? Design.Color.tint(.red) : Design.Color.tint(.teal)).frame(width: 18)
                titleBlock(t.name.isEmpty ? "Timer" : t.name, finished ? "Time's up" : (t.isRunning ? nil : "Paused"))
                Spacer(minLength: 6)
                Num(finished ? "-" + Format.countdown(-remaining) : Format.countdown(max(0, remaining)), size: 13, weight: .medium,
                    color: finished ? Design.Color.tint(.red) : Design.Color.textPrimary)
                if finished {
                    IconButton(symbol: "checkmark", label: "Dismiss \(t.name)") { p.dismiss(signalID: "time.timer.\(t.id.uuidString)") }
                } else {
                    IconButton(symbol: t.isRunning ? "pause.fill" : "play.fill", label: t.isRunning ? "Pause \(t.name)" : "Resume \(t.name)") {
                        t.isRunning ? p.pause(timerID: t.id) : p.resume(timerID: t.id)
                    }
                }
            }
        }
        .contextMenu {
            Button("Add 5 minutes") { p.addMinutes(5, to: t.id) }
            Button("Reset") { p.reset(timerID: t.id) }
            Button("Remove", role: .destructive) { p.remove(timerID: t.id) }
        }
        .accessibilityElement(children: .contain)
    }

    private func countdownRow(_ c: Countdown, _ p: TimeProvider) -> some View {
        rowFrame {
            Image(systemName: "hourglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Design.Color.tint(.violet)).frame(width: 18)
            titleBlock(c.name, c.repeatRule.isRepeating ? c.repeatRule.label : nil)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = c.fireAt.timeIntervalSince(ctx.date)
                Num(left <= 900 ? Format.countdown(max(0, left)) : Format.relative(c.fireAt, now: ctx.date), size: 13, weight: .medium)
            }
            IconButton(symbol: "xmark", label: "Remove \(c.name)") { p.remove(countdownID: c.id) }
        }
        .contextMenu { Button("Remove", role: .destructive) { p.remove(countdownID: c.id) } }
    }

    private func stopwatchRow(_ sw: Stopwatch, _ p: TimeProvider) -> some View {
        rowFrame {
            Image(systemName: "stopwatch").font(.system(size: 13, weight: .medium)).foregroundStyle(Design.Color.tint(.amber)).frame(width: 18)
            titleBlock("Stopwatch", sw.laps.last.map { "Lap \($0.number) \u{00B7} \(Format.countdown($0.split))" })
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Num(Format.countdown(sw.elapsed(at: ctx.date)), size: 13, weight: .medium)
            }
            if sw.isRunning {
                IconButton(symbol: "flag.fill", label: "Lap") { p.lapStopwatch() }
                IconButton(symbol: "stop.fill", label: "Stop stopwatch") { p.stopStopwatch() }
            } else {
                IconButton(symbol: "play.fill", label: "Start stopwatch") { p.startStopwatch() }
                IconButton(symbol: "arrow.counterclockwise", label: "Reset stopwatch") { p.resetStopwatch() }
            }
        }
    }

    // MARK: Read-only fallback (no provider: snapshots)

    @ViewBuilder private func fallback(_ signals: [Signal]) -> some View {
        let entries = Self.entries(in: signals).prefix(4)
        let clocks = Self.clocks(in: signals).prefix(2)
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, s in
            if index > 0 { StripDivider() }
            rowFrame {
                Image(systemName: s.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Design.Color.tint(s.tint)).frame(width: 18)
                titleBlock(s.title, s.detail)
                Spacer(minLength: 6)
                SignalValue(signal: s, font: Design.Font.number(13, weight: .medium))
                if let url = s.actionURL, let title = s.actionTitle { JoinButton(title: title, spoken: "\(title) \(s.title)", url: url) }
            }
        }
        if !clocks.isEmpty {
            if !entries.isEmpty { StripDivider() }
            HStack(spacing: 0) {
                ForEach(Array(clocks), id: \.id) { c in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary)
                        if let v = c.value { Num(v, size: 15, weight: .medium) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
    }
}

// MARK: - Agents

struct AgentsStrip: View {
    let model: AppModel

    private var provider: AgentsProvider? { model.provider(AgentsProvider.self) }

    static func sessions(in signals: [Signal]) -> [Signal] {
        signals.filter { $0.kind == .agent }.sorted { ($0.attention, $0.priority) > ($1.attention, $1.priority) }
    }

    var body: some View {
        let signals = model.signals // refresh when the provider republishes
        VStack(spacing: 0) {
            if let provider {
                let sessions = provider.sessions.filter { !$0.dismissed }.sorted { Self.rank($0.state) < Self.rank($1.state) }
                if !provider.isActive {
                    quiet("Turn on in Settings \u{2192} Agents")
                } else if sessions.isEmpty {
                    quiet("No coding agents running")
                }
                ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, s in
                    if index > 0 { StripDivider() }
                    sessionRow(s, provider)
                }
            } else {
                let list = Self.sessions(in: signals)
                if list.isEmpty { quiet("No coding agents running") }
                ForEach(Array(list.prefix(4).enumerated()), id: \.element.id) { index, s in
                    if index > 0 { StripDivider() }
                    signalRow(s)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .meridianSurface(radius: Design.Radius.tile)
    }

    private static func rank(_ s: AgentState) -> Int {
        switch s { case .needsYou: 0; case .working: 1; case .done: 2; case .idle: 3 }
    }

    private func quiet(_ text: String) -> some View {
        HStack {
            Text(text).font(Design.Font.body).foregroundStyle(Design.Color.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func color(_ s: AgentState) -> Color {
        switch s {
        case .working: return Design.Color.tint(.violet)
        case .needsYou: return Design.Color.tint(.amber)
        case .done: return Design.Color.tint(.green)
        case .idle: return Design.Color.textTertiary
        }
    }

    private func detail(_ s: AgentSession) -> String {
        switch s.state {
        case .needsYou: return s.needsReason ?? "Needs you"
        case .working: return s.lastToolName.map { "Working \u{00B7} \($0)" } ?? "Working"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }

    private func elapsedStart(_ s: AgentSession) -> Date? {
        switch s.state {
        case .needsYou: return s.needsSince
        case .working: return s.turnStartedAt
        default: return nil
        }
    }

    @ViewBuilder private func sessionRow(_ s: AgentSession, _ p: AgentsProvider) -> some View {
        let row = HStack(spacing: 10) {
            Circle().fill(color(s.state)).frame(width: 8, height: 8).frame(width: 18)
            Text(s.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
            Text(detail(s)).font(Design.Font.caption).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
            Spacer(minLength: 6)
            if let start = elapsedStart(s) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Num(Format.countdown(max(0, ctx.date.timeIntervalSince(start))), size: 12, weight: .medium, color: Design.Color.textSecondary)
                }
            } else if s.state == .done, let d = s.lastTurnDuration {
                Num(Format.countdown(d), size: 12, weight: .medium, color: Design.Color.textSecondary)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, s.state == .done ? 4 : 12)
        .frame(height: 36)
        .contentShape(Rectangle())

        HStack(spacing: 0) {
            if let url = s.actionURL {
                Button { openURL(url) } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s.name), \(detail(s)). Opens the session")
            } else {
                row.accessibilityElement(children: .ignore).accessibilityLabel("\(s.name), \(detail(s))")
            }
            if s.state == .done {
                IconButton(symbol: "xmark", label: "Dismiss \(s.name)") { p.dismiss(sessionID: s.id) }.padding(.trailing, 8)
            }
        }
    }

    @ViewBuilder private func signalRow(_ s: Signal) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Design.Color.tint(s.tint)).frame(width: 8, height: 8).frame(width: 18)
            Text(s.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
            if let d = s.detail { Text(d).font(Design.Font.caption).foregroundStyle(Design.Color.textSecondary).lineLimit(1) }
            Spacer(minLength: 6)
            if let v = s.value { Num(v, size: 12, weight: .medium, color: Design.Color.textSecondary) }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.title), \(s.detail ?? "")")
    }
}
