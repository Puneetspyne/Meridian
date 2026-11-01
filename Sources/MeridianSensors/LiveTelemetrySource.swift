import Foundation
import MeridianKit

/// PLACEHOLDER. Owned by the Sensors workstream. Samples the live machine.
public struct LiveTelemetrySource: TelemetrySource {
    public init() {}
    public func sample() async throws -> TelemetrySnapshot {
        TelemetrySnapshot(timestamp: Date())
    }
}
