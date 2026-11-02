import SwiftUI
import MeridianKit
import MeridianTime

/// The open card both bodies show. Keep `CardView(model:presentation:)` working: other workstreams embed it.
///
/// Two layouts (`Settings.cardLayout`): tall, a drawer; wide, a low pebble in one row. The view reports its size
/// honestly (fixed frame, no scrolling in wide mode), so hosts can read `fittingSize`.
///
/// On a notch the top band beside the hardware notch carries the chip, the layout toggle and the settings button
/// (the band is otherwise dead black). Elsewhere those live in the footer (tall) or a header row (wide).
struct CardView: View {
    let model: AppModel
    /// Which body opened the card; lets the hero anchor and corner radii match the opener.
    var presentation: CardPresentation = .notch
    /// Shared with the closed wing so the wing ring flies into the hero ring on open.
    var ringNamespace: Namespace.ID? = nil
    var ringIsSource: Bool = true
    /// Called by the gear button. Falls back to the environment, then to a notification the app can observe.
    var openSettings: (() -> Void)? = nil

    @Environment(\.meridianOpenSettings) private var envOpenSettings
    @Environment(\.meridianNotchClearance) private var clearance
    @Environment(\.meridianScreenWidth) private var envScreenWidth
    @Environment(\.meridianReduceMotion) private var reduce

    static let openSettingsNotification = Notification.Name("meridian.openSettings")

    private var isNotch: Bool { presentation == .notch }
    private var wide: Bool { model.settings.cardLayout == .wide }
    private var material: CardMaterial { model.settings.cardMaterial }

    /// Width of the card itself, flares excluded.
    static func width(layout: CardLayout, screenWidth: CGFloat, isNotch: Bool) -> CGFloat {
        switch layout {
        case .tall: return Design.Size.cardWidth
        case .wide: return WideMetrics.width(screenWidth: screenWidth > 0 ? screenWidth : (NSScreen.main?.frame.width ?? 1440),
                                             flare: isNotch ? Design.NotchMetrics.openTopRadius : 0)
        }
    }

    var body: some View {
        let width = Self.width(layout: model.settings.cardLayout, screenWidth: envScreenWidth, isNotch: isNotch)
        let content = ZStack(alignment: .top) {
            if wide {
                wideBody(width: width)
                    .transition(.asymmetric(insertion: .opacity.animation(reduce ? .easeInOut(duration: 0.15) : Design.Motion.swap.delay(0.09)), removal: .identity))
            } else {
                tallBody
                    .transition(.asymmetric(insertion: .opacity.animation(reduce ? .easeInOut(duration: 0.15) : Design.Motion.swap.delay(0.09)), removal: .identity))
            }
        }
        .frame(width: width)
        .environment(\.meridianMaterial, material)

        if isNotch {
            content
        } else {
            content.background(cornerBackground)
        }
    }

    @ViewBuilder private var cornerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
        if material == .glass {
            CardGlassBackground(shape: shape, scrim: SystemAppearance.scrim())
        } else {
            shape.fill(Design.Color.notch).overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
        }
    }

    // MARK: Tall

    private var tallBody: some View {
        VStack(spacing: 0) {
            if isNotch { notchBand }
            VStack(spacing: Design.Space.m) {
                HeroView(signal: model.top, ringNamespace: ringNamespace, ringIsSource: ringIsSource).staggered(0)
                CardTiles(model: model).staggered(1)
                Group {
                    if showsTimeStrip { TimeStrip(model: model) }
                    if showsAgentsStrip { AgentsStrip(model: model) }
                }
                .staggered(2)
                footer.staggered(3)
            }
            .padding(.horizontal, Design.Size.cardPadding)
            .padding(.top, isNotch ? Design.Space.xs : Design.Size.cardPadding)
            .padding(.bottom, Design.Size.cardPadding)
        }
    }

    private var showsTimeStrip: Bool {
        let t = Set(model.settings.visibleTiles)
        guard !t.isDisjoint(with: [.meeting, .timers, .clocks]) else { return false }
        return model.provider(TimeProvider.self) != nil
            || !TimeStrip.entries(in: model.signals).isEmpty
            || !TimeStrip.clocks(in: model.signals).isEmpty
    }

    private var showsAgentsStrip: Bool { model.settings.visibleTiles.contains(.agents) }

    private var chipName: String? { model.snapshot.system?.chipName }

    private func gear() -> some View {
        Button {
            if let openSettings { openSettings() } else {
                envOpenSettings()
                NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Design.Color.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    /// Beside the hardware notch: chip on the left; layout toggle and settings on the right.
    private var notchBand: some View {
        HStack(spacing: 0) {
            if let chipName { Chip(text: chipName, symbol: "cpu") }
            if wide, let up = model.snapshot.cpu?.uptime, up > 0 {
                Text("Up \(Format.uptime(up))").font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary).padding(.leading, 8)
            }
            Spacer(minLength: clearance.width)
            if wide { UpdatedLabel(timestamp: model.snapshot.timestamp).padding(.trailing, 10) }
            LayoutToggle(model: model).padding(.trailing, 6)
            gear()
        }
        .padding(.horizontal, Design.Size.cardPadding)
        .frame(height: clearance.height, alignment: .center)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isNotch, let chipName { Chip(text: chipName, symbol: "cpu") }
            if let up = model.snapshot.cpu?.uptime, up > 0 {
                Text("Up \(Format.uptime(up))").font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary)
            }
            Spacer(minLength: 0)
            UpdatedLabel(timestamp: model.snapshot.timestamp)
            if !isNotch {
                LayoutToggle(model: model)
                gear()
            }
        }
        .frame(height: 26)
        .padding(.horizontal, 2)
    }

    // MARK: Wide

    private func wideBody(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            if isNotch { notchBand } else { wideHeader }
            WideCardContent(model: model, width: width, ringNamespace: ringNamespace, ringIsSource: ringIsSource)
                .staggered(0)
                .padding(.top, isNotch ? Design.Space.xs : 2)
                .padding(.bottom, WideMetrics.padding)
        }
    }

    /// Corner and menu bar presentations: a slim header with the same controls the notch band has.
    private var wideHeader: some View {
        HStack(spacing: 8) {
            if let chipName { Chip(text: chipName, symbol: "cpu") }
            if let up = model.snapshot.cpu?.uptime, up > 0 {
                Text("Up \(Format.uptime(up))").font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary)
            }
            Spacer(minLength: 0)
            UpdatedLabel(timestamp: model.snapshot.timestamp)
            LayoutToggle(model: model)
            gear()
        }
        .padding(.horizontal, WideMetrics.padding + 2)
        .frame(height: 34)
    }
}

// MARK: - Layout toggle

/// Two SF Symbols in a small capsule: tall (rectangle.portrait) and wide (rectangle). Writes the setting inside
/// `Motion.open`, so the shape morphs and the content cross-fades after it starts moving.
struct LayoutToggle: View {
    let model: AppModel
    @Environment(\.meridianReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: 2) {
            segment(.tall, symbol: "rectangle.portrait", label: "Tall card")
            segment(.wide, symbol: "rectangle", label: "Wide bar")
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card layout")
    }

    private func segment(_ layout: CardLayout, symbol: String, label: String) -> some View {
        let selected = model.settings.cardLayout == layout
        return Button {
            guard !selected else { return }
            withAnimation(Design.Motion.respecting(Design.Motion.open, reduce: reduce)) { model.settings.cardLayout = layout }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(selected ? Design.Color.textPrimary : Design.Color.textTertiary)
                .frame(width: 24, height: 20)
                .background(Capsule().fill(selected ? Color.white.opacity(0.16) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Entrance

private struct Staggered: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.meridianReduceMotion) private var reduce
    @Environment(\.meridianSnapshot) private var snapshot

    func body(content: Content) -> some View {
        let visible = shown || reduce || snapshot
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 4)
            .onAppear {
                guard !shown else { return }
                withAnimation(Design.Motion.swap.delay(0.02 * Double(index))) { shown = true }
            }
    }
}

extension View {
    /// Card entrance: each section starts 20 ms after the one above it.
    func staggered(_ index: Int) -> some View { modifier(Staggered(index: index)) }
}

/// "Live" while samples arrive, then "Updated 3 s ago", "10 s", "30 s", "1 min" as one without new data goes stale.
///
/// Not a once-a-second TimelineView: its tick falls between sample ticks, which made the open card repaint twice
/// a second for a number that always read "0". Each new sample re-creates this view with a fresh schedule.
struct UpdatedLabel: View {
    var timestamp: Date

    var body: some View {
        let marks: [Double] = [0, 3, 10, 30, 60, 120, 300, 900]
        TimelineView(.explicit(marks.map { timestamp.addingTimeInterval($0) })) { ctx in
            let age = Int(max(0, ctx.date.timeIntervalSince(timestamp)))
            Group {
                if timestamp.timeIntervalSince1970 < 1 {
                    Text("Waiting for data")
                } else if age < 3 {
                    Text("Live")
                } else if age < 60 {
                    Text("Updated \(age) s ago")
                } else {
                    Text("Updated \(age / 60) min ago")
                }
            }
            .font(Design.Font.caption)
            .foregroundStyle(Design.Color.textTertiary)
            .monospacedDigit()
        }
    }
}

enum CardPresentation: Equatable {
    case notch
    case corner(ScreenCorner)
    case menuBar
}
