import AppKit
import SwiftUI
import Observation
import MeridianKit

@MainActor
@Observable
final class CornerCardState {
    var corner: ScreenCorner = .topLeft
    var isOpen = false
}

/// The card, as the corner body shows it: a second panel anchored to the corner it grew from.
/// The panel is laid out at its final size at once; the card inside scales out of the corner with `Motion.open`.
@MainActor
final class CornerCardController {
    private let model: AppModel
    private let cardState = CornerCardState()
    private var panel: CardPanel?
    private var hosting: CardHostingView<CornerCardRoot>?
    private var corner: ScreenCorner = .topLeft
    private var area: CGRect = .zero

    private var exitWork: DispatchWorkItem?
    private var autoCloseWork: DispatchWorkItem?
    private var teardownWork: DispatchWorkItem?
    private var resizeScheduled = false
    private var hasEntered = false
    private var monitors: [Any] = []

    private(set) var isOpen = false
    /// Called with the new open state after every open or close.
    var onChange: (Bool) -> Void = { _ in }

    init(model: AppModel) { self.model = model }

    /// The card without its transparent margin: what the user sees, in screen coordinates.
    var visibleFrame: CGRect {
        guard let panel, isOpen else { return .zero }
        return panel.frame.insetBy(dx: Design.Corner.cardMargin, dy: Design.Corner.cardMargin)
    }

    // MARK: Open and close

    func open(corner: ScreenCorner, area: CGRect) {
        guard !isOpen else { return }
        isOpen = true
        hasEntered = false
        self.corner = corner
        self.area = area
        teardownWork?.cancel()
        cardState.corner = corner

        if panel == nil {
            let root = CornerCardRoot(model: model, state: cardState)
            let host = CardHostingView(rootView: root)
            host.onSizeInvalidated = { [weak self] in self?.scheduleResize() }
            let p = CardPanel(frame: CGRect(x: 0, y: 0, width: Design.Size.cardWidth, height: 200))
            p.contentView = host
            hosting = host
            panel = p
        }
        layout()
        panel?.orderFrontRegardless()
        // One tick closed, so SwiftUI has a first frame to grow from.
        cardState.isOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.isOpen else { return }
            self.cardState.isOpen = true
        }
        installMonitors()
        scheduleAutoClose()
        onChange(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        cardState.isOpen = false
        removeMonitors()
        exitWork?.cancel(); exitWork = nil
        autoCloseWork?.cancel(); autoCloseWork = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isOpen else { return }
            self.releasePanel()
        }
        teardownWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        onChange(false)
    }

    func teardown() {
        close()
        teardownWork?.cancel()
        releasePanel()
    }

    /// A hidden panel still keeps its SwiftUI graph alive and re-renders it on every sample, so a closed
    /// card is released entirely and rebuilt on the next open.
    private func releasePanel() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hosting = nil
    }

    /// The body moved to another corner or screen while the card was up.
    func reanchor(corner: ScreenCorner, area: CGRect) {
        self.corner = corner
        self.area = area
        cardState.corner = corner
        if isOpen { layout() }
    }

    // MARK: Pointer

    /// Fed by the controller's 20 Hz pointer sampling.
    func pointerMoved(_ p: CGPoint, overBody: Bool) {
        guard isOpen else { return }
        let inside = overBody || visibleFrame.insetBy(dx: -Design.Corner.cardHoverSlack, dy: -Design.Corner.cardHoverSlack).contains(p)
        if inside {
            hasEntered = true
            exitWork?.cancel(); exitWork = nil
            scheduleAutoClose()
        } else if hasEntered, exitWork == nil {
            // Opened from the menu bar the pointer starts elsewhere: only a real exit arms this.
            let work = DispatchWorkItem { [weak self] in self?.close() }
            exitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Design.Corner.closeDelay, execute: work)
        }
    }

    private func scheduleAutoClose() {
        autoCloseWork?.cancel(); autoCloseWork = nil
        let seconds = model.settings.cardAutoCloseSeconds
        guard seconds > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.close() }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Layout

    private func scheduleResize() {
        guard isOpen, !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            if self.isOpen { self.layout() }
        }
    }

    private func layout() {
        guard let panel, let hosting else { return }
        let margin = Design.Corner.cardMargin, inset = Design.Corner.cardInset
        var fit = hosting.fittingSize
        if fit.width < 1 || fit.height < 1 { fit = CGSize(width: Design.Size.cardWidth + 2 * margin, height: 320) }
        let maxW = max(120, area.width - 2 * inset), maxH = max(120, area.height - 2 * inset)
        let w = min(fit.width - 2 * margin, maxW), h = min(fit.height - 2 * margin, maxH)
        let x = corner.isRight ? area.maxX - inset - w : area.minX + inset
        let y = corner.isBottom ? area.minY + inset : area.maxY - inset - h
        let frame = CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -margin, dy: -margin)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    // MARK: Dismissal monitors

    private func installMonitors() {
        removeMonitors()
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downs, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedAt(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        // Clicks in our own other windows (Settings); clicks on the card itself return early.
        if let m = NSEvent.addLocalMonitorForEvents(matching: downs, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel, let w = event.window, !(w is CornerPanel) {
                    self.close()
                }
            }
            return event
        }) { monitors.append(m) }
        // Esc. The global form needs Accessibility; without it the local one still covers the card being key.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.close() } }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.close() } }
            return e
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func clickedAt(_ p: CGPoint) {
        if !visibleFrame.contains(p) { close() }
    }
}

/// The card with its growth from the corner. Content fades in 60 ms after the shape begins.
struct CornerCardRoot: View {
    let model: AppModel
    let state: CornerCardState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { model.settings.reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let c = state.corner
        let open = state.isOpen
        CardView(model: model, presentation: .corner(c))
            .opacity(open ? 1 : 0)
            .animation(reduceMotion ? .easeInOut(duration: 0.15)
                       : (open ? Design.Motion.swap.delay(Design.Corner.cardContentDelay) : Design.Motion.close), value: open)
            .scaleEffect(reduceMotion || open ? 1 : Design.Corner.cardClosedScale, anchor: c.unitPoint)
            .animation(reduceMotion ? nil : (open ? Design.Motion.open : Design.Motion.close), value: open)
            .padding(Design.Corner.cardMargin)
            .fixedSize()
    }
}
