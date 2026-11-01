import Foundation
import MeridianKit

/// Last successful forecast on disk, so the notch has something to show at launch and when offline.
public struct WeatherCache: Sendable {
    public static let defaultMaxAge: TimeInterval = 15 * 60

    public let fileURL: URL
    public let maxAge: TimeInterval
    let now: @Sendable () -> Date

    public init(fileURL: URL? = nil, maxAge: TimeInterval = WeatherCache.defaultMaxAge,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL ?? Paths.supportDirectory.appendingPathComponent("weather-cache.json")
        self.maxAge = maxAge
        self.now = now
    }

    public func save(_ forecast: Forecast) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(forecast) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The cached forecast for this location, of any age. Nil when there is none or it is for somewhere else.
    public func load(latitude: Double, longitude: Double) -> Forecast? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let f = try? dec.decode(Forecast.self, from: data) else { return nil }
        // About 1 km: same place, tolerant of coordinates rounded by the geocoder.
        guard abs(f.latitude - latitude) < 0.02, abs(f.longitude - longitude) < 0.02 else { return nil }
        return f
    }

    public func isFresh(_ forecast: Forecast) -> Bool {
        let age = now().timeIntervalSince(forecast.fetchedAt)
        return age >= 0 && age < maxAge
    }

    public func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
