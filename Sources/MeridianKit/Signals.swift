import Foundation

/// How much a signal deserves the user's eye. The closed surface shows exactly one signal: the top of the ranking.
public enum Attention: Int, Sendable, Codable, Comparable, CaseIterable {
    case calm = 0
    case info = 1
    case warning = 2
    case critical = 3

    public static func < (lhs: Attention, rhs: Attention) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum SignalKind: String, Sendable, Codable, CaseIterable {
    case thermal, cpu, memory, disk, network, battery, power, gpu
    case timer, countdown, stopwatch, meeting
    case agent
    case weather
    case clock
    case custom
}

/// A single accent per signal. Mapped to system colours in the app so every surface stays consistent.
public enum SignalTint: String, Sendable, Codable, CaseIterable {
    case neutral, teal, blue, green, amber, red, violet, pink
}

/// A signal is anything worth a glance: a hot CPU, a meeting in two minutes, an agent waiting on you.
/// Every module in Meridian speaks this one vocabulary, which is what lets the notch show "the one thing that matters".
public struct Signal: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var kind: SignalKind
    public var attention: Attention
    /// Short, fits a notch wing: "CPU 94%", "Standup", "Claude needs you".
    public var title: String
    /// One line for the card: "Xcode is using 7 cores", "in 1m 20s · Zoom".
    public var detail: String?
    /// SF Symbol name.
    public var symbol: String
    /// 0...1 for arcs and rings when the signal has a natural fill.
    public var progress: Double?
    /// The headline number as text: "94%", "71°", "12:40".
    public var value: String?
    /// For countdowns, meetings and timers: the ranker prefers the soonest.
    public var deadline: Date?
    public var createdAt: Date
    /// Tie-breaker within the same attention. Higher wins.
    public var priority: Int
    public var tint: SignalTint
    /// Optional deep link the card can open: a session URL, a meeting join link, a settings pane.
    public var actionURL: URL?
    public var actionTitle: String?

    public init(id: String, kind: SignalKind, attention: Attention, title: String, detail: String? = nil,
                symbol: String, progress: Double? = nil, value: String? = nil, deadline: Date? = nil,
                createdAt: Date = Date(), priority: Int = 0, tint: SignalTint = .neutral,
                actionURL: URL? = nil, actionTitle: String? = nil) {
        self.id = id
        self.kind = kind
        self.attention = attention
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.progress = progress
        self.value = value
        self.deadline = deadline
        self.createdAt = createdAt
        self.priority = priority
        self.tint = tint
        self.actionURL = actionURL
        self.actionTitle = actionTitle
    }
}

/// Decides what the closed surface shows. Pure and deterministic so it is trivially testable.
///
/// Order: higher attention first; within the same attention the soonest deadline, then higher priority,
/// then the most recently created. Calm signals (the clock, an ambient CPU ring) only surface when nothing else does.
public enum UrgencyRanker {
    public static func rank(_ signals: [Signal], now: Date = Date()) -> [Signal] {
        signals.sorted { a, b in
            if a.attention != b.attention { return a.attention > b.attention }
            switch (a.deadline, b.deadline) {
            case let (da?, db?) where da != db:
                return da < db
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.createdAt > b.createdAt
        }
    }

    public static func top(_ signals: [Signal], now: Date = Date()) -> Signal? {
        rank(signals, now: now).first
    }

    /// Signals that need acting on, for badges and notifications.
    public static func urgent(_ signals: [Signal]) -> [Signal] {
        signals.filter { $0.attention >= .warning }
    }
}
