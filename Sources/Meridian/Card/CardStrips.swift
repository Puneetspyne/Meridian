import SwiftUI
import MeridianKit

/// Time and Agents strips. Both read the stable contract: signals of the right kind in `model.signals`.
/// (The providers' own public APIs were still placeholders when this was written.)
struct TimeStrip: View {
    let model: AppModel

    static func entries(in signals: [Signal]) -> [Signal] {
        let kinds: Set<SignalKind> = [.meeting, .countdown, .timer, .stopwatch]
        return signals.filter { kinds.contains($0.kind) }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }
    static func clocks(in signals: [Signal]) -> [Signal] { signals.filter { $0.kind == .clock } }
    static func weather(in signals: [Signal]) -> Signal? { signals.first { $0.kind == .weather } }

    var body: some View {
        let entries = Self.entries(in: model.signals).prefix(4)
        let clocks = Self.clocks(in: model.signals).prefix(2)
        let weather = Self.weather(in: model.signals)
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, s in
                if index > 0 { divider }
                row(s)
            }
            if !clocks.isEmpty || weather != nil {
                if !entries.isEmpty { divider }
                HStack(spacing: 0) {
                    ForEach(Array(clocks), id: \.id) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title).font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary)
                            if let v = c.value { Num(v, size: 15, weight: .medium) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(c.title) \(c.value ?? "")")
                    }
                    if let w = weather {
                        HStack(spacing: 6) {
                            Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 14))
                            if let v = w.value { Num(v, size: 15, weight: .medium) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(w.title) \(w.value ?? "")")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .meridianSurface(radius: Design.Radius.tile)
    }

    private var divider: some View {
        Rectangle().fill(Design.Color.hairline).frame(height: 1).padding(.horizontal, 12)
    }

    private func row(_ s: Signal) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Design.Color.tint(s.tint))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
                if let d = s.detail {
                    Text(d).font(Design.Font.caption).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            SignalValue(signal: s, font: Design.Font.number(13, weight: .medium), color: Design.Color.textPrimary)
            if let url = s.actionURL, let title = s.actionTitle {
                Button { openURL(url) } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(Design.Color.tint(.blue)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(s.title)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }
}

struct AgentsStrip: View {
    let model: AppModel

    static func sessions(in signals: [Signal]) -> [Signal] {
        signals.filter { $0.kind == .agent }
            .sorted { ($0.attention, $0.priority) > ($1.attention, $1.priority) }
    }

    var body: some View {
        let sessions = Self.sessions(in: model.signals)
        VStack(spacing: 0) {
            if sessions.isEmpty {
                HStack {
                    Text("No coding agents running").font(Design.Font.body).foregroundStyle(Design.Color.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
            }
            ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, s in
                if index > 0 { Rectangle().fill(Design.Color.hairline).frame(height: 1).padding(.horizontal, 12) }
                row(s)
            }
        }
        .frame(maxWidth: .infinity)
        .meridianSurface(radius: Design.Radius.tile)
    }

    @ViewBuilder private func row(_ s: Signal) -> some View {
        let content = HStack(spacing: 10) {
            Circle().fill(Design.Color.tint(s.tint)).frame(width: 8, height: 8).frame(width: 18)
            Text(s.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Design.Color.textPrimary).lineLimit(1)
            if let d = s.detail {
                Text(d).font(Design.Font.caption).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let v = s.value { Num(v, size: 12, weight: .medium, color: Design.Color.textSecondary) }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
        if let url = s.actionURL {
            Button { openURL(url) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.title), \(s.detail ?? ""). Opens the session")
        } else {
            content.accessibilityElement(children: .ignore).accessibilityLabel("\(s.title), \(s.detail ?? "")")
        }
    }
}
