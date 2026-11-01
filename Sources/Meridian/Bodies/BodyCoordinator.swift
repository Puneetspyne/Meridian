import AppKit
import MeridianKit

/// PLACEHOLDER. Owned by the UI workstream (see docs/ARCHITECTURE.md). Decides which bodies to show:
/// the notch body on a notched display, the corner body elsewhere, or both, and keeps them in sync.
@MainActor
final class BodyCoordinator {
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func start() {}
    func stop() {}
}
