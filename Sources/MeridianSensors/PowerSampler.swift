import Foundation
import MeridianKit

/// CPU, GPU and Neural Engine power from IOReport's "Energy Model" group (private API, dlsym-resolved).
///
/// Energy counters are cumulative, so power is the delta between two samples divided by the elapsed time.
/// If the counters do not advance (macOS builds that stopped updating them for unprivileged clients), the
/// result is `source: "unavailable"` rather than a misleading zero.
final class PowerSampler {
    private typealias CopyChannelsFn = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscriptionFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    private typealias CreateSamplesFn = @convention(c) (UnsafeRawPointer, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelNameFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias IntegerValueFn = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias UnitLabelFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?

    private struct API {
        var copyChannels: CopyChannelsFn, createSubscription: CreateSubscriptionFn
        var createSamples: CreateSamplesFn, createDelta: CreateDeltaFn
        var channelName: ChannelNameFn, integerValue: IntegerValueFn, unitLabel: UnitLabelFn
    }

    private let api: API?
    private var subscription: UnsafeRawPointer?
    private var subscribed: CFMutableDictionary?
    private var previous: (sample: CFDictionary, time: TimeInterval)?
    private let smc: SMCSampler

    init(smc: SMCSampler) {
        self.smc = smc
        api = Self.resolve()
        if let api { subscribe(api) }
    }

    private static func resolve() -> API? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/IOReport.framework/IOReport", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let a = sym("IOReportCopyChannelsInGroup", as: CopyChannelsFn.self),
              let b = sym("IOReportCreateSubscription", as: CreateSubscriptionFn.self),
              let c = sym("IOReportCreateSamples", as: CreateSamplesFn.self),
              let d = sym("IOReportCreateSamplesDelta", as: CreateDeltaFn.self),
              let e = sym("IOReportChannelGetChannelName", as: ChannelNameFn.self),
              let f = sym("IOReportSimpleGetIntegerValue", as: IntegerValueFn.self),
              let g = sym("IOReportChannelGetUnitLabel", as: UnitLabelFn.self) else { return nil }
        return API(copyChannels: a, createSubscription: b, createSamples: c, createDelta: d,
                   channelName: e, integerValue: f, unitLabel: g)
    }

    private func subscribe(_ api: API) {
        guard let channels = api.copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = api.createSubscription(nil, channels, &subbed, 0, nil) else { return }
        subscription = sub
        subscribed = subbed?.takeRetainedValue()
    }

    func sample() -> PowerMetrics {
        let smcTotal = smc.systemWatts()
        let fallback = PowerMetrics(totalWatts: smcTotal, source: smcTotal != nil ? "smc" : "unavailable")
        guard let api, let subscription, let subscribed else { return fallback }
        guard let current = api.createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return fallback }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (current, now) }
        guard let previous, now > previous.time,
              let delta = api.createDelta(previous.sample, current, nil)?.takeRetainedValue() else { return fallback }

        let dt = now - previous.time
        var cpu = 0.0, gpu = 0.0, ane = 0.0, clusterCPU = 0.0
        var sawCPUTotal = false, advanced = false

        let channels = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] ?? []
        for channel in channels {
            guard let name = api.channelName(channel)?.takeUnretainedValue() as String? else { continue }
            let raw = api.integerValue(channel, 0)
            guard raw >= 0 else { continue }
            let unit = (api.unitLabel(channel)?.takeUnretainedValue() as String?) ?? "mJ"
            let joules = Self.joules(raw, unit: unit)
            if joules > 0 { advanced = true }
            let upper = name.uppercased()
            if upper == "CPU ENERGY" { cpu = joules; sawCPUTotal = true }
            else if upper == "GPU ENERGY" { gpu = joules }
            else if upper.hasPrefix("ANE") && !upper.contains("SRAM") { ane += joules }
            // Chips without a "CPU Energy" rollup publish per-cluster channels instead (ECPU, PCPU, with numbered variants).
            else if upper.range(of: "^[EP]CPU\\d*$", options: .regularExpression) != nil { clusterCPU += joules }
        }
        guard advanced else { return fallback }
        if !sawCPUTotal { cpu = clusterCPU }

        let cpuW = cpu / dt, gpuW = gpu / dt, aneW = ane / dt
        return PowerMetrics(cpuWatts: cpuW, gpuWatts: gpuW, aneWatts: aneW,
                            totalWatts: smcTotal ?? (cpuW + gpuW + aneW), source: "ioreport")
    }

    /// Converts an IOReport energy count to joules from its unit label.
    static func joules(_ value: Int64, unit: String) -> Double {
        let v = Double(value)
        switch unit {
        case "mJ": return v / 1e3
        case "uJ", "µJ": return v / 1e6
        case "nJ": return v / 1e9
        case "J": return v
        default: return v / 1e3
        }
    }
}
