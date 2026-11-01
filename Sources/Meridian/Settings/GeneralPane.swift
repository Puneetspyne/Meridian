import SwiftUI
import MeridianKit

struct GeneralPane: View {
    @Bindable var model: AppModel
    @State private var login = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                Picker("Show Meridian as", selection: $model.settings.body) {
                    ForEach(BodyMode.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Automatic uses the notch on a display that has one and a corner everywhere else.")
            }

            Section {
                Picker("Corner", selection: $model.settings.corner) {
                    ForEach(ScreenCorner.allCases) { Text($0.label).tag($0) }
                }
                Picker("Size", selection: $model.settings.cornerSize) {
                    ForEach(CornerSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("When idle", selection: $model.settings.cornerRest) {
                    ForEach(CornerRestStyle.allCases) { Text($0.label).tag($0) }
                }
            } header: { Text("Corner") } footer: {
                Text("You can also drag the corner anywhere on screen; it settles into the nearest corner.")
            }

            Section {
                Toggle("Open the notch when the pointer rests on it", isOn: $model.settings.notchHoverToOpen)
                ValueSlider(title: "Hover delay", value: $model.settings.notchHoverDelay,
                            range: 0.1...1.0, step: 0.05) { String(format: "%.2f s", $0) }
                    .disabled(!model.settings.notchHoverToOpen)
                ValueSlider(title: "Close after", value: $model.settings.cardAutoCloseSeconds,
                            range: 0...30, step: 1) { $0 == 0 ? "Never" : "\(Int($0)) s" }
            } header: { Text("Card") } footer: {
                Text("The card also closes when the pointer leaves it, on Esc, or when you click elsewhere. The corner opens with a click or by pressing and holding.")
            }

            Section {
                ValueSlider(title: "Refresh every", value: $model.settings.refreshInterval,
                            range: 0.5...5, step: 0.5) { String(format: "%.1f s", $0) }
            } footer: {
                Text("Faster refresh shows changes sooner and uses slightly more energy.")
            }

            Section {
                Picker("Menu bar item", selection: $model.settings.menuBar) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Open Meridian at login", isOn: Binding(
                    get: { login.isOn },
                    set: { on in model.settings.launchAtLogin = login.set(on) }
                ))
                if let message = login.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                if login.state == .needsApproval {
                    LabeledContent("Waiting for approval") {
                        Button("Open Login Items…") { login.openLoginItemsSettings() }
                    }
                }
            } footer: {
                Text("Click the menu bar item to open the card; right-click for the menu.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            login.refresh()
            if model.settings.launchAtLogin != login.isOn { model.settings.launchAtLogin = login.isOn }
        }
    }
}
