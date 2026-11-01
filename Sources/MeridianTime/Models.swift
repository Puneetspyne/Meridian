import Foundation

/// How a countdown recurs after it fires.
public enum RepeatRule: Codable, Equatable, Hashable, Sendable {
    case none
    case daily
    /// Monday to Friday.
    case weekdays
    /// Calendar weekday numbers, 1 = Sunday ... 7 = Saturday (the `Calendar` convention).
    case weekly(Set<Int>)

    /// The weekdays on which the rule fires, `nil` for a one-off.
    public var weekdaySet: Set<Int>? {
        switch self {
        case .none: return nil
        case .daily: return Set(1...7)
        case .weekdays: return Set(2...6)
        case .weekly(let days): return days
        }
    }

    public var isRepeating: Bool { self != .none }

    /// "every day", "every weekday", "every Mon, Wed". Empty for a one-off.
    public var label: String {
        switch self {
        case .none: return ""
        case .daily: return "every day"
        case .weekdays: return "every weekday"
        case .weekly(let days):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let list = days.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
            return "every " + list.joined(separator: ", ")
        }
    }

    /// The first occurrence strictly after `date`, at the time of day of `reference`.
    public func next(after date: Date, timeOfDayFrom reference: Date, calendar: Calendar) -> Date? {
        guard let days = weekdaySet else { return nil }
        let hm = calendar.dateComponents([.hour, .minute], from: reference)
        return Schedule.next(hour: hm.hour ?? 0, minute: hm.minute ?? 0,
                             fromDay: calendar.startOfDay(for: date), notBefore: date,
                             weekdays: days, calendar: calendar)
    }
}

/// Shared "next wall-clock occurrence" search used by the parser and by repeating countdowns.
enum Schedule {
    /// Walks forward day by day from `fromDay` and returns the first `hour:minute` that is later than `notBefore`
    /// and falls on one of `weekdays` (nil = any day). Gives up after two weeks.
    static func next(hour: Int, minute: Int, fromDay: Date, notBefore: Date,
                     weekdays: Set<Int>?, calendar: Calendar) -> Date? {
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: fromDay),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }
            if candidate <= notBefore { continue }
            if let weekdays, !weekdays.contains(calendar.component(.weekday, from: candidate)) { continue }
            return candidate
        }
        return nil
    }
}

/// A timer. While running it ends at `startedAt + duration`; paused it remembers `pausedRemaining`.
public struct TimerItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Total length, including any minutes added with `addMinutes`.
    public var duration: TimeInterval
    /// Virtual start: while running, `endsAt == startedAt + duration`. Resuming shifts it so that holds.
    public var startedAt: Date
    public var pausedRemaining: TimeInterval?
    public var isRunning: Bool
    /// The user dismissed the "Time's up" signal. The item stays in the list until reset or removed.
    public var isDismissed: Bool

    public init(id: UUID = UUID(), name: String, duration: TimeInterval, startedAt: Date,
                pausedRemaining: TimeInterval? = nil, isRunning: Bool = true, isDismissed: Bool = false) {
        self.id = id
        self.name = name
        self.duration = duration
        self.startedAt = startedAt
        self.pausedRemaining = pausedRemaining
        self.isRunning = isRunning
        self.isDismissed = isDismissed
    }

    /// When the timer fires. `nil` while paused.
    public var endsAt: Date? { isRunning ? startedAt.addingTimeInterval(duration) : nil }

    /// Seconds left; negative once past the end (overtime).
    public func remaining(at now: Date) -> TimeInterval {
        isRunning ? startedAt.addingTimeInterval(duration).timeIntervalSince(now) : (pausedRemaining ?? duration)
    }

    /// Running and past its end.
    public func isFinished(at now: Date) -> Bool { isRunning && remaining(at: now) <= 0 }

    /// 0...1 elapsed fraction.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (duration - remaining(at: now)) / duration))
    }

    mutating func pause(at now: Date) {
        let left = remaining(at: now)
        guard isRunning, left > 0 else { return }
        pausedRemaining = left
        isRunning = false
    }

    mutating func resume(at now: Date) {
        guard !isRunning, let left = pausedRemaining else { return }
        startedAt = now.addingTimeInterval(-(duration - left))
        pausedRemaining = nil
        isRunning = true
        isDismissed = false
    }

    mutating func reset(at now: Date) {
        isRunning = false
        pausedRemaining = duration
        startedAt = now
        isDismissed = false
    }

    mutating func addTime(_ seconds: TimeInterval) {
        guard seconds != 0, duration + seconds > 0 else { return }
        duration += seconds
        if let left = pausedRemaining { pausedRemaining = max(0, left + seconds) }
        isDismissed = false
    }
}

/// A wall-clock target: "6pm standup", "every weekday 10am".
public struct Countdown: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var fireAt: Date
    public var repeatRule: RepeatRule

    public init(id: UUID = UUID(), name: String, fireAt: Date, repeatRule: RepeatRule = .none) {
        self.id = id
        self.name = name
        self.fireAt = fireAt
        self.repeatRule = repeatRule
    }
}

/// A stopwatch. Stopped when `startedAt` is nil; `accumulated` holds the time from earlier runs.
public struct Stopwatch: Codable, Equatable, Sendable {
    public struct Lap: Codable, Equatable, Sendable {
        public var number: Int
        /// Elapsed at the moment of the lap.
        public var total: TimeInterval
        /// Time since the previous lap.
        public var split: TimeInterval
    }

    public var startedAt: Date?
    public var accumulated: TimeInterval
    public var laps: [Lap]

    public init(startedAt: Date? = nil, accumulated: TimeInterval = 0, laps: [Lap] = []) {
        self.startedAt = startedAt
        self.accumulated = accumulated
        self.laps = laps
    }

    public var isRunning: Bool { startedAt != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

/// The smallest possible to-do: anything the quick-add box could not parse as a time.
public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.done = done
        self.createdAt = createdAt
    }
}
