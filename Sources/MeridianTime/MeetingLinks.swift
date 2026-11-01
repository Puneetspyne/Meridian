import Foundation

/// A video-call link found on a calendar event.
public struct JoinLink: Equatable, Sendable {
    public var url: URL
    /// "Zoom", "Meet", "Teams", "Webex", "FaceTime".
    public var service: String
}

/// Finds the join link of a meeting in its URL, location and notes, in that order.
public enum MeetingLinks {
    public static func extract(url: URL?, location: String?, notes: String?) -> JoinLink? {
        var sources: [String] = []
        if let url { sources.append(url.absoluteString) }
        if let location { sources.append(location) }
        if let notes { sources.append(notes) }
        for text in sources {
            for candidate in urls(in: text) {
                if let service = service(for: candidate) { return JoinLink(url: candidate, service: service) }
            }
        }
        return nil
    }

    static func urls(in text: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\)\]]+"#, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            var raw = String(text[r])
            while let last = raw.last, ".,;:!?".contains(last) { raw.removeLast() }
            return URL(string: raw)
        }
    }

    static func service(for url: URL) -> String? {
        let s = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        if s.contains("zoom.us/j/") { return "Zoom" }
        if host == "meet.google.com", url.path.count > 1 { return "Meet" }
        if s.contains("teams.microsoft.com/l/meetup-join") { return "Teams" }
        if host == "webex.com" || host.hasSuffix(".webex.com") { return "Webex" }
        if host == "facetime.apple.com" { return "FaceTime" }
        return nil
    }
}

/// A calendar event reduced to what Meridian shows.
public struct MeetingEvent: Equatable, Identifiable, Sendable {
    /// Unique per occurrence (recurring events share an event identifier, so the start time is part of it).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var joinLink: JoinLink?

    public init(id: String, title: String, start: Date, end: Date, joinLink: JoinLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.joinLink = joinLink
    }

    /// The soonest event whose start is at or after `now - 1 minute`, so "now" stays up for a minute.
    public static func next(in events: [MeetingEvent], now: Date, skipping dismissed: Set<String> = []) -> MeetingEvent? {
        events
            .filter { $0.start >= now.addingTimeInterval(-60) && !dismissed.contains($0.id) }
            .min { $0.start < $1.start }
    }
}
