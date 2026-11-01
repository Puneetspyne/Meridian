import AppKit
import MeridianKit

/// PLACEHOLDER. Owned by the Notch & Card workstream. The black extension around the hardware notch.
@MainActor
final class NotchPanelController {
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func start(on screen: NSScreen) {}
    func stop() {}
    func openCard() {}
    func closeCard() {}

    /// True when the screen has a hardware notch.
    static func hasNotch(_ screen: NSScreen) -> Bool { screen.safeAreaInsets.top > 0 }
}
