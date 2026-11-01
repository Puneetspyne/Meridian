import Foundation
import Testing
@testable import MeridianTime

struct ParseCase: Sendable, CustomTestStringConvertible {
    var input: String
    var expected: QuickParse.Parsed
    var testDescription: String { input }
}

private func d(_ day: Int, _ h: Int, _ m: Int = 0, month: Int = 11) -> Date { Fixture.date(2026, month, day, h, m) }

private let cases: [ParseCase] = [
    // Durations.
    .init(input: "25m focus", expected: .timer(name: "Focus", seconds: 1500)),
    .init(input: "1h30m", expected: .timer(name: "Timer", seconds: 5400)),
    .init(input: "90s", expected: .timer(name: "Timer", seconds: 90)),
    .init(input: "2h deploy", expected: .timer(name: "Deploy", seconds: 7200)),
    .init(input: "10min tea break", expected: .timer(name: "Tea break", seconds: 600)),
    // Times today, past times roll to tomorrow.
    .init(input: "6pm standup", expected: .countdown(name: "Standup", fireAt: d(4, 18), repeatRule: .none)),
    .init(input: "18:00 standup", expected: .countdown(name: "Standup", fireAt: d(4, 18), repeatRule: .none)),
    .init(input: "6:30pm", expected: .countdown(name: "Countdown", fireAt: d(4, 18, 30), repeatRule: .none)),
    .init(input: "6 pm sync", expected: .countdown(name: "Sync", fireAt: d(4, 18), repeatRule: .none)),
    .init(input: "noon", expected: .countdown(name: "Countdown", fireAt: d(5, 12), repeatRule: .none)),
    .init(input: "midnight", expected: .countdown(name: "Countdown", fireAt: d(5, 0), repeatRule: .none)),
    .init(input: "9am", expected: .countdown(name: "Countdown", fireAt: d(5, 9), repeatRule: .none)),
    .init(input: "2:32pm", expected: .countdown(name: "Countdown", fireAt: d(5, 14, 32), repeatRule: .none)),
    .init(input: "12am call", expected: .countdown(name: "Call", fireAt: d(5, 0), repeatRule: .none)),
    .init(input: "6PM Standup", expected: .countdown(name: "Standup", fireAt: d(4, 18), repeatRule: .none)),
    // Day qualifiers.
    .init(input: "fri 6pm release", expected: .countdown(name: "Release", fireAt: d(6, 18), repeatRule: .none)),
    .init(input: "tomorrow 9am", expected: .countdown(name: "Countdown", fireAt: d(5, 9), repeatRule: .none)),
    .init(input: "tomorrow 6pm", expected: .countdown(name: "Countdown", fireAt: d(5, 18), repeatRule: .none)),
    .init(input: "mon 10:00", expected: .countdown(name: "Countdown", fireAt: d(9, 10), repeatRule: .none)),
    .init(input: "wed 6pm", expected: .countdown(name: "Countdown", fireAt: d(4, 18), repeatRule: .none)),
    .init(input: "wed 9am", expected: .countdown(name: "Countdown", fireAt: d(11, 9), repeatRule: .none)),
    .init(input: "today 6pm", expected: .countdown(name: "Countdown", fireAt: d(4, 18), repeatRule: .none)),
    // Repeats.
    .init(input: "every day 9am", expected: .countdown(name: "Countdown", fireAt: d(5, 9), repeatRule: .daily)),
    .init(input: "every weekday 10am standup", expected: .countdown(name: "Standup", fireAt: d(5, 10), repeatRule: .weekdays)),
    .init(input: "every mon,wed 7pm gym", expected: .countdown(name: "Gym", fireAt: d(4, 19), repeatRule: .weekly([2, 4]))),
    .init(input: "every mon, wed 7pm gym", expected: .countdown(name: "Gym", fireAt: d(4, 19), repeatRule: .weekly([2, 4]))),
    .init(input: "every fri 5pm", expected: .countdown(name: "Countdown", fireAt: d(6, 17), repeatRule: .weekly([6]))),
    .init(input: "every sat 8am", expected: .countdown(name: "Countdown", fireAt: d(7, 8), repeatRule: .weekly([7]))),
    // Stopwatch.
    .init(input: "sw", expected: .stopwatch),
    .init(input: "Stopwatch", expected: .stopwatch),
    // To-dos.
    .init(input: "buy milk", expected: .todo(text: "buy milk")),
    .init(input: "5 things to pack", expected: .todo(text: "5 things to pack")),
    .init(input: "fri release notes", expected: .todo(text: "fri release notes")),
    // Invalid.
    .init(input: "", expected: .invalid(reason: "Type something: 25m focus, 6pm standup, every day 9am.")),
    .init(input: "25:99 standup", expected: .invalid(reason: "That is not a valid time.")),
    .init(input: "13pm", expected: .invalid(reason: "That is not a valid time.")),
    .init(input: "0m", expected: .invalid(reason: "A timer needs a duration above zero.")),
]

@Test("QuickParse grammar", arguments: cases)
func quickParse(_ c: ParseCase) {
    #expect(QuickParse.parse(c.input, now: Fixture.now, calendar: Fixture.calendar) == c.expected)
}

@Test func everyWithoutTimeOrDaysIsInvalid() {
    for text in ["every", "every day", "every fortnight 9am", "every mon"] {
        let parsed = QuickParse.parse(text, now: Fixture.now, calendar: Fixture.calendar)
        guard case .invalid = parsed else {
            Issue.record("\(text) parsed as \(parsed)")
            continue
        }
    }
}

@Test func timeEqualToNowRollsForward() {
    // 14:32 exactly now is not in the future.
    let parsed = QuickParse.parse("2:32pm", now: Fixture.now, calendar: Fixture.calendar)
    #expect(parsed == .countdown(name: "Countdown", fireAt: Fixture.date(2026, 11, 5, 14, 32), repeatRule: .none))
}

@Test func repeatRuleAdvancesToNextMatchingDay() {
    let rule = RepeatRule.weekly([2, 4])  // Mon, Wed
    let wedEvening = Fixture.date(2026, 11, 4, 19)
    let next = rule.next(after: wedEvening.addingTimeInterval(61), timeOfDayFrom: wedEvening, calendar: Fixture.calendar)
    #expect(next == Fixture.date(2026, 11, 9, 19))  // Monday
    let weekdays = RepeatRule.weekdays.next(after: Fixture.date(2026, 11, 6, 10, 1), timeOfDayFrom: Fixture.date(2026, 11, 6, 10),
                                            calendar: Fixture.calendar)
    #expect(weekdays == Fixture.date(2026, 11, 9, 10))  // Friday to Monday
    #expect(RepeatRule.none.next(after: Fixture.now, timeOfDayFrom: Fixture.now, calendar: Fixture.calendar) == nil)
}

@Test func repeatRuleCodableRoundTrip() throws {
    for rule in [RepeatRule.none, .daily, .weekdays, .weekly([1, 7])] {
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(RepeatRule.self, from: data) == rule)
    }
}
