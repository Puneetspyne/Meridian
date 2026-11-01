// swift-tools-version:6.0
import PackageDescription

// Meridian builds with the Xcode Command Line Tools alone: `swift build`, no Xcode project.
// Language mode 5 keeps the AppKit/IOKit bridging pragmatic; concurrency is still used where it helps.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Meridian",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Meridian", targets: ["Meridian"]),
        .executable(name: "meridianctl", targets: ["meridianctl"]),
        .library(name: "MeridianKit", targets: ["MeridianKit"]),
    ],
    targets: [
        // Pure Swift, no AppKit: models, urgency ranking, rules, formatting. Unit-testable anywhere.
        .target(name: "MeridianKit", swiftSettings: swift5),

        // C shim for IOKit structures and private symbols resolved at runtime (SMC, HID sensors, IOReport).
        .target(name: "CMeridian", path: "Sources/CMeridian", publicHeadersPath: "include"),

        // Hardware and OS telemetry: CPU, memory, GPU, disks, network, battery, temperatures, fans, power, processes.
        .target(name: "MeridianSensors", dependencies: ["MeridianKit", "CMeridian"], swiftSettings: swift5,
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),

        // Timers, countdowns, stopwatch, calendar (EventKit) and world clocks.
        .target(name: "MeridianTime", dependencies: ["MeridianKit"], swiftSettings: swift5,
                linkerSettings: [.linkedFramework("EventKit")]),

        // Coding-agent sessions (Claude Code hooks), opt-in.
        .target(name: "MeridianAgents", dependencies: ["MeridianKit"], swiftSettings: swift5),

        // Weather via Open-Meteo (no API key).
        .target(name: "MeridianWeather", dependencies: ["MeridianKit"], swiftSettings: swift5),

        // The app: notch body, corner body, card, settings, menu bar item, snapshot renderer.
        .executableTarget(
            name: "Meridian",
            dependencies: ["MeridianKit", "MeridianSensors", "MeridianTime", "MeridianAgents", "MeridianWeather"],
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications")]
        ),

        // Terminal probe: prints a telemetry snapshot as JSON, lists SMC keys, dumps sensor maps for contribution.
        .executableTarget(name: "meridianctl", dependencies: ["MeridianKit", "MeridianSensors"], swiftSettings: swift5),

        .testTarget(name: "MeridianKitTests", dependencies: ["MeridianKit"], swiftSettings: swift5),
        .testTarget(name: "MeridianSensorsTests", dependencies: ["MeridianSensors"], swiftSettings: swift5),
        .testTarget(name: "MeridianTimeTests", dependencies: ["MeridianTime"], swiftSettings: swift5),
        .testTarget(name: "MeridianAgentsTests", dependencies: ["MeridianAgents"], swiftSettings: swift5),
        .testTarget(name: "MeridianWeatherTests", dependencies: ["MeridianWeather"], swiftSettings: swift5),
    ]
)
