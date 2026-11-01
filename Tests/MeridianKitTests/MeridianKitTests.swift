import Foundation
import Testing
@testable import MeridianKit

struct UrgencyRankerTests {
    @Test func testHigherAttentionWins() {
        let calm = Signal(id: "a", kind: .clock, attention: .calm, title: "Clock", symbol: "clock")
        let critical = Signal(id: "b", kind: .battery, attention: .critical, title: "Battery 5%", symbol: "battery.0percent")
        #expect(UrgencyRanker.top([calm, critical])?.id == "b")
    }

    @Test func testSoonestDeadlineWinsWithinAttention() {
        let now = Date()
        let later = Signal(id: "later", kind: .meeting, attention: .warning, title: "Design review", symbol: "calendar", deadline: now.addingTimeInterval(600))
        let soon = Signal(id: "soon", kind: .meeting, attention: .warning, title: "Standup", symbol: "calendar", deadline: now.addingTimeInterval(60))
        let noDeadline = Signal(id: "none", kind: .cpu, attention: .warning, title: "CPU", symbol: "cpu", priority: 100)
        let ranked = UrgencyRanker.rank([later, noDeadline, soon], now: now).map(\.id)
        #expect(ranked == ["soon", "later", "none"])
    }

    @Test func testPriorityThenRecencyBreakTies() {
        let old = Signal(id: "old", kind: .cpu, attention: .calm, title: "", symbol: "", createdAt: Date(timeIntervalSince1970: 1), priority: 5)
        let new = Signal(id: "new", kind: .cpu, attention: .calm, title: "", symbol: "", createdAt: Date(timeIntervalSince1970: 2), priority: 5)
        let high = Signal(id: "high", kind: .cpu, attention: .calm, title: "", symbol: "", createdAt: Date(timeIntervalSince1970: 0), priority: 9)
        #expect(UrgencyRanker.rank([old, new, high]).map(\.id) == ["high", "new", "old"])
    }
}

struct RuleEngineTests {
    @Test func testCalmMachineProducesOnlyAmbientSignals() {
        var engine = RuleEngine()
        let snapshot = MockTelemetrySource(scenario: .calm, start: Date(timeIntervalSince1970: 0)).snapshot(at: Date(timeIntervalSince1970: 1))
        let signals = engine.evaluate(snapshot, now: Date())
        #expect(!(signals.isEmpty))
        #expect(signals.allSatisfy { $0.attention == .calm }, Comment(rawValue: "\(signals.map { "\($0.id):\($0.attention)" })"))
    }

    @Test func testSustainedCPUNeedsTime() {
        var engine = RuleEngine()
        let source = MockTelemetrySource(scenario: .busy, start: Date(timeIntervalSince1970: 0))
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = engine.evaluate(source.snapshot(at: t0), now: t0)
        let early = engine.evaluate(source.snapshot(at: t0.addingTimeInterval(10)), now: t0.addingTimeInterval(10))
        #expect(!(early.contains { $0.id == "rule.cpu.sustained" }))
        let late = engine.evaluate(source.snapshot(at: t0.addingTimeInterval(61)), now: t0.addingTimeInterval(61))
        #expect(late.contains { $0.id == "rule.cpu.sustained" && $0.attention == .warning })
    }

    @Test func testHotAndLowBatteryEscalate() {
        var engine = RuleEngine()
        let hot = MockTelemetrySource(scenario: .hot, start: Date(timeIntervalSince1970: 0)).snapshot(at: Date(timeIntervalSince1970: 1))
        #expect(engine.evaluate(hot).contains { $0.kind == .thermal && $0.attention >= .warning })
        let low = MockTelemetrySource(scenario: .lowBattery, start: Date(timeIntervalSince1970: 0)).snapshot(at: Date(timeIntervalSince1970: 1))
        #expect(UrgencyRanker.top(engine.evaluate(low))?.kind == .battery)
        let full = MockTelemetrySource(scenario: .diskFull, start: Date(timeIntervalSince1970: 0)).snapshot(at: Date(timeIntervalSince1970: 1))
        #expect(engine.evaluate(full).contains { $0.kind == .disk && $0.attention == .critical })
    }
}

struct FormatTests {
    @Test func testBytesUseDecimalUnits() {
        #expect(Format.bytes(999) == "999 B")
        #expect(Format.bytes(1_500) == "1.5 KB")
        #expect(Format.bytes(24_000_000_000) == "24 GB")
        #expect(Format.bytes(994_000_000_000) == "994 GB")
    }

    @Test func testRatesAndPercents() {
        #expect(Format.rate(512) == "512 B/s")
        #expect(Format.rate(4_200_000) == "4.2 MB/s")
        #expect(Format.percent(0.9412) == "94%")
        #expect(Format.percent(3.2, of: 8) == "40%")
    }

    @Test func testTemperatureAndTime() {
        #expect(Format.temperature(71.4, unit: .celsius) == "71°")
        #expect(Format.temperature(100, unit: .fahrenheit) == "212°")
        #expect(Format.countdown(80) == "1:20")
        #expect(Format.countdown(3_753) == "1:02:33")
        #expect(Format.countdown(-5) == "-0:05")
        #expect(Format.minutes(72) == "1h 12m")
        let now = Date()
        #expect(Format.relative(now.addingTimeInterval(80), now: now) == "in 1m 20s")
        #expect(Format.relative(now.addingTimeInterval(-7_200), now: now) == "2h ago")
    }
}

struct HistoryTests {
    @Test func testRingKeepsChronologicalOrder() {
        var h = History<Int>(capacity: 3)
        for i in 1...5 { h.append(i) }
        #expect(h.values == [3, 4, 5])
        #expect(h.last == 5)
        #expect(h.isFull)
    }

    @Test func testMetricHistoryAverages() {
        var m = MetricHistory(capacity: 4)
        [0.2, 0.4, 0.6, 0.8].forEach { m.record($0) }
        #expect(abs((m.average(last: 2)!) - (0.7)) <= 0.0001)
        #expect(m.max == 0.8)
    }
}
