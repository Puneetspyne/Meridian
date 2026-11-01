import Foundation
import MeridianKit

/// PLACEHOLDER. Owned by the Agents workstream. Coding-agent sessions (Claude Code hooks), opt-in.
@MainActor
public final class AgentsProvider: SignalProvider {
    public let providerID = "agents"
    public private(set) var signals: [Signal] = []
    public var onChange: (@MainActor () -> Void)?
    public init(settings: ModuleSettings) {}
    public func start() {}
    public func stop() {}
    public func apply(_ settings: ModuleSettings) {}
}
