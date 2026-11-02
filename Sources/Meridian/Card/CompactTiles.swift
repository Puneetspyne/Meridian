import SwiftUI
import MeridianKit

/// Tiles for the wide card: about 112 pt wide, one value, one caption, one short sparkline. Tiles that do not fit
/// are left out instead of squeezed (`WideMetrics.tileCount`).
struct CompactTiles: View {
    let model: AppModel
    var tiles: [Tile]
    var tileWidth: CGFloat

    static let supported: [Tile] = [.cpu, .memory, .temperature, .network, .disk, .battery, .gpu, .power]

    var body: some View {
        HStack(spacing: WideMetrics.tileGap) {
            ForEach(tiles) { t in
                CompactTile(facts: facts(t), width: tileWidth)
            }
        }
    }

    // MARK: Facts

    private var snap: TelemetrySnapshot { model.snapshot }
    private var unit: TemperatureUnit { model.settings.modules.temperatureUnit }
    private func series(_ id: MetricID) -> [Double] { model.histories[id]?.values ?? [] }
    private func attention(_ kind: SignalKind) -> Attention { model.signals.filter { $0.kind == kind }.map(\.attention).max() ?? .calm }

    private func facts(_ t: Tile) -> CompactFacts {
        let dash = Placeholder.dash
        switch t {
        case .cpu:
            let a = attention(.cpu)
            let c = snap.cpu
            var f = CompactFacts(title: "CPU", value: c.map { Format.percent($0.total) } ?? dash, attention: a)
            f.caption = c.map { $0.efficiencyCoreCount > 0 ? "\($0.efficiencyCoreCount)E \u{00B7} \($0.performanceCoreCount)P" : "\($0.coreCount) cores" }
            f.series = series(.cpu); f.domain = 0...1; f.minSpan = 0.5
            if let c, !c.perCore.isEmpty { f.efficiency = Array(c.efficiencyCores); f.performance = Array(c.performanceCores) }
            return f
        case .memory:
            let a = attention(.memory)
            let m = snap.memory
            var f = CompactFacts(title: "Memory", value: m.map { Format.percent($0.usedFraction) } ?? dash, attention: a)
            f.caption = m.map { "\(Format.bytes($0.usedBytes)) of \(Format.bytes($0.totalBytes))" }
            f.dot = m.map { $0.pressure == .normal ? Design.Color.tint(.green) : ($0.pressure == .warning ? Design.Color.tint(.amber) : Design.Color.tint(.red)) }
            f.series = series(.memory); f.domain = 0...1; f.minSpan = 0.2
            return f
        case .temperature:
            let a = attention(.thermal)
            let hot = snap.thermal?.sensors.max(by: { $0.celsius < $1.celsius })
            var f = CompactFacts(title: "Temperature", value: hot.map { Format.temperature($0.celsius, unit: unit) } ?? dash, attention: a)
            f.caption = snap.thermal?.fans.map(\.rpm).max().map { Format.rpm($0) } ?? hot.map { $0.group.rawValue.uppercased() }
            f.series = series(.cpuTemp); f.minSpan = 12
            return f
        case .network:
            let n = snap.network
            var f = CompactFacts(title: "Network", value: "", attention: .calm)
            f.down = n.map { Format.rate($0.rxBytesPerSec) } ?? dash
            f.up = n.map { Format.rate($0.txBytesPerSec) } ?? dash
            f.series = series(.networkDown); f.minSpan = 100_000
            f.spokenOverride = "Network, download \(f.down ?? dash), upload \(f.up ?? dash)"
            return f
        case .disk:
            let a = attention(.disk)
            let d = snap.bootDisk
            var f = CompactFacts(title: "Disk", value: d.map { Format.bytes($0.freeBytes) } ?? dash, attention: a)
            f.caption = d == nil ? nil : "free"
            f.series = series(.diskRead); f.minSpan = 500_000
            return f
        case .battery:
            let a = attention(.battery)
            let b = snap.battery.flatMap { $0.isPresent ? $0 : nil }
            var f = CompactFacts(title: "Battery", value: b.map { Format.percent($0.level) } ?? dash, attention: a)
            if let b { f.caption = b.isCharging ? "Charging" : b.minutesRemaining.map { Format.minutes($0) } } else { f.caption = "No battery" }
            f.series = series(.battery); f.domain = 0...1; f.minSpan = 0.1
            if b?.isCharging == true { f.tint = Design.Color.tint(.green) }
            return f
        case .gpu:
            var f = CompactFacts(title: "GPU", value: snap.gpu?.utilization.map { Format.percent($0) } ?? dash, attention: .calm)
            f.caption = snap.gpu?.coreCount.map { "\($0) cores" }
            f.series = series(.gpu); f.domain = 0...1; f.minSpan = 0.5
            return f
        default: // power
            var f = CompactFacts(title: "Power", value: snap.power?.totalWatts.map { Format.watts($0) } ?? dash, attention: .calm)
            f.caption = snap.battery.flatMap { $0.isPresent ? ($0.isPluggedIn ? "Adapter" : "Battery") : nil }
            f.series = series(.power); f.minSpan = 5
            return f
        }
    }
}

struct CompactFacts {
    var title: String
    var value: String
    var attention: Attention
    var caption: String?
    var dot: Color?
    var series: [Double] = []
    var domain: ClosedRange<Double>?
    var minSpan: Double = 0
    var tint: Color?
    var efficiency: [Double]?
    var performance: [Double]?
    var down: String?
    var up: String?
    var spokenOverride: String?

    var spoken: String {
        if let spokenOverride { return spokenOverride }
        let level = attention == .critical ? ", critical" : (attention == .warning ? ", warning" : "")
        return "\(title) \(value.replacingOccurrences(of: "%", with: " percent"))\(level)" + (caption.map { ", " + $0 } ?? "")
    }
}

private struct CompactTile: View {
    let facts: CompactFacts
    let width: CGFloat
    @State private var hover = false
    @Environment(\.meridianReduceMotion) private var reduce

    var body: some View {
        let warn = facts.attention >= .warning
        let valueColor = warn ? Design.Color.attention(facts.attention) : Design.Color.textPrimary
        let line = facts.tint ?? (warn ? Design.Color.attention(facts.attention) : Design.Color.textSecondary)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text(facts.title).font(Design.Font.tileLabel).foregroundStyle(Design.Color.textSecondary).lineLimit(1)
                if let dot = facts.dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Spacer(minLength: 0)
            }
            .frame(height: 14)

            if let down = facts.down, let up = facts.up {
                VStack(alignment: .leading, spacing: 1) {
                    rate("arrow.down", down, Design.Color.tint(.teal))
                    rate("arrow.up", up, Design.Color.tint(.blue))
                }
                .padding(.top, 6)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    Num(facts.value, font: Design.Font.tileValue, color: valueColor).frame(height: 26, alignment: .leading)
                    Spacer(minLength: 2)
                    if let e = facts.efficiency, let p = facts.performance {
                        CoreBars(efficiency: e, performance: p, height: 22, barWidth: 3)
                    }
                }
                .padding(.top, 4)
                Text(facts.caption ?? " ")
                    .font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary).lineLimit(1)
                    .padding(.top, 1)
            }
            Spacer(minLength: 4)
            Sparkline(values: facts.series, tint: line, domain: facts.domain, minSpan: facts.minSpan)
                .frame(height: 26)
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 9)
        .frame(width: width, height: WideMetrics.rowHeight, alignment: .topLeading)
        .meridianSurface(radius: Design.Radius.tile, lifted: hover)
        .offset(y: hover ? -1 : 0)
        .animation(reduce ? nil : Design.Motion.hover, value: hover)
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facts.spoken)
    }

    private func rate(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint).frame(width: 9)
            Num(text, size: 12, weight: .medium)
        }
    }
}
