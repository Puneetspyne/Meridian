import AppKit
import MeridianKit

/// PLACEHOLDER. Owned by the UI workstream. Menu bar item: icon or a live value, with a menu for
/// opening the card, pausing, settings and quit.
@MainActor
final class StatusItemController {
    private let model: AppModel
    private let openSettings: () -> Void
    private var item: NSStatusItem?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Meridian")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meridian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.item = item
    }

    @objc private func settings() { openSettings() }
}
