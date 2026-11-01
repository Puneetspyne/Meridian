import AppKit
import SwiftUI

/// Pure geometry for the corner body. AppKit screen coordinates (origin bottom-left, y up) unless noted.
enum CornerGeometry {
    /// The point of `rect` where the quarter circle is centred.
    static func cornerPoint(_ corner: ScreenCorner, in rect: CGRect) -> CGPoint {
        CGPoint(x: corner.isRight ? rect.maxX : rect.minX, y: corner.isBottom ? rect.minY : rect.maxY)
    }

    /// The square panel frame for `corner` of `area`.
    static func panelFrame(_ corner: ScreenCorner, radius: CGFloat, in area: CGRect) -> CGRect {
        CGRect(x: corner.isRight ? area.maxX - radius : area.minX,
               y: corner.isBottom ? area.minY : area.maxY - radius,
               width: radius, height: radius)
    }

    /// The corner of `screenFrame` closest to `point`: a plain quadrant test.
    static func nearestCorner(to point: CGPoint, in screenFrame: CGRect) -> ScreenCorner {
        let right = point.x >= screenFrame.midX
        let bottom = point.y < screenFrame.midY
        switch (right, bottom) {
        case (false, false): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (true, true): return .bottomRight
        }
    }

    /// Whether `point` lies on the drawn quarter circle of `drawnRadius` anchored at `corner` of `panelFrame`.
    static func hit(_ point: CGPoint, corner: ScreenCorner, panelFrame: CGRect, drawnRadius: CGFloat) -> Bool {
        let c = cornerPoint(corner, in: panelFrame)
        let dx = point.x - c.x, dy = point.y - c.y
        guard panelFrame.insetBy(dx: -0.5, dy: -0.5).contains(point) else { return false }
        return dx * dx + dy * dy <= drawnRadius * drawnRadius
    }

    /// Whether the pointer is pressing against the screen edge beside the corner, within `span` of it.
    /// `area` is the frame the body is laid out in (visible frame, or the full frame in full screen).
    static func pressingEdge(_ point: CGPoint, corner: ScreenCorner, area: CGRect, screenFrame: CGRect,
                             span: CGFloat, slop: CGFloat) -> Bool {
        let c = cornerPoint(corner, in: area)
        // Distance from the horizontal edge (top or bottom) and from the vertical edge, measured inward.
        let inward = CGPoint(x: corner.isRight ? -1 : 1, y: corner.isBottom ? 1 : -1)
        let along = CGPoint(x: (point.x - c.x) * inward.x, y: (point.y - c.y) * inward.y)
        let nearHorizontalEdge = along.y > -slop && along.y <= slop && along.x >= 0 && along.x <= span
        let nearVerticalEdge = along.x > -slop && along.x <= slop && along.y >= 0 && along.y <= span
        // Also honour the physical screen edge when the layout area sits inside it (menu bar, Dock).
        let s = cornerPoint(corner, in: screenFrame)
        let sAlong = CGPoint(x: (point.x - s.x) * inward.x, y: (point.y - s.y) * inward.y)
        let atScreenH = sAlong.y > -slop && sAlong.y <= slop && sAlong.x >= 0 && sAlong.x <= span
        let atScreenV = sAlong.x > -slop && sAlong.x <= slop && sAlong.y >= 0 && sAlong.y <= span
        return nearHorizontalEdge || nearVerticalEdge || atScreenH || atScreenV
    }
}

extension ScreenCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

// MARK: - Shapes (SwiftUI space: y down)

/// A quarter disk centred on `corner` of its rect.
struct QuarterDisk: Shape {
    var corner: ScreenCorner
    func path(in rect: CGRect) -> Path {
        let r = rect.width
        let (center, a0, a1) = QuarterArc.parts(corner, in: rect, radius: r)
        var p = Path()
        p.move(to: center)
        p.addLine(to: QuarterArc.point(center, r, a0))
        p.addArc(center: center, radius: r, startAngle: a0, endAngle: a1, clockwise: QuarterArc.clockwise(corner))
        p.closeSubpath()
        return p
    }
}

/// The track along the curve, starting at the horizontal screen edge and sweeping toward the vertical one,
/// so every corner is the mirror image of the top-left one.
struct QuarterArc: Shape {
    var corner: ScreenCorner
    var inset: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.width - inset
        let (center, a0, a1) = Self.parts(corner, in: rect, radius: r)
        var p = Path()
        p.addArc(center: center, radius: r, startAngle: a0, endAngle: a1, clockwise: Self.clockwise(corner))
        return p
    }

    static func parts(_ corner: ScreenCorner, in rect: CGRect, radius: CGFloat) -> (CGPoint, Angle, Angle) {
        switch corner {
        case .topLeft: return (CGPoint(x: rect.minX, y: rect.minY), .degrees(0), .degrees(90))
        case .topRight: return (CGPoint(x: rect.maxX, y: rect.minY), .degrees(180), .degrees(90))
        case .bottomLeft: return (CGPoint(x: rect.minX, y: rect.maxY), .degrees(0), .degrees(-90))
        case .bottomRight: return (CGPoint(x: rect.maxX, y: rect.maxY), .degrees(180), .degrees(270))
        }
    }
    /// SwiftUI measures angles clockwise on screen; `clockwise: false` follows increasing angle.
    static func clockwise(_ corner: ScreenCorner) -> Bool {
        switch corner { case .topLeft, .bottomRight: false; case .topRight, .bottomLeft: true }
    }
    static func point(_ c: CGPoint, _ r: CGFloat, _ a: Angle) -> CGPoint {
        CGPoint(x: c.x + r * CGFloat(cos(a.radians)), y: c.y + r * CGFloat(sin(a.radians)))
    }
}
