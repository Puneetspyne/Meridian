import SwiftUI
import MeridianKit
import MeridianTime

/// The open card both bodies show. Keep `CardView(model:presentation:)` working: other workstreams embed it.
///
/// On a notch the top band beside the hardware notch is used for the chip and the settings button (the band is
/// otherwise dead black), and the rest of the footer sits at the bottom. Elsewhere one footer row holds everything.
struct CardView: View {
    let model: AppModel
    /// Which body opened the card; lets the hero anchor and corner radii match the opener.
    var presentation: CardPresentation = .notch
    /// Shared with the closed wing so the wing ring flies into the hero ring on open.
    var ringNamespace: Namespace.ID? = nil
    var ringIsSource: Bool = true
    /// Called by the gear button. Falls back to the environment, then to a notification the app can observe.
    var openSettings: (() -> Void)? = nil

    @Environment(\.meridianOpenSettings) private var envOpenSettings
    @Environment(\.meridianNotchClearance) private var clearance

    static let openSettingsNotification = Notification.Name("meridian.openSettings")

    private var isNotch: Bool { presentation == .notch }

    var body: some View {
        let content = VStack(spacing: 0) {
            if isNotch { notchBand }
            VStack(spacing: Design.Space.m) {
                HeroView(signal: model.top, ringNamespace: ringNamespace, ringIsSource: ringIsSource)
                CardTiles(model: model)
                if showsTimeStrip { TimeStrip(model: model) }
                if showsAgentsStrip { AgentsStrip(model: model) }
                footer
            }
            .padding(.horizontal, Design.Size.cardPadding)
            .padding(.top, isNotch ? Design.Space.xs : Design.Size.cardPadding)
            .padding(.bottom, Design.Size.cardPadding)
        }
        .frame(width: Design.Size.cardWidth)

        if isNotch {
            content
        } else {
            content.meridianSurface(radius: Design.Radius.card)
        }
    }

    // MARK: Sections

    private var showsTimeStrip: Bool {
        let t = Set(model.settings.visibleTiles)
        guard !t.isDisjoint(with: [.meeting, .timers, .clocks]) else { return false }
        return model.provider(TimeProvider.self) != nil
            || !TimeStrip.entries(in: model.signals).isEmpty
            || !TimeStrip.clocks(in: model.signals).isEmpty
    }

    private var showsAgentsStrip: Bool {
        model.settings.visibleTiles.contains(.agents)
    }

    private var chipName: String? { model.snapshot.system?.chipName }

    private func gear() -> some View {
        Button {
            if let openSettings { openSettings() } else {
                envOpenSettings()
                NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Design.Color.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    /// Beside the hardware notch: chip on the left, settings on the right.
    private var notchBand: some View {
        HStack(spacing: 0) {
            if let chipName { Chip(text: chipName, symbol: "cpu") }
            Spacer(minLength: clearance.width)
            gear()
        }
        .padding(.horizontal, Design.Size.cardPadding)
        .frame(height: clearance.height, alignment: .center)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isNotch, let chipName { Chip(text: chipName, symbol: "cpu") }
            if let up = model.snapshot.cpu?.uptime, up > 0 {
                Text("Up \(Format.uptime(up))").font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary)
            }
            Spacer(minLength: 0)
            UpdatedLabel(timestamp: model.snapshot.timestamp)
            if !isNotch { gear() }
        }
        .frame(height: 22)
        .padding(.horizontal, 2)
    }
}

/// "Updated 3 s ago", refreshed once a second while visible.
struct UpdatedLabel: View {
    var timestamp: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = Int(max(0, ctx.date.timeIntervalSince(timestamp)))
            Group {
                if timestamp.timeIntervalSince1970 < 1 {
                    Text("Waiting for data")
                } else if age < 60 {
                    Text("Updated \(age) s ago")
                } else {
                    Text("Updated \(age / 60) min ago")
                }
            }
            .font(Design.Font.caption)
            .foregroundStyle(Design.Color.textTertiary)
            .monospacedDigit()
        }
    }
}

enum CardPresentation: Equatable {
    case notch
    case corner(ScreenCorner)
    case menuBar
}
