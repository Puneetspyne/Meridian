import Foundation
import MeridianKit

/// Timers, countdowns, stopwatch, the next meeting, world clocks and the always-present clock, as signals.
///
/// Signal ids (stable, prefix `time.`): `time.timer.<uuid>`, `time.countdown.<uuid>`, `time.stopwatch`,
/// `time.meeting.<event id>`, `time.clock`. State is persisted to `time.json` and reloaded on init.
@MainActor
public final class TimeProvider: SignalProvider {
    public let providerID = "time"
    public private(set) var signals: [Signal] = []
    public var onChange: (@MainActor () -> Void)?

    // Read-only state for the UI.
    public private(set) var timers: [TimerItem] = []
    public private(set) var countdowns: [Countdown] = []
    public private(set) var stopwatch: Stopwatch?
    public private(set) var todos: [TodoItem] = []
    public private(set) var worldClocks: [WorldClock] = []
    public private(set) var nextMeeting: MeetingEvent?
    /// 0...1 between 09:00 and 18:00 local time, for the corner ring.
    public private(set) var workdayProgress: Double = 0
    /// Set when the last write to `time.json` failed.
    public private(set) var lastSaveError: Error?
    public private(set) var settings: ModuleSettings

    /// The calendar reader. Exposed so settings UI can show access state.
    public let calendarSource = CalendarSource()

    let calendar: Calendar
    private let clock: () -> Date
    private let store: TimeStore
    private var tickTimer: Timer?
    private var saveTask: Task<Void, Never>?
    private var isStarted = false
    private var firstSeen: [String: Date] = [:]
    private var dismissedMeetings = Set<String>()
    /// Tests inject meetings here instead of touching EventKit.
    var meetingEventsOverride: [MeetingEvent]?

    /// - Parameters:
    ///   - storeDirectory: where `time.json` lives; defaults to `Paths.supportDirectory`.
    ///   - calendar: supplies the local time zone; defaults to the user's.
    ///   - now: the clock, injectable for tests.
    public init(settings: ModuleSettings, storeDirectory: URL? = nil, calendar: Calendar = .current,
                now: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.calendar = calendar
        self.clock = now
        self.store = TimeStore(directory: storeDirectory ?? Paths.supportDirectory)
        let state = store.load()
        timers = state.timers
        countdowns = state.countdowns
        stopwatch = state.stopwatch
        todos = state.todos
        calendarSource.onChange = { [weak self] in self?.tick() }
        evaluate(now: now(), force: false)
    }

    // MARK: SignalProvider

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        if meetingEventsOverride == nil { calendarSource.setEnabled(settings.calendarEnabled) }
        tick()
    }

    public func stop() {
        isStarted = false
        tickTimer?.invalidate()
        tickTimer = nil
        calendarSource.setEnabled(false)
        flush()
    }

    public func apply(_ settings: ModuleSettings) {
        self.settings = settings
        if isStarted, meetingEventsOverride == nil { calendarSource.setEnabled(settings.calendarEnabled) }
        evaluate(now: clock(), force: true)
    }

    // MARK: Mutation API

    /// Applies a parsed quick-add line. Returns false for `.invalid`.
    @discardableResult
    public func add(parsed: QuickParse.Parsed) -> Bool {
        switch parsed {
        case let .timer(name, seconds): addTimer(name: name, seconds: seconds)
        case let .countdown(name, fireAt, rule): addCountdown(name: name, fireAt: fireAt, repeatRule: rule)
        case .stopwatch: startStopwatch()
        case let .todo(text): addTodo(text)
        case .invalid: return false
        }
        return true
    }

    /// Starts a timer immediately.
    @discardableResult
    public func addTimer(name: String, seconds: TimeInterval) -> UUID {
        let item = TimerItem(name: name.isEmpty ? "Timer" : name, duration: max(1, seconds), startedAt: clock())
        timers.append(item)
        commit()
        return item.id
    }

    @discardableResult
    public func addCountdown(name: String, fireAt: Date, repeatRule: RepeatRule = .none) -> UUID {
        let item = Countdown(name: name.isEmpty ? "Countdown" : name, fireAt: fireAt, repeatRule: repeatRule)
        countdowns.append(item)
        commit()
        return item.id
    }

    @discardableResult
    public func addTodo(_ text: String) -> UUID {
        let item = TodoItem(text: text, createdAt: clock())
        todos.append(item)
        commit()
        return item.id
    }

    public func pause(timerID: UUID) { mutateTimer(timerID) { $0.pause(at: clock()) } }
    public func resume(timerID: UUID) { mutateTimer(timerID) { $0.resume(at: clock()) } }
    /// Back to the full duration, stopped. Resume to start it again.
    public func reset(timerID: UUID) { mutateTimer(timerID) { $0.reset(at: clock()) } }
    public func addMinutes(_ minutes: Int, to timerID: UUID) { mutateTimer(timerID) { $0.addTime(TimeInterval(minutes) * 60) } }
    public func remove(timerID: UUID) {
        timers.removeAll { $0.id == timerID }
        commit()
    }
    public func remove(countdownID: UUID) {
        countdowns.removeAll { $0.id == countdownID }
        commit()
    }
    public func remove(todo id: UUID) {
        todos.removeAll { $0.id == id }
        commit()
    }
    /// Marks a to-do done (or not done again if it already was).
    public func complete(todo id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        commit()
    }

    /// Starts the stopwatch, or resumes a stopped one. No-op while running.
    public func startStopwatch() {
        var sw = stopwatch ?? Stopwatch()
        guard !sw.isRunning else { return }
        sw.startedAt = clock()
        stopwatch = sw
        commit()
    }
    /// Records a lap while running.
    public func lapStopwatch() {
        guard var sw = stopwatch, sw.isRunning else { return }
        let total = sw.elapsed(at: clock())
        sw.laps.append(.init(number: sw.laps.count + 1, total: total, split: total - (sw.laps.last?.total ?? 0)))
        stopwatch = sw
        commit()
    }
    /// Pauses the stopwatch, keeping the elapsed time and laps.
    public func stopStopwatch() {
        guard var sw = stopwatch, sw.isRunning else { return }
        sw.accumulated = sw.elapsed(at: clock())
        sw.startedAt = nil
        stopwatch = sw
        commit()
    }
    /// Discards the stopwatch entirely.
    public func resetStopwatch() {
        stopwatch = nil
        commit()
    }

    /// Dismisses the signal with this id: a finished timer stops nagging, a countdown completes (a repeating
    /// one moves to its next occurrence), a meeting is hidden. Other ids are ignored.
    public func dismiss(signalID: String) {
        let now = clock()
        if let raw = signalID.removingPrefix("time.timer."), let id = UUID(uuidString: raw) {
            mutateTimer(id) { $0.isDismissed = true }
        } else if let raw = signalID.removingPrefix("time.countdown."), let id = UUID(uuidString: raw),
                  let i = countdowns.firstIndex(where: { $0.id == id }) {
            completeCountdown(at: i, now: now)
            commit()
        } else if let raw = signalID.removingPrefix("time.meeting.") {
            dismissedMeetings.insert(raw)
            commit()
        }
    }

    /// Writes `time.json` now, cancelling any pending debounced save.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        var state = TimeState()
        state.timers = timers
        state.countdowns = countdowns
        state.stopwatch = stopwatch
        state.todos = todos
        do {
            try store.save(state)
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }

    // MARK: Evaluation

    private func tick() { evaluate(now: clock(), force: false) }

    private func commit() {
        scheduleSave()
        evaluate(now: clock(), force: true)
    }

    private func mutateTimer(_ id: UUID, _ change: (inout TimerItem) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[i])
        commit()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// A countdown that reached its end for 60 s: repeating ones jump to the next occurrence, others go away.
    private func completeCountdown(at index: Int, now: Date) {
        let c = countdowns[index]
        if let next = c.repeatRule.next(after: now, timeOfDayFrom: c.fireAt, calendar: calendar) {
            countdowns[index].fireAt = next
        } else {
            countdowns.remove(at: index)
        }
    }

    /// Recomputes every derived value for `now` and publishes when something changed textually.
    /// `force` publishes regardless, used after a mutation so list UIs refresh even if no signal changed.
    func evaluate(now: Date, force: Bool) {
        // Settle countdowns whose 60 s "now" window is over.
        var settled = false
        for c in countdowns.reversed() where now >= c.fireAt.addingTimeInterval(60) {
            if let i = countdowns.firstIndex(where: { $0.id == c.id }) {
                completeCountdown(at: i, now: now)
                settled = true
            }
        }
        if settled { scheduleSave() }

        let use24 = settings.uses24HourClock
        let zone = calendar.timeZone
        var out: [Signal] = []

        for t in timers { out.append(contentsOf: timerSignal(t, now: now, use24: use24, zone: zone)) }
        for c in countdowns { out.append(countdownSignal(c, now: now, use24: use24)) }
        if let sw = stopwatch { out.append(stopwatchSignal(sw, now: now)) }

        let events = meetingEventsOverride ?? (settings.calendarEnabled ? calendarSource.events : [])
        nextMeeting = MeetingEvent.next(in: events, now: now, skipping: dismissedMeetings)
        if let m = nextMeeting { out.append(meetingSignal(m, now: now, use24: use24, zone: zone)) }

        out.append(Signal(
            id: "time.clock", kind: .clock, attention: .calm, title: "Clock",
            detail: TimeFormatting.dayMonth(now, zone: zone), symbol: "clock", progress: nil,
            value: TimeFormatting.clock(now, zone: zone, uses24Hour: use24),
            createdAt: .distantPast, priority: 5, tint: .neutral))

        let clocks = settings.secondaryTimeZones.compactMap {
            WorldClock.make(identifier: $0, now: now, local: zone, uses24Hour: use24)
        }
        workdayProgress = Self.workdayProgress(at: now, calendar: calendar)

        // Keep createdAt stable per id so identical signals compare equal between ticks.
        var seen: [String: Date] = [:]
        for i in out.indices where out[i].id != "time.clock" {
            let created = firstSeen[out[i].id] ?? now
            seen[out[i].id] = created
            out[i].createdAt = created
        }
        firstSeen = seen

        let changed = out != signals || clocks != worldClocks
        worldClocks = clocks
        signals = out
        if changed || force { onChange?() }
    }

    /// Fraction of the 09:00–18:00 workday elapsed at `date`, clamped to 0...1.
    public static func workdayProgress(at date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        return min(1, max(0, (minutes - 9 * 60) / (9 * 60)))
    }

    // MARK: Signal builders

    private func timerSignal(_ t: TimerItem, now: Date, use24: Bool, zone: TimeZone) -> [Signal] {
        let id = "time.timer.\(t.id.uuidString)"
        let remaining = t.remaining(at: now)
        if !t.isRunning {
            let fresh = t.pausedRemaining.map { abs($0 - t.duration) < 0.5 } ?? true
            return [Signal(id: id, kind: .timer, attention: .calm, title: t.name, detail: fresh ? "Ready" : "Paused",
                           symbol: "timer", progress: t.progress(at: now),
                           value: Format.countdown(remaining.rounded(.up)), priority: 40, tint: .teal)]
        }
        if remaining > 0 {
            return [Signal(id: id, kind: .timer, attention: .info, title: t.name,
                           detail: "Ends " + TimeFormatting.clock(t.endsAt ?? now, zone: zone, uses24Hour: use24),
                           symbol: "timer", progress: t.progress(at: now),
                           value: Format.countdown(remaining.rounded(.up)), deadline: t.endsAt,
                           priority: 50, tint: .teal)]
        }
        guard !t.isDismissed else { return [] }
        return [Signal(id: id, kind: .timer, attention: .critical, title: "Time's up", detail: t.name,
                       symbol: "timer", progress: 1, value: Format.countdown(remaining.rounded(.up)),
                       deadline: t.endsAt, priority: 50, tint: .red)]
    }

    private func countdownSignal(_ c: Countdown, now: Date, use24: Bool) -> Signal {
        let remaining = c.fireAt.timeIntervalSince(now)
        let attention: Attention
        switch remaining {
        case ...0: attention = .critical
        case ...120: attention = .warning
        case ...900: attention = .info
        default: attention = .calm
        }
        var detail = "At " + TimeFormatting.shortWhen(c.fireAt, now: now, calendar: calendar, uses24Hour: use24)
        if c.repeatRule.isRepeating { detail += " · " + c.repeatRule.label }
        let value: String
        switch attention {
        case .calm: value = Format.relative(c.fireAt, now: now)
        case .critical: value = "Now"
        default: value = Format.countdown(remaining.rounded(.up))
        }
        return Signal(id: "time.countdown.\(c.id.uuidString)", kind: .countdown, attention: attention,
                      title: c.name, detail: detail, symbol: "hourglass", value: value, deadline: c.fireAt,
                      priority: 52, tint: attention == .critical ? .red : (attention == .warning ? .amber : .violet))
    }

    private func stopwatchSignal(_ sw: Stopwatch, now: Date) -> Signal {
        var detail = sw.isRunning ? "Running" : "Stopped"
        if let lap = sw.laps.last { detail = "Lap \(lap.number) · \(Format.countdown(lap.split)) · " + detail }
        return Signal(id: "time.stopwatch", kind: .stopwatch, attention: sw.isRunning ? .info : .calm,
                      title: "Stopwatch", detail: detail, symbol: "stopwatch",
                      value: Format.countdown(sw.elapsed(at: now)), priority: 45, tint: .teal)
    }

    private func meetingSignal(_ m: MeetingEvent, now: Date, use24: Bool, zone: TimeZone) -> Signal {
        let remaining = m.start.timeIntervalSince(now)
        var detail = TimeFormatting.range(m.start, m.end, zone: zone, uses24Hour: use24)
        if let service = m.joinLink?.service { detail += " · " + service }

        let attention: Attention
        let title: String
        let value: String
        switch remaining {
        case ...0:
            attention = .critical; title = "\(m.title) now"; value = "Now"
        case ...120:
            attention = .warning; title = "\(m.title) \(Format.relative(m.start, now: now))"
            value = Format.countdown(remaining.rounded(.up))
        case ...900:
            attention = .info; title = "\(m.title) \(Format.relative(m.start, now: now))"
            value = Format.countdown(remaining.rounded(.up))
        default:
            attention = .calm; title = m.title; value = Format.relative(m.start, now: now)
        }
        return Signal(id: "time.meeting.\(m.id)", kind: .meeting, attention: attention, title: title,
                      detail: detail, symbol: "calendar", value: value, deadline: m.start, priority: 55,
                      tint: .blue, actionURL: m.joinLink?.url, actionTitle: m.joinLink == nil ? nil : "Join")
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
