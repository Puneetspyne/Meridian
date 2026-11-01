import Foundation
import MeridianKit

/// Static machine facts, read once.
enum SystemInfoSampler {
    static func read() -> SystemInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let isARM = (Sysctl.int32("hw.optional.arm64") ?? 0) == 1
        // gethostname is instant; ProcessInfo.hostName can stall on reverse DNS.
        var host = [CChar](repeating: 0, count: 256)
        gethostname(&host, host.count)
        return SystemInfo(
            chipName: Sysctl.string("machdep.cpu.brand_string") ?? (isARM ? "Apple silicon" : "Intel"),
            modelIdentifier: Sysctl.string("hw.model") ?? "Mac",
            macOSVersion: version,
            hostName: String(cString: host),
            hasNotch: false, // The app overrides this; this module has no AppKit.
            isAppleSilicon: isARM)
    }
}

enum ThermalSampler {
    static func pressure() -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}
