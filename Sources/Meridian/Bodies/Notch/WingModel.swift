import Foundation
import MeridianKit

/// Everything the closed wings draw, reduced to values that only change when something visible changes.
/// `AppModel.top` is a fresh `Signal` every second; this is `Equatable` so the closed view can be skipped
/// when the text, ring and tint on screen are identical.
struct WingModel: Equatable {
    var symbol: String = ""
    /// Left-wing text. Nil for live countdowns (they tick on their own) and for signals with no value.
    var valueText: String?
    /// Right-wing text. Empty for live countdowns.
    var title: String = ""
    var tint: SignalTint = .neutral
    var attention: Attention = .calm
    /// Rounded to 0.02 (about 7 degrees on a 16 pt ring, invisible) so it does not redraw for tiny changes. Nil means "no ring" (symbol instead).
    var progress: Double?
    var deadline: Date?
    var isLiveCountdown = false
    var isEmpty = true
    var spoken = "Meridian, waiting for data"

    init(_ s: Signal?) {
        guard let s else { return }
        isEmpty = false
        symbol = s.symbol
        tint = s.tint
        attention = s.attention
        progress = s.progress.map { (min(1, max(0, $0)) * 50).rounded() / 50 }
        isLiveCountdown = s.isLiveCountdown
        deadline = s.isLiveCountdown ? s.deadline : nil
        valueText = s.isLiveCountdown ? nil : s.value
        title = s.isLiveCountdown ? "" : s.title
        spoken = s.isLiveCountdown ? "\(s.detail ?? "Countdown"), counting down" : s.accessibilityPhrase
    }
}
