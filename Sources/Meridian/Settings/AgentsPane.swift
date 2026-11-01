import SwiftUI
import MeridianKit

struct AgentsPane: View {
    @Bindable var model: AppModel
    @State private var requested = false

    var body: some View {
        Form {
            Section {
                Toggle("Show coding agents in the card", isOn: $model.settings.modules.agentsEnabled)
            } footer: {
                Text("One row per Claude Code session: working, needs you, or done. Off by default.")
            }

            Section {
                LabeledContent("Hooks") {
                    HStack(spacing: 8) {
                        if requested { Label("Requested", systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout) }
                        Button("Install hooks") {
                            NotificationCenter.default.post(name: Notification.Name("meridian.agents.install"), object: nil)
                            requested = true
                        }
                        .disabled(!model.settings.modules.agentsEnabled)
                    }
                }
            } header: { Text("Claude Code hooks") } footer: {
                Text("Meridian learns what a session is doing from Claude Code hooks. Installing adds entries to ~/.claude/settings.json, keeps your own settings, and saves a backup next to it. Nothing is written until you click Install.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings.modules.agentsEnabled) { _, on in if !on { requested = false } }
    }
}
