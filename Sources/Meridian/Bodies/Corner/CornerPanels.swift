import AppKit
import SwiftUI

/// The closed body. Never key, never main, never activates the app.
final class CornerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        // The SwiftUI view is the only thing that should be hit; the controller toggles this per pointer sample.
        ignoresMouseEvents = true
    }
}

/// The open card. It may take key only when a control inside needs typing (the quick add field),
/// and even then without activating Meridian or pulling the user out of the app they are using.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }
}

/// Hosts `CornerView` and turns raw mouse events into press, drag and release for the controller.
/// SwiftUI gestures are not used: the panel itself has to move under the pointer.
final class CornerHostingView: NSHostingView<CornerView> {
    var isPointerOnBody: () -> Bool = { true }
    var onDown: () -> Void = {}
    var onDragged: () -> Void = {}
    var onUp: () -> Void = {}
    var onContextMenu: (NSEvent) -> Void = { _ in }

    required init(rootView: CornerView) {
        super.init(rootView: rootView)
        sizingOptions = []
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Pass through everything outside the drawn quarter circle.
    override func hitTest(_ point: NSPoint) -> NSView? { isPointerOnBody() ? self : nil }

    override func mouseDown(with event: NSEvent) { onDown() }
    override func mouseDragged(with event: NSEvent) { onDragged() }
    override func mouseUp(with event: NSEvent) { onUp() }
    override func rightMouseDown(with event: NSEvent) { onContextMenu(event) }
}

/// Hosts the card and reports when SwiftUI wants a different size, so the panel can follow.
final class CardHostingView<Content: View>: NSHostingView<Content> {
    var onSizeInvalidated: () -> Void = {}

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeInvalidated()
    }
}
