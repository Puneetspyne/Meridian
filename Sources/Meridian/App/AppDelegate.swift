import AppKit
import MeridianKit
import MeridianSensors
import MeridianTime
import MeridianAgents
import MeridianWeather

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var statusItem: StatusItemController?
    private var bodies: BodyCoordinator?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let useMock = CommandLine.arguments.contains("--mock")
        let source: TelemetrySource = useMock ? MockTelemetrySource(scenario: mockScenario()) : LiveTelemetrySource()
        model = AppModel(source: source)

        model.register(provider: TimeProvider(settings: model.settings.modules))
        model.register(provider: AgentsProvider(settings: model.settings.modules))
        model.register(provider: WeatherProvider(settings: model.settings.modules))

        statusItem = StatusItemController(model: model, openSettings: { [weak self] in self?.showSettings() })
        bodies = BodyCoordinator(model: model, openSettings: { [weak self] in self?.showSettings() })
        model.start()
        bodies?.start()

        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        bodies?.stop()
    }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: model) }
        settingsWindow?.show()
    }

    private func mockScenario() -> MockTelemetrySource.Scenario {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scenario"), i + 1 < args.count, let s = MockTelemetrySource.Scenario(rawValue: args[i + 1]) {
            return s
        }
        return .calm
    }
}
