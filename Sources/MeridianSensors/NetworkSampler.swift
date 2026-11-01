import CoreWLAN
import Foundation
import MeridianKit
import SystemConfiguration

/// Primary-interface throughput, addressing and Wi-Fi details. Makes no network calls.
final class NetworkSampler {
    private struct Counters { var rx: UInt32; var tx: UInt32; var time: TimeInterval }
    private var previous: [String: Counters] = [:]
    private let store = SCDynamicStoreCreate(nil, "Meridian" as CFString, nil, nil)
    private lazy var wifi: CWWiFiClient = CWWiFiClient.shared()

    func sample() -> NetworkMetrics? {
        let primary = primaryInterface()
        let now = ProcessInfo.processInfo.systemUptime

        var rx = 0.0, tx = 0.0
        var localIP: String?
        var baudrate: UInt64 = 0
        var seen: [String: Counters] = [:]

        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            defer { freeifaddrs(list) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let ifa = cursor {
                defer { cursor = ifa.pointee.ifa_next }
                let name = String(cString: ifa.pointee.ifa_name)
                guard name == primary, let addr = ifa.pointee.ifa_addr else { continue }
                switch Int32(addr.pointee.sa_family) {
                case AF_LINK:
                    guard let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                    let counters = Counters(rx: data.pointee.ifi_ibytes, tx: data.pointee.ifi_obytes, time: now)
                    seen[name] = counters
                    baudrate = UInt64(data.pointee.ifi_baudrate)
                    if let old = previous[name], now > old.time {
                        let dt = now - old.time
                        // if_data counters are 32-bit; wrapping subtraction survives a rollover between samples.
                        rx = Double(counters.rx &- old.rx) / dt
                        tx = Double(counters.tx &- old.tx) / dt
                    }
                case AF_INET:
                    if localIP == nil { localIP = Self.numericHost(addr) }
                default: break
                }
            }
        }
        previous = seen

        var ssid: String?
        var linkSpeed: Double? = baudrate > 0 ? Double(baudrate) / 1_000_000 : nil
        if let primary, let interface = wifi.interface(withName: primary) {
            // Without location permission macOS returns nil for the SSID; that is expected, not an error.
            ssid = interface.ssid()
            let rate = interface.transmitRate()
            if rate > 0 { linkSpeed = rate }
        }

        return NetworkMetrics(rxBytesPerSec: rx, txBytesPerSec: tx, interfaceName: primary,
                              isConnected: primary != nil, localIP: localIP, publicIP: nil,
                              wifiSSID: ssid, linkSpeedMbps: linkSpeed)
    }

    private func primaryInterface() -> String? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return global["PrimaryInterface"] as? String
    }

    private static func numericHost(_ addr: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }
}
