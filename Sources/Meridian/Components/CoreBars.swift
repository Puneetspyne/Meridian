import SwiftUI
import MeridianKit

/// Per-core load as slim vertical bars: efficiency cores first, a gap, then performance cores.
struct CoreBars: View {
    var efficiency: [Double]
    var performance: [Double]
    var height: CGFloat = 26
    var barWidth: CGFloat = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            group(efficiency, tint: Design.Color.tint(.teal))
            group(performance, tint: Design.Color.tint(.neutral))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func group(_ values: [Double], tint: Color) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                let f = min(1, max(0, v))
                ZStack(alignment: .bottom) {
                    Capsule().fill(Design.Color.trackIdle)
                    Capsule().fill(tint).frame(height: max(barWidth, height * f))
                }
                .frame(width: barWidth, height: height)
            }
        }
    }

    private var label: String {
        func avg(_ a: [Double]) -> String { a.isEmpty ? Placeholder.dash : Format.percent(a.reduce(0, +) / Double(a.count)) }
        return "Efficiency cores \(avg(efficiency)), performance cores \(avg(performance))"
    }
}
