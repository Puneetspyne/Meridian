import Foundation
import MeridianKit

enum BodyMode: String, Codable, CaseIterable, Identifiable {
    /// Notch on a notched display, corner everywhere else.
    case automatic, notch, corner, both
    var id: String { rawValue }
    var label: String {
        switch self { case .automatic: "Automatic"; case .notch: "Notch"; case .corner: "Corner"; case .both: "Notch and corner" }
    }
}

enum ScreenCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    var label: String {
        switch self { case .topLeft: "Top left"; case .topRight: "Top right"; case .bottomLeft: "Bottom left"; case .bottomRight: "Bottom right" }
    }
}

enum CornerRestStyle: String, Codable, CaseIterable, Identifiable {
    /// Full quarter circle at all times.
    case full
    /// Rests small, grows when the pointer arrives.
    case shrink
    /// A 10pt dot that lets clicks through to window controls underneath.
    case tuck
    var id: String { rawValue }
    var label: String { switch self { case .full: "Stay full size"; case .shrink: "Shrink, grow on hover"; case .tuck: "Tuck into a dot" } }
}

enum CornerSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var points: CGFloat { switch self { case .small: 56; case .medium: 72; case .large: 92 } }
    var label: String { rawValue.capitalized }
}

/// Which tiles the card shows and in what order.
enum Tile: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, disk, network, battery, temperature, fans, power, processes, clocks, timers, meeting, agents, weather
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "Memory"; case .disk: "Disk"; case .network: "Network"
        case .battery: "Battery"; case .temperature: "Temperature"; case .fans: "Fans"; case .power: "Power"
        case .processes: "Top processes"; case .clocks: "Clocks"; case .timers: "Timers"; case .meeting: "Next meeting"
        case .agents: "Coding agents"; case .weather: "Weather"
        }
    }
    static let defaultOrder: [Tile] = [.cpu, .memory, .temperature, .network, .disk, .battery, .gpu, .fans, .power, .processes, .meeting, .timers, .clocks, .agents, .weather]
}

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case icon, cpu, temperature, topSignal, hidden
    var id: String { rawValue }
    var label: String {
        switch self { case .icon: "Icon only"; case .cpu: "CPU"; case .temperature: "Temperature"; case .topSignal: "Most urgent"; case .hidden: "Hidden" }
    }
}

struct Settings: Codable, Equatable {
    var body: BodyMode = .automatic
    var corner: ScreenCorner = .topLeft
    var cornerSize: CornerSize = .medium
    var cornerRest: CornerRestStyle = .shrink
    var notchHoverToOpen: Bool = true
    var notchHoverDelay: TimeInterval = 0.35
    var notchWingWidth: CGFloat = 132
    var cardAutoCloseSeconds: TimeInterval = 8
    var refreshInterval: TimeInterval = 1.0
    var tiles: [Tile] = Tile.defaultOrder
    var hiddenTiles: Set<Tile> = [.agents, .weather]
    var menuBar: MenuBarStyle = .icon
    var launchAtLogin: Bool = false
    var reduceMotionOverride: Bool? = nil
    var modules = ModuleSettings()
    var thresholds = Thresholds.default
    var hasCompletedOnboarding: Bool = false

    var visibleTiles: [Tile] { tiles.filter { !hiddenTiles.contains($0) } }

    // MARK: Persistence
    private static let key = "meridian.settings.v1"

    static func load(defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Settings.key) }
    }
}
