import SwiftUI
import MeridianKit
import MeridianTime
import MeridianAgents

/// Sizes of the wide "pebble" card. One place, so the notch shape, the corner panel and the content agree.
enum WideMetrics {
    static let maxWidth: CGFloat = 880
    static let rowHeight: CGFloat = 112
    static let heroWidth: CGFloat = 190
    static let timeWidth: CGFloat = 152
    static let tileGap: CGFloat = 8
    static let padding: CGFloat = 14
    static let sectionGap: CGFloat = 12
    static let pillsHeight: CGFloat = 30
    static let minTileWidth: CGFloat = 112

    /// Card width: 880, or the screen minus 24 pt margins (and minus both flares on a notch).
    static func width(screenWidth: CGFloat, flare: CGFloat) -> CGFloat {
        min(maxWidth, max(480, screenWidth - 24 - 2 * flare))
    }
    static func tilesWidth(_ width: CGFloat) -> CGFloat {
        width - 2 * padding - heroWidth - timeWidth - 2 * sectionGap
    }
    /// How many compact tiles fit; the rest are hidden, never squeezed below `minTileWidth`.
    static func tileCount(_ width: CGFloat) -> Int {
        max(1, Int((tilesWidth(width) + tileGap) / (minTileWidth + tileGap)))
    }
    static func tileWidth(_ width: CGFloat, count: Int) -> CGFloat {
        (tilesWidth(width) - tileGap * CGFloat(count - 1)) / CGFloat(max(1, count))
    }
}

/// Hero at the left, compact tiles in the middle, time column at the right, agent pills under the tiles.
struct WideCardContent: View {
    let model: AppModel
    var width: CGFloat
    var ringNamespace: Namespace.ID?
    var ringIsSource: Bool

    var body: some View {
        let count = WideMetrics.tileCount(width)
        let tiles = Array(model.settings.visibleTiles.filter { CompactTiles.supported.contains($0) }.prefix(count))
        let tileWidth = WideMetrics.tileWidth(width, count: max(1, min(count, tiles.count == 0 ? count : count)))
        let showsPills = model.settings.visibleTiles.contains(.agents) && !WidePills.items(model).isEmpty
        HStack(alignment: .top, spacing: WideMetrics.sectionGap) {
            HeroView(signal: model.top, ringNamespace: ringNamespace, ringIsSource: ringIsSource, compact: true)
                .frame(width: WideMetrics.heroWidth, height: WideMetrics.rowHeight, alignment: .center)
            VStack(alignment: .leading, spacing: 6) {
                CompactTiles(model: model, tiles: tiles, tileWidth: tileWidth)
                if showsPills { WidePills(model: model).frame(height: WideMetrics.pillsHeight - 6) }
            }
            .frame(width: WideMetrics.tilesWidth(width), alignment: .leading)
            WideTimeColumn(model: model)
                .frame(width: WideMetrics.timeWidth, height: WideMetrics.rowHeight)
        }
        .padding(.horizontal, WideMetrics.padding)
    }
}

// MARK: - Agent pills

private struct Pill: Identifiable {
    var id: String
    var name: String
    var color: Color
    var start: Date?
    var url: URL?
}

struct WidePills: View {
    let model: AppModel

    fileprivate static func items(_ model: AppModel) -> [Pill] {
        if let p = model.provider(AgentsProvider.self) {
            return p.sessions.filter { !$0.dismissed && $0.state != .idle }
                .sorted { rank($0.state) < rank($1.state) }.prefix(3).map { s in
                    let c: Color
                    switch s.state {
                    case .working: c = Design.Color.tint(.violet)
                    case .needsYou: c = Design.Color.tint(.amber)
                    default: c = Design.Color.tint(.green)
                    }
                    return Pill(id: s.id, name: s.name, color: c, start: s.state == .needsYou ? s.needsSince : (s.state == .working ? s.turnStartedAt : nil), url: s.actionURL)
                }
        }
        return AgentsStrip.sessions(in: model.signals).prefix(3).map {
            Pill(id: $0.id, name: $0.title, color: Design.Color.tint($0.tint), start: nil, url: $0.actionURL)
        }
    }

    private static func rank(_ s: AgentState) -> Int { switch s { case .needsYou: 0; case .working: 1; default: 2 } }

    var body: some View {
        let _ = model.signals // refresh when the provider republishes
        HStack(spacing: 6) {
            ForEach(Self.items(model)) { pill in
                let label = HStack(spacing: 6) {
                    Circle().fill(pill.color).frame(width: 7, height: 7)
                    Text(pill.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
                    if let start = pill.start {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Num(Format.countdown(max(0, ctx.date.timeIntervalSince(start))), size: 11, weight: .medium, color: Design.Color.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                if let url = pill.url {
                    Button { openURL(url) } label: { label }.buttonStyle(.plain).accessibilityLabel("\(pill.name). Opens the session")
                } else {
                    label.accessibilityElement(children: .ignore).accessibilityLabel(pill.name)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Time column

/// Clock, the next meeting or running timer, one world clock.
struct WideTimeColumn: View {
    let model: AppModel
    private var provider: TimeProvider? { model.provider(TimeProvider.self) }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    var body: some View {
        let signals = model.signals // provider mutations republish signals
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.everyMinute) { ctx in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ClockText.string(ctx.date, use24Hour: model.settings.modules.uses24HourClock))
                        .font(Design.Font.number(22)).foregroundStyle(Design.Color.textPrimary)
                    Text(Self.dateFormat.string(from: ctx.date)).font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            nextItem(signals)
            Spacer(minLength: 4)
            if let clock = provider?.worldClocks.first {
                HStack(spacing: 6) {
                    Text(clock.cityName == clock.abbreviation ? clock.abbreviation : clock.cityName)
                        .font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Num(clock.time, size: 12, weight: .medium)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(clock.cityName) \(clock.time)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .meridianSurface(radius: Design.Radius.tile)
    }

    @ViewBuilder private func nextItem(_ signals: [Signal]) -> some View {
        if let meeting = signals.first(where: { $0.kind == .meeting }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    if meeting.isLiveCountdown { SignalValue(signal: meeting, font: Design.Font.number(12, weight: .medium), color: Design.Color.tint(.blue)) }
                    Spacer(minLength: 0)
                    if let url = meeting.actionURL, let title = meeting.actionTitle {
                        Button { openURL(url) } label: {
                            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 9).frame(height: 20).background(Capsule().fill(Design.Color.tint(.blue)))
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(title) \(meeting.title)")
                    }
                }
            }
        } else if let provider, let t = provider.timers.first(where: { !$0.isDismissed }) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let finished = t.isFinished(at: ctx.date)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.name.isEmpty ? "Timer" : t.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
                        Num(finished ? "Time's up" : Format.countdown(max(0, t.remaining(at: ctx.date))), size: 12, weight: .medium,
                            color: finished ? Design.Color.tint(.red) : Design.Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if finished {
                        IconButton(symbol: "checkmark", label: "Dismiss \(t.name)") { provider.dismiss(signalID: "time.timer.\(t.id.uuidString)") }
                    } else {
                        IconButton(symbol: t.isRunning ? "pause.fill" : "play.fill", label: t.isRunning ? "Pause \(t.name)" : "Resume \(t.name)") {
                            t.isRunning ? provider.pause(timerID: t.id) : provider.resume(timerID: t.id)
                        }
                    }
                }
            }
        } else {
            Text("Nothing scheduled").font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary)
        }
    }
}
