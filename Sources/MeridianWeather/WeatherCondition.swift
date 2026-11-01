import Foundation

/// How much a condition deserves attention on its own.
public enum WeatherSeverity: Int, Sendable, Codable, Comparable {
    case normal = 0
    /// Heavy rain, snow, freezing precipitation.
    case notable = 1
    /// Thunderstorm, hail, violent showers.
    case severe = 2

    public static func < (lhs: WeatherSeverity, rhs: WeatherSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A WMO weather interpretation code (as used by Open-Meteo) turned into words, an SF Symbol and a severity.
public struct WeatherCondition: Sendable, Equatable {
    public let code: Int
    public let isDay: Bool
    public let description: String
    public let symbol: String
    public let severity: WeatherSeverity
    /// True for anything falling from the sky (drizzle, rain, snow, showers, thunderstorm).
    public let isWet: Bool

    public init(code: Int, isDay: Bool) {
        self.code = code
        self.isDay = isDay
        let sun = isDay ? "sun.max.fill" : "moon.stars.fill"
        let partly = isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        let t: (String, String, WeatherSeverity, Bool)
        switch code {
        case 0: t = ("Clear", sun, .normal, false)
        case 1: t = ("Mostly clear", sun, .normal, false)
        case 2: t = ("Partly cloudy", partly, .normal, false)
        case 3: t = ("Overcast", "cloud.fill", .normal, false)
        case 45: t = ("Fog", "cloud.fog.fill", .normal, false)
        case 48: t = ("Rime fog", "cloud.fog.fill", .normal, false)
        case 51: t = ("Light drizzle", "cloud.drizzle.fill", .normal, true)
        case 53: t = ("Drizzle", "cloud.drizzle.fill", .normal, true)
        case 55: t = ("Heavy drizzle", "cloud.drizzle.fill", .normal, true)
        case 56: t = ("Freezing drizzle", "cloud.drizzle.fill", .notable, true)
        case 57: t = ("Heavy freezing drizzle", "cloud.drizzle.fill", .notable, true)
        case 61: t = ("Light rain", "cloud.rain.fill", .normal, true)
        case 63: t = ("Rain", "cloud.rain.fill", .normal, true)
        case 65: t = ("Heavy rain", "cloud.heavyrain.fill", .notable, true)
        case 66: t = ("Freezing rain", "cloud.sleet.fill", .notable, true)
        case 67: t = ("Heavy freezing rain", "cloud.sleet.fill", .notable, true)
        case 71: t = ("Light snow", "cloud.snow.fill", .notable, true)
        case 73: t = ("Snow", "cloud.snow.fill", .notable, true)
        case 75: t = ("Heavy snow", "cloud.snow.fill", .notable, true)
        case 77: t = ("Snow grains", "cloud.snow.fill", .notable, true)
        case 80: t = ("Light showers", "cloud.rain.fill", .normal, true)
        case 81: t = ("Showers", "cloud.rain.fill", .normal, true)
        case 82: t = ("Violent showers", "cloud.heavyrain.fill", .severe, true)
        case 85: t = ("Snow showers", "cloud.snow.fill", .notable, true)
        case 86: t = ("Heavy snow showers", "cloud.snow.fill", .notable, true)
        case 95: t = ("Thunderstorm", "cloud.bolt.rain.fill", .severe, true)
        case 96: t = ("Thunderstorm with hail", "cloud.bolt.rain.fill", .severe, true)
        case 99: t = ("Thunderstorm with heavy hail", "cloud.bolt.rain.fill", .severe, true)
        default: t = ("Unknown", "questionmark.circle", .normal, false)
        }
        description = t.0
        symbol = t.1
        severity = t.2
        isWet = t.3
    }
}
