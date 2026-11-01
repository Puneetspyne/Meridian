import AppKit
import SwiftUI
import MeridianKit
import MeridianTime

/// Renders the notch and card surfaces to PNG with mock data, headless: no panels, no run loop.
/// `swift run Meridian --snapshot docs/snapshots`
@MainActor
enum SnapshotRenderer {
    /// Scenarios the mock source knows, plus two that need module signals (a meeting, a waiting agent).
    enum Scenario: String, CaseIterable {
        case calm, busy, hot, lowBattery, diskFull, charging, meeting, agent

        var mock: MockTelemetrySource.Scenario {
            switch self {
            case .calm, .meeting, .agent: return .calm
            case .busy: return .busy
            case .hot: return .hot
            case .lowBattery: return .lowBattery
            case .diskFull: return .diskFull
            case .charging: return .charging
            }
        }
    }

    static let notchGeometry = NotchGeometry(notchWidth: 209, notchHeight: 38, centerX: 855.5, topY: 1112)

    static func run(outputDirectory: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var written: [URL] = []

        var models: [(Scenario, AppModel)] = []
        for scenario in Scenario.allCases {
            let model = makeModel(scenario)
            models.append((scenario, model))
            written += render(model: model, name: scenario.rawValue, into: outputDirectory)
        }

        // Every closed state stacked, for reviewing the wings side by side.
        let gallery = VStack(spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, entry in
                closedCanvas(model: entry.1, state: NotchState()).frame(height: 60, alignment: .top).clipped()
            }
        }
        if let url = write(gallery, size: nil, to: outputDirectory.appendingPathComponent("notch-closed-gallery.png")) { written.append(url) }

        // Every section nil: what the card looks like before a sampler has produced anything.
        let empty = AppModel(source: MockTelemetrySource(), settings: snapshotSettings())
        written += render(model: empty, name: "empty", into: outputDirectory)

        // Wings clamped to 84 pt, as when macOS put a menu bar item close to the notch.
        for name in ["hot", "calm"] {
            let m = makeModel(name == "hot" ? .hot : .calm)
            let st = NotchState()
            st.wingCap = 84
            if let url = write(closedCanvas(model: m, state: st), size: CGSize(width: 600, height: 120),
                               to: outputDirectory.appendingPathComponent("notch-closed-narrow-\(name).png")) { written.append(url) }
        }

        // Hovering, closed, calm.
        let hoverModel = makeModel(.calm)
        let hoverState = NotchState()
        hoverState.isHovering = true
        if let url = write(closedCanvas(model: hoverModel, state: hoverState), size: CGSize(width: 600, height: 120), to: outputDirectory.appendingPathComponent("notch-hover-calm.png")) {
            written.append(url)
        }

        // Quick add open, mid-typing: the live parse preview under the field.
        CardCommands.shared.quickAddPending = true
        CardCommands.shared.quickAddPrefill = "tomorrow 9am standup"
        let qa = makeModel(.meeting)
        let quick = ZStack { FakeDesktop(menuBar: false); CardView(model: qa, presentation: .corner(.topLeft)).padding(32) }
            .frame(width: Design.Size.cardWidth + 64)
        if let url = write(quick.fixedSize(horizontal: false, vertical: true), size: nil, to: outputDirectory.appendingPathComponent("card-quickadd.png")) { written.append(url) }
        CardCommands.shared.quickAddPending = false
        CardCommands.shared.quickAddPrefill = nil

        if let url = write(ComponentSheet(model: makeModel(.calm)), size: nil, to: outputDirectory.appendingPathComponent("components.png")) {
            written.append(url)
        }

        for url in written { print(url.path) }
    }

    // MARK: Scenarios

    private static func snapshotSettings() -> Settings {
        var s = Settings()
        s.hiddenTiles = []
        s.modules.secondaryTimeZones = ["UTC", "Asia/Tokyo"]
        return s
    }

    private static func makeModel(_ scenario: Scenario) -> AppModel {
        let model = AppModel(source: MockTelemetrySource(scenario: scenario.mock), settings: snapshotSettings())
        let provider = SnapshotProvider(signals: signals(for: scenario))
        model.register(provider: provider)
        provider.onChange?()

        // The real Time module, in a throwaway directory, so the strip shows its real controls.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-snapshot-\(UUID().uuidString)")
        let time = TimeProvider(settings: model.settings.modules, storeDirectory: dir)
        model.register(provider: time)
        if scenario == .meeting {
            _ = time.addTimer(name: "Focus", seconds: 25 * 60)
            _ = time.addCountdown(name: "Release", fireAt: Date().addingTimeInterval(2 * 3600 + 14 * 60))
            time.startStopwatch()
            time.lapStopwatch()
        } else {
            time.onChange?()
        }

        // Wide steps: the mock waves have periods of a few seconds, and 180 samples a second apart alias into a regular zigzag.
        let step = 17.0
        let mock = MockTelemetrySource(scenario: scenario.mock, start: Date().addingTimeInterval(-(180 * step + 1)))
        for i in 1...180 { model.apply(snapshot: mock.snapshot(at: mock.start.addingTimeInterval(Double(i) * step))) }
        return model
    }

    private static func signals(for scenario: Scenario) -> [Signal] {
        let now = Date()
        var out: [Signal] = [
            Signal(id: "weather.current", kind: .weather, attention: .calm, title: "Cupertino", detail: "Partly cloudy \u{00B7} feels 22\u{00B0}", symbol: "cloud.sun.fill", value: "21\u{00B0}", priority: 0),
        ]
        switch scenario {
        case .meeting:
            out.append(Signal(id: "time.meeting.1", kind: .meeting, attention: .info, title: "Design review", detail: "Zoom \u{00B7} 4 attendees",
                              symbol: "video.fill", deadline: now.addingTimeInterval(75), priority: 70, tint: .blue,
                              actionURL: URL(string: "https://zoom.us/j/0"), actionTitle: "Join"))
            out.append(Signal(id: "time.timer.1", kind: .timer, attention: .info, title: "Tea", symbol: "timer",
                              deadline: now.addingTimeInterval(4 * 60 + 12), priority: 30, tint: .amber))
        case .agent:
            out.append(Signal(id: "agents.session.a", kind: .agent, attention: .warning, title: "Claude needs you", detail: "meridian \u{00B7} run swift test?",
                              symbol: "exclamationmark.bubble.fill", value: "2m 14s", priority: 60, tint: .amber,
                              actionURL: URL(string: "https://example.invalid/session/a"), actionTitle: "Open"))
            out.append(Signal(id: "agents.session.b", kind: .agent, attention: .calm, title: "Claude", detail: "dealer-api \u{00B7} working",
                              symbol: "sparkles", value: "11m 40s", priority: 20, tint: .violet))
            out.append(Signal(id: "agents.session.c", kind: .agent, attention: .calm, title: "Claude", detail: "docs \u{00B7} done",
                              symbol: "checkmark.circle.fill", value: "31m", priority: 10, tint: .green))
        default: break
        }
        return out
    }

    // MARK: Per-scenario output

    private static func render(model: AppModel, name: String, into dir: URL) -> [URL] {
        var out: [URL] = []
        let closedState = NotchState()
        if let url = write(closedCanvas(model: model, state: closedState), size: CGSize(width: 600, height: 120),
                           to: dir.appendingPathComponent("notch-closed-\(name).png")) { out.append(url) }

        // Measure the card the way the panel would, then draw the open notch at that height.
        let clearance = CGSize(width: notchGeometry.notchWidth + 2 * Design.Size.notchInsetSide + 12, height: notchGeometry.notchHeight)
        let measure = ImageRenderer(content: CardView(model: model, presentation: .notch)
            .environment(\.meridianNotchClearance, clearance).environment(\.meridianSnapshot, true))
        measure.scale = 1
        let cardHeight = CGFloat(measure.cgImage?.height ?? 640)

        let openState = NotchState()
        openState.isOpen = true
        openState.cardHeight = cardHeight
        if let url = write(openCanvas(model: model, state: openState, cardHeight: cardHeight),
                           size: CGSize(width: 580, height: cardHeight + 56),
                           to: dir.appendingPathComponent("notch-open-\(name).png")) { out.append(url) }

        let card = ZStack {
            FakeDesktop(menuBar: false)
            CardView(model: model, presentation: .corner(.topLeft)).padding(32)
        }
        .frame(width: Design.Size.cardWidth + 64)
        if let url = write(card.fixedSize(horizontal: false, vertical: true), size: nil,
                           to: dir.appendingPathComponent("card-\(name).png")) { out.append(url) }
        return out
    }

    private static func closedCanvas(model: AppModel, state: NotchState) -> some View {
        ZStack(alignment: .top) {
            FakeDesktop(menuBar: true)
            NotchView(model: model, state: state, geometry: notchGeometry, panelHeight: 120)
        }
        .frame(width: 600, height: 120)
    }

    private static func openCanvas(model: AppModel, state: NotchState, cardHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            FakeDesktop(menuBar: true)
            NotchView(model: model, state: state, geometry: notchGeometry, panelHeight: cardHeight + 40, scrolls: false)
        }
        .frame(width: 580, height: cardHeight + 56)
    }

    // MARK: Writing

    /// Renders at scale 2 on a dark appearance. `size` nil renders at the view's ideal size.
    private static func write<V: View>(_ view: V, size: CGSize?, to url: URL) -> URL? {
        let content = view
            .environment(\.meridianSnapshot, true)
            .environment(\.colorScheme, .dark)
            .environment(\.meridianReduceMotion, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let size { renderer.proposedSize = ProposedViewSize(size) }
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("failed to render \(url.lastPathComponent)\n".utf8))
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try data.write(to: url) } catch {
            FileHandle.standardError.write(Data("could not write \(url.path): \(error)\n".utf8))
            return nil
        }
        return url
    }
}

/// A stand-in provider so snapshots can show module signals (meeting, agents, clocks) with no real modules.
@MainActor
final class SnapshotProvider: SignalProvider {
    let providerID = "snapshot"
    var signals: [Signal]
    var onChange: (@MainActor () -> Void)?
    init(signals: [Signal]) { self.signals = signals }
    func start() {}
    func stop() {}
    func apply(_ settings: ModuleSettings) {}
}

/// A dim desktop with a menu bar strip, so a screenshot of the notch has the context a README reader needs.
struct FakeDesktop: View {
    var menuBar: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.34), Color(red: 0.30, green: 0.18, blue: 0.36), Color(red: 0.10, green: 0.14, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if menuBar {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.28))
                    HStack(spacing: 14) {
                        Image(systemName: "applelogo")
                        Text("Finder").fontWeight(.semibold)
                        Text("File"); Text("Edit"); Text("View")
                        Spacer()
                        Image(systemName: "wifi"); Image(systemName: "magnifyingglass"); Text("Mon 14:02")
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 12)
                }
                .frame(height: 38)
            }
        }
    }
}

/// Rings, sparklines, chips, core bars and hero variants on one sheet, for design review.
struct ComponentSheet: View {
    let model: AppModel

    var body: some View {
        ZStack {
            FakeDesktop(menuBar: false)
            VStack(alignment: .leading, spacing: 20) {
                section("Rings") {
                    HStack(spacing: 18) {
                        ForEach([0.0, 0.18, 0.5, 0.94, 1.0], id: \.self) { p in
                            Ring(progress: p, lineWidth: Design.Size.ringStroke, tint: Design.Color.tint(.neutral)).frame(width: 16, height: 16)
                        }
                        ForEach([SignalTint.teal, .blue, .green, .amber, .red, .violet], id: \.self) { t in
                            Ring(progress: 0.7, lineWidth: Design.Size.heroRingStroke, tint: Design.Color.tint(t)).frame(width: 40, height: 40)
                        }
                    }
                }
                section("Sparklines") {
                    HStack(spacing: 12) {
                        ForEach([MetricID.cpu, .memory, .networkDown, .cpuTemp], id: \.self) { id in
                            Sparkline(values: model.histories[id]?.values ?? [], tint: Design.Color.tint(.teal), minSpan: 0.2)
                                .frame(width: 96, height: 28)
                        }
                    }
                }
                section("Chips and core bars") {
                    HStack(spacing: 12) {
                        Chip(text: "Apple M2", symbol: "cpu")
                        Chip(text: "Charging", symbol: "bolt.fill", tint: Design.Color.tint(.green))
                        Chip(text: "Serious", tint: Design.Color.tint(.amber))
                        CoreBars(efficiency: [0.2, 0.5, 0.1, 0.35], performance: [0.9, 0.7, 0.4, 0.8], height: 28)
                    }
                }
                section("Hero") {
                    VStack(spacing: 14) {
                        HeroView(signal: model.top)
                        HeroView(signal: Signal(id: "x", kind: .thermal, attention: .critical, title: "Running hot", detail: "CPU at 98\u{00B0}. macOS is throttling.",
                                                symbol: "flame.fill", progress: 0.88, value: "98\u{00B0}", tint: .red))
                        HeroView(signal: nil)
                    }
                    .frame(width: 400)
                }
            }
            .padding(24)
        }
        .fixedSize()
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary)
            content()
        }
    }
}
