import AppKit

/// Where macOS put the menu bar items (status items) to the right of the notch. They are drawn above our panel by
/// the menu bar server, so the right wing must stop short of the first one instead of overlapping it.
/// Window bounds are readable without any permission.
enum MenuBarItems {
    /// Left edge (global x) of the leftmost status item right of `notchMaxX`, or nil when none is on screen.
    static func firstItemMinX(rightOf notchMaxX: CGFloat, menuBarHeight: CGFloat) -> CGFloat? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var best: CGFloat?
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let h = b["Height"],
                  y <= 2, h <= menuBarHeight + 6, x >= notchMaxX - 1 else { continue }
            best = min(best ?? x, x)
        }
        return best
    }

    /// Per-wing width limit: the free menu bar between the notch and the first item, never below `minimum`.
    static func wingCap(for g: NotchGeometry, minimum: CGFloat = 84, margin: CGFloat = 6) -> CGFloat? {
        let notchMaxX = g.centerX + g.notchWidth / 2
        guard let x = firstItemMinX(rightOf: notchMaxX, menuBarHeight: g.notchHeight) else { return nil }
        return max(minimum, x - notchMaxX - Design.Size.notchInsetSide - margin)
    }
}
