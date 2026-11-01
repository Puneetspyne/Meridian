import SwiftUI
import MeridianKit

/// The 2-column tile grid. Order comes from `Settings.visibleTiles`; tiles that belong to the Time and Agents
/// strips are not drawn here. Missing data shows an em dash, never a zero that lies.
struct CardTiles: View {
    let model: AppModel

    private static let metricTiles: Set<Tile> = [.cpu, .gpu, .memory, .disk, .network, .battery, .temperature, .fans, .power, .processes]

    var body: some View {
        let tiles = model.settings.visibleTiles.filter { Self.metricTiles.contains($0) }
        let rows = stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    if row.count == 2 {
                        tile(row[0])
                        tile(row[1])
                    } else {
                        tile(row[0]).gridCellColumns(2)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var snap: TelemetrySnapshot { model.snapshot }
    private var unit: TemperatureUnit { model.settings.modules.temperatureUnit }

    private func series(_ id: MetricID) -> [Double] { model.histories[id]?.values ?? [] }

    /// The worst attention among signals of a kind, so a hot tile turns amber or red like the notch does.
    private func attention(_ kind: SignalKind) -> Attention {
        model.signals.filter { $0.kind == kind }.map(\.attention).max() ?? .calm
    }

    private func valueColor(_ a: Attention) -> Color {
        a >= .warning ? Design.Color.attention(a) : Design.Color.textPrimary
    }

    private func lineColor(_ a: Attention) -> Color {
        a >= .warning ? Design.Color.attention(a) : Design.Color.textSecondary
    }

    private func spoken(_ name: String, _ value: String, _ a: Attention = .calm) -> String {
        let level = a == .critical ? ", critical" : (a == .warning ? ", warning" : "")
        return "\(name) \(value.replacingOccurrences(of: "%", with: " percent"))\(level)"
    }

    /// Big number, optional small unit text, optional sparkline underneath.
    private func valueRow(_ value: String, caption: String? = nil, color: Color = Design.Color.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Num(value, font: Design.Font.tileValue, color: color)
            if let caption {
                Text(caption).font(Design.Font.caption).foregroundStyle(Design.Color.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24, alignment: .leading)
    }

    private func spark(_ id: MetricID, tint: Color, domain: ClosedRange<Double>? = nil, minSpan: Double = 0) -> some View {
        Sparkline(values: series(id), tint: tint, domain: domain, minSpan: minSpan)
            .frame(height: Design.Size.sparkHeight)
            .padding(.top, 3)
    }

    // MARK: Tiles

    @ViewBuilder private func tile(_ t: Tile) -> some View {
        switch t {
        case .cpu: cpuTile
        case .memory: memoryTile
        case .temperature: temperatureTile
        case .network: networkTile
        case .disk: diskTile
        case .battery: batteryTile
        case .gpu: gpuTile
        case .fans: fansTile
        case .power: powerTile
        case .processes: processesTile
        default: EmptyView()
        }
    }

    private var cpuTile: some View {
        let a = attention(.cpu)
        let cpu = snap.cpu
        let value = cpu.map { Format.percent($0.total) } ?? Placeholder.dash
        let split = cpu.map { $0.efficiencyCoreCount > 0 ? "\($0.efficiencyCoreCount)E \u{00B7} \($0.performanceCoreCount)P" : "\($0.coreCount) cores" }
        return MetricTile(title: "CPU", trailing: split, spoken: spoken("CPU", value, a)) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    valueRow(value, color: valueColor(a))
                    spark(.cpu, tint: lineColor(a), domain: 0...1, minSpan: 0.5)
                }
                if let cpu, !cpu.perCore.isEmpty {
                    CoreBars(efficiency: Array(cpu.efficiencyCores), performance: Array(cpu.performanceCores), height: 28)
                }
            }
        }
    }

    private var memoryTile: some View {
        let a = attention(.memory)
        let mem = snap.memory
        let value = mem.map { Format.percent($0.usedFraction) } ?? Placeholder.dash
        let caption = mem.map { "\(Format.bytes($0.usedBytes)) of \(Format.bytes($0.totalBytes))" }
        let dot: Color? = mem.map { m in
            switch m.pressure {
            case .normal: return Design.Color.tint(.green)
            case .warning: return Design.Color.tint(.amber)
            case .critical: return Design.Color.tint(.red)
            }
        }
        let pressure = mem.map { "pressure \($0.pressure.rawValue)" } ?? "unavailable"
        return MetricTile(title: "Memory", dot: dot, spoken: spoken("Memory", value, a) + ", \(pressure)") {
            valueRow(value, caption: caption, color: valueColor(a))
            spark(.memory, tint: lineColor(a), domain: 0...1, minSpan: 0.2)
        }
    }

    private static func groupName(_ g: SensorGroup) -> String {
        switch g {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .storage: return "SSD"
        case .system: return "System"
        case .other: return "Sensor"
        }
    }

    private var temperatureTile: some View {
        let a = attention(.thermal)
        let thermal = snap.thermal
        let hottest = thermal?.sensors.max(by: { $0.celsius < $1.celsius })
        let value = hottest.map { Format.temperature($0.celsius, unit: unit) } ?? Placeholder.dash
        let fan = thermal?.fans.map(\.rpm).max()
        let trailing = fan.map { Format.rpm($0) }
        let spokenFan = fan.map { ", fan \(Int($0.rounded())) rpm" } ?? ""
        return MetricTile(title: "Temperature", trailing: trailing, spoken: spoken("Temperature", value, a) + spokenFan) {
            valueRow(value, caption: hottest.map { Self.groupName($0.group) }, color: valueColor(a))
            spark(.cpuTemp, tint: lineColor(a), minSpan: 12)
        }
    }

    private var networkTile: some View {
        let net = snap.network
        let down = net.map { Format.rate($0.rxBytesPerSec) } ?? Placeholder.dash
        let up = net.map { Format.rate($0.txBytesPerSec) } ?? Placeholder.dash
        return MetricTile(title: "Network", trailing: net?.interfaceName, spoken: "Network, download \(down), upload \(up)") {
            VStack(spacing: 3) {
                rateRow(symbol: "arrow.down", text: down, id: .networkDown, tint: Design.Color.tint(.teal))
                rateRow(symbol: "arrow.up", text: up, id: .networkUp, tint: Design.Color.tint(.blue))
            }
            .padding(.top, 3)
        }
    }

    private func rateRow(symbol: String, text: String, id: MetricID, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint).frame(width: 9)
            Num(text, size: 12, weight: .medium).frame(width: 66, alignment: .leading)
            Sparkline(values: series(id), tint: tint, minSpan: 100_000, fill: false).frame(height: 18)
        }
        .frame(height: 18)
    }

    private var diskTile: some View {
        let a = attention(.disk)
        let disk = snap.bootDisk
        let value = disk.map { Format.bytes($0.freeBytes) } ?? Placeholder.dash
        let io: String? = disk.map { "R \(Format.rate($0.readBytesPerSec))  W \(Format.rate($0.writeBytesPerSec))" }
        return MetricTile(title: "Disk", trailing: io, spoken: spoken("Disk", value + " free", a)) {
            valueRow(value, caption: disk == nil ? nil : "free", color: valueColor(a))
            spark(.diskRead, tint: lineColor(a), minSpan: 500_000)
        }
    }

    private var batteryTile: some View {
        let a = attention(.battery)
        let b = snap.battery.flatMap { $0.isPresent ? $0 : nil }
        let value = b.map { Format.percent($0.level) } ?? Placeholder.dash
        var parts: [String] = []
        if let b {
            if let m = b.minutesRemaining { parts.append(Format.minutes(m)) }
            if let w = b.watts { parts.append(Format.watts(abs(w))) }
        }
        let caption = b == nil ? "No battery" : parts.joined(separator: " \u{00B7} ")
        let state: String? = b.map { $0.isFullyCharged ? "Full" : ($0.isCharging ? "Charging" : ($0.isPluggedIn ? "Plugged in" : nil)) } ?? nil
        let tint: Color = (b?.isCharging ?? false) ? Design.Color.tint(.green) : lineColor(a)
        return MetricTile(title: "Battery", trailing: state, spoken: spoken("Battery", value, a) + (caption.isEmpty ? "" : ", " + caption)) {
            valueRow(value, caption: caption.isEmpty ? nil : caption, color: valueColor(a))
            spark(.battery, tint: tint, domain: 0...1, minSpan: 0.1)
        }
    }

    private var gpuTile: some View {
        let g = snap.gpu
        let value = g?.utilization.map { Format.percent($0) } ?? Placeholder.dash
        let trailing = g?.coreCount.map { "\($0) cores" }
        return MetricTile(title: "GPU", trailing: trailing, spoken: spoken("GPU", value)) {
            valueRow(value)
            spark(.gpu, tint: lineColor(.calm), domain: 0...1, minSpan: 0.5)
        }
    }

    private var fansTile: some View {
        let fans = snap.thermal?.fans ?? []
        let fastest = fans.max(by: { $0.rpm < $1.rpm })
        let value = fastest.map { "\(Int($0.rpm.rounded()))" } ?? Placeholder.dash
        let caption: String? = fastest == nil ? (snap.thermal == nil ? nil : "No fans") : "rpm"
        let trailing = fastest?.fraction.map { Format.percent($0) }
        return MetricTile(title: "Fans", trailing: trailing, spoken: fastest == nil ? "Fans, none" : "Fans \(value) rpm") {
            valueRow(value, caption: caption)
            spark(.fan, tint: lineColor(.calm), minSpan: 1000)
        }
    }

    private var powerTile: some View {
        let p = snap.power
        let value = p?.totalWatts.map { Format.watts($0) } ?? Placeholder.dash
        var parts: [String] = []
        if let c = p?.cpuWatts { parts.append("CPU \(Format.watts(c))") }
        if let g = p?.gpuWatts { parts.append("GPU \(Format.watts(g))") }
        let source: String? = snap.battery.flatMap { $0.isPresent ? ($0.isPluggedIn ? "Adapter" : "Battery") : nil }
        return MetricTile(title: "Power", trailing: source, spoken: "Power \(value)" + (source.map { ", on \($0.lowercased())" } ?? "")) {
            valueRow(value, caption: parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} "))
            spark(.power, tint: lineColor(.calm), minSpan: 5)
        }
    }

    private var processesTile: some View {
        let cores = snap.cpu?.coreCount ?? 0
        let top = Array(snap.processes.sorted(by: { $0.cpuFraction > $1.cpuFraction }).prefix(3))
        let spokenList = top.map { "\($0.name) \(Format.percent($0.cpuFraction, of: cores))".replacingOccurrences(of: "%", with: " percent") }.joined(separator: ", ")
        return MetricTile(title: "Top processes", trailing: "CPU", spoken: top.isEmpty ? "Top processes unavailable" : "Top processes: " + spokenList) {
            VStack(spacing: 2) {
                if top.isEmpty {
                    Text(Placeholder.dash).font(Design.Font.body).foregroundStyle(Design.Color.textTertiary)
                } else {
                    ForEach(top) { proc in
                        HStack(spacing: 6) {
                            Text(proc.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Design.Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Num(Format.percent(proc.cpuFraction, of: cores), size: 11.5, weight: .medium, color: Design.Color.textSecondary)
                        }
                        .frame(height: 14)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
