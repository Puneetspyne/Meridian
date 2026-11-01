import SwiftUI

/// Extra tokens for the corner body and its card. Kept out of Tokens.swift so the design system file
/// stays owned by one workstream; values still follow docs/DESIGN.md ("Corner body").
extension Design {
    enum Corner {
        // Closed body
        /// `shrink` rest size as a fraction of the full radius.
        static let restScale: CGFloat = 0.6
        /// `tuck` collapses to this diameter.
        static let tuckDiameter: CGFloat = 10
        /// Distance from the curve to the arc track, and the track's thickness.
        static let arcInset: CGFloat = 6
        static let arcStroke: CGFloat = 3
        static let hairline: CGFloat = 1
        /// Press feedback while the pointer is down on the body.
        static let pressedScale: CGFloat = 0.96

        // Interaction timing
        static let holdToOpen: TimeInterval = 0.25
        static let dragThreshold: CGFloat = 4
        static let closeDelay: TimeInterval = 0.4
        /// Pointer sampling cap: 20 Hz.
        static let pointerSampleInterval: TimeInterval = 0.05
        /// How near the screen edge counts as "pressing against it" for `tuck`, and for how long.
        static let edgePressSlop: CGFloat = 3
        static let edgePressDwell: TimeInterval = 0.15
        static let tuckCollapseDelay: TimeInterval = 0.3

        // Card
        /// Gap between the open card and the screen edges of its corner.
        static let cardInset: CGFloat = 8
        /// Transparent room around the card inside its panel so glass shadows are not clipped.
        static let cardMargin: CGFloat = 20
        static let cardClosedScale: CGFloat = 0.18
        static let cardContentDelay: TimeInterval = 0.06
        /// Slack around the open card in which the pointer still counts as "inside".
        static let cardHoverSlack: CGFloat = 8

        // Settle spring for the drop animation. Mirrors Motion.open (response 0.46, damping 0.80).
        static let settleResponse: Double = 0.46
        static let settleDamping: Double = 0.80

        /// Type scales with the body so the value always fits inside the arc track.
        static func valueSize(radius: CGFloat) -> CGFloat { (radius * 0.24).rounded() }
        static func titleWidth(radius: CGFloat) -> CGFloat { radius * 0.62 }
    }
}
