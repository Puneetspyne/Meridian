import Foundation

/// Wall-clock formatting for a given time zone, independent of the user's locale so output is predictable.
enum TimeFormatting {
    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// "14:32" or "2:32 PM".
    static func clock(_ date: Date, zone: TimeZone, uses24Hour: Bool) -> String {
        formatter(uses24Hour ? "HH:mm" : "h:mm a", zone).string(from: date)
    }

    /// "Wed 4 Nov".
    static func dayMonth(_ date: Date, zone: TimeZone) -> String {
        formatter("EEE d MMM", zone).string(from: date)
    }

    /// "Fri 18:00" for another day, "18:00" for today.
    static func shortWhen(_ date: Date, now: Date, calendar: Calendar, uses24Hour: Bool) -> String {
        let time = clock(date, zone: calendar.timeZone, uses24Hour: uses24Hour)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        return formatter("EEE", calendar.timeZone).string(from: date) + " " + time
    }

    /// "9:40–10:10" (24 h) or "9:40–10:10 AM" / "11:40 AM–12:10 PM" (12 h).
    static func range(_ start: Date, _ end: Date, zone: TimeZone, uses24Hour: Bool) -> String {
        if uses24Hour {
            let f = formatter("H:mm", zone)
            return "\(f.string(from: start))–\(f.string(from: end))"
        }
        let bare = formatter("h:mm", zone)
        let marker = formatter("a", zone)
        let a = marker.string(from: start), b = marker.string(from: end)
        if a == b { return "\(bare.string(from: start))–\(bare.string(from: end)) \(b)" }
        return "\(bare.string(from: start)) \(a)–\(bare.string(from: end)) \(b)"
    }
}
