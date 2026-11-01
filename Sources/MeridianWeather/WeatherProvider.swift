import Foundation
import MeridianKit

/// Open-Meteo current conditions and forecast, no API key. Silent unless the user enabled weather and picked a place.
@MainActor
public final class WeatherProvider: SignalProvider {
    public let providerID = "weather"
    public private(set) var signals: [Signal] = []
    public var onChange: (@MainActor () -> Void)?

    // MARK: Read-only state for the UI

    public private(set) var forecast: Forecast?
    public private(set) var lastUpdated: Date?
    /// True when what is shown came from the cache because a refresh failed (offline, server error).
    public private(set) var isStale = false
    public private(set) var lastError: WeatherError?
    public private(set) var settings: ModuleSettings

    public var current: CurrentConditions? { forecast?.current }
    /// The next 12 hours, starting with the current hour.
    public var hourly: [HourForecast] {
        guard let f = forecast else { return [] }
        let start = now().addingTimeInterval(-3600)
        return Array(f.hourly.filter { $0.time > start }.prefix(12))
    }
    public var daily: [DayForecast] { forecast?.daily ?? [] }
    public var sunrise: Date? { daily.first?.sunrise }
    public var sunset: Date? { daily.first?.sunset }
    public var place: Place? {
        guard let lat = settings.weatherLatitude, let lon = settings.weatherLongitude else { return nil }
        return Place(name: settings.weatherLocationName ?? "Current location", latitude: lat, longitude: lon,
                     timezone: forecast?.timeZoneIdentifier)
    }
    public var isEnabled: Bool { Self.enabled(settings) }

    // MARK: Internals

    public static let refreshInterval: TimeInterval = 15 * 60
    private let client: OpenMeteoClient
    private let cache: WeatherCache
    private let now: @Sendable () -> Date
    private var started = false
    private var timer: Timer?
    private var generation = 0

    public init(settings: ModuleSettings, client: OpenMeteoClient = OpenMeteoClient(),
                cache: WeatherCache = WeatherCache(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.client = client
        self.cache = cache
        self.now = now
    }

    private static func enabled(_ s: ModuleSettings) -> Bool {
        s.weatherEnabled && s.weatherLatitude != nil && s.weatherLongitude != nil
    }

    /// For the settings location picker.
    public func search(_ query: String) async throws -> [Place] {
        try await client.geocode(query: query)
    }

    public func start() {
        started = true
        if isEnabled { begin() }
    }

    public func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        generation += 1
    }

    public func apply(_ new: ModuleSettings) {
        let old = settings
        settings = new
        guard Self.enabled(new) else {
            let had = forecast != nil || !signals.isEmpty
            timer?.invalidate()
            timer = nil
            generation += 1
            forecast = nil
            lastUpdated = nil
            isStale = false
            lastError = nil
            signals = []
            if had { onChange?() }
            return
        }
        let moved = !Self.enabled(old) || old.weatherLatitude != new.weatherLatitude || old.weatherLongitude != new.weatherLongitude
        if moved {
            forecast = nil
            if started { begin() }
        } else if old.temperatureUnit != new.temperatureUnit || old.uses24HourClock != new.uses24HourClock
                    || old.weatherLocationName != new.weatherLocationName {
            rebuild()
        }
    }

    private func begin() {
        timer?.invalidate()
        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.kick(force: true) }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        kick(force: false)
    }

    private func kick(force: Bool) {
        Task { @MainActor [weak self] in await self?.refresh(force: force) }
    }

    /// Show the cache if it is fresh, otherwise fetch. A failed fetch falls back to the cache and marks it stale.
    public func refresh(force: Bool = false) async {
        guard Self.enabled(settings), let lat = settings.weatherLatitude, let lon = settings.weatherLongitude else { return }
        generation += 1
        let mine = generation
        let cached = cache.load(latitude: lat, longitude: lon)
        if let cached, forecast == nil {
            // Paint something immediately while the network call is in flight.
            adopt(cached, stale: !cache.isFresh(cached), error: nil)
        }
        if !force, let cached, cache.isFresh(cached) {
            adopt(cached, stale: false, error: nil)
            return
        }
        do {
            let fresh = try await client.forecast(latitude: lat, longitude: lon, unit: .celsius)
            guard mine == generation else { return }
            cache.save(fresh)
            adopt(fresh, stale: false, error: nil)
        } catch {
            guard mine == generation else { return }
            let err = (error as? WeatherError) ?? .server(error.localizedDescription)
            if let fallback = forecast ?? cached {
                adopt(fallback, stale: true, error: err)
            } else {
                lastError = err
                onChange?()
            }
        }
    }

    private func adopt(_ f: Forecast, stale: Bool, error: WeatherError?) {
        forecast = f
        lastUpdated = f.fetchedAt
        isStale = stale
        lastError = error
        rebuild()
    }

    private func rebuild() {
        guard let f = forecast, Self.enabled(settings) else { return }
        let name = settings.weatherLocationName ?? "Weather"
        let new = WeatherSignals.make(forecast: f, placeName: name, unit: settings.temperatureUnit,
                                      use24Hour: settings.uses24HourClock, now: now())
        // Keep createdAt stable when nothing else changed so the ranker does not reshuffle ties.
        signals = new
        onChange?()
    }
}
