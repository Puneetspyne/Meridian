import AppKit
import Observation
import MeridianKit

/// The optional menu bar item (docs/DESIGN.md, "Menu bar item"). Left click toggles the card through
/// `meridian.toggleCard`, which the body coordinator listens to; right click shows the menu.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let openSettings: () -> Void
    private var item: NSStatusItem?
    private var timer: Timer?
    private var style: MenuBarStyle?
    private var paused = false
    private var lastTitle = ""
    private var lastSymbol = ""

    private static let toggleCard = Notification.Name("meridian.toggleCard")

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        rebuild()
        track()
    }

    deinit {
        // Only touched from the main actor in practice; the controller lives as long as the app.
        MainActor.assumeIsolated {
            timer?.invalidate()
            if let item { NSStatusBar.system.removeStatusItem(item) }
        }
    }

    // MARK: Style

    private func track() {
        withObservationTracking {
            _ = model.settings.menuBar
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.rebuild()
                self.track()
            }
        }
    }

    private func rebuild() {
        let wanted = model.settings.menuBar
        guard wanted != style else { return }
        style = wanted
        timer?.invalidate(); timer = nil
        lastTitle = ""; lastSymbol = ""

        if wanted == .hidden {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            created.button?.target = self
            created.button?.action = #selector(clicked(_:))
            created.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            created.behavior = []
            item = created
        }
        item?.button?.setAccessibilityLabel("Meridian")
        refresh()
        if wanted != .icon {
            // Once a second at most: the value does not need to move faster than the sampler.
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    // MARK: Content

    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

    private func refresh() {
        guard let button = item?.button, let style else { return }
        switch style {
        case .hidden:
            return
        case .icon:
            button.title = ""
            button.image = Self.glyph
            button.imagePosition = .imageOnly
            button.toolTip = "Meridian"
        case .cpu:
            show(text: model.snapshot.cpu.map { Format.percent($0.total) } ?? "–", symbol: nil, tip: "CPU")
        case .temperature:
            let unit = model.settings.modules.temperatureUnit
            let c = model.snapshot.thermal?.cpuCelsius ?? model.snapshot.thermal?.hottestCelsius
            show(text: c.map { Format.temperature($0, unit: unit) } ?? "–", symbol: nil, tip: "Temperature")
        case .topSignal:
            if let top = model.top {
                show(text: top.value ?? top.title, symbol: top.symbol, tip: top.title)
            } else {
                show(text: "", symbol: "circle.dotted", tip: "Meridian")
            }
        }
    }

    private func show(text: String, symbol: String?, tip: String) {
        guard let button = item?.button else { return }
        if text != lastTitle {
            lastTitle = text
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: Self.valueFont,
                .baselineOffset: 0,
            ])
        }
        let sym = symbol ?? ""
        if sym != lastSymbol {
            lastSymbol = sym
            if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                img.isTemplate = true
                button.image = img
            } else {
                button.image = nil
            }
        }
        button.imagePosition = button.image == nil ? .noImage : (text.isEmpty ? .imageOnly : .imageLeading)
        button.toolTip = tip
        button.setAccessibilityLabel("Meridian, \(tip) \(text)")
    }

    // MARK: Glyph

    /// 18 x 18 template: a circle with one thin meridian arc. Template, so the system tints it for light,
    /// dark, and the highlighted state.
    static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 7.25
            let circle = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            circle.lineWidth = 1.4
            circle.stroke()

            // The meridian: the right half of a narrow ellipse, pole to pole.
            let arc = NSBezierPath()
            arc.move(to: NSPoint(x: c.x, y: c.y + r))
            arc.curve(to: NSPoint(x: c.x, y: c.y - r),
                      controlPoint1: NSPoint(x: c.x + 5.6, y: c.y + r * 0.62),
                      controlPoint2: NSPoint(x: c.x + 5.6, y: c.y - r * 0.62))
            arc.lineWidth = 1.0
            arc.lineCapStyle = .round
            arc.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Meridian"
        return image
    }()

    // MARK: Actions

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRight {
            showMenu()
        } else {
            NotificationCenter.default.post(name: Self.toggleCard, object: self)
        }
    }

    private func showMenu() {
        guard let item else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        add(menu, "Open Meridian", #selector(openCard), "")

        let pause = add(menu, paused ? "Resume updates" : "Pause updates", #selector(togglePause), "")
        pause.state = paused ? .on : .off

        let bodyItem = NSMenuItem(title: "Body", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Body")
        for mode in BodyMode.allCases {
            let mi = NSMenuItem(title: mode.label, action: #selector(pickBody(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = model.settings.body == mode ? .on : .off
            sub.addItem(mi)
        }
        bodyItem.submenu = sub
        menu.addItem(bodyItem)

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(settings), ",")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Meridian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // Attach only for this click, so the next left click is still ours.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    @objc private func openCard() { NotificationCenter.default.post(name: Self.toggleCard, object: self) }
    @objc private func settings() { openSettings() }

    @objc private func togglePause() {
        paused.toggle()
        if paused { model.stop() } else { model.start() }
    }

    @objc private func pickBody(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = BodyMode(rawValue: raw) else { return }
        model.settings.body = mode
    }
}
