import SwiftUI
import MeridianKit

/// The tile frame: label row on top, content below, glass underneath. 76 pt minimum height.
struct MetricTile<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var dot: Color? = nil
    var spoken: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text(title).font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary)
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing).font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary).lineLimit(1)
                }
            }
            .frame(height: 14)
            content
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Design.Size.tileHeight, maxHeight: .infinity, alignment: .topLeading)
        .meridianSurface(radius: Design.Radius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
