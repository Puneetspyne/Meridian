import AppKit
import SwiftUI
import MeridianKit

/// The standard macOS settings window: unified toolbar, sidebar of panes, one grouped form per pane.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Meridian Settings"
            let host = NSHostingController(rootView: SettingsView(model: model))
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 680, height: 480))
            w.toolbarStyle = .unified
            w.titlebarSeparatorStyle = .automatic
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("MeridianSettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// An accessory app has no main menu, so the standard shortcuts a settings window needs are routed here:
/// close, and the edit commands for the text fields in it.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers else { return false }
        let selector: Selector?
        switch key {
        case "w": performClose(nil); return true
        case "c": selector = #selector(NSText.copy(_:))
        case "v": selector = #selector(NSText.paste(_:))
        case "x": selector = #selector(NSText.cut(_:))
        case "a": selector = #selector(NSText.selectAll(_:))
        case "z": selector = Selector(("undo:"))
        default: selector = nil
        }
        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: self)
    }
}
