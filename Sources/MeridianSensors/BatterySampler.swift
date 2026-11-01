import Foundation
import IOKit
import IOKit.ps
import MeridianKit

/// Charge state from IOPowerSources, health and electrical detail from the AppleSmartBattery registry entry.
final class BatterySampler {
    func sample() -> BatteryMetrics? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        var internalBattery: [String: Any]?
        for source in list {
            if let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
               d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { internalBattery = d; break }
        }
        let pluggedIn = (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()) != nil

        // Desktop Macs have no battery; say so explicitly rather than returning nil for the whole section.
        guard let d = internalBattery else {
            return BatteryMetrics(isPresent: false, level: 0, isCharging: false, isPluggedIn: true)
        }

        let current = (d[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
        let max = (d[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
        let level = max > 0 ? Swift.min(1, Swift.max(0, current / max)) : 0
        let state = d[kIOPSPowerSourceStateKey] as? String
        let charging = d[kIOPSIsChargingKey] as? Bool ?? false
        let charged = d[kIOPSIsChargedKey] as? Bool ?? false
        let isPlugged = state == kIOPSACPowerValue || pluggedIn
        let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let minutes = (d[minutesKey] as? NSNumber)?.intValue
        // IOPS reports -1 while still estimating, and 0 when plugged in but not charging; neither is a real estimate.
        let remaining = (minutes ?? -1) > 0 || (minutes == 0 && charged) ? minutes : nil

        var metrics = BatteryMetrics(isPresent: true, level: level, isCharging: charging, isPluggedIn: isPlugged,
                                     isFullyCharged: charged, minutesRemaining: remaining)

        if let smart = IORegistry.firstService("AppleSmartBattery") {
            metrics.cycleCount = smart.int("CycleCount")
            // AppleRawMaxCapacity is in mAh; plain MaxCapacity is a percentage on Apple silicon, so it cannot be used.
            let design = smart.double("DesignCapacity")
            let maxCap = smart.double("AppleRawMaxCapacity") ?? smart.double("NominalChargeCapacity")
            if let design, design > 0, let maxCap, maxCap > 0 { metrics.healthFraction = Swift.min(1.2, maxCap / design) }
            // Temperature is hundredths of a degree Celsius.
            if let t = smart.double("Temperature"), t > 0 { metrics.temperatureC = t / 100 }
            if let mA = smart.signedInt64("Amperage"), let mV = smart.double("Voltage"), mV > 0 {
                metrics.watts = Double(mA) * mV / 1_000_000
            }
            if let adapter = smart["AdapterDetails"] as? [String: Any], let w = adapter.double("Watts"), w > 0 {
                metrics.adapterWatts = w
            }
        }
        return metrics
    }
}
