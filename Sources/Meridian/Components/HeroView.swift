import SwiftUI
import MeridianKit

/// The top signal, large: ring or symbol on the left, title, value and detail on the right.
struct HeroView: View {
    var signal: Signal?
    var ringNamespace: Namespace.ID? = nil
    var ringIsSource: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(signal?.title ?? "Waiting for data")
                    .font(Design.Font.heroTitle)
                    .foregroundStyle(Design.Color.textPrimary)
                    .lineLimit(1)
                if let signal {
                    if signal.value != nil || signal.isLiveCountdown {
                        SignalValue(signal: signal, font: Design.Font.heroValue, color: tint)
                            .minimumScaleFactor(0.7)
                            .frame(height: 50, alignment: .leading)
                    }
                } else {
                    Num(Placeholder.dash, font: Design.Font.heroValue, color: Design.Color.textTertiary)
                        .frame(height: 50, alignment: .leading)
                }
                if let detail = signal?.detail {
                    Text(detail)
                        .font(Design.Font.body)
                        .foregroundStyle(Design.Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let signal, let url = signal.actionURL, let title = signal.actionTitle {
                Button { openURL(url) } label: {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(tint.opacity(0.9)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        guard let signal else { return Design.Color.textTertiary }
        return signal.attention == .calm ? Design.Color.textPrimary : Design.Color.tint(signal.tint)
    }

    @ViewBuilder private var ring: some View {
        let size = Design.Size.heroRing
        let glyph = ZStack {
            Ring(progress: signal?.progress, lineWidth: Design.Size.heroRingStroke,
                 tint: signal.map { Design.Color.tint($0.tint) } ?? Design.Color.tint(.neutral))
            if let symbol = signal?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        if let ns = ringNamespace {
            glyph.matchedGeometryEffect(id: "signalRing", in: ns, isSource: ringIsSource)
        } else {
            glyph
        }
    }
}
