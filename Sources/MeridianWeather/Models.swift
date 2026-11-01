import Foundation

/// User-readable failures. The settings UI shows `errorDescription` as is.
public enum WeatherError: Error, Equatable, LocalizedError, Sendable {
    case offline
    case timeout
    case badStatus(Int)
    case server(String)
    case decoding(String)
    case invalidURL
    case noLocation

    public var errorDescription: String? {
        switch self {
        case .offline: return "You appear to be offline. Showing the last forecast."
        case .timeout: return "The weather service took too long to answer."
        case .badStatus(let code): return "The weather service returned an error (HTTP \(code))."
        case .server(let reason): return "The weather service said: \(reason)"
        case .decoding: return "The weather service sent a response Meridian could not read."
        case .invalidURL: return "Could not build the weather request."
        case .noLocation: return "Choose a location in Settings to see the weather."
        }
    }
}

/// A geocoding result. Also what the app stores as the chosen location.
public struct Place: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var name: String
    public var admin1: String?
    public var country: String?
    public var latitude: Double
    public var longitude: Double
    public var timezone: String?

    public var id: String { "\(latitude),\(longitude)" }

    public init(name: String, admin1: String? = nil, country: String? = nil,
                latitude: Double, longitude: Double, timezone: String? = nil) {
        self.name = name
        self.admin1 = admin1
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
    }

    /// "Bengaluru, Karnataka, India". Repeated parts ("Singapore, Singapore") are collapsed.
    public var displayName: String {
        var parts = [name]
        for extra in [admin1, country] {
            if let extra, !extra.isEmpty, !parts.contains(extra) { parts.append(extra) }
        }
        return parts.joined(separator: ", ")
    }
}

public struct CurrentConditions: Sendable, Codable, Equatable {
    public var time: Date
    /// Celsius. Format with `Format.temperature`.
    public var temperature: Double
    public var feelsLike: Double
    /// Percent, 0...100.
    public var humidity: Double
    /// km/h.
    public var wind: Double
    /// mm in the last interval.
    public var precipitation: Double
    public var weatherCode: Int
    public var isDay: Bool
    public var condition: WeatherCondition { WeatherCondition(code: weatherCode, isDay: isDay) }
}

public struct HourForecast: Sendable, Codable, Equatable, Identifiable {
    public var time: Date
    public var temperature: Double
    /// Percent, 0...100.
    public var precipitationProbability: Int
    public var weatherCode: Int
    public var isDay: Bool
    public var id: Date { time }
    public var condition: WeatherCondition { WeatherCondition(code: weatherCode, isDay: isDay) }
}

public struct DayForecast: Sendable, Codable, Equatable, Identifiable {
    /// Local midnight of the day in the place's time zone.
    public var date: Date
    public var weatherCode: Int
    public var high: Double
    public var low: Double
    public var sunrise: Date?
    public var sunset: Date?
    public var precipitationProbabilityMax: Int
    public var id: Date { date }
    public var condition: WeatherCondition { WeatherCondition(code: weatherCode, isDay: true) }
}

/// A normalised forecast: real `Date`s, celsius, km/h. This is what is cached and what the UI reads.
public struct Forecast: Sendable, Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    public var current: CurrentConditions
    /// Next 24 hours starting at the current hour.
    public var hourly: [HourForecast]
    /// Seven days starting today.
    public var daily: [DayForecast]
    public var fetchedAt: Date

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

// MARK: - Open-Meteo wire format

/// Field names match the JSON so no key strategy is needed.
struct RawForecast: Decodable {
    struct Current: Decodable {
        var time: String
        var temperature_2m: Double
        var apparent_temperature: Double?
        var relative_humidity_2m: Double?
        var is_day: Int?
        var weather_code: Int
        var wind_speed_10m: Double?
        var precipitation: Double?
    }
    struct Hourly: Decodable {
        var time: [String]
        var temperature_2m: [Double?]
        var precipitation_probability: [Double?]?
        var weather_code: [Int?]
    }
    struct Daily: Decodable {
        var time: [String]
        var weather_code: [Int?]
        var temperature_2m_max: [Double?]
        var temperature_2m_min: [Double?]
        var sunrise: [String?]?
        var sunset: [String?]?
        var precipitation_probability_max: [Double?]?
    }
    var latitude: Double
    var longitude: Double
    var utc_offset_seconds: Int?
    var timezone: String?
    var current: Current
    var hourly: Hourly?
    var daily: Daily?
}

struct RawGeocoding: Decodable {
    struct Result: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var timezone: String?
        var country: String?
        var admin1: String?
    }
    var results: [Result]?
}

struct RawError: Decodable {
    var reason: String?
}

extension RawForecast {
    /// "2026-11-02T14:00" or "2026-11-02", both local to the forecast's zone.
    static func parse(_ text: String, in zone: TimeZone) -> Date? {
        let halves = text.split(separator: "T", maxSplits: 1).map(String.init)
        let ymd = halves[0].split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3 else { return nil }
        var c = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2], hour: 0, minute: 0)
        if halves.count == 2 {
            let hm = halves[1].split(separator: ":").compactMap { Int($0) }
            guard hm.count >= 2 else { return nil }
            c.hour = hm[0]
            c.minute = hm[1]
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: c)
    }

    func normalised(fetchedAt: Date) throws -> Forecast {
        let zone = timezone.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: utc_offset_seconds ?? 0) ?? .gmt
        guard let now = Self.parse(current.time, in: zone) else {
            throw WeatherError.decoding("bad current time \(current.time)")
        }
        let cur = CurrentConditions(
            time: now, temperature: current.temperature_2m,
            feelsLike: current.apparent_temperature ?? current.temperature_2m,
            humidity: current.relative_humidity_2m ?? 0, wind: current.wind_speed_10m ?? 0,
            precipitation: current.precipitation ?? 0, weatherCode: current.weather_code,
            isDay: (current.is_day ?? 1) == 1)

        var days: [DayForecast] = []
        if let d = daily {
            for i in d.time.indices {
                guard let date = Self.parse(d.time[i], in: zone),
                      i < d.temperature_2m_max.count, i < d.temperature_2m_min.count,
                      let hi = d.temperature_2m_max[i], let lo = d.temperature_2m_min[i] else { continue }
                days.append(DayForecast(
                    date: date,
                    weatherCode: (i < d.weather_code.count ? d.weather_code[i] : nil) ?? 0,
                    high: hi, low: lo,
                    sunrise: d.sunrise.flatMap { i < $0.count ? $0[i] : nil }.flatMap { Self.parse($0, in: zone) },
                    sunset: d.sunset.flatMap { i < $0.count ? $0[i] : nil }.flatMap { Self.parse($0, in: zone) },
                    precipitationProbabilityMax: Int(((d.precipitation_probability_max.flatMap { i < $0.count ? $0[i] : nil }) ?? 0).rounded())))
            }
        }

        var hours: [HourForecast] = []
        if let h = hourly {
            for i in h.time.indices {
                guard let time = Self.parse(h.time[i], in: zone),
                      i < h.temperature_2m.count, let temp = h.temperature_2m[i] else { continue }
                // Hourly data has no is_day; derive it from that day's sunrise and sunset.
                let day = days.last { $0.date <= time }
                var isDay = true
                if let rise = day?.sunrise, let set = day?.sunset { isDay = time >= rise && time < set }
                hours.append(HourForecast(
                    time: time, temperature: temp,
                    precipitationProbability: Int(((h.precipitation_probability.flatMap { i < $0.count ? $0[i] : nil }) ?? 0).rounded()),
                    weatherCode: (i < h.weather_code.count ? h.weather_code[i] : nil) ?? 0,
                    isDay: isDay))
            }
        }
        return Forecast(latitude: latitude, longitude: longitude,
                        timeZoneIdentifier: zone.identifier, current: cur,
                        hourly: hours, daily: days, fetchedAt: fetchedAt)
    }
}
