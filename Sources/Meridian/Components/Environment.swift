import SwiftUI
import AppKit
import MeridianKit

// MARK: - Environment

private struct ReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
private struct OpenSettingsKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
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

/// `meridianGlass` on screen; a flat translucent fill while snapshotting.
struct MeridianSurface: ViewModifier {
    var radius: CGFloat
    @Environment(\.meridianSnapshot) private var snapshot

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if snapshot {
            content
                .background(shape.fill(Color.white.opacity(0.085)))
                .overlay(shape.strokeBorder(Design.Color.hairline, lineWidth: 1))
        } else {
            // A dark underlay keeps text legible when the window behind is bright or busy.
            content
                .background(shape.fill(Color.black.opacity(0.28)))
                .meridianGlass(radius: radius)
        }
    }
}

extension View {
    func meridianSurface(radius: CGFloat = Design.Radius.tile) -> some View {
        modifier(MeridianSurface(radius: radius))
    }
}

// MARK: - Numbers

/// Every number in the UI: rounded monospaced digits, animated as digits roll.
struct Num: View {
    let text: String
    var font: Font
    var color: Color = Design.Color.textPrimary
    @Environment(\.meridianReduceMotion) private var reduce

    init(_ text: String, font: Font, color: Color = Design.Color.textPrimary) {
        self.text = text
        self.font = font
        self.color = color
    }

    init(_ text: String, size: CGFloat, weight: Font.Weight = .semibold, color: Color = Design.Color.textPrimary) {
        self.init(text, font: Design.Font.number(size, weight: weight), color: color)
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(reduce ? nil : Design.Motion.value, value: text)
    }
}

enum Placeholder {
    static let dash = "\u{2014}"
}
