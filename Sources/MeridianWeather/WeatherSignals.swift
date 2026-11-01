import Foundation
import MeridianKit

/// Turns a forecast into signals. Pure, so tests pin the exact output.
enum WeatherSignals {
    static func formatHour(_ date: Date, zone: TimeZone, use24Hour: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = use24Hour ? "HH:mm" : "h a"
        return f.string(from: date)
    }

    /// Hours after `now` and up to six hours ahead.
    static func nextSixHours(_ forecast: Forecast, now: Date) -> [HourForecast] {
        forecast.hourly.filter { $0.time > now && $0.time <= now.addingTimeInterval(6 * 3600) }
    }

    static func make(forecast: Forecast, placeName: String, unit: TemperatureUnit,
                     use24Hour: Bool, now: Date) -> [Signal] {
        let cur = forecast.current
        let cond = cur.condition
        let zone = forecast.timeZone
        let ahead = nextSixHours(forecast, now: now)

        var detail = "\(cond.description) · feels \(Format.temperature(cur.feelsLike, unit: unit))"
        if let rainy = ahead.first(where: { $0.precipitationProbability >= 40 }) {
            detail += " · rain \(rainy.precipitationProbability)% at \(formatHour(rainy.time, zone: zone, use24Hour: use24Hour))"
        }

        var signals = [Signal(
            id: "weather.current", kind: .weather, attention: .calm, title: placeName, detail: detail,
            symbol: cond.symbol, value: Format.temperature(cur.temperature, unit: unit),
            createdAt: now, priority: 4, tint: .neutral)]

        if cond.severity == .severe {
            signals.append(Signal(
                id: "weather.alert", kind: .weather, attention: .warning, title: cond.description,
                detail: "\(placeName) · \(Format.temperature(cur.temperature, unit: unit))",
                symbol: cond.symbol, value: Format.temperature(cur.temperature, unit: unit),
                createdAt: now, priority: 45, tint: .amber))
        } else if !cond.isWet, cur.precipitation < 0.1,
                  let soon = ahead.first(where: { $0.precipitationProbability >= 70 }) {
            let peak = ahead.map(\.precipitationProbability).max() ?? soon.precipitationProbability
            signals.append(Signal(
                id: "weather.alert", kind: .weather, attention: .info,
                title: "Rain at \(formatHour(soon.time, zone: zone, use24Hour: use24Hour))",
                detail: "\(peak)% chance in \(placeName)",
                symbol: "umbrella.fill", createdAt: now, priority: 20, tint: .blue))
        }
        return signals
    }
}
