import Foundation

/// A module that contributes signals (time, agents, weather) to the shared ranking.
///
/// Providers run on the main actor because their consumers are UI state. They publish by
/// setting `signals` and calling `onChange`; the app merges every provider's signals with the rule engine's.
@MainActor
public protocol SignalProvider: AnyObject {
    /// Stable identifier, used to namespace signal ids and settings: "time", "agents", "weather".
    var providerID: String { get }
    /// The provider's current signals. Replace wholesale; the app diffs by `Signal.id`.
    var signals: [Signal] { get }
    /// Called by the provider whenever `signals` changed.
    var onChange: (@MainActor () -> Void)? { get set }
    func start()
    func stop()
}

/// Shared user preferences every module can read. The app owns persistence; modules receive a copy.
public struct ModuleSettings: Sendable, Codable, Equatable {
    public var temperatureUnit: TemperatureUnit = .celsius
    public var uses24HourClock: Bool = true
    public var secondaryTimeZones: [String] = ["UTC"]
    public var weatherEnabled: Bool = false
    public var weatherLocationName: String? = nil
    public var weatherLatitude: Double? = nil
    public var weatherLongitude: Double? = nil
    public var agentsEnabled: Bool = false
    public var calendarEnabled: Bool = false

    public init() {}
}

/// Where Meridian keeps its files: `~/Library/Application Support/Meridian`.
public enum Paths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Meridian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
