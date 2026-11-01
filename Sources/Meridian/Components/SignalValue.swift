import SwiftUI
import AppKit
import MeridianKit

extension Signal {
    /// Countdown-style signals tick live; everything else shows the text the module published.
    var isLiveCountdown: Bool {
        guard deadline != nil else { return false }
        return kind == .countdown || kind == .timer || kind == .meeting
    }

    var accessibilityPhrase: String {
        let level: String
        switch attention {
        case .calm: level = ""
        case .info: level = ", for your attention"
        case .warning: level = ", warning"
        case .critical: level = ", critical"
        }
        var core = title
        if let value, !title.contains(value) { core += " \(value)" }
        return core.replacingOccurrences(of: "%", with: " percent") + level
    }
}

/// The headline text of a signal. Deadlines count down live, once per second, only while on screen.
struct SignalValue: View {
    var signal: Signal
    var font: Font
    var color: Color = Design.Color.textPrimary

    var body: some View {
        if signal.isLiveCountdown, let deadline = signal.deadline {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Num(Format.countdown(max(0, deadline.timeIntervalSince(ctx.date))), font: font, color: color)
            }
        } else if let value = signal.value {
            Num(value, font: font, color: color)
        }
    }
}

func openURL(_ url: URL) { NSWorkspace.shared.open(url) }
