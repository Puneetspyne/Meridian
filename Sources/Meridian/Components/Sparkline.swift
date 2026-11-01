import SwiftUI
import MeridianKit

/// A 1 pt line over recent samples. Newest sample sits on the right edge; the line draws itself once, on first appearance.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Design.Color.textSecondary
    /// Fixed vertical domain (for fractions). Nil autoscales to the data.
    var domain: ClosedRange<Double>? = nil
    /// Autoscaling never zooms in tighter than this, so a flat signal reads as flat.
    var minSpan: Double = 0
    var fill: Bool = true
    var lineWidth: CGFloat = 1
    /// Samples the window is sized for; fewer samples fill from the right.
    var window: Int = 180
    @State private var reveal: CGFloat = 0
    @Environment(\.meridianReduceMotion) private var reduce
    @Environment(\.meridianSnapshot) private var snapshot

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                // Baseline so an empty history still shows where the line will go.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 0.5))
                }
                .stroke(Design.Color.hairline, lineWidth: 0.5)

                if pts.count > 1 {
                    if fill {
                        area(pts, height: geo.size.height)
                            .fill(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .opacity(reveal)
                    }
                    line(pts)
                        .trim(from: 0, to: reveal)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .onAppear {
            if reduce || snapshot { reveal = 1 } else { withAnimation(Design.Motion.draw) { reveal = 1 } }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let v = Array(values.suffix(window))
        guard v.count > 1 else { return [] }
        var lo = domain?.lowerBound ?? (v.min() ?? 0)
        var hi = domain?.upperBound ?? (v.max() ?? 1)
        if hi - lo < max(minSpan, 1e-9) {
            let mid = (hi + lo) / 2
            let half = max(minSpan, 1e-9) / 2
            lo = mid - half
            hi = mid + half
        }
        let inset = lineWidth + 0.5
        let usable = max(1, size.height - inset * 2)
        let step = size.width / CGFloat(max(v.count, 30) - 1)
        return v.enumerated().map { i, value in
            let x = size.width - CGFloat(v.count - 1 - i) * step
            let n = min(1, max(0, (value - lo) / (hi - lo)))
            return CGPoint(x: x, y: size.height - inset - CGFloat(n) * usable)
        }
    }

    /// Midpoint-quadratic smoothing: soft corners without overshoot.
    private func line(_ pts: [CGPoint]) -> Path {
        Path { p in
            p.move(to: pts[0])
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                if i == 1 { p.addLine(to: mid) } else { p.addQuadCurve(to: mid, control: pts[i - 1]) }
            }
            p.addLine(to: pts[pts.count - 1])
        }
    }

    private func area(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = line(pts)
        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: height))
        p.addLine(to: CGPoint(x: pts[0].x, y: height))
        p.closeSubpath()
        return p
    }
}
