import Foundation
import MeridianKit

/// PLACEHOLDER. Owned by the Time workstream. Timers, countdowns, stopwatch, next meeting, world clocks.
@MainActor
public final class TimeProvider: SignalProvider {
    public let providerID = "time"
    public private(set) var signals: [Signal] = []
    public var onChange: (@MainActor () -> Void)?
    public init(settings: ModuleSettings) {}
    public func start() {}
    public func stop() {}
    public func apply(_ settings: ModuleSettings) {}
}
