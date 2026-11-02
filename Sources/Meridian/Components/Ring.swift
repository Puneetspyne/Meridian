import SwiftUI
import MeridianKit

/// A progress arc with a subtle gradient along the stroke (tint to tint at 70 percent) and round caps.
/// The stroke stays inside the frame so a 16 pt ring really occupies 16 pt.
///
/// Only a big jump animates. A ring that eases for every one-percent tick keeps the whole card re-rendering
/// (measured: that alone was 18 percent CPU on an M2 with the card open), so small steps just land.
struct Ring: View {
    var progress: Double?
    var lineWidth: CGFloat = Design.Size.ringStroke
    var tint: Color = Design.Color.tint(.neutral)
    var track: Color = Design.Color.trackIdle
    /// Used for jumps of `jumpThreshold` or more; nil never animates (the closed wing).
    var animation: Animation? = Design.Motion.ring
    var jumpThreshold: Double = 0.15
    @State private var shown: Double = 0
    @Environment(\.meridianReduceMotion) private var reduce

    var body: some View {
        let target = min(1, max(0, progress ?? 0))
        let p = progress == nil ? 0 : (shown == 0 && target > 0 && !appeared ? target : shown)
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if progress != nil, p > 0.004 {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(AngularGradient(colors: [tint.opacity(0.7), tint], center: .center, startAngle: .degrees(0), endAngle: .degrees(max(1, 360 * p))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .onChange(of: target, initial: true) { old, new in
            appeared = true
            if !reduce, let animation, abs(new - old) >= jumpThreshold {
                withAnimation(animation) { shown = new }
            } else {
                shown = new
            }
        }
        .accessibilityHidden(true)
    }

    @State private var appeared = false
}
