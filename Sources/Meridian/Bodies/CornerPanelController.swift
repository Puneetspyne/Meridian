import AppKit
import MeridianKit

/// PLACEHOLDER. Owned by the Corner & Settings workstream. The quarter-circle body in a screen corner.
/// Keep this exact interface: `BodyCoordinator` drives it.
@MainActor
final class CornerPanelController {
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    /// Show on the given screen (defaults to the main screen).
    func start(on screen: NSScreen? = nil) {}
    func stop() {}
    func openCard() {}
    func closeCard() {}
}
