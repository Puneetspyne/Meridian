import Foundation

/// Turns one line typed into the quick-add box into a timer, countdown, stopwatch or to-do.
///
/// Grammar (case-insensitive, name = the remaining words with the first letter capitalised):
/// - durations: `25m focus`, `1h30m`, `90s`, `2h deploy`
/// - times: `6pm standup`, `18:00 standup`, `6:30pm`, `noon`, `midnight`
/// - day qualifiers: `fri 6pm release`, `tomorrow 9am`, `mon 10:00`
/// - repeats: `every day 9am`, `every weekday 10am standup`, `every mon,wed 7pm gym`
/// - `sw` / `stopwatch`
/// - anything else is a to-do.
///
/// A time already past today rolls to tomorrow (or to the next matching weekday).
public enum QuickParse {
    public enum Parsed: Equatable, Sendable {
        case timer(name: String, seconds: TimeInterval)
        case countdown(name: String, fireAt: Date, repeatRule: RepeatRule)
        case stopwatch
        case todo(text: String)
        case invalid(reason: String)
    }

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Parsed {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return .invalid(reason: "Type something: 25m focus, 6pm standup, every day 9am.") }
        let lower = words.map { $0.lowercased() }

        if lower.count == 1, lower[0] == "sw" || lower[0] == "stopwatch" { return .stopwatch }

        // Durations: "25m focus".
        if let seconds = duration(lower[0]) {
            guard seconds > 0 else { return .invalid(reason: "A timer needs a duration above zero.") }
            return .timer(name: name(words, from: 1, default: "Timer"), seconds: seconds)
        }

        // Repeats: "every mon,wed 7pm gym".
        if lower[0] == "every" { return parseRepeat(words, lower, now: now, calendar: calendar) }

        // Optional day qualifier, then a time.
        var index = 0
        var qualifier: Qualifier?
        if let q = Qualifier(lower[0]) {
            qualifier = q
            index = 1
        }
        if index < lower.count, let clock = timeOfDay(lower, at: index) {
            guard let (hour, minute) = clock.value else { return .invalid(reason: "That is not a valid time.") }
            let nameStart = index + clock.consumed
            let fireAt = resolve(hour: hour, minute: minute, qualifier: qualifier, weekdays: nil, now: now, calendar: calendar)
            guard let fireAt else { return .invalid(reason: "Could not work out when that is.") }
            return .countdown(name: name(words, from: nameStart, default: "Countdown"), fireAt: fireAt, repeatRule: .none)
        }

        return .todo(text: words.joined(separator: " "))
    }

    // MARK: Repeats

    private static func parseRepeat(_ words: [String], _ lower: [String], now: Date, calendar: Calendar) -> Parsed {
        let hint = "Try: every day 9am, every weekday 10am standup, every mon,wed 7pm gym."
        guard lower.count > 1 else { return .invalid(reason: hint) }
        var index = 1
        let rule: RepeatRule
        switch lower[1] {
        case "day", "daily":
            rule = .daily
            index = 2
        case "weekday", "weekdays":
            rule = .weekdays
            index = 2
        default:
            var days = Set<Int>()
            while index < lower.count {
                let parts = lower[index].split(separator: ",", omittingEmptySubsequences: true).map(String.init)
                let numbers = parts.compactMap { weekdayNumber($0) }
                guard !parts.isEmpty, numbers.count == parts.count else { break }
                days.formUnion(numbers)
                index += 1
                if !lower[index - 1].hasSuffix(",") { break }
            }
            guard !days.isEmpty else { return .invalid(reason: hint) }
            rule = .weekly(days)
        }
        guard index < lower.count, let clock = timeOfDay(lower, at: index) else {
            return .invalid(reason: "Add a time: " + hint)
        }
        guard let (hour, minute) = clock.value else { return .invalid(reason: "That is not a valid time.") }
        guard let fireAt = resolve(hour: hour, minute: minute, qualifier: nil, weekdays: rule.weekdaySet,
                                   now: now, calendar: calendar)
        else { return .invalid(reason: "Could not work out when that is.") }
        return .countdown(name: name(words, from: index + clock.consumed, default: "Countdown"),
                          fireAt: fireAt, repeatRule: rule)
    }

    // MARK: Pieces

    private enum Qualifier {
        case today, tomorrow, weekday(Int)

        init?(_ word: String) {
            switch word {
            case "today": self = .today
            case "tomorrow", "tmrw": self = .tomorrow
            default:
                guard let day = QuickParse.weekdayNumber(word) else { return nil }
                self = .weekday(day)
            }
        }
    }

    private static func resolve(hour: Int, minute: Int, qualifier: Qualifier?, weekdays: Set<Int>?,
                                now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch qualifier {
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return Schedule.next(hour: hour, minute: minute, fromDay: tomorrow, notBefore: now, weekdays: nil, calendar: calendar)
        case .weekday(let day):
            return Schedule.next(hour: hour, minute: minute, fromDay: today, notBefore: now, weekdays: [day], calendar: calendar)
        case .today, .none:
            return Schedule.next(hour: hour, minute: minute, fromDay: today, notBefore: now, weekdays: weekdays, calendar: calendar)
        }
    }

    /// Calendar weekday number (1 = Sunday) for "mon", "tues", "thursday", ...
    static func weekdayNumber(_ word: String) -> Int? {
        switch word {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "weds", "wednesday": return 4
        case "thu", "thur", "thurs", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return nil
        }
    }

    /// "1h30m", "90s", "25min", "2hr". Returns nil when the word is not purely a duration.
    static func duration(_ word: String) -> TimeInterval? {
        let units: [String: Double] = [
            "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
            "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
            "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        ]
        var total = 0.0
        var digits = ""
        var letters = ""
        var pairs = 0
        func flush() -> Bool {
            guard !digits.isEmpty, let n = Double(digits), let unit = units[letters] else { return false }
            total += n * unit
            pairs += 1
            digits = ""
            letters = ""
            return true
        }
        for ch in word {
            if ch.isASCII, ch.isNumber {
                if !letters.isEmpty, !flush() { return nil }
                digits.append(ch)
            } else if ch.isLetter {
                guard !digits.isEmpty else { return nil }
                letters.append(ch)
            } else {
                return nil
            }
        }
        guard flush(), pairs > 0 else { return nil }
        return total
    }

    private struct Clock {
        /// nil when the word looked like a time but was out of range ("25:99").
        var value: (Int, Int)?
        /// Words used: 2 for "6 pm", otherwise 1.
        var consumed: Int
    }

    /// Reads "6pm", "6:30pm", "6 pm", "18:00", "noon" or "midnight" starting at `index`.
    private static func timeOfDay(_ lower: [String], at index: Int) -> Clock? {
        let word = lower[index]
        if word == "noon" { return Clock(value: (12, 0), consumed: 1) }
        if word == "midnight" { return Clock(value: (0, 0), consumed: 1) }

        // "6 pm" split over two words.
        if word.count <= 2, word.allSatisfy({ $0.isASCII && $0.isNumber }), index + 1 < lower.count,
           lower[index + 1] == "am" || lower[index + 1] == "pm" {
            return Clock(value: twelveHour(word, nil, lower[index + 1]), consumed: 2)
        }

        // "6pm" / "6:30pm".
        if word.hasSuffix("am") || word.hasSuffix("pm") {
            let body = String(word.dropLast(2))
            let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count <= 2, let h = parts.first, isDigits(h, max: 2),
                  parts.count == 1 || isDigits(parts[1], max: 2, exact: 2)
            else { return nil }
            return Clock(value: twelveHour(h, parts.count == 2 ? parts[1] : nil, String(word.suffix(2))), consumed: 1)
        }

        // "18:00".
        let parts = word.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, isDigits(parts[0], max: 2), isDigits(parts[1], max: 2, exact: 2) {
            let h = Int(parts[0])!, m = Int(parts[1])!
            return Clock(value: (0..<24).contains(h) && (0..<60).contains(m) ? (h, m) : nil, consumed: 1)
        }
        return nil
    }

    private static func isDigits(_ s: String, max: Int, exact: Int? = nil) -> Bool {
        guard !s.isEmpty, s.count <= max, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        return exact.map { s.count == $0 } ?? true
    }

    private static func twelveHour(_ hour: String, _ minute: String?, _ meridiem: String) -> (Int, Int)? {
        guard let h = Int(hour), (1...12).contains(h) else { return nil }
        let m = minute.flatMap { Int($0) } ?? 0
        guard (0..<60).contains(m) else { return nil }
        return ((h % 12) + (meridiem == "pm" ? 12 : 0), m)
    }

    private static func name(_ words: [String], from start: Int, default fallback: String) -> String {
        guard start < words.count else { return fallback }
        let joined = words[start...].joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
