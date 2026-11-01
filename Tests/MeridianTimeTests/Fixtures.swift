import Foundation
import MeridianKit
@testable import MeridianTime

/// Wednesday 2026-11-04 14:32 in Asia/Kolkata (UTC+5:30, no DST).
enum Fixture {
    static let zone = TimeZone(identifier: "Asia/Kolkata")!
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    static let now = date(2026, 11, 4, 14, 32)

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meridian-time-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A mutable clock for driving the provider.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date = Fixture.now) { self.now = now }
}

@MainActor
func makeProvider(clock: TestClock = TestClock(), settings: ModuleSettings = ModuleSettings(),
                  directory: URL = Fixture.tempDirectory()) -> TimeProvider {
    TimeProvider(settings: settings, storeDirectory: directory, calendar: Fixture.calendar, now: { clock.now })
}
