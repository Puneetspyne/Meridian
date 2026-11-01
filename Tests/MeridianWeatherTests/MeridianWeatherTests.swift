import Foundation
import Testing
import MeridianKit
@testable import MeridianWeather

// MARK: - Fixtures (shape from the Open-Meteo documentation, Bengaluru, 2 Nov 2026)

let forecastJSON = """
{
  "latitude": 12.97, "longitude": 77.59, "generationtime_ms": 0.21,
  "utc_offset_seconds": 19800, "timezone": "Asia/Kolkata", "timezone_abbreviation": "GMT+5:30",
  "elevation": 911.0,
  "current_units": {"time": "iso8601", "interval": "seconds", "temperature_2m": "°C"},
  "current": {
    "time": "2026-11-02T14:15", "interval": 900, "temperature_2m": 27.4, "apparent_temperature": 29.1,
    "relative_humidity_2m": 61, "is_day": 1, "weather_code": 2, "wind_speed_10m": 11.2, "precipitation": 0.0
  },
  "hourly": {
    "time": ["2026-11-02T14:00","2026-11-02T15:00","2026-11-02T16:00","2026-11-02T17:00","2026-11-02T18:00","2026-11-02T19:00","2026-11-02T20:00","2026-11-02T21:00"],
    "temperature_2m": [27.4, 27.0, 26.1, 25.0, 24.2, 23.8, 23.1, null],
    "precipitation_probability": [10, 20, 45, 60, 75, 80, 30, 10],
    "weather_code": [2, 3, 61, 63, 95, 61, 3, 1]
  },
  "daily": {
    "time": ["2026-11-02","2026-11-03"],
    "weather_code": [3, 61],
    "temperature_2m_max": [28.5, 27.0],
    "temperature_2m_min": [19.2, 19.8],
    "sunrise": ["2026-11-02T06:10", "2026-11-03T06:10"],
    "sunset": ["2026-11-02T17:56", "2026-11-03T17:55"],
    "precipitation_probability_max": [80, 65]
  }
}
"""

let geocodingJSON = """
{"results":[
 {"id":1277333,"name":"Bengaluru","latitude":12.97194,"longitude":77.59369,"elevation":911.0,"feature_code":"PPLA","country_code":"IN","admin1_id":1267701,"timezone":"Asia/Kolkata","population":8443675,"country_id":1269750,"country":"India","admin1":"Karnataka"},
 {"id":1880252,"name":"Singapore","latitude":1.28967,"longitude":103.85007,"timezone":"Asia/Singapore","country":"Singapore","admin1":"Singapore"}
],"generationtime_ms":0.8}
"""

/// 14:20 local in Bengaluru.
let fixtureNow = RawForecast.parse("2026-11-02T14:20", in: TimeZone(identifier: "Asia/Kolkata")!)!

func fixtureForecast(fetchedAt: Date = fixtureNow) throws -> Forecast {
    try JSONDecoder().decode(RawForecast.self, from: Data(forecastJSON.utf8)).normalised(fetchedAt: fetchedAt)
}

final class StubTransport: WeatherTransport, @unchecked Sendable {
    var handler: @Sendable (URLRequest) throws -> (Data, Int)
    private(set) var requests: [URLRequest] = []
    init(_ handler: @escaping @Sendable (URLRequest) throws -> (Data, Int)) { self.handler = handler }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let (d, code) = try handler(request)
        return (d, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

func tempCache(now: @escaping @Sendable () -> Date = { fixtureNow }) -> WeatherCache {
    WeatherCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("meridian-weather-\(UUID().uuidString).json"), now: now)
}

// MARK: - Decoding

@Test func forecastDecodes() throws {
    let f = try fixtureForecast()
    #expect(f.timeZoneIdentifier == "Asia/Kolkata")
    #expect(f.current.temperature == 27.4)
    #expect(f.current.feelsLike == 29.1)
    #expect(f.current.humidity == 61)
    #expect(f.current.isDay)
    #expect(f.current.condition.description == "Partly cloudy")
    #expect(f.hourly.count == 7, "the hour with a null temperature is skipped")
    #expect(f.hourly[2].precipitationProbability == 45)
    #expect(f.daily.count == 2)
    #expect(f.daily[0].high == 28.5)
    #expect(f.daily[0].precipitationProbabilityMax == 80)
    #expect(f.daily[0].sunrise == RawForecast.parse("2026-11-02T06:10", in: f.timeZone))
    // 14:15 local at +05:30 is 08:45 UTC.
    #expect(f.current.time == ISO8601DateFormatter().date(from: "2026-11-02T08:45:00Z"))
    // Night derived from sunset at 17:56.
    #expect(f.hourly[3].isDay)
    #expect(!f.hourly[4].isDay)
}

@Test func geocodingDecodesAndFormatsDisplayName() async throws {
    let t = StubTransport { _ in (Data(geocodingJSON.utf8), 200) }
    let places = try await OpenMeteoClient(transport: t).geocode(query: "Bengaluru")
    #expect(places.count == 2)
    #expect(places[0].displayName == "Bengaluru, Karnataka, India")
    #expect(places[0].timezone == "Asia/Kolkata")
    #expect(places[1].displayName == "Singapore", "repeated parts collapse")
}

@Test func geocodingNoResultsIsEmpty() async throws {
    let t = StubTransport { _ in (Data(#"{"generationtime_ms":0.3}"#.utf8), 200) }
    #expect(try await OpenMeteoClient(transport: t).geocode(query: "zzzzzz").isEmpty)
}

@Test func errorsAreReadable() async throws {
    let offline = StubTransport { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: WeatherError.offline) { try await OpenMeteoClient(transport: offline).forecast(latitude: 1, longitude: 2) }
    let slow = StubTransport { _ in throw URLError(.timedOut) }
    await #expect(throws: WeatherError.timeout) { try await OpenMeteoClient(transport: slow).forecast(latitude: 1, longitude: 2) }
    let bad = StubTransport { _ in (Data(#"{"error":true,"reason":"Latitude must be in range of -90 to 90°."}"#.utf8), 400) }
    await #expect(throws: WeatherError.server("Latitude must be in range of -90 to 90°.")) {
        try await OpenMeteoClient(transport: bad).forecast(latitude: 100, longitude: 2)
    }
    let junk = StubTransport { _ in (Data("<html>".utf8), 200) }
    do {
        _ = try await OpenMeteoClient(transport: junk).forecast(latitude: 1, longitude: 2)
        Issue.record("expected a decoding error")
    } catch let e as WeatherError {
        if case .decoding = e {} else { Issue.record("wrong error \(e)") }
        #expect(e.errorDescription?.isEmpty == false)
    }
    for e in [WeatherError.offline, .timeout, .badStatus(500), .invalidURL, .noLocation] {
        #expect(e.errorDescription?.isEmpty == false)
    }
}

// MARK: - URLs

@Test func forecastURLConstruction() throws {
    let url = try #require(OpenMeteoClient.forecastURL(latitude: 12.97, longitude: 77.59))
    let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(c.host == "api.open-meteo.com")
    #expect(c.path == "/v1/forecast")
    func q(_ n: String) -> String? { c.queryItems?.first { $0.name == n }?.value }
    #expect(q("latitude") == "12.97")
    #expect(q("longitude") == "77.59")
    #expect(q("current") == "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,precipitation")
    #expect(q("hourly") == "temperature_2m,precipitation_probability,weather_code")
    #expect(q("daily") == "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max")
    #expect(q("timezone") == "auto")
    #expect(q("temperature_unit") == "celsius")
    #expect(q("forecast_hours") == "24")
    #expect(q("forecast_days") == "7")
}

@Test func geocodeURLConstructionEscapesQuery() throws {
    let url = try #require(OpenMeteoClient.geocodeURL(query: "San José & co"))
    let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(c.host == "geocoding-api.open-meteo.com")
    #expect(c.path == "/v1/search")
    #expect(c.queryItems?.first { $0.name == "name" }?.value == "San José & co")
    #expect(c.queryItems?.first { $0.name == "count" }?.value == "8")
    #expect(c.queryItems?.first { $0.name == "language" }?.value == "en")
    #expect(!url.absoluteString.contains(" "))
}

@Test func requestsCarryTenSecondTimeout() async throws {
    let t = StubTransport { _ in (Data(forecastJSON.utf8), 200) }
    _ = try await OpenMeteoClient(transport: t).forecast(latitude: 12.97, longitude: 77.59)
    #expect(t.requests.first?.timeoutInterval == 10)
}

// MARK: - WMO mapping

@Test(arguments: [
    (0, true, "Clear", "sun.max.fill", WeatherSeverity.normal),
    (0, false, "Clear", "moon.stars.fill", .normal),
    (2, true, "Partly cloudy", "cloud.sun.fill", .normal),
    (2, false, "Partly cloudy", "cloud.moon.fill", .normal),
    (3, true, "Overcast", "cloud.fill", .normal),
    (45, true, "Fog", "cloud.fog.fill", .normal),
    (53, true, "Drizzle", "cloud.drizzle.fill", .normal),
    (61, true, "Light rain", "cloud.rain.fill", .normal),
    (63, true, "Rain", "cloud.rain.fill", .normal),
    (65, true, "Heavy rain", "cloud.heavyrain.fill", .notable),
    (66, true, "Freezing rain", "cloud.sleet.fill", .notable),
    (73, true, "Snow", "cloud.snow.fill", .notable),
    (81, true, "Showers", "cloud.rain.fill", .normal),
    (82, true, "Violent showers", "cloud.heavyrain.fill", .severe),
    (95, true, "Thunderstorm", "cloud.bolt.rain.fill", .severe),
    (96, true, "Thunderstorm with hail", "cloud.bolt.rain.fill", .severe),
    (99, false, "Thunderstorm with heavy hail", "cloud.bolt.rain.fill", .severe),
    (42, true, "Unknown", "questionmark.circle", .normal),
])
func wmoMapping(code: Int, isDay: Bool, text: String, symbol: String, severity: WeatherSeverity) {
    let c = WeatherCondition(code: code, isDay: isDay)
    #expect(c.description == text)
    #expect(c.symbol == symbol)
    #expect(c.severity == severity)
}

@Test func everyDocumentedCodeIsKnown() {
    for code in [0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99] {
        #expect(WeatherCondition(code: code, isDay: true).description != "Unknown", "code \(code)")
    }
}

// MARK: - Signals

@Test func rainSoonRaisesInfoAndDetailMentionsFirstRainyHour() throws {
    let f = try fixtureForecast()
    var s = ModuleSettings(); s.temperatureUnit = .celsius
    let signals = WeatherSignals.make(forecast: f, placeName: "Bengaluru", unit: .celsius, use24Hour: true, now: fixtureNow)
    #expect(signals.map(\.id) == ["weather.current", "weather.alert"])
    let cur = signals[0]
    #expect(cur.kind == .weather && cur.attention == .calm && cur.priority == 4 && cur.tint == .neutral)
    #expect(cur.title == "Bengaluru")
    #expect(cur.value == "27°")
    #expect(cur.detail == "Partly cloudy · feels 29° · rain 45% at 16:00")
    #expect(cur.symbol == "cloud.sun.fill")
    let alert = signals[1]
    #expect(alert.attention == .info && alert.priority == 20 && alert.tint == .blue)
    #expect(alert.title == "Rain at 18:00")
    #expect(alert.symbol == "umbrella.fill")
}

@Test func twelveHourClockAndFahrenheit() throws {
    let f = try fixtureForecast()
    let signals = WeatherSignals.make(forecast: f, placeName: "Bengaluru", unit: .fahrenheit, use24Hour: false, now: fixtureNow)
    #expect(signals[0].value == "81°")
    #expect(signals[0].detail == "Partly cloudy · feels 84° · rain 45% at 4 PM")
    #expect(signals[1].title == "Rain at 6 PM")
}

@Test func thunderstormNowIsAWarning() throws {
    var f = try fixtureForecast()
    f.current.weatherCode = 95
    f.current.precipitation = 2.4
    let signals = WeatherSignals.make(forecast: f, placeName: "Bengaluru", unit: .celsius, use24Hour: true, now: fixtureNow)
    let alert = try #require(signals.first { $0.id == "weather.alert" })
    #expect(alert.attention == .warning && alert.priority == 45)
    #expect(alert.title == "Thunderstorm")
}

@Test func calmDayHasOnlyTheCurrentSignal() throws {
    var f = try fixtureForecast()
    f.hourly = f.hourly.map { var h = $0; h.precipitationProbability = 10; return h }
    let signals = WeatherSignals.make(forecast: f, placeName: "Bengaluru", unit: .celsius, use24Hour: true, now: fixtureNow)
    #expect(signals.map(\.id) == ["weather.current"])
    #expect(signals[0].detail == "Partly cloudy · feels 29°")
}

@Test func alreadyRainingSuppressesRainWarning() throws {
    var f = try fixtureForecast()
    f.current.weatherCode = 63
    f.current.precipitation = 1.2
    let signals = WeatherSignals.make(forecast: f, placeName: "Bengaluru", unit: .celsius, use24Hour: true, now: fixtureNow)
    #expect(signals.map(\.id) == ["weather.current"])
}

@Test func rainBeyondSixHoursIsIgnored() throws {
    var f = try fixtureForecast()
    f.hourly = f.hourly.map { var h = $0; h.precipitationProbability = h.time > fixtureNow.addingTimeInterval(6 * 3600) ? 90 : 0; return h }
    let signals = WeatherSignals.make(forecast: f, placeName: "X", unit: .celsius, use24Hour: true, now: fixtureNow)
    #expect(signals.count == 1)
}

// MARK: - Cache

@Test func cacheFreshnessWithInjectedClock() throws {
    final class Clock: @unchecked Sendable { var t = fixtureNow }
    let clock = Clock()
    let cache = tempCache { clock.t }
    defer { cache.clear() }
    let f = try fixtureForecast(fetchedAt: fixtureNow)
    cache.save(f)
    let loaded = try #require(cache.load(latitude: 12.97, longitude: 77.59))
    #expect(loaded.current == f.current)
    #expect(cache.isFresh(loaded))
    clock.t = fixtureNow.addingTimeInterval(14 * 60 + 59)
    #expect(cache.isFresh(loaded))
    clock.t = fixtureNow.addingTimeInterval(15 * 60)
    #expect(!cache.isFresh(loaded))
    #expect(cache.load(latitude: 40.7, longitude: -74.0) == nil, "another place is a miss")
}

// MARK: - Provider

@MainActor
func makeProvider(transport: StubTransport, cache: WeatherCache, enabled: Bool = true) -> WeatherProvider {
    var s = ModuleSettings()
    s.weatherEnabled = enabled
    s.weatherLocationName = "Bengaluru"
    s.weatherLatitude = 12.97
    s.weatherLongitude = 77.59
    return WeatherProvider(settings: s, client: OpenMeteoClient(transport: transport, now: { fixtureNow }),
                           cache: cache, now: { fixtureNow })
}

@MainActor @Test func providerRefreshPublishesSignalsAndCaches() async throws {
    let t = StubTransport { _ in (Data(forecastJSON.utf8), 200) }
    let cache = tempCache(); defer { cache.clear() }
    let p = makeProvider(transport: t, cache: cache)
    var changes = 0
    p.onChange = { changes += 1 }
    await p.refresh()
    #expect(p.providerID == "weather")
    #expect(p.signals.map(\.id) == ["weather.current", "weather.alert"])
    #expect(p.current?.temperature == 27.4)
    #expect(!p.isStale && p.lastError == nil)
    #expect(p.lastUpdated == fixtureNow)
    #expect(p.daily.count == 2)
    #expect(p.hourly.first?.time == RawForecast.parse("2026-11-02T14:00", in: p.forecast!.timeZone))
    #expect(p.sunset != nil)
    #expect(p.place?.name == "Bengaluru")
    #expect(changes > 0)
    #expect(cache.load(latitude: 12.97, longitude: 77.59) != nil)

    // A second, non-forced refresh is served from the fresh cache without touching the network.
    await p.refresh()
    #expect(t.requests.count == 1)
}

@MainActor @Test func offlineFallsBackToStaleCache() async throws {
    let cache = tempCache(); defer { cache.clear() }
    // Cache written 40 minutes ago.
    cache.save(try fixtureForecast(fetchedAt: fixtureNow.addingTimeInterval(-40 * 60)))
    let t = StubTransport { _ in throw URLError(.notConnectedToInternet) }
    let p = makeProvider(transport: t, cache: cache)
    await p.refresh()
    #expect(p.isStale)
    #expect(p.lastError == .offline)
    #expect(p.current?.temperature == 27.4)
    #expect(!p.signals.isEmpty)
}

@MainActor @Test func disabledOrLocationlessProviderIsSilent() async throws {
    let t = StubTransport { _ in (Data(forecastJSON.utf8), 200) }
    let off = makeProvider(transport: t, cache: tempCache(), enabled: false)
    await off.refresh()
    #expect(off.signals.isEmpty && t.requests.isEmpty)

    var noLoc = ModuleSettings(); noLoc.weatherEnabled = true
    let p = WeatherProvider(settings: noLoc, client: OpenMeteoClient(transport: t), cache: tempCache())
    await p.refresh()
    #expect(p.signals.isEmpty && t.requests.isEmpty && !p.isEnabled)
}

@MainActor @Test func applyingDisabledSettingsClearsSignals() async throws {
    let t = StubTransport { _ in (Data(forecastJSON.utf8), 200) }
    let cache = tempCache(); defer { cache.clear() }
    let p = makeProvider(transport: t, cache: cache)
    await p.refresh()
    #expect(!p.signals.isEmpty)
    var s = p.settings; s.weatherEnabled = false
    p.apply(s)
    #expect(p.signals.isEmpty && p.current == nil)
}

@MainActor @Test func unitChangeRebuildsWithoutRefetching() async throws {
    let t = StubTransport { _ in (Data(forecastJSON.utf8), 200) }
    let cache = tempCache(); defer { cache.clear() }
    let p = makeProvider(transport: t, cache: cache)
    await p.refresh()
    var s = p.settings; s.temperatureUnit = .fahrenheit
    p.apply(s)
    #expect(p.signals.first?.value == "81°")
    #expect(t.requests.count == 1)
}

// MARK: - Live (optional)

@Test(.enabled(if: ProcessInfo.processInfo.environment["MERIDIAN_LIVE"] == "1"))
func liveBengaluru() async throws {
    let client = OpenMeteoClient()
    let places = try await client.geocode(query: "Bengaluru")
    let p = try #require(places.first)
    let f = try await client.forecast(latitude: p.latitude, longitude: p.longitude)
    print("LIVE \(p.displayName): \(Format.temperature(f.current.temperature, unit: .celsius)) \(f.current.condition.description), feels \(Format.temperature(f.current.feelsLike, unit: .celsius)), hourly \(f.hourly.count), daily \(f.daily.count)")
    #expect(f.daily.count == 7)
    #expect(f.hourly.count == 24)
}
