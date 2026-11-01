import AppKit
import Observation
import MeridianKit

/// Decides which bodies exist and keeps them in step with the Settings body mode and the screens.
///
/// - automatic: notch on every notched screen; the corner body only when no screen has a notch.
/// - both: notch on every notched screen plus the corner on the main screen.
/// - notch / corner: force one. Forcing the notch on a Mac with no notch falls back to the corner,
///   so the app is never invisible.
///
/// Other code asks for the card through `openCard()` / `closeCard()` / `toggleCard()`, or by posting
/// `Notification.Name("meridian.toggleCard")`.
@MainActor
final class BodyCoordinator {
    static let toggleCardNotification = Notification.Name("meridian.toggleCard")

    private let model: AppModel
    private let openSettings: () -> Void
    private var notches: [CGDirectDisplayID: NotchPanelController] = [:]
    private var corner: CornerPanelController?
    private var cornerDisplay: CGDirectDisplayID?
    private var cornerCardOpen = false
    private var running = false
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    // MARK: Lifecycle

    func start() {
        guard !running else { return }
        running = true
        reconcile()
        trackSettings()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Self.toggleCardNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleCard() }
        })
    }

    func stop() {
        running = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        notches.values.forEach { $0.stop() }
        notches = [:]
        corner?.stop()
        corner = nil
        cornerDisplay = nil
        cornerCardOpen = false
    }

    // MARK: Card

    var isCardOpen: Bool { notches.values.contains { $0.isOpen } || cornerCardOpen }

    func openCard() {
        if let notch = primaryNotch {
            notch.openCard()
        } else if let corner {
            corner.openCard()
            cornerCardOpen = true
        }
    }

    func closeCard() {
        notches.values.forEach { $0.closeCard() }
        if cornerCardOpen { corner?.closeCard(); cornerCardOpen = false }
    }

    func toggleCard() { isCardOpen ? closeCard() : openCard() }

    /// The notch on the main screen if it has one, otherwise any notch.
    private var primaryNotch: NotchPanelController? {
        if let main = NSScreen.main, let id = Self.displayID(of: main), let c = notches[id] { return c }
        return notches.values.first
    }

    // MARK: Reconcile

    private func trackSettings() {
        guard running else { return }
        withObservationTracking {
            _ = model.settings.body
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.reconcile()
                self.trackSettings()
            }
        }
    }

    private func reconcile() {
        guard running else { return }
        let notched = NSScreen.screens.filter(NotchPanelController.hasNotch)
        let wantNotch: Bool
        let wantCorner: Bool
        switch model.settings.body {
        case .automatic: wantNotch = !notched.isEmpty; wantCorner = notched.isEmpty
        case .notch: wantNotch = !notched.isEmpty; wantCorner = notched.isEmpty
        case .corner: wantNotch = false; wantCorner = true
        case .both: wantNotch = !notched.isEmpty; wantCorner = true
        }

        // Notch bodies: one per notched screen.
        let wanted: [CGDirectDisplayID: NSScreen] = wantNotch
            ? Dictionary(uniqueKeysWithValues: notched.compactMap { s in Self.displayID(of: s).map { ($0, s) } })
            : [:]
        for (id, controller) in notches where wanted[id] == nil {
            controller.stop()
            notches[id] = nil
        }
        for (id, screen) in wanted where notches[id] == nil {
            let controller = NotchPanelController(model: model, openSettings: openSettings)
            controller.start(on: screen)
            notches[id] = controller
        }

        // Corner body: the main screen.
        if wantCorner {
            let main = NSScreen.main ?? NSScreen.screens.first
            let id = main.flatMap(Self.displayID(of:))
            if corner == nil || cornerDisplay != id {
                corner?.stop()
                let c = corner ?? CornerPanelController(model: model, openSettings: openSettings)
                c.start(on: main)
                corner = c
                cornerDisplay = id
                cornerCardOpen = false
            }
        } else if let c = corner {
            c.stop()
            corner = nil
            cornerDisplay = nil
            cornerCardOpen = false
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
