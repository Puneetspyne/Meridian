import AppKit
import SwiftUI
import Observation
import MeridianKit

/// The quarter-circle body in a screen corner (docs/DESIGN.md, "Corner body").
/// `BodyCoordinator` drives it through `start(on:)`, `stop()`, `openCard()` and `closeCard()`.
///
/// Debug: `--corner topRight|topLeft|bottomLeft|bottomRight` forces the corner at launch and logs the panel frame.
@MainActor
final class CornerPanelController {
    private let model: AppModel
    private let openSettings: () -> Void

    private let state = CornerState()
    private let card: CornerCardController
    private let spring = SpringAnimator()

    private var panel: CornerPanel?
    private var hosting: CornerHostingView?
    private var screen: NSScreen?
    private var fullScreenCovering = false

    // Pointer sampling
    private var monitors: [Any] = []
    private var lastSample: CFTimeInterval = 0
    private var trailingSample: DispatchWorkItem?
    private var edgeWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    // Press, hold and drag
    private var holdWork: DispatchWorkItem?
    private var pressMouse = CGPoint.zero
    private var pressOrigin = CGPoint.zero
    private var holdFired = false
    private var dragging = false

    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var environmentWork: DispatchWorkItem?
    private var running = false

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        self.card = CornerCardController(model: model)
        card.onChange = { [weak self] open in
            guard let self else { return }
            self.state.cardOpen = open
            NSLog("[corner] card %@", open ? "open" : "closed")
            self.refreshInteractivity()
        }
    }

    // MARK: Interface used by BodyCoordinator

    /// Show on the given screen (defaults to the main screen).
    func start(on screen: NSScreen? = nil) {
        guard !running else { return }
        running = true
        self.screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        applyDebugCorner()

        let s = model.settings
        state.corner = s.corner
        state.radius = s.cornerSize.points
        state.rest = s.cornerRest
        fullScreenCovering = Self.fullScreenAppCovers(self.screen)

        let host = CornerHostingView(rootView: CornerView(model: model, state: state))
        host.isPointerOnBody = { [weak self] in self?.pointerIsOnBody() ?? false }
        host.onDown = { [weak self] in self?.pressBegan() }
        host.onDragged = { [weak self] in self?.pressMoved() }
        host.onUp = { [weak self] in self?.pressEnded() }
        host.onContextMenu = { [weak self] e in self?.showContextMenu(e) }
        let p = CornerPanel(frame: targetFrame())
        p.contentView = host
        hosting = host
        panel = p
        p.orderFrontRegardless()
        NSLog("[corner] corner=%@ frame=%@", state.corner.rawValue, NSStringFromRect(p.frame))

        installPointerMonitors()
        installEnvironmentObservers()
        trackSettings()
    }

    func stop() {
        guard running else { return }
        running = false
        spring.stop()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        [trailingSample, edgeWork, collapseWork, holdWork, environmentWork].forEach { $0?.cancel() }
        card.teardown()
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
    }

    func openCard() {
        guard running, !card.isOpen else { return }
        state.pressed = false
        card.open(corner: state.corner, area: layoutArea())
    }

    func closeCard() { card.close() }

    private func toggleCard() { card.isOpen ? closeCard() : openCard() }

    // MARK: Placement

    /// The visible frame normally, the full frame when a full-screen app hides the menu bar.
    private func layoutArea() -> CGRect {
        guard let screen else { return .zero }
        return fullScreenCovering ? screen.frame : screen.visibleFrame
    }

    private func targetFrame() -> CGRect {
        CornerGeometry.panelFrame(state.corner, radius: state.radius, in: layoutArea())
    }

    /// Move to the target frame, with the settle spring when `animated`.
    private func reposition(animated: Bool) {
        guard let panel else { return }
        let target = targetFrame()
        if panel.frame.size != target.size { panel.setContentSize(target.size) }
        let reduce = model.settings.reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated, !reduce, panel.frame.origin != target.origin {
            spring.run(from: panel.frame.origin, to: target.origin,
                       response: Design.Corner.settleResponse, damping: Design.Corner.settleDamping,
                       apply: { [weak panel] in panel?.setFrameOrigin($0) },
                       done: { [weak self] in self?.settled() })
        } else {
            spring.stop()
            panel.setFrame(target, display: true)
            settled()
        }
        card.reanchor(corner: state.corner, area: layoutArea())
    }

    private func settled() {
        guard let panel else { return }
        NSLog("[corner] settled corner=%@ frame=%@", state.corner.rawValue, NSStringFromRect(panel.frame))
        refreshInteractivity()
    }

    // MARK: Settings

    private func trackSettings() {
        guard running else { return }
        withObservationTracking {
            _ = model.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.settingsChanged()
                self.trackSettings()
            }
        }
    }

    private func settingsChanged() {
        let s = model.settings
        if state.rest != s.cornerRest {
            state.rest = s.cornerRest
            state.tuckExpanded = false
            state.hovering = false
            refreshInteractivity()
        }
        guard !dragging else { return }
        let radiusChanged = state.radius != s.cornerSize.points
        let cornerChanged = state.corner != s.corner
        if radiusChanged || cornerChanged {
            state.radius = s.cornerSize.points
            state.corner = s.corner
            reposition(animated: cornerChanged)
        }
    }

    /// `--corner` for geometry checks. Persists like any change of corner.
    private func applyDebugCorner() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--corner"), i + 1 < args.count,
              let c = ScreenCorner(rawValue: args[i + 1]) else { return }
        if model.settings.corner != c { model.settings.corner = c }
    }

    // MARK: Environment (screens, Spaces, full screen)

    private func installEnvironmentObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.environmentChanged() }
            })
        }
    }

    /// Debounced: Space switches and app activations arrive in bursts, and the window-list check is not free.
    private func environmentChanged() {
        environmentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            if let current = self.screen, !NSScreen.screens.contains(current) {
                self.screen = NSScreen.main ?? NSScreen.screens.first
            }
            self.fullScreenCovering = Self.fullScreenAppCovers(self.screen)
            if !self.dragging { self.reposition(animated: false) }
        }
        environmentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// A window-list check: an ordinary app window exactly covering the screen means a full-screen app,
    /// which hides the menu bar and the Dock, so the body lays out against the full frame.
    private static func fullScreenAppCovers(_ screen: NSScreen?) -> Bool {
        guard let screen, let primary = NSScreen.screens.first else { return false }
        let cgFrame = CGRect(x: screen.frame.minX, y: primary.frame.height - screen.frame.maxY,
                             width: screen.frame.width, height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r == cgFrame { return true }
        }
        return false
    }

    // MARK: Pointer sampling (at most 20 Hz)

    private func installPointerMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSoon() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.sampleSoon() }
            return e
        }) { monitors.append(m) }
    }

    /// Leading-edge throttle with one trailing sample, so the last position of a flick is never lost.
    private func sampleSoon() {
        let now = CACurrentMediaTime()
        let wait = Design.Corner.pointerSampleInterval - (now - lastSample)
        if wait <= 0 {
            lastSample = now
            sample()
        } else if trailingSample == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.trailingSample = nil
                self.lastSample = CACurrentMediaTime()
                self.sample()
            }
            trailingSample = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
        }
    }

    private func sample() {
        guard let panel, !dragging else { return }
        let p = NSEvent.mouseLocation
        let frame = panel.frame
        let corner = state.corner

        switch state.rest {
        case .shrink:
            // Hysteresis: grow against the resting shape, shrink once the pointer leaves the grown one.
            let radius = state.hovering ? state.radius : state.radius * Design.Corner.restScale
            let over = CornerGeometry.hit(p, corner: corner, panelFrame: frame, drawnRadius: radius)
            if over != state.hovering { state.hovering = over }
        case .tuck:
            sampleTuck(p, frame: frame)
        case .full:
            break
        }

        let overBody = CornerGeometry.hit(p, corner: corner, panelFrame: frame, drawnRadius: state.hitRadius)
        card.pointerMoved(p, overBody: CornerGeometry.hit(p, corner: corner, panelFrame: frame, drawnRadius: state.radius))
        applyInteractivity(overBody: overBody)
    }

    private func sampleTuck(_ p: CGPoint, frame: CGRect) {
        guard let screen else { return }
        if state.tuckExpanded {
            let near = CornerGeometry.hit(p, corner: state.corner, panelFrame: frame, drawnRadius: state.radius + 6)
            if near {
                collapseWork?.cancel(); collapseWork = nil
            } else if collapseWork == nil, !card.isOpen {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let panel = self.panel else { return }
                    self.collapseWork = nil
                    let q = NSEvent.mouseLocation
                    let still = CornerGeometry.hit(q, corner: self.state.corner, panelFrame: panel.frame, drawnRadius: self.state.radius + 6)
                    if !still && !self.dragging { self.state.tuckExpanded = false; self.refreshInteractivity() }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Design.Corner.tuckCollapseDelay, execute: work)
            }
        } else if pressingEdge(p, screen: screen) {
            // Needs a short dwell: sliding along an edge toward the menu bar must not pop the body open.
            guard edgeWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, let screen = self.screen else { return }
                self.edgeWork = nil
                if self.pressingEdge(NSEvent.mouseLocation, screen: screen), !self.state.tuckExpanded {
                    self.state.tuckExpanded = true
                    self.refreshInteractivity()
                }
            }
            edgeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Design.Corner.edgePressDwell, execute: work)
        } else {
            edgeWork?.cancel(); edgeWork = nil
        }
    }

    private func pressingEdge(_ p: CGPoint, screen: NSScreen) -> Bool {
        CornerGeometry.pressingEdge(p, corner: state.corner, area: layoutArea(), screenFrame: screen.frame,
                                    span: state.radius, slop: Design.Corner.edgePressSlop)
    }

    private func pointerIsOnBody() -> Bool {
        guard let panel else { return false }
        return state.dragging || CornerGeometry.hit(NSEvent.mouseLocation, corner: state.corner,
                                                    panelFrame: panel.frame, drawnRadius: state.hitRadius)
    }

    /// The panel only takes the mouse while the pointer is on the drawn shape (and never while tucked or
    /// under the card), so everything around the quarter circle belongs to the app underneath.
    private func applyInteractivity(overBody: Bool) {
        guard let panel else { return }
        let live = !state.cardOpen && !state.isTucked && (state.pressed || state.dragging || overBody)
        if panel.ignoresMouseEvents == live { panel.ignoresMouseEvents = !live }
    }

    private func refreshInteractivity() {
        guard let panel else { return }
        let over = CornerGeometry.hit(NSEvent.mouseLocation, corner: state.corner, panelFrame: panel.frame, drawnRadius: state.hitRadius)
        applyInteractivity(overBody: over)
    }

    // MARK: Press, hold, drag

    private func pressBegan() {
        spring.stop()
        guard let panel else { return }
        pressMouse = NSEvent.mouseLocation
        pressOrigin = panel.frame.origin
        holdFired = false
        dragging = false
        state.pressed = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.pressed, !self.dragging else { return }
            self.holdFired = true
            self.openCard()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.Corner.holdToOpen, execute: work)
    }

    private func pressMoved() {
        guard let panel, state.pressed || dragging else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - pressMouse.x, dy = m.y - pressMouse.y
        if !dragging {
            guard !holdFired, hypot(dx, dy) > Design.Corner.dragThreshold else { return }
            dragging = true
            holdWork?.cancel()
            state.pressed = false
            state.dragging = true
        }
        panel.setFrameOrigin(CGPoint(x: pressOrigin.x + dx, y: pressOrigin.y + dy))
        // The body takes the orientation of the corner it would land in, live.
        let s = Self.screen(containing: m) ?? screen
        if let s {
            let near = CornerGeometry.nearestCorner(to: m, in: s.frame)
            if near != state.corner { state.corner = near }
        }
    }

    private func pressEnded() {
        holdWork?.cancel(); holdWork = nil
        let wasPressed = state.pressed
        state.pressed = false
        if dragging {
            dragging = false
            drop()
        } else if wasPressed, !holdFired {
            toggleCard()
        }
        holdFired = false
        refreshInteractivity()
    }

    /// Spring into the nearest corner of the screen the pointer is on, and remember it.
    private func drop() {
        let m = NSEvent.mouseLocation
        if let s = Self.screen(containing: m) { screen = s }
        guard let screen else { return }
        let corner = CornerGeometry.nearestCorner(to: m, in: screen.frame)
        fullScreenCovering = Self.fullScreenAppCovers(screen)
        state.dragging = false
        state.corner = corner
        state.hovering = true
        if model.settings.corner != corner { model.settings.corner = corner }
        reposition(animated: true)
    }

    private static func screen(containing p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(p) }
    }

    // MARK: Context menu

    private func showContextMenu(_ event: NSEvent) {
        guard let hosting else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Meridian", action: #selector(menuOpenCard), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        NSMenu.popUpContextMenu(menu, with: event, for: hosting)
    }

    @objc private func menuOpenCard() { openCard() }
    @objc private func menuSettings() { openSettings() }
}
