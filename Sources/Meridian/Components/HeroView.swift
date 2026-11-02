import SwiftUI
import MeridianKit

/// The top signal, large: ring or symbol on the left, title, value and detail on the right.
struct HeroView: View {
    var signal: Signal?
    var ringNamespace: Namespace.ID? = nil
    var ringIsSource: Bool = true
    /// The wide card's hero: 44 pt ring, smaller type, no action button (the time column carries Join).
    var compact = false
    @State private var matching = true

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(signal?.title ?? "Waiting for data")
                    .font(compact ? .system(size: 13, weight: .semibold) : Design.Font.heroTitle)
                    .foregroundStyle(Design.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(compact ? 0.8 : 1)
                if let signal {
                    if signal.value != nil || signal.isLiveCountdown {
                        SignalValue(signal: signal, font: compact ? Design.Font.number(30) : Design.Font.heroValue, color: tint, animates: true)
                            .minimumScaleFactor(0.7)
                            .frame(height: compact ? 34 : 50, alignment: .leading)
                    }
                } else {
                    Num(Placeholder.dash, font: compact ? Design.Font.number(30) : Design.Font.heroValue, color: Design.Color.textTertiary)
                        .frame(height: compact ? 34 : 50, alignment: .leading)
                }
                if let detail = signal?.detail {
                    Text(detail)
                        .font(compact ? Design.Font.caption : Design.Font.body)
                        .foregroundStyle(Design.Color.textSecondary)
                        .lineLimit(compact ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !compact, let signal, let url = signal.actionURL, let title = signal.actionTitle {
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
        .task {
            guard ringNamespace != nil else { return }
            try? await Task.sleep(for: .milliseconds(900))
            matching = false
        }
    }

    private var tint: Color {
        guard let signal else { return Design.Color.textTertiary }
        return signal.attention == .calm ? Design.Color.textPrimary : Design.Color.tint(signal.tint)
    }

    @ViewBuilder private var ring: some View {
        let size = compact ? CGFloat(44) : Design.Size.heroRing
        let glyph = ZStack {
            Ring(progress: signal?.progress, lineWidth: compact ? 3.5 : Design.Size.heroRingStroke,
                 tint: signal.map { Design.Color.tint($0.tint) } ?? Design.Color.tint(.neutral))
            if let symbol = signal?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 15 : 19, weight: .medium))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        // The wing ring flies into this one while the card opens. Afterwards the effect is dropped: a matched
        // geometry that stays attached made the open card re-render continuously (measured).
        if let ns = ringNamespace, matching {
            glyph.matchedGeometryEffect(id: "signalRing", in: ns, isSource: ringIsSource)
        } else {
            glyph
        }
    }
}
