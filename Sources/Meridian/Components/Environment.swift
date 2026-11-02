import SwiftUI
import AppKit
import MeridianKit

// MARK: - Environment

private struct ReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
private struct OpenSettingsKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
private struct MaterialKey: EnvironmentKey { static let defaultValue: CardMaterial = .glass }
private struct ScreenWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct KeyboardKey: EnvironmentKey { static let defaultValue: (Bool) -> Void = { _ in } }
private struct NotchClearanceKey: EnvironmentKey { static let defaultValue: CGSize = .zero }

extension EnvironmentValues {
    /// Resolved Reduce Motion: system setting, or the app-level override.
    var meridianReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
    /// True while ImageRenderer draws: glass has no backdrop to sample there, so surfaces use a flat fill.
    var meridianSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
    var meridianOpenSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
    /// The card's surface: tiles are flat on glass (no blur on blur) and glass on matte black.
    var meridianMaterial: CardMaterial {
        get { self[MaterialKey.self] }
        set { self[MaterialKey.self] = newValue }
    }
    /// Width of the screen the card sits on; 0 means "ask NSScreen.main". The wide card clamps to it.
    var meridianScreenWidth: CGFloat {
        get { self[ScreenWidthKey.self] }
        set { self[ScreenWidthKey.self] = newValue }
    }
    /// Asks the hosting panel for (true) or releases (false) keyboard focus, for text fields in the card.
    var meridianKeyboard: (Bool) -> Void {
        get { self[KeyboardKey.self] }
        set { self[KeyboardKey.self] = newValue }
    }
    /// Size of the dead zone the hardware notch leaves at the top of an open notch card.
    var meridianNotchClearance: CGSize {
        get { self[NotchClearanceKey.self] }
        set { self[NotchClearanceKey.self] = newValue }
    }
}

enum Motion {
    /// The user's choice wins; otherwise the system accessibility setting.
    static func reduce(override: Bool?) -> Bool {
        override ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - Surfaces

/// Tile surface. On a glass card it is a flat translucent fill (a second blur over the card's glass would be
/// blur behind blur); on a matte black card it is glass over black. Both get a 1 pt top highlight, and a lifted
/// tile gets a stronger hairline. Snapshots use the flat fill because ImageRenderer has no backdrop.
struct MeridianSurface: ViewModifier {
    var radius: CGFloat
    var lifted = false
    @Environment(\.meridianSnapshot) private var snapshot
    @Environment(\.meridianMaterial) private var material

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let hairline = lifted ? Design.Color.hairlineStrong : Design.Color.hairline
        let highlight = shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
        if snapshot || material == .glass {
            content
                .background(shape.fill(Color.white.opacity(snapshot ? 0.085 : 0.075)))
                .overlay(shape.strokeBorder(hairline, lineWidth: 1))
                .overlay(highlight)
        } else {
            // A dark underlay keeps text legible when the window behind is bright or busy.
            content
                .background(shape.fill(Color.black.opacity(0.28)))
                .meridianGlass(radius: radius)
                .overlay(highlight)
        }
    }
}

extension View {
    func meridianSurface(radius: CGFloat = Design.Radius.tile, lifted: Bool = false) -> some View {
        modifier(MeridianSurface(radius: radius, lifted: lifted))
    }
}

/// The glass body of an open card: Liquid Glass (macOS 26) or the dark ultra-thin material, a scrim chosen by the
/// system appearance so white text keeps AA contrast over a light wallpaper, hairline, and the shadow the material needs.
struct CardGlassBackground<S: InsettableShape>: View {
    var shape: S
    /// Black scrim over the glass: a touch heavier when the system appearance is light.
    var scrim: Double
    @Environment(\.meridianSnapshot) private var snapshot

    var body: some View {
        if snapshot {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.fill(Color.black.opacity(scrim)))
                .overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
        } else {
            Color.clear
                .meridianGlassFill(shape)
                .overlay(shape.fill(Color.black.opacity(scrim)))
                .overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
        }
    }
}

extension View {
    /// Glass in an arbitrary shape: Liquid Glass on macOS 26, dark ultra-thin material before.
    @ViewBuilder func meridianGlassFill<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape).shadow(color: .black.opacity(0.45), radius: 30, y: 18)
        }
    }
}

enum SystemAppearance {
    /// Scrim opacity from the system appearance (not from sampling the wallpaper): light mode leaves the most
    /// room for a bright wallpaper to wash the glass out, so it gets 14 percent, dark gets 10.
    static func scrim() -> Double {
        let name = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return name == .aqua ? 0.14 : 0.10
    }
}

// MARK: - Numbers

/// Every number in the UI: rounded monospaced digits so nothing jitters.
struct Num: View {
    let text: String
    var font: Font
    var color: Color = Design.Color.textPrimary
    /// Reserved for rolling digits; ignored for now (see `body`).
    var animates = false

    init(_ text: String, font: Font, color: Color = Design.Color.textPrimary, animates: Bool = false) {
        self.text = text
        self.font = font
        self.color = color
        self.animates = animates
    }

    init(_ text: String, size: CGFloat, weight: Font.Weight = .semibold, color: Color = Design.Color.textPrimary, animates: Bool = false) {
        self.init(text, font: Design.Font.number(size, weight: weight), color: color, animates: animates)
    }

    var body: some View {
        // Plain text on purpose. Measured on an M2 with the card open and live data: any rolling-digit machinery on
        // a number that changes every second (`contentTransition(.numericText())`, an `onChange` that writes state,
        // or an `id` swap with a push transition) cost 6 to 12 percent CPU, against 2 percent for plain text,
        // because SwiftUI repaints this panel in software and every effect layer is redrawn on each tick.
        // `animates` is kept so a caller can ask for a roll once that cost is gone; it does nothing today.
        Text(text).font(font).foregroundStyle(color).lineLimit(1)
    }
}

enum Placeholder {
    static let dash = "\u{2014}"
}


