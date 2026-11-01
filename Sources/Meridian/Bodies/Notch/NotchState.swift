import AppKit
import Observation

/// Interaction state of one notch body. The controller writes it (from AppKit events, inside `withAnimation`),
/// the SwiftUI view only reads it, so the view never needs timers or hover callbacks of its own.
@MainActor
@Observable
final class NotchState {
    var isOpen = false
    var isHovering = false
    /// Last measured height of the open card, kept across opens so the drawer opens to the right size at once.
    /// Upper bound for each wing so the black never covers menu bar items macOS placed beside the notch.
    var wingCap: CGFloat?
    var cardHeight: CGFloat = 640
    var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}
