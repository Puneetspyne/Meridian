import Foundation
import MeridianKit
import MeridianSensors

// PLACEHOLDER. Owned by the Sensors workstream. `meridianctl snapshot` prints one JSON snapshot.
let source = LiveTelemetrySource()
let snapshot = try await source.sample()
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
