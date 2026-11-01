import Foundation
import MeridianKit
import Testing
@testable import MeridianTime

@MainActor
struct TimerLifecycleTests {
    private func timerSignal(_ p: TimeProvider) -> Signal? { p.signals.first { $0.kind == .timer } }

    @Test func runningTimerThenTimesUp() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let id = p.addTimer(name: "Focus", seconds: 60)
        let t0 = clock.now

        p.evaluate(now: t0.addingTimeInterval(10), force: false)
        let running = try #require(timerSignal(p))
        #expect(running.id == "time.timer.\(id.uuidString)")
        #expect(running.attention == .info)
        #expect(running.title == "Focus")
        #expect(running.value == "0:50")
        #expect(running.symbol == "timer")
        #expect(running.tint == .teal)
        #expect(running.priority == 50)
        #expect(running.deadline == t0.addingTimeInterval(60))
        #expect(abs((running.progress ?? 0) - 10.0 / 60) < 0.001)

        p.evaluate(now: t0.addingTimeInterval(60), force: false)
        let due = try #require(timerSignal(p))
        #expect(due.attention == .critical)
        #expect(due.title == "Time's up")
        #expect(due.detail == "Focus")
        #expect(due.value == "0:00")
        #expect(due.tint == .red)

        p.evaluate(now: t0.addingTimeInterval(65), force: false)
        #expect(timerSignal(p)?.value == "-0:05")

        clock.now = t0.addingTimeInterval(65)  // mutations evaluate at the injected clock
        p.dismiss(signalID: due.id)
        #expect(timerSignal(p) == nil)
        #expect(p.timers.count == 1)  // stays in the list for reset
        #expect(p.signals.contains { $0.id == "time.clock" })
    }

    @Test func pauseResumeResetAndAddMinutes() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let id = p.addTimer(name: "Tea", seconds: 300)
        clock.now += 100
        p.pause(timerID: id)
        #expect(p.timers[0].pausedRemaining == 200)
        #expect(p.timers[0].endsAt == nil)
        #expect(timerSignal(p)?.attention == .calm)
        #expect(timerSignal(p)?.detail == "Paused")

        clock.now += 1000  // paused time does not count
        p.resume(timerID: id)
        #expect(p.timers[0].endsAt == clock.now.addingTimeInterval(200))

        p.addMinutes(5, to: id)
        #expect(p.timers[0].duration == 600)
        #expect(p.timers[0].endsAt == clock.now.addingTimeInterval(500))

        p.reset(timerID: id)
        #expect(p.timers[0].isRunning == false)
        #expect(p.timers[0].pausedRemaining == 600)
        #expect(timerSignal(p)?.detail == "Ready")

        p.remove(timerID: id)
        #expect(p.timers.isEmpty)
        #expect(timerSignal(p) == nil)
    }

    @Test func addingMinutesToFinishedTimerRevivesIt() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let id = p.addTimer(name: "Deploy", seconds: 60)
        clock.now += 90
        p.dismiss(signalID: "time.timer.\(id.uuidString)")
        p.addMinutes(5, to: id)
        let s = try #require(timerSignal(p))
        #expect(s.attention == .info)
        #expect(s.value == "4:30")
    }

    @Test func clockSignalAlwaysPresent() throws {
        let p = makeProvider()
        let clock = try #require(p.signals.first { $0.id == "time.clock" })
        #expect(p.signals.count == 1)
        #expect(clock.kind == .clock)
        #expect(clock.attention == .calm)
        #expect(clock.title == "Clock")
        #expect(clock.value == "14:32")
        #expect(clock.detail == "Wed 4 Nov")
        #expect(clock.priority == 5)
        #expect(clock.symbol == "clock")
    }

    @Test func clockRespects12HourSetting() throws {
        var s = ModuleSettings()
        s.uses24HourClock = false
        let p = makeProvider(settings: s)
        #expect(p.signals.first?.value == "2:32 PM")
        var s24 = s
        s24.uses24HourClock = true
        p.apply(s24)
        #expect(p.signals.first?.value == "14:32")
    }

    @Test func workdayProgress() {
        let cal = Fixture.calendar
        #expect(TimeProvider.workdayProgress(at: Fixture.date(2026, 11, 4, 8), calendar: cal) == 0)
        #expect(TimeProvider.workdayProgress(at: Fixture.date(2026, 11, 4, 9), calendar: cal) == 0)
        #expect(abs(TimeProvider.workdayProgress(at: Fixture.date(2026, 11, 4, 13, 30), calendar: cal) - 0.5) < 1e-9)
        #expect(TimeProvider.workdayProgress(at: Fixture.date(2026, 11, 4, 18), calendar: cal) == 1)
        #expect(TimeProvider.workdayProgress(at: Fixture.date(2026, 11, 4, 23), calendar: cal) == 1)
        #expect(abs(makeProvider().workdayProgress - 332.0 / 540) < 1e-9)
    }

    @Test func onChangeFiresOnlyWhenTextChanges() {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        var fired = 0
        p.onChange = { fired += 1 }
        p.evaluate(now: clock.now, force: false)
        p.evaluate(now: clock.now.addingTimeInterval(5), force: false)  // same HH:mm, nothing running
        #expect(fired == 0)
        p.evaluate(now: clock.now.addingTimeInterval(60), force: false)  // minute rolled
        #expect(fired == 1)
        p.addTodo("buy milk")  // mutation always notifies
        #expect(fired == 2)
    }
}

@MainActor
struct CountdownAndStopwatchTests {
    @Test func countdownBands() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let fire = clock.now.addingTimeInterval(3600)
        let id = p.addCountdown(name: "Release", fireAt: fire)
        func signal() -> Signal? { p.signals.first { $0.kind == .countdown } }

        let calm = try #require(signal())
        #expect(calm.id == "time.countdown.\(id.uuidString)")
        #expect(calm.attention == .calm)
        #expect(calm.value == "in 1h")
        #expect(calm.symbol == "hourglass")
        #expect(calm.detail == "At 15:32")

        p.evaluate(now: fire.addingTimeInterval(-900), force: false)
        #expect(signal()?.attention == .info)
        #expect(signal()?.value == "15:00")
        p.evaluate(now: fire.addingTimeInterval(-901), force: false)
        #expect(signal()?.attention == .calm)
        p.evaluate(now: fire.addingTimeInterval(-120), force: false)
        #expect(signal()?.attention == .warning)
        p.evaluate(now: fire.addingTimeInterval(-119), force: false)
        #expect(signal()?.value == "1:59")
        p.evaluate(now: fire, force: false)
        #expect(signal()?.attention == .critical)
        p.evaluate(now: fire.addingTimeInterval(59), force: false)
        #expect(signal()?.attention == .critical)
        p.evaluate(now: fire.addingTimeInterval(60), force: false)
        #expect(signal() == nil)
        #expect(p.countdowns.isEmpty)
    }

    @Test func repeatingCountdownSchedulesNextOccurrence() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let fire = Fixture.date(2026, 11, 4, 19)
        p.addCountdown(name: "Gym", fireAt: fire, repeatRule: .weekly([2, 4]))
        p.evaluate(now: fire.addingTimeInterval(61), force: false)
        #expect(p.countdowns.count == 1)
        #expect(p.countdowns[0].fireAt == Fixture.date(2026, 11, 9, 19))
        let s = try #require(p.signals.first { $0.kind == .countdown })
        #expect(s.attention == .calm)
        #expect(s.detail == "At Mon 19:00 · every Mon, Wed")
    }

    @Test func dismissCompletesCountdown() {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        let id = p.addCountdown(name: "Once", fireAt: clock.now.addingTimeInterval(10))
        p.dismiss(signalID: "time.countdown.\(id.uuidString)")
        #expect(p.countdowns.isEmpty)
        let daily = p.addCountdown(name: "Daily", fireAt: clock.now.addingTimeInterval(10), repeatRule: .daily)
        p.dismiss(signalID: "time.countdown.\(daily.uuidString)")
        #expect(p.countdowns.first?.fireAt == Fixture.date(2026, 11, 5, 14, 32))
    }

    @Test func addParsedRoutesEveryKind() {
        let p = makeProvider()
        #expect(p.add(parsed: QuickParse.parse("25m focus", now: Fixture.now, calendar: Fixture.calendar)))
        #expect(p.add(parsed: QuickParse.parse("6pm standup", now: Fixture.now, calendar: Fixture.calendar)))
        #expect(p.add(parsed: QuickParse.parse("sw", now: Fixture.now, calendar: Fixture.calendar)))
        #expect(p.add(parsed: QuickParse.parse("buy milk", now: Fixture.now, calendar: Fixture.calendar)))
        #expect(!p.add(parsed: .invalid(reason: "nope")))
        #expect(p.timers.count == 1 && p.countdowns.count == 1 && p.stopwatch?.isRunning == true && p.todos.count == 1)
    }

    @Test func stopwatchLifecycle() throws {
        let clock = TestClock()
        let p = makeProvider(clock: clock)
        p.startStopwatch()
        clock.now += 42
        p.lapStopwatch()
        clock.now += 20
        p.evaluate(now: clock.now, force: false)
        let running = try #require(p.signals.first { $0.kind == .stopwatch })
        #expect(running.id == "time.stopwatch")
        #expect(running.attention == .info)
        #expect(running.symbol == "stopwatch")
        #expect(running.value == "1:02")
        #expect(p.stopwatch?.laps == [.init(number: 1, total: 42, split: 42)])

        p.stopStopwatch()
        #expect(p.stopwatch?.accumulated == 62)
        #expect(p.signals.first { $0.kind == .stopwatch }?.attention == .calm)
        clock.now += 100  // stopped time does not count
        p.startStopwatch()
        clock.now += 8
        p.lapStopwatch()
        #expect(p.stopwatch?.laps.last == .init(number: 2, total: 70, split: 28))

        p.resetStopwatch()
        #expect(p.stopwatch == nil)
        #expect(!p.signals.contains { $0.kind == .stopwatch })
    }

    @Test func todosCompleteAndRemove() throws {
        let p = makeProvider()
        let id = p.addTodo("buy milk")
        p.complete(todo: id)
        #expect(p.todos[0].done)
        p.remove(todo: id)
        #expect(p.todos.isEmpty)
        // To-dos never produce signals.
        #expect(p.signals.map(\.id) == ["time.clock"])
    }
}

@MainActor
struct MeetingTests {
    private func event(startingIn seconds: TimeInterval, from now: Date, title: String = "Standup",
                       link: JoinLink? = nil) -> MeetingEvent {
        MeetingEvent(id: "e1", title: title, start: now.addingTimeInterval(seconds),
                     end: now.addingTimeInterval(seconds + 1800), joinLink: link)
    }

    @Test func attentionBands() throws {
        let p = makeProvider()
        let now = Fixture.now
        let cases: [(TimeInterval, Attention, String)] = [
            (3 * 3600, .calm, "Standup"),
            (901, .calm, "Standup"),
            (900, .info, "Standup in 15m"),
            (121, .info, "Standup in 2m 1s"),
            (120, .warning, "Standup in 2m"),
            (80, .warning, "Standup in 1m 20s"),
            (20, .warning, "Standup now"),  // Format.relative says "now" inside 30 s
            (0, .critical, "Standup now"),
            (-59, .critical, "Standup now"),
        ]
        for (offset, attention, title) in cases {
            p.meetingEventsOverride = [event(startingIn: offset, from: now)]
            p.evaluate(now: now, force: false)
            let s = try #require(p.signals.first { $0.kind == .meeting }, "offset \(offset)")
            #expect(s.attention == attention, "offset \(offset)")
            #expect(s.title == title, "offset \(offset)")
            #expect(s.symbol == "calendar")
            #expect(s.tint == .blue)
            #expect(s.priority == 55)
            #expect(s.id == "time.meeting.e1")
        }
    }

    @Test func meetingDisappearsAfterOneMinute() {
        let p = makeProvider()
        p.meetingEventsOverride = [event(startingIn: -60, from: Fixture.now)]  // exactly start + 1 min
        p.evaluate(now: Fixture.now, force: false)
        #expect(p.nextMeeting != nil)
        p.meetingEventsOverride = [event(startingIn: -61, from: Fixture.now)]
        p.evaluate(now: Fixture.now, force: false)
        #expect(p.nextMeeting == nil)
        #expect(!p.signals.contains { $0.kind == .meeting })
    }

    @Test func detailAndJoinAction() throws {
        let p = makeProvider()
        let url = URL(string: "https://acme.zoom.us/j/123456789")!
        let start = Fixture.date(2026, 11, 4, 9, 40)
        p.meetingEventsOverride = [MeetingEvent(id: "z", title: "Standup", start: start, end: Fixture.date(2026, 11, 4, 10, 10),
                                                joinLink: JoinLink(url: url, service: "Zoom"))]
        p.evaluate(now: Fixture.date(2026, 11, 4, 9, 30), force: false)
        let s = try #require(p.signals.first { $0.kind == .meeting })
        #expect(s.detail == "9:40–10:10 · Zoom")
        #expect(s.actionURL == url)
        #expect(s.actionTitle == "Join")
        #expect(s.deadline == start)
        #expect(s.attention == .info)
    }

    @Test func meetingWithoutLinkHasNoAction() throws {
        let p = makeProvider()
        p.meetingEventsOverride = [event(startingIn: 3600, from: Fixture.now)]
        p.evaluate(now: Fixture.now, force: false)
        let s = try #require(p.signals.first { $0.kind == .meeting })
        #expect(s.actionURL == nil && s.actionTitle == nil)
        #expect(s.detail == "15:32–16:02")
    }

    @Test func twelveHourRange() {
        let a = Fixture.date(2026, 11, 4, 9, 40), b = Fixture.date(2026, 11, 4, 10, 10), c = Fixture.date(2026, 11, 4, 12, 10)
        #expect(TimeFormatting.range(a, b, zone: Fixture.zone, uses24Hour: false) == "9:40–10:10 AM")
        #expect(TimeFormatting.range(b, c, zone: Fixture.zone, uses24Hour: false) == "10:10 AM–12:10 PM")
    }

    @Test func nextPicksSoonestAndDismissHides() throws {
        let p = makeProvider()
        let now = Fixture.now
        p.meetingEventsOverride = [
            MeetingEvent(id: "late", title: "Later", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000)),
            MeetingEvent(id: "soon", title: "Sooner", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800)),
        ]
        p.evaluate(now: now, force: false)
        #expect(p.nextMeeting?.id == "soon")
        p.dismiss(signalID: "time.meeting.soon")
        #expect(p.nextMeeting?.id == "late")
    }

    @Test func calendarDisabledMeansNoMeetingSignals() {
        let p = makeProvider()
        #expect(p.nextMeeting == nil)
        #expect(!p.signals.contains { $0.kind == .meeting })
    }
}

struct JoinLinkTests {
    @Test("service detection", arguments: [
        ("Join: https://us02web.zoom.us/j/81234567890?pwd=abc.", "Zoom", "https://us02web.zoom.us/j/81234567890?pwd=abc"),
        ("https://meet.google.com/abc-defg-hij", "Meet", "https://meet.google.com/abc-defg-hij"),
        ("<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y>", "Teams", "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y"),
        ("Webex: https://acme.webex.com/meet/jo", "Webex", "https://acme.webex.com/meet/jo"),
        ("(https://facetime.apple.com/join#v=1&p=abc)", "FaceTime", "https://facetime.apple.com/join#v=1&p=abc"),
    ])
    func services(_ text: String, _ service: String, _ url: String) throws {
        let link = try #require(MeetingLinks.extract(url: nil, location: text, notes: nil))
        #expect(link.service == service)
        #expect(link.url.absoluteString == url)
    }

    @Test func noLinkCases() {
        #expect(MeetingLinks.extract(url: nil, location: "Room 4B", notes: "see https://example.com/agenda") == nil)
        #expect(MeetingLinks.extract(url: nil, location: "https://meet.google.com/", notes: nil) == nil)
        #expect(MeetingLinks.extract(url: nil, location: nil, notes: nil) == nil)
    }

    @Test func prefersUrlThenLocationThenNotes() throws {
        let zoom = URL(string: "https://zoom.us/j/1")!
        let a = try #require(MeetingLinks.extract(url: zoom, location: "https://meet.google.com/aaa-bbbb-ccc", notes: nil))
        #expect(a.service == "Zoom")
        let b = try #require(MeetingLinks.extract(url: nil, location: "https://meet.google.com/aaa-bbbb-ccc",
                                                  notes: "https://zoom.us/j/2"))
        #expect(b.service == "Meet")
        let c = try #require(MeetingLinks.extract(url: nil, location: "Office", notes: "Agenda https://example.com then https://zoom.us/j/2"))
        #expect(c.service == "Zoom")
    }
}

struct WorldClockTests {
    private let local = Fixture.zone  // UTC+5:30

    @Test func newYorkAt24Hour() throws {
        let c = try #require(WorldClock.make(identifier: "America/New_York", now: Fixture.now, local: local, uses24Hour: true))
        #expect(c.cityName == "New York")
        #expect(c.time == "04:02")  // 09:02 UTC, EST after the 1 Nov change
        #expect(c.offsetDescription == "-10h30")
        #expect(!c.isDaytime)
        #expect(c.id == "America/New_York")
    }

    @Test func newYorkAt12Hour() throws {
        let c = try #require(WorldClock.make(identifier: "America/New_York", now: Fixture.now, local: local, uses24Hour: false))
        #expect(c.time == "4:02 AM")
    }

    @Test func offsetsAndDaytime() throws {
        let utc = TimeZone(identifier: "UTC")!
        let kabul = try #require(WorldClock.make(identifier: "Asia/Kabul", now: Fixture.now, local: utc, uses24Hour: true))
        #expect(kabul.offsetDescription == "+4h30")
        let kathmandu = try #require(WorldClock.make(identifier: "Asia/Kathmandu", now: Fixture.now, local: utc, uses24Hour: true))
        #expect(kathmandu.offsetDescription == "+5h45")
        let same = try #require(WorldClock.make(identifier: "UTC", now: Fixture.now, local: utc, uses24Hour: true))
        #expect(same.offsetDescription == "+0h")
        #expect(same.cityName == "UTC")
        #expect(same.abbreviation == "UTC")
        let dubai = try #require(WorldClock.make(identifier: "Asia/Dubai", now: Fixture.now, local: local, uses24Hour: true))
        #expect(dubai.offsetDescription == "-1h30")
        #expect(dubai.time == "13:02")
        #expect(dubai.isDaytime)
        let tokyo = try #require(WorldClock.make(identifier: "Asia/Tokyo", now: Fixture.now, local: local, uses24Hour: true))
        #expect(tokyo.time == "18:02")
        #expect(tokyo.offsetDescription == "+3h30")
        #expect(!tokyo.isDaytime)  // 18:00 is dusk
    }

    @Test func invalidIdentifierIsDropped() {
        #expect(WorldClock.make(identifier: "Mars/Olympus", now: Fixture.now, local: local, uses24Hour: true) == nil)
    }

    @MainActor @Test func providerBuildsClocksFromSettings() {
        var s = ModuleSettings()
        s.secondaryTimeZones = ["UTC", "Nowhere/Land", "America/New_York"]
        let p = makeProvider(settings: s)
        #expect(p.worldClocks.map(\.cityName) == ["UTC", "New York"])
        s.secondaryTimeZones = ["Asia/Tokyo"]
        p.apply(s)
        #expect(p.worldClocks.map(\.cityName) == ["Tokyo"])
    }
}

@MainActor
struct PersistenceTests {
    @Test func storeRoundTrip() throws {
        let dir = Fixture.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TimeStore(directory: dir)
        #expect(store.load() == TimeState())  // missing file

        var state = TimeState()
        state.timers = [TimerItem(name: "Focus", duration: 1500, startedAt: Fixture.now)]
        state.countdowns = [Countdown(name: "Gym", fireAt: Fixture.now.addingTimeInterval(3600), repeatRule: .weekly([2, 4]))]
        state.stopwatch = Stopwatch(startedAt: nil, accumulated: 12.5, laps: [.init(number: 1, total: 12.5, split: 12.5)])
        state.todos = [TodoItem(text: "buy milk", done: true, createdAt: Fixture.now)]
        try store.save(state)
        #expect(store.load() == state)
        #expect(store.fileURL.lastPathComponent == "time.json")
    }

    @Test func corruptFileLoadsEmpty() throws {
        let dir = Fixture.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8).write(to: dir.appendingPathComponent("time.json"))
        #expect(TimeStore(directory: dir).load() == TimeState())
    }

    @Test func providerPersistsAndReloads() throws {
        let dir = Fixture.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock()
        let a = makeProvider(clock: clock, directory: dir)
        a.addTimer(name: "Focus", seconds: 1500)
        a.addCountdown(name: "Gym", fireAt: clock.now.addingTimeInterval(3600), repeatRule: .daily)
        a.startStopwatch()
        a.addTodo("buy milk")
        a.flush()
        #expect(a.lastSaveError == nil)

        let b = makeProvider(clock: clock, directory: dir)
        #expect(b.timers == a.timers)
        #expect(b.countdowns == a.countdowns)
        #expect(b.stopwatch == a.stopwatch)
        #expect(b.todos == a.todos)
        #expect(b.signals.map(\.id).sorted() == a.signals.map(\.id).sorted())
    }

    @Test func debouncedSaveEventuallyWrites() async throws {
        let dir = Fixture.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = makeProvider(directory: dir)
        p.addTodo("later")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("time.json").path))
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(TimeStore(directory: dir).load().todos.map(\.text) == ["later"])
    }
}
