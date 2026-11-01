import SwiftUI
import MeridianKit

/// The notch body: one black shape that is a wrapped notch with two wings when closed, grows slightly on hover,
/// and unfolds downward into the card when open. The wing ring flies into the hero ring through a shared namespace.
struct NotchView: View {
    let model: AppModel
    let state: NotchState
    let geometry: NotchGeometry
    let panelHeight: CGFloat
    var openSettings: () -> Void = {}
    var onClosedTap: () -> Void = {}
    /// ImageRenderer cannot draw a ScrollView, so the snapshot renderer turns this off.
    var scrolls: Bool = true

    @Namespace private var ringSpace

    private var layout: NotchLayout {
        NotchLayout(geometry: geometry, wing: model.settings.notchWingWidth, cardHeight: state.cardHeight, panelHeight: panelHeight)
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
        let top = model.top
        let fadeIn: Animation = reduce ? .easeInOut(duration: 0.15) : Design.Motion.swap.delay(Design.Motion.contentDelay)
        let showsHairline = !open && (top?.attention ?? .calm) >= .warning

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Design.Color.notch
                if open {
                    openContent
                        .transition(.opacity.animation(fadeIn))
                } else {
                    closedContent(top: top, layout: layout)
                        .transition(.opacity)
                }
                if showsHairline, let top {
                    Rectangle()
                        .fill(Design.Color.attention(top.attention))
                        .frame(height: 1)
                        .padding(.horizontal, Design.Radius.notchBottom * 0.7)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .animation(reduce ? nil : Design.Motion.swap, value: state.cardHeight)
            .animation(Design.Motion.respecting(Design.Motion.swap, reduce: reduce), value: showsHairline)
        }
        .frame(width: layout.panelWidth, height: layout.panelHeight, alignment: .top)
        .environment(\.meridianReduceMotion, reduce)
        .environment(\.meridianNotchClearance, CGSize(width: geometry.notchWidth + 2 * Design.Size.notchInsetSide + 12, height: geometry.notchHeight))
        .ignoresSafeArea()
    }

    // MARK: Closed

    private func closedContent(top: Signal?, layout: NotchLayout) -> some View {
        let extra = state.isHovering ? Design.NotchMetrics.hoverGrowWing : 0
        let wingWidth = layout.wing + Design.Size.notchInsetSide + extra
        return HStack(spacing: 0) {
            leftWing(top)
                .padding(.leading, Design.NotchMetrics.wingEdgePadding)
                .frame(width: wingWidth, alignment: .leading)
            Color.clear.frame(width: geometry.notchWidth)
            rightWing(top)
                .padding(.trailing, Design.NotchMetrics.wingEdgePadding)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: geometry.notchHeight, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onClosedTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(top?.accessibilityPhrase ?? "Meridian, waiting for data")
        .accessibilityHint("Opens the Meridian card")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onClosedTap() }
    }

    private func leftWing(_ top: Signal?) -> some View {
        let tint = top.map { Design.Color.tint($0.tint) } ?? Design.Color.tint(.neutral)
        return HStack(spacing: 6) {
            Group {
                if let top, top.progress == nil {
                    Image(systemName: top.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Ring(progress: top?.progress, lineWidth: Design.Size.ringStroke, tint: tint)
                }
            }
            .frame(width: Design.Size.ring, height: Design.Size.ring)
            .matchedGeometryEffect(id: "signalRing", in: ringSpace)

            if let top, !top.isLiveCountdown, top.value != nil {
                SignalValue(signal: top, font: Design.Font.wing, color: top.attention >= .warning ? tint : Design.Color.textPrimary)
            } else if top == nil {
                Num(Placeholder.dash, font: Design.Font.wing, color: Design.Color.textTertiary)
            }
        }
    }

    @ViewBuilder private func rightWing(_ top: Signal?) -> some View {
        if let top, top.attention > .calm {
            let color = top.attention >= .warning ? Design.Color.attention(top.attention) : Design.Color.textPrimary
            if top.isLiveCountdown {
                SignalValue(signal: top, font: Design.Font.wing, color: color)
            } else {
                Text(top.title)
                    .font(Design.Font.wing)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            ClockText(use24Hour: model.settings.modules.uses24HourClock)
        }
    }

    // MARK: Open

    private var card: some View {
        CardView(model: model, presentation: .notch, ringNamespace: ringSpace, openSettings: openSettings)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if abs(state.cardHeight - height) > 0.5 { state.cardHeight = height }
            }
    }

    @ViewBuilder private var openContent: some View {
        if scrolls {
            ScrollView(.vertical, showsIndicators: false) { card }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            card.frame(maxHeight: .infinity, alignment: .top)
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
