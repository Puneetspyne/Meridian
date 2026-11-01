import Foundation
import MeridianKit

/// The seam tests use to avoid the network.
public protocol WeatherTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WeatherTransport {}

public struct OpenMeteoClient: Sendable {
    public static let forecastEndpoint = "https://api.open-meteo.com/v1/forecast"
    public static let geocodingEndpoint = "https://geocoding-api.open-meteo.com/v1/search"
    public static let timeout: TimeInterval = 10

    let transport: WeatherTransport
    let now: @Sendable () -> Date

    public init(transport: WeatherTransport? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.timeout
            config.timeoutIntervalForResource = Self.timeout * 2
            self.transport = URLSession(configuration: config)
        }
        self.now = now
    }

    // MARK: URLs

    /// Temperature is always requested in celsius; `Format` converts for display.
    public static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: forecastEndpoint)
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,precipitation"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "forecast_hours", value: "24"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
        ]
        return c?.url
    }

    public static func geocodeURL(query: String) -> URL? {
        var c = URLComponents(string: geocodingEndpoint)
        c?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
        ]
        return c?.url
    }

    // MARK: Calls

    /// `unit` is accepted for API symmetry with the UI but the request is always celsius.
    public func forecast(latitude: Double, longitude: Double, unit: TemperatureUnit = .celsius) async throws -> Forecast {
        guard let url = Self.forecastURL(latitude: latitude, longitude: longitude) else { throw WeatherError.invalidURL }
        let data = try await fetch(url)
        do {
            let raw = try JSONDecoder().decode(RawForecast.self, from: data)
            return try raw.normalised(fetchedAt: now())
        } catch let e as WeatherError {
            throw e
        } catch {
            throw WeatherError.decoding("\(error)")
        }
    }

    public func geocode(query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let url = Self.geocodeURL(query: trimmed) else { throw WeatherError.invalidURL }
        let data = try await fetch(url)
        do {
            let raw = try JSONDecoder().decode(RawGeocoding.self, from: data)
            return (raw.results ?? []).map {
                Place(name: $0.name, admin1: $0.admin1, country: $0.country,
                      latitude: $0.latitude, longitude: $0.longitude, timezone: $0.timezone)
            }
        } catch {
            throw WeatherError.decoding("\(error)")
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let e as WeatherError {
            throw e
        } catch let e as URLError {
            switch e.code {
            case .timedOut: throw WeatherError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw WeatherError.offline
            default: throw WeatherError.server(e.localizedDescription)
            }
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let reason = try? JSONDecoder().decode(RawError.self, from: data).reason { throw WeatherError.server(reason) }
            throw WeatherError.badStatus(http.statusCode)
        }
        return data
    }
}
