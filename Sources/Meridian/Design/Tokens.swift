import SwiftUI
import MeridianKit

/// The design system in one file. Every surface reads from here; nothing hardcodes a colour, radius or spring.
/// See docs/DESIGN.md for the reasoning behind each value.
enum Design {
    // MARK: Colour
    enum Color {
        /// The notch extension is hardware-black, never glass. Matches the bezel so the shape reads as one piece.
        static let notch = SwiftUI.Color(red: 0.0, green: 0.0, blue: 0.0)
        /// Card surfaces sit on system materials; these are the tints layered on top.
        static let cardTint = SwiftUI.Color.white.opacity(0.04)
        static let hairline = SwiftUI.Color.white.opacity(0.08)
        static let hairlineStrong = SwiftUI.Color.white.opacity(0.16)
        static let textPrimary = SwiftUI.Color.white.opacity(0.92)
        static let textSecondary = SwiftUI.Color.white.opacity(0.58)
        static let textTertiary = SwiftUI.Color.white.opacity(0.36)
        static let trackIdle = SwiftUI.Color.white.opacity(0.10)

        static func tint(_ t: SignalTint) -> SwiftUI.Color {
            switch t {
            case .neutral: return SwiftUI.Color.white.opacity(0.85)
            case .teal: return SwiftUI.Color(.systemTeal)
            case .blue: return SwiftUI.Color(.systemBlue)
            case .green: return SwiftUI.Color(.systemGreen)
            case .amber: return SwiftUI.Color(.systemOrange)
            case .red: return SwiftUI.Color(.systemRed)
            case .violet: return SwiftUI.Color(.systemPurple)
            case .pink: return SwiftUI.Color(.systemPink)
            }
        }

        static func attention(_ a: Attention) -> SwiftUI.Color {
            switch a {
            case .calm: return textPrimary
            case .info: return SwiftUI.Color(.systemTeal)
            case .warning: return SwiftUI.Color(.systemOrange)
            case .critical: return SwiftUI.Color(.systemRed)
            }
        }
    }

    // MARK: Geometry
    enum Radius {
        /// Bottom corners of the notch extension. Apple's notch corners are close to this.
        static let notchBottom: CGFloat = 14
        static let card: CGFloat = 26
        static let tile: CGFloat = 16
        static let chip: CGFloat = 8
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Size {
        /// Extra black around the hardware notch when closed: a hair on each side, a little more below.
        static let notchInsetSide: CGFloat = 2
        static let notchInsetBottom: CGFloat = 4
        static let cardWidth: CGFloat = 440
        static let tileHeight: CGFloat = 76
        static let ring: CGFloat = 16
        static let ringStroke: CGFloat = 2.5
    }

    // MARK: Type
    enum Font {
        /// Numbers everywhere: rounded, monospaced digits so values do not jitter as they change.
        static func number(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
        static let wing = SwiftUI.Font.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit()
        static let wingLabel = SwiftUI.Font.system(size: 9.5, weight: .medium, design: .rounded)
        static let heroValue = number(44, weight: .semibold)
        static let heroTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 12.5, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium)
        static let tileValue = number(20)
        static let tileLabel = SwiftUI.Font.system(size: 10.5, weight: .semibold)
    }

    // MARK: Motion
    /// All motion is springs. No linear or ease curves anywhere in the app.
    enum Motion {
        static let open = Animation.spring(response: 0.46, dampingFraction: 0.80)
        static let close = Animation.spring(response: 0.34, dampingFraction: 0.92)
        static let hover = Animation.spring(response: 0.26, dampingFraction: 0.84)
        static let value = Animation.smooth(duration: 0.55)
        static let ring = Animation.spring(response: 0.7, dampingFraction: 0.9)
        static let swap = Animation.spring(response: 0.38, dampingFraction: 0.86)

        /// Honours the system Reduce Motion setting, or the app-level override.
        static func respecting(_ animation: Animation, reduce: Bool) -> Animation? {
            reduce ? .easeInOut(duration: 0.15) : animation
        }
    }
}

// MARK: - Materials

/// Glass for cards: Liquid Glass on macOS 26, a dark ultra-thin material before that. Same shape either way.
struct MeridianGlass: ViewModifier {
    var radius: CGFloat
    var prominent: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(prominent ? .regular.tint(Design.Color.cardTint) : .regular, in: shape)
                .overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Design.Color.cardTint, in: shape)
                .overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
        }
    }
}

extension View {
    func meridianGlass(radius: CGFloat = Design.Radius.card, prominent: Bool = false) -> some View {
        modifier(MeridianGlass(radius: radius, prominent: prominent))
    }
}
