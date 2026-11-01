import SwiftUI
import MeridianKit

/// PLACEHOLDER. Owned by the Notch & Card workstream. The open card both bodies show.
/// Keep this exact initializer: other workstreams embed `CardView(model:)`.
struct CardView: View {
    let model: AppModel
    /// Which body opened the card; lets the hero anchor and corner radii match the opener.
    var presentation: CardPresentation = .notch

    var body: some View {
        Text("Card").foregroundStyle(Design.Color.textPrimary).padding()
            .frame(width: Design.Size.cardWidth)
            .meridianGlass()
    }
}

enum CardPresentation: Equatable {
    case notch
    case corner(ScreenCorner)
    case menuBar
}
