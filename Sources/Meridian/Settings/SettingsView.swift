import SwiftUI
import MeridianKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, tiles, thresholds, modules, agents, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"; case .tiles: "Tiles"; case .thresholds: "Thresholds"
        case .modules: "Modules"; case .agents: "Agents"; case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"; case .tiles: "square.grid.2x2"; case .thresholds: "slider.horizontal.3"
        case .modules: "puzzlepiece.extension"; case .agents: "terminal"; case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: SettingsPane

    init(model: AppModel) {
        self.model = model
        // `--settings-pane tiles` opens a given pane, for screenshots and reviews.
        let args = CommandLine.arguments
        let wanted = args.firstIndex(of: "--settings-pane").flatMap { i in
            i + 1 < args.count ? SettingsPane(rawValue: args[i + 1]) : nil
        }
        _selection = State(initialValue: wanted ?? .general)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .frame(width: 680, height: 480)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: GeneralPane(model: model)
        case .tiles: TilesPane(model: model)
        case .thresholds: ThresholdsPane(model: model)
        case .modules: ModulesPane(model: model)
        case .agents: AgentsPane(model: model)
        case .about: AboutPane()
        }
    }
}

/// A labelled slider with its current value on the right: the one control shape the panes share.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 140, maxWidth: 190)
                    .accessibilityLabel(title)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
