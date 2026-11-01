import SwiftUI

/// The notch silhouette. The body is a rectangle with continuous bottom corners; when `topRadius` > 0 two concave
/// flares at the top corners curve outward so the shape melts into the top screen edge, like a drawer.
/// The body is inset by `topRadius` on each side, so the shape's outer width is body width plus both flares.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = max(0, min(topRadius, rect.width / 4))
        let body = CGRect(x: rect.minX + tr, y: rect.minY, width: rect.width - 2 * tr, height: rect.height)
        let br = max(0, min(bottomRadius, body.width / 2, body.height))
        var path = UnevenRoundedRectangle(bottomLeadingRadius: br, bottomTrailingRadius: br, style: .continuous).path(in: body)
        if tr > 0.25 {
            // Left flare: the sliver between the screen edge and the body's rising side.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: body.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: body.minX, y: rect.minY + tr))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: body.minX, y: rect.minY))
            path.closeSubpath()
            // Right flare.
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: rect.minY + tr))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: body.maxX, y: rect.minY))
            path.closeSubpath()
        }
        return path
    }
}
