import SwiftUI
import MeridianKit

/// A small rounded label: the chip name, a source, a state.
struct Chip: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = Design.Color.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text).font(Design.Font.caption)
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: Design.Radius.chip, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
