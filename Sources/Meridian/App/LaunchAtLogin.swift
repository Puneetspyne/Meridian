import Foundation
import Observation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp`. Registration only works from a signed app bundle in a
/// normal location; from `swift run` it throws, and that error is shown in Settings instead of crashing.
@MainActor
@Observable
final class LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user has to allow it in System Settings > General > Login Items.
        case needsApproval
        /// The system cannot find the app (running outside a bundle, for example).
        case unavailable
    }

    private(set) var state: State = .disabled
    private(set) var errorMessage: String?

    var isOn: Bool { state == .enabled || state == .needsApproval }

    init() { refresh() }

    /// Read the truth from the system; the stored preference can be stale after the user edits Login Items.
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .needsApproval
        case .notFound: state = .unavailable
        case .notRegistered: state = .disabled
        @unknown default: state = .disabled
        }
    }

    /// Returns the state that is actually in effect afterwards.
    @discardableResult
    func set(_ enabled: Bool) -> Bool {
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = Self.describe(error, enabling: enabled)
        }
        refresh()
        return isOn
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    private static func describe(_ error: Error, enabling: Bool) -> String {
        let ns = error as NSError
        let verb = enabling ? "turn on" : "turn off"
        if ns.domain == "SMAppServiceErrorDomain" && ns.code == 1 {
            return "Meridian could not \(verb) launch at login. It has to run as an installed app (Meridian.app in Applications) first."
        }
        return "Meridian could not \(verb) launch at login: \(ns.localizedDescription)"
    }
}
