import SwiftUI
import MeridianKit
import MeridianAgents

struct AgentsPane: View {
    @Bindable var model: AppModel
    @State private var status: HooksStatus = .notInstalled
    @State private var message: String?

    private var agents: AgentsProvider? { model.provider(AgentsProvider.self) }

    var body: some View {
        Form {
            Section {
                Toggle("Show coding agents in the card", isOn: $model.settings.modules.agentsEnabled)
            } footer: {
                Text("One row per Claude Code session: working, needs you, or done. Off by default.")
            }

            Section {
                LabeledContent("Hooks") {
                    Label(statusText, systemImage: statusSymbol).foregroundStyle(.secondary)
                }
                HStack {
                    Button(status == .partial ? "Repair hooks" : "Install hooks", action: install)
                        .disabled(!model.settings.modules.agentsEnabled || status == .installed)
                    Button("Remove hooks", action: uninstall)
                        .disabled(status == .notInstalled)
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                }
            } header: { Text("Claude Code hooks") } footer: {
                Text("Installing writes a small script to ~/Library/Application Support/Meridian/hooks, adds one hook entry per event to ~/.claude/settings.json (your other settings are kept, and a backup is saved beside it), and logs session identifiers locally. Nothing is written until you click Install. Running Claude Code sessions need a restart to pick up the hooks.")
            }

            Section {
                Link("What is written, and what is not", destination: URL(string: "https://github.com/Puneetspyne/Meridian/blob/main/docs/AGENTS.md")!)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: model.settings.modules.agentsEnabled) { _, _ in refresh() }
    }

    private var statusText: String {
        switch status { case .installed: "Installed"; case .partial: "Partly installed"; case .notInstalled: "Not installed" }
    }
    private var statusSymbol: String {
        switch status { case .installed: "checkmark.circle"; case .partial: "exclamationmark.circle"; case .notInstalled: "circle" }
    }

    private func refresh() { status = agents?.hooksStatus ?? .notInstalled }

    private func install() {
        message = nil
        if let agents {
            do { try agents.installHooks() } catch { message = String(describing: error) }
        } else {
            // The provider listens for this while it runs.
            NotificationCenter.default.post(name: Notification.Name("meridian.agents.install"), object: nil)
        }
        refresh()
    }

    private func uninstall() {
        message = nil
        do { try agents?.uninstallHooks() } catch { message = String(describing: error) }
        refresh()
    }
}
