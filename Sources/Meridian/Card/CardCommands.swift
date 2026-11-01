import Foundation
import Observation

/// One-shot requests from outside the card (a global hotkey, the status item) to views inside it.
@MainActor
@Observable
final class CardCommands {
    static let shared = CardCommands()
    /// Set before opening the card; the Time strip consumes it, opens quick add and focuses the field.
    var quickAddPending = false
    /// Text the quick-add field starts with (the snapshot renderer uses this to show the live parse preview).
    var quickAddPrefill: String?
    private init() {}
}
