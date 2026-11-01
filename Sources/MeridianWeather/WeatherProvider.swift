import Foundation
import MeridianKit

/// PLACEHOLDER. Owned by the Weather workstream. Open-Meteo current conditions and forecast, no API key.
@MainActor
public final class WeatherProvider: SignalProvider {
    public let providerID = "weather"
    public private(set) var signals: [Signal] = []
    public var onChange: (@MainActor () -> Void)?
    public init(settings: ModuleSettings) {}
    public func start() {}
    public func stop() {}
    public func apply(_ settings: ModuleSettings) {}
}
