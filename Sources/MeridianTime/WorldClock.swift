import Foundation

/// One secondary time zone, formatted for the card and the corner body.
public struct WorldClock: Equatable, Identifiable, Sendable {
    public var identifier: String
    public var abbreviation: String
    /// Last path component with spaces: "America/New_York" becomes "New York".
    public var cityName: String
    /// "14:32" or "2:32 PM" depending on `uses24HourClock`.
    public var time: String
    /// Offset against the local zone: "+4h30", "-10h30", "+0h".
    public var offsetDescription: String
    /// Local hour between 06:00 and 18:00 there.
    public var isDaytime: Bool

    public var id: String { identifier }

    /// nil when `identifier` is not a known time zone.
    public static func make(identifier: String, now: Date, local: TimeZone, uses24Hour: Bool) -> WorldClock? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let city = (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
        let diff = zone.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        return WorldClock(
            identifier: identifier,
            abbreviation: ["UTC", "Etc/UTC", "GMT", "Etc/GMT"].contains(identifier) ? "UTC" : (zone.abbreviation(for: now) ?? identifier),
            cityName: city,
            time: TimeFormatting.clock(now, zone: zone, uses24Hour: uses24Hour),
            offsetDescription: offset(diff),
            isDaytime: (6..<18).contains(hour))
    }

    static func offset(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let total = abs(seconds) / 60
        let h = total / 60, m = total % 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h" + String(format: "%02d", m)
    }
}
