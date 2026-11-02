import AppKit
import MeridianKit

/// What the hardware gives us: where the notch is and how tall the safe-area band is. Pure values, so tests
/// and the snapshot renderer can build one without a screen.
struct NotchGeometry: Equatable {
    /// Width of the camera housing gap between the two auxiliary areas.
    var notchWidth: CGFloat
    /// `safeAreaInsets.top`: the height of the menu bar band the notch occupies.
    var notchHeight: CGFloat
    /// Horizontal centre of the notch in global screen coordinates.
    var centerX: CGFloat
    /// Top edge of the screen in global coordinates (AppKit: y grows upward).
    var topY: CGFloat
    /// Width of the screen, for clamping the wide card.
    var screenWidth: CGFloat = 1710

    /// The notch on a 14-inch MacBook Air class machine, used when a screen reports a notch but no auxiliary areas.
    static let fallbackWidth: CGFloat = 200

    init(notchWidth: CGFloat, notchHeight: CGFloat, centerX: CGFloat, topY: CGFloat, screenWidth: CGFloat = 1710) {
        self.screenWidth = screenWidth
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.centerX = centerX
        self.topY = topY
    }

    /// Nil when the screen has no notch.
    init?(screen: NSScreen) {
        let inset = screen.safeAreaInsets.top
        guard inset > 0 else { return nil }
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
            notchWidth = right.minX - left.maxX
            centerX = (left.maxX + right.minX) / 2
        } else {
            notchWidth = Self.fallbackWidth
            centerX = frame.midX
        }
        notchHeight = inset
        topY = frame.maxY
        screenWidth = frame.width
    }
}

/// Every size the notch body passes through, derived from the hardware and the user's wing width.
struct NotchLayout: Equatable {
    var geometry: NotchGeometry
    var wing: CGFloat
    var cardHeight: CGFloat
    var panelHeight: CGFloat
    var cardLayout: CardLayout = .tall
    /// Wide enough for the biggest shape (the wide card) on this screen; the panel is mouse-transparent outside the shape.
    var panelWidth: CGFloat { Self.panelWidth(screenWidth: geometry.screenWidth) }
    static func panelWidth(screenWidth: CGFloat) -> CGFloat {
        max(Design.NotchMetrics.panelWidth, min(screenWidth, WideMetrics.maxWidth + 2 * Design.NotchMetrics.openTopRadius + 24))
    }
    var cardWidth: CGFloat { CardView.width(layout: cardLayout, screenWidth: geometry.screenWidth, isNotch: true) }

    var closedSize: CGSize {
        CGSize(width: geometry.notchWidth + 2 * (Design.Size.notchInsetSide + wing),
               height: geometry.notchHeight + Design.Size.notchInsetBottom)
    }
    var hoverSize: CGSize {
        CGSize(width: closedSize.width + 2 * Design.NotchMetrics.hoverGrowWing,
               height: closedSize.height + Design.NotchMetrics.hoverGrowHeight)
    }
    /// Outer width includes the concave flares on both sides; the card itself is `cardWidth` wide.
    var openSize: CGSize {
        CGSize(width: cardWidth + 2 * Design.NotchMetrics.openTopRadius,
               height: min(cardHeight, maxCardHeight))
    }
    var maxCardHeight: CGFloat { panelHeight }

    func size(open: Bool, hovering: Bool) -> CGSize { open ? openSize : (hovering ? hoverSize : closedSize) }

    /// Panel height that fits the tallest card we allow on this screen.
    static func panelHeight(for screenHeight: CGFloat, notchHeight: CGFloat) -> CGFloat {
        min(screenHeight - 40, notchHeight + Design.Size.notchInsetBottom + Design.NotchMetrics.panelMaxCardHeight)
    }
}
