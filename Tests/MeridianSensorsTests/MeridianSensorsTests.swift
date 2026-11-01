import Foundation
import MeridianKit
import Testing
@testable import MeridianSensors

// MARK: SMC decoders (byte fixtures)

@Suite struct SMCDecoderTests {
    @Test func sp78() {
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0x3D, 0x80]) == 61.5)
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0xFF, 0x00]) == -1.0) // signed
    }

    @Test func otherFixedPoint() {
        #expect(SMCDecoder.decode(type: "sp87", bytes: [0x01, 0x80]) == 3.0)   // 0x0180 / 128
        #expect(SMCDecoder.decode(type: "sp96", bytes: [0x00, 0x40]) == 1.0)   // 0x0040 / 64
        #expect(SMCDecoder.decode(type: "fp1f", bytes: [0x40, 0x00]) == 0.5)   // 0x4000 / 32768
        #expect(SMCDecoder.decode(type: "fpe2", bytes: [0x1F, 0x40]) == 2000.0) // 0x1F40 / 4 = 2000 rpm
        #expect(SMCDecoder.decode(type: "fpe2", bytes: [0x00, 0x01]) == 0.25)
    }

    @Test func flt() {
        // 36.5 as little-endian IEEE 754 single.
        let bits = Float(36.5).bitPattern
        let bytes = [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        #expect(SMCDecoder.decode(type: "flt ", bytes: bytes) == 36.5)
        #expect(SMCDecoder.decode(type: "flt", bytes: [0xFF, 0xFF, 0xFF, 0xFF]) == nil) // NaN is rejected
    }

    @Test func integers() {
        #expect(SMCDecoder.decode(type: "ui8 ", bytes: [200]) == 200)
        #expect(SMCDecoder.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCDecoder.decode(type: "ui32", bytes: [0x00, 0x00, 0x01, 0x00]) == 256)
        #expect(SMCDecoder.decode(type: "si8 ", bytes: [0xFE]) == -2)
        #expect(SMCDecoder.decode(type: "si16", bytes: [0xFF, 0x38]) == -200)
    }

    @Test func ioft() {
        // 1500.5 in 48.16 fixed point, little-endian.
        let raw = UInt64(1500.5 * 65536)
        let bytes = (0..<8).map { UInt8((raw >> (8 * UInt64($0))) & 0xFF) }
        #expect(SMCDecoder.decode(type: "ioft", bytes: bytes) == 1500.5)
    }

    @Test func shortAndUnknownInputFailSoft() {
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0x3D]) == nil)
        #expect(SMCDecoder.decode(type: "flt ", bytes: [1, 2]) == nil)
        #expect(SMCDecoder.decode(type: "zzzz", bytes: [1, 2, 3, 4]) == nil)
    }

    @Test func text() {
        #expect(SMCDecoder.text(type: "ch8*", bytes: Array("M2 Air".utf8) + [0, 0]) == "M2 Air")
        #expect(SMCDecoder.text(type: "ui8 ", bytes: [1]) == nil)
    }

    @Test func fourCCRoundTrips() {
        #expect(FourCC.decode(FourCC.encode("TC0P")) == "TC0P")
        #expect(FourCC.decode(FourCC.encode("#KEY")) == "#KEY")
        #expect(FourCC.decode(FourCC.encode("flt")) == "flt ")
    }
}

// MARK: Sensor catalog

@Suite struct SensorCatalogTests {
    @Test func hidGroupHeuristics() {
        #expect(SensorCatalog.group(forSensorName: "PMU tdie3") == .cpu)
        #expect(SensorCatalog.group(forSensorName: "pACC MTR Temp Sensor2") == .cpu)
        #expect(SensorCatalog.group(forSensorName: "eACC MTR Temp Sensor1") == .cpu)
        #expect(SensorCatalog.group(forSensorName: "SOC MTR Temp Sensor0") == .cpu)
        #expect(SensorCatalog.group(forSensorName: "GPU MTR Temp Sensor4") == .gpu)
        #expect(SensorCatalog.group(forSensorName: "DRAM temp") == .memory)
        #expect(SensorCatalog.group(forSensorName: "gas gauge battery") == .battery)
        #expect(SensorCatalog.group(forSensorName: "NAND CH0 temp") == .storage)
        #expect(SensorCatalog.group(forSensorName: "PMU tdev1") == .system)
    }

    @Test func hidFriendlyNames() {
        #expect(SensorCatalog.friendlyName(forHIDName: "PMU tdie4") == "SoC die 4")
        #expect(SensorCatalog.friendlyName(forHIDName: "gas gauge battery") == "Battery")
        #expect(SensorCatalog.friendlyName(forHIDName: "NAND CH0 temp") == "SSD channel 0")
        #expect(SensorCatalog.friendlyName(forHIDName: "Something New") == "Something New")
    }

    @Test func smcGroups() {
        #expect(SensorCatalog.group(forSMCKey: "Tp01") == .cpu)
        #expect(SensorCatalog.group(forSMCKey: "TC0P") == .cpu)
        #expect(SensorCatalog.group(forSMCKey: "Tg0f") == .gpu)
        #expect(SensorCatalog.group(forSMCKey: "Tm0B") == .memory)
        #expect(SensorCatalog.group(forSMCKey: "TB0T") == .battery)
        #expect(SensorCatalog.group(forSMCKey: "TH0A") == .storage)
        #expect(SensorCatalog.group(forSMCKey: "TW0P") == .system)
        #expect(SensorCatalog.group(forSMCKey: "TL0P") == .system)
    }

    @Test func smcNames() {
        #expect(SensorCatalog.name(forSMCKey: "TC0P", appleSilicon: false) == "CPU Proximity")
        #expect(SensorCatalog.name(forSMCKey: "TG0D", appleSilicon: false) == "GPU Die")
        #expect(SensorCatalog.name(forSMCKey: "PSTR", appleSilicon: true) == "System Total Power")
        #expect(SensorCatalog.name(forSMCKey: "TW0P", appleSilicon: true) == "Wi-Fi (TW0P)")
        // Intel placement names must not leak onto Apple silicon, where the same keys mean something else.
        #expect(SensorCatalog.name(forSMCKey: "Ts0P", appleSilicon: true) == "Ts0P")
        #expect(SensorCatalog.name(forSMCKey: "Zz9z", appleSilicon: false) == "Zz9z")
    }
}

// MARK: Units and layout

@Suite struct LowLevelTests {
    @Test func smcStructIs80Bytes() {
        #expect(MemoryLayout<SMCParamStructProbe>.size == 80)
    }

    @Test func energyUnits() {
        #expect(PowerSampler.joules(1500, unit: "mJ") == 1.5)
        #expect(PowerSampler.joules(2_000_000, unit: "uJ") == 2.0)
        #expect(PowerSampler.joules(3_000_000_000, unit: "nJ") == 3.0)
    }

    @Test func wholeDiskName() {
        #expect(DiskSampler.wholeDiskName("/dev/disk4s2") == "disk4")
        #expect(DiskSampler.wholeDiskName("/dev/disk12") == "disk12")
    }
}

// MARK: Live smoke test

@Suite(.serialized) struct LiveSmokeTests {
    @Test func samplePopulatesEverySection() async throws {
        let source = LiveTelemetrySource()
        _ = try await source.sample()
        try await Task.sleep(nanoseconds: 300_000_000)
        let s = try await source.sample()

        let cpu = try #require(s.cpu)
        #expect(cpu.perCore.count > 0)
        #expect((0...1).contains(cpu.total))
        #expect(cpu.efficiencyCoreCount + cpu.performanceCoreCount == cpu.perCore.count || cpu.efficiencyCoreCount + cpu.performanceCoreCount == 0)
        let memory = try #require(s.memory)
        #expect(memory.totalBytes > 0 && memory.usedBytes > 0 && memory.usedBytes <= memory.totalBytes)
        #expect(!s.disks.isEmpty)
        #expect(s.bootDisk?.mountPoint == "/")
        let system = try #require(s.system)
        #expect(!system.chipName.isEmpty)
        #expect(!s.processes.isEmpty)

        if system.isAppleSilicon {
            let thermal = try #require(s.thermal)
            #expect(!thermal.sensors.isEmpty)
            #expect(thermal.sensors.allSatisfy { $0.celsius > 0 && $0.celsius <= 130 })
            #expect(Set(thermal.sensors.map(\.id)).count == thermal.sensors.count) // ids are unique
        }
    }

    @Test func sampleStaysWithinBudgetAfterWarmUp() async throws {
        let source = LiveTelemetrySource()
        _ = try await source.sample()
        _ = try await source.sample()
        let clock = ContinuousClock()
        var worst = Duration.zero
        var total = Duration.zero
        for _ in 0..<5 {
            let d = try await clock.measure { _ = try await source.sample() }
            worst = max(worst, d)
            total += d
        }
        print("sample() latency over 5 calls: mean \(total / 5), worst \(worst)")
        // The brief asks for ~50 ms; allow headroom for a loaded CI machine but catch real regressions.
        #expect(worst < .milliseconds(250), "worst sample took \(worst)")
    }
}
