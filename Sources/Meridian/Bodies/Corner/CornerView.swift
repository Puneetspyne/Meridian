import SwiftUI
import Observation
import MeridianKit

/// What the closed corner shows right now. Written by the controller, read by `CornerView`.
@MainActor
@Observable
final class CornerState {
    var corner: ScreenCorner = .topLeft
    var radius: CGFloat = CornerSize.medium.points
    var rest: CornerRestStyle = .shrink
    /// Pointer is over the body (drives `shrink`).
    var hovering = false
    /// Pointer pressed against the edge and the tucked dot opened (drives `tuck`).
    var tuckExpanded = false
    var pressed = false
    var dragging = false
    var cardOpen = false

    /// Size relative to `radius` when nothing else applies.
    var baseScale: CGFloat {
        if dragging { return 1 }
        switch rest {
        case .full: return 1
        case .shrink: return hovering ? 1 : Design.Corner.restScale
        case .tuck: return tuckExpanded ? 1 : Design.Corner.tuckDiameter / radius
        }
    }
    var isTucked: Bool { rest == .tuck && !tuckExpanded && !dragging }
    var hitRadius: CGFloat { radius * baseScale }
}

/// The closed corner body: matte black quarter disk, hairline, an arc track for the top signal's progress,
/// the value near the corner and a 9.5 pt title beside it. Calm shows the clock with ambient CPU on the arc.
struct CornerView: View {
    let model: AppModel
    let state: CornerState

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { model.settings.reduceMotionOverride ?? systemReduceMotion }
    private func motion(_ a: Animation) -> Animation { Design.Motion.respecting(a, reduce: reduceMotion) ?? a }

    var body: some View {
        let r = state.radius
        let corner = state.corner
        let face = Face(model: model)
        let scale = state.baseScale * (state.pressed ? Design.Corner.pressedScale : 1)
        let hairline = contrast == .increased ? Design.Color.hairlineStrong : Design.Color.hairline

        ZStack(alignment: corner.alignment) {
            ZStack(alignment: corner.alignment) {
                QuarterDisk(corner: corner).fill(Design.Color.notch)
                QuarterDisk(corner: corner).stroke(hairline, lineWidth: Design.Corner.hairline)

                // Track and progress. Without a natural progress the arc shows the whole signal dimmed.
                QuarterArc(corner: corner, inset: Design.Corner.arcInset)
                    .stroke(Design.Color.trackIdle, style: StrokeStyle(lineWidth: Design.Corner.arcStroke, lineCap: .round))
                QuarterArc(corner: corner, inset: Design.Corner.arcInset)
                    .trim(from: 0, to: max(0.001, face.progress ?? 1))
                    .stroke(face.tint.opacity(face.progress == nil ? 0.35 : 1),
                            style: StrokeStyle(lineWidth: Design.Corner.arcStroke, lineCap: .round))
                    .animation(reduceMotion ? nil : Design.Motion.ring, value: face.progress)

                labels(face: face, r: r, corner: corner)
            }
            .frame(width: r, height: r)
            .opacity(state.isTucked ? 0 : 1)
            .scaleEffect(scale, anchor: corner.unitPoint)

            // The tucked dot: a tint core inside the 10 pt quarter disk the shape has shrunk to.
            Circle()
                .fill(face.tint)
                .frame(width: 4, height: 4)
                .padding(Design.Corner.tuckDiameter * 0.28)
                .opacity(state.isTucked ? 1 : 0)
        }
        .frame(width: r, height: r, alignment: corner.alignment)
        .opacity(state.cardOpen ? 0 : 1)
        .animation(motion(Design.Motion.hover), value: scale)
        .animation(motion(Design.Motion.swap), value: state.isTucked)
        .animation(motion(Design.Motion.swap), value: state.cardOpen)
        .animation(motion(Design.Motion.swap), value: face.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meridian, \(face.title) \(face.valueDescription)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the card")
    }

    @ViewBuilder
    private func labels(face: Face, r: CGFloat, corner: ScreenCorner) -> some View {
        let alignment: HorizontalAlignment = corner.isRight ? .trailing : .leading
        let value = valueView(face: face, r: r)
        let title = Text(face.title)
            .font(Design.Font.wingLabel)
            .foregroundStyle(Design.Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: Design.Corner.titleWidth(radius: r), alignment: corner.isRight ? .trailing : .leading)

        VStack(alignment: alignment, spacing: 1) {
            // The value is always the line nearest the corner.
            if corner.isBottom { title; value } else { value; title }
        }
        .padding(.horizontal, r * 0.13)
        .padding(.vertical, r * 0.10)
        .frame(width: r, height: r, alignment: corner.alignment)
        .animation(motion(Design.Motion.value), value: face.valueDescription)
    }

    @ViewBuilder
    private func valueView(face: Face, r: CGFloat) -> some View {
        let size = Design.Corner.valueSize(radius: r)
        let color = contrast == .increased ? Color.white : Design.Color.textPrimary
        if face.isCalm {
            TimelineView(.everyMinute) { ctx in
                Text(Face.clock(ctx.date, use24Hour: model.settings.modules.uses24HourClock))
                    .contentTransition(.numericText())
            }
            .font(Design.Font.number(size)).foregroundStyle(color)
        } else if let value = face.value {
            Text(value)
                .contentTransition(.numericText())
                .font(Design.Font.number(size)).foregroundStyle(face.tint == Design.Color.tint(.neutral) ? color : face.tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        } else if let deadline = face.deadline {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.countdown(deadline.timeIntervalSince(ctx.date))).contentTransition(.numericText())
            }
            .font(Design.Font.number(size)).foregroundStyle(face.tint).lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Image(systemName: face.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(face.tint)
        }
    }

    /// The closed surface's single signal, resolved to what the quarter disk can draw.
    struct Face {
        var isCalm: Bool
        var title: String
        var value: String?
        var deadline: Date?
        var symbol: String
        var progress: Double?
        var tint: Color

        @MainActor
        init(model: AppModel) {
            if let top = model.top, top.attention > .calm {
                isCalm = false
                title = top.title
                value = top.value
                deadline = top.deadline
                symbol = top.symbol
                progress = top.progress.map { min(1, max(0, $0)) }
                tint = Design.Color.tint(top.tint)
            } else {
                isCalm = true
                let cpu = model.snapshot.cpu?.total
                title = cpu.map { "CPU \(Format.percent($0))" } ?? "Meridian"
                value = nil; deadline = nil; symbol = "circle.dotted"
                progress = cpu.map { min(1, max(0, $0)) }
                tint = Design.Color.tint(.neutral)
            }
        }

        var valueDescription: String {
            if isCalm { return Self.clock(Date(), use24Hour: true) }
            return value ?? deadline.map { Format.relative($0) } ?? ""
        }

        static func clock(_ date: Date, use24Hour: Bool) -> String {
            let f = use24Hour ? Self.f24 : Self.f12
            return f.string(from: date)
        }
        private static let f24: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
        private static let f12: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()
    }
}
