import SwiftUI
import MeridianKit

/// A progress arc. The stroke stays inside the frame so a 16 pt ring really occupies 16 pt.
struct Ring: View {
    var progress: Double?
    var lineWidth: CGFloat = Design.Size.ringStroke
    var tint: Color = Design.Color.tint(.neutral)
    var track: Color = Design.Color.trackIdle
    /// The closed wing ring passes nil: animating a once-a-second tick kept the notch rendering at full frame rate (measured, about 10 times the idle CPU).
    var animation: Animation? = Design.Motion.ring
    @Environment(\.meridianReduceMotion) private var reduce

    var body: some View {
        let p = min(1, max(0, progress ?? 0))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if progress != nil, p > 0.004 {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .animation(reduce ? nil : animation, value: p)
        .accessibilityHidden(true)
    }
}
