import AppKit
import SwiftUI
import MeridianKit

/// A panel that can never take focus or activate the app: it floats over the menu bar and the pointer works on it,
/// but the user's frontmost app stays frontmost.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Borderless windows are normally pushed below the menu bar. This one lives over it on purpose.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosts the SwiftUI notch. Hits outside the drawn shape fall through (`hitTest` returns nil) and the first click
/// on a non-key panel is delivered instead of being swallowed.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Interactive area in this view's (flipped) coordinates.
    var hitRect: () -> NSRect = { .zero }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return hitRect().contains(local) ? super.hitTest(point) : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// The black extension around the hardware notch.
///
/// Interaction contract:
/// - The panel is big enough for the open card but is mouse-transparent (`ignoresMouseEvents`) until the pointer is
///   over the visible shape, found with mouse-moved monitors, so the menu bar beside the wings stays clickable.
/// - Pointer enters the closed shape: it grows (hover). After `notchHoverDelay` it opens, if hover-to-open is on.
///   Pointer leaves: hover and the pending open cancel at once.
/// - Click on the closed shape opens at once.
/// - Open: pointer leaves for 400 ms, Esc, a click outside, or `cardAutoCloseSeconds` without pointer activity closes.
@MainActor
final class NotchPanelController {
    private let model: AppModel
    private let openSettings: () -> Void
    private let state = NotchState()

    private var panel: NotchPanel?
    private var host: NotchHostingView<NotchView>?
    private var displayID: CGDirectDisplayID?
    private var geometry: NotchGeometry?
    private var panelHeight: CGFloat = 0

    private var pointerInside = false
    /// After an Esc or auto close with the pointer still on the shape, do not reopen until it leaves and returns.
    private var suppressHover = false
    private var dwellTimer: Timer?
    private var closeTimer: Timer?
    private var idleTimer: Timer?
    private var moveMonitors: [Any] = []
    private var openMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    var isOpen: Bool { state.isOpen }
    var isActive: Bool { panel != nil }

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    // MARK: Lifecycle

    func start(on screen: NSScreen) {
        stop()
        guard let g = NotchGeometry(screen: screen) else { return }
        geometry = g
        displayID = Self.displayID(of: screen)
        panelHeight = NotchLayout.panelHeight(for: screen.frame.height, notchHeight: g.notchHeight)

        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.title = "Meridian notch"

        let view = NotchView(model: model, state: state, geometry: g, panelHeight: panelHeight,
                             openSettings: { [weak self] in self?.closeCard(); self?.openSettings() },
                             onClosedTap: { [weak self] in self?.openCard() })
        let host = NotchHostingView(rootView: view)
        host.hitRect = { [weak self] in self?.hitRectInView() ?? .zero }
        panel.contentView = host
        self.host = host
        self.panel = panel

        applyFrame()
        panel.orderFrontRegardless()
        installMoveMonitors()
        installObservers()
    }

    func stop() {
        cancelTimers()
        removeOpenMonitors()
        moveMonitors.forEach { NSEvent.removeMonitor($0) }
        moveMonitors = []
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        host = nil
        state.isOpen = false
        state.isHovering = false
        pointerInside = false
    }

    // MARK: Card

    func openCard() {
        guard panel != nil, !state.isOpen else { return }
        cancelTimers()
        installOpenMonitors()
        animate(Design.Motion.open) {
            state.isOpen = true
            state.isHovering = false
        }
        resetIdle()
    }

    func closeCard() {
        guard state.isOpen else { return }
        cancelTimers()
        removeOpenMonitors()
        suppressHover = pointerInside
        animate(Design.Motion.close) {
            state.isOpen = false
            state.isHovering = false
        }
    }

    func toggleCard() { state.isOpen ? closeCard() : openCard() }

    // MARK: Geometry

    private func applyFrame() {
        guard let panel, let g = geometry else { return }
        let w = Design.NotchMetrics.panelWidth
        panel.setFrame(NSRect(x: g.centerX - w / 2, y: g.topY - panelHeight, width: w, height: panelHeight), display: true)
    }

    private var currentLayout: NotchLayout? {
        guard let g = geometry else { return nil }
        return NotchLayout(geometry: g, wing: model.settings.notchWingWidth, cardHeight: state.cardHeight, panelHeight: panelHeight)
    }

    private func currentSize() -> CGSize {
        currentLayout?.size(open: state.isOpen, hovering: state.isHovering) ?? .zero
    }

    /// The visible shape in global screen coordinates, padded a hair at the top so the screen's top edge counts.
    private func screenRect() -> NSRect {
        guard let g = geometry else { return .zero }
        let s = currentSize()
        // While closed, the pointer enters on the resting shape and stays "inside" on the grown one.
        let size = (!state.isOpen && !state.isHovering) ? (currentLayout?.closedSize ?? s) : s
        return NSRect(x: g.centerX - size.width / 2, y: g.topY - size.height, width: size.width, height: size.height + 2)
    }

    private func hitRectInView() -> NSRect {
        let s = currentSize()
        let w = Design.NotchMetrics.panelWidth
        return NSRect(x: (w - s.width) / 2, y: 0, width: s.width, height: s.height)
    }

    // MARK: Pointer

    private func installMoveMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) { moveMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in handler(event); return event }) { moveMonitors.append(l) }
    }

    private func pointerMoved() {
        guard let panel, panel.isVisible else { return }
        let inside = screenRect().contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside && !pointerInside {
            pointerInside = true
            pointerEntered()
        } else if !inside && pointerInside {
            pointerInside = false
            pointerLeft()
        } else if inside, state.isOpen {
            resetIdle()
        }
    }

    private func pointerEntered() {
        closeTimer?.invalidate()
        closeTimer = nil
        guard !state.isOpen, !suppressHover else { return }
        animate(Design.Motion.hover) { state.isHovering = true }
        guard model.settings.notchHoverToOpen else { return }
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: model.settings.notchHoverDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.openCard() }
        }
    }

    private func pointerLeft() {
        suppressHover = false
        dwellTimer?.invalidate()
        dwellTimer = nil
        if state.isOpen {
            closeTimer?.invalidate()
            closeTimer = Timer.scheduledTimer(withTimeInterval: Design.NotchMetrics.exitCloseDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeCard() }
            }
        } else if state.isHovering {
            animate(Design.Motion.hover) { state.isHovering = false }
        }
    }

    private func resetIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
        let seconds = model.settings.cardAutoCloseSeconds
        guard seconds > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeCard() }
        }
    }

    private func cancelTimers() {
        dwellTimer?.invalidate(); dwellTimer = nil
        closeTimer?.invalidate(); closeTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
    }

    // MARK: Open-only monitors

    /// Esc is only seen while Meridian is the active app (the panel never takes focus, by design). A click anywhere
    /// outside the card closes it, which needs no special permission.
    private func installOpenMonitors() {
        removeOpenMonitors()
        if let k = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closeCard() }
            return nil
        }) { openMonitors.append(k) }
        let outside: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isOpen else { return }
                if !self.screenRect().contains(NSEvent.mouseLocation) { self.closeCard() }
            }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: outside) { openMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in outside(event); return event }) { openMonitors.append(l) }
    }

    private func removeOpenMonitors() {
        openMonitors.forEach { NSEvent.removeMonitor($0) }
        openMonitors = []
    }

    // MARK: Observers

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
    }

    /// Resolution, arrangement or notch changed: find our display again and re-anchor, or hide if it lost its notch.
    private func screensChanged() {
        guard let id = displayID, let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == id }),
              let g = NotchGeometry(screen: screen) else {
            panel?.orderOut(nil)
            return
        }
        geometry = g
        panelHeight = NotchLayout.panelHeight(for: screen.frame.height, notchHeight: g.notchHeight)
        host?.rootView = NotchView(model: model, state: state, geometry: g, panelHeight: panelHeight,
                                   openSettings: { [weak self] in self?.closeCard(); self?.openSettings() },
                                   onClosedTap: { [weak self] in self?.openCard() })
        applyFrame()
        panel?.orderFrontRegardless()
    }

    // MARK: Helpers

    private func animate(_ animation: Animation, _ body: () -> Void) {
        let reduce = Motion.reduce(override: model.settings.reduceMotionOverride)
        withAnimation(Design.Motion.respecting(animation, reduce: reduce), body)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// True when the screen has a hardware notch.
    static func hasNotch(_ screen: NSScreen) -> Bool { screen.safeAreaInsets.top > 0 }
}
