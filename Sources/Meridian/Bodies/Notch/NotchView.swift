import SwiftUI
import MeridianKit

/// The notch body: one black shape that is a wrapped notch with two wings when closed, grows slightly on hover,
/// and unfolds downward into the card when open. The wing ring flies into the hero ring through a shared namespace.
///
/// Performance: this view never reads `model.top`. The closed wings live in `ClosedHost`, which turns the signal
/// into an `Equatable` `WingModel` and hides it behind `.equatable()`, so a new sample with the same visible
/// result redraws nothing. The card only exists in the tree while open.
struct NotchView: View {
    let model: AppModel
    let state: NotchState
    let geometry: NotchGeometry
    let panelHeight: CGFloat
    var openSettings: () -> Void = {}
    var onClosedTap: () -> Void = {}
    /// Called when a card control needs the keyboard (quick add): the host makes its panel key, or lets go.
    var onKeyboard: (Bool) -> Void = { _ in }
    /// ImageRenderer cannot draw a ScrollView, so the snapshot renderer turns this off.
    var scrolls: Bool = true

    @Namespace private var ringSpace

    private var layout: NotchLayout {
        NotchLayout(geometry: geometry, wing: effectiveWing, cardHeight: state.cardHeight, panelHeight: panelHeight, cardLayout: model.settings.cardLayout)
    }

    private var effectiveWing: CGFloat {
        min(model.settings.notchWingWidth, state.wingCap ?? .infinity)
    }

    private var reduce: Bool {
        model.settings.reduceMotionOverride ?? state.systemReduceMotion
    }

    var body: some View {
        let layout = layout
        let open = state.isOpen
        let size = layout.size(open: open, hovering: state.isHovering)
        let shape = NotchShape(topRadius: open ? Design.NotchMetrics.openTopRadius : 0,
                               bottomRadius: open ? Design.Radius.card : Design.Radius.notchBottom)
        let fadeIn: Animation = reduce ? .easeInOut(duration: 0.15) : Design.Motion.swap.delay(Design.Motion.contentDelay)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Design.Color.notch
                if open, model.settings.cardMaterial == .glass { glassBody(layout) }
                if open {
                    openContent
                        .transition(.opacity.animation(fadeIn))
                } else {
                    ClosedHost(model: model, state: state, geometry: geometry, wing: layout.wing,
                               ringSpace: ringSpace, reduce: reduce, onTap: onClosedTap)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .animation(reduce ? nil : Design.Motion.swap, value: state.cardHeight)
        }
        .frame(width: layout.panelWidth, height: layout.panelHeight, alignment: .top)
        .environment(\.meridianReduceMotion, reduce)
        .environment(\.meridianNotchClearance, CGSize(width: geometry.notchWidth + 2 * Design.Size.notchInsetSide + 12, height: geometry.notchHeight))
        .environment(\.meridianKeyboard, onKeyboard)
        .environment(\.meridianScreenWidth, geometry.screenWidth)
        .ignoresSafeArea()
    }

    // MARK: Open

    private var card: some View {
        CardView(model: model, presentation: .notch, ringNamespace: ringSpace, ringIsSource: true, openSettings: openSettings)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if abs(state.cardHeight - height) > 0.5 { state.cardHeight = height }
            }
    }

    /// The glass under the black notch band: same silhouette as the card's lower part, with the top edge fading
    /// out of the band so there is no seam. The band itself stays matte black.
    private func glassBody(_ layout: NotchLayout) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Design.Radius.card, bottomTrailingRadius: Design.Radius.card, style: .continuous)
        return VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchHeight)
            CardGlassBackground(shape: shape, scrim: state.scrim)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Design.Color.notch, Design.Color.notch.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 22)
                }
                .clipShape(shape)
        }
        .frame(width: layout.openSize.width - 2 * Design.NotchMetrics.openTopRadius)
        .transition(.opacity)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var openContent: some View {
        if scrolls, model.settings.cardLayout == .tall {
            ScrollView(.vertical, showsIndicators: false) { card }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            card.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Closed

/// Reads the top signal (the only place that does while closed) and hands the wings an `Equatable` value.
private struct ClosedHost: View {
    let model: AppModel
    let state: NotchState
    let geometry: NotchGeometry
    let wing: CGFloat
    let ringSpace: Namespace.ID
    let reduce: Bool
    let onTap: () -> Void

    var body: some View {
        let w = WingModel(model.top)
        ZStack(alignment: .top) {
            ClosedWings(wing: w, geometry: geometry, wingWidth: wing + Design.Size.notchInsetSide + (state.isHovering ? Design.NotchMetrics.hoverGrowWing : 0),
                        ringSpace: ringSpace, use24Hour: model.settings.modules.uses24HourClock, onTap: onTap)
                .equatable()
            if w.attention >= .warning {
                Rectangle()
                    .fill(Design.Color.attention(w.attention))
                    .frame(height: 1)
                    .padding(.horizontal, Design.Radius.notchBottom * 0.7)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(Design.Motion.respecting(Design.Motion.swap, reduce: reduce), value: w.attention >= .warning)
    }
}

private struct ClosedWings: View, Equatable {
    let wing: WingModel
    let geometry: NotchGeometry
    let wingWidth: CGFloat
    let ringSpace: Namespace.ID
    let use24Hour: Bool
    let onTap: () -> Void

    static func == (l: ClosedWings, r: ClosedWings) -> Bool {
        l.wing == r.wing && l.geometry == r.geometry && l.wingWidth == r.wingWidth && l.use24Hour == r.use24Hour
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .padding(.leading, edgePadding)
                .frame(width: wingWidth, alignment: .leading)
            Color.clear.frame(width: geometry.notchWidth)
            rightWing
                .padding(.trailing, edgePadding)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: geometry.notchHeight, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wing.spoken)
        .accessibilityHint("Opens the Meridian card")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }

    private var tint: Color { Design.Color.tint(wing.tint) }
    /// Tighter edge padding when the wing is clamped, so text truncates later.
    private var edgePadding: CGFloat { wingWidth < 100 ? 10 : Design.NotchMetrics.wingEdgePadding }

    private var leftWing: some View {
        HStack(spacing: 6) {
            Group {
                if !wing.isEmpty, wing.progress == nil {
                    Image(systemName: wing.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Ring(progress: wing.progress, lineWidth: Design.Size.ringStroke, tint: tint, animation: nil)
                }
            }
            .frame(width: Design.Size.ring, height: Design.Size.ring)
            // The only holder of this id while closed: the hero is not in the tree until the card opens.
            .matchedGeometryEffect(id: "signalRing", in: ringSpace, isSource: true)

            if let text = wing.valueText {
                Num(text, font: Design.Font.wing, color: wing.attention >= .warning ? tint : Design.Color.textPrimary, animates: false)
            } else if wing.isEmpty {
                Num(Placeholder.dash, font: Design.Font.wing, color: Design.Color.textTertiary)
            }
        }
    }

    @ViewBuilder private var rightWing: some View {
        if !wing.isEmpty, wing.attention > .calm {
            let color = wing.attention >= .warning ? Design.Color.attention(wing.attention) : Design.Color.textPrimary
            if wing.isLiveCountdown, let deadline = wing.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Num(Format.countdown(max(0, deadline.timeIntervalSince(ctx.date))), font: Design.Font.wing, color: color, animates: false)
                }
            } else {
                Text(wing.title)
                    .font(Design.Font.wing)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            ClockText(use24Hour: use24Hour)
        }
    }
}

/// Calm right wing: the time, redrawn once a minute.
struct ClockText: View {
    var use24Hour: Bool

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(Self.string(ctx.date, use24Hour: use24Hour))
                .font(Design.Font.wing)
                .foregroundStyle(Design.Color.textSecondary)
        }
        .accessibilityLabel("Time")
    }

    private static let f24: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let f12: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()

    static func string(_ date: Date, use24Hour: Bool) -> String {
        (use24Hour ? f24 : f12).string(from: date)
    }
}
