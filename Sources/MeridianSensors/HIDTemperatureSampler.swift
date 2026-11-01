import Foundation
import MeridianKit

/// Apple silicon temperature sensors via the private IOHIDEventSystemClient API, resolved with dlsym so a
/// missing symbol on a future macOS yields nil instead of a link failure.
public final class HIDTemperatureSampler: @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeRawPointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int32) -> Double

    private struct API {
        var create: CreateFn, setMatching: SetMatchingFn, copyServices: CopyServicesFn
        var copyProperty: CopyPropertyFn, copyEvent: CopyEventFn, getFloat: GetFloatFn
    }

    private struct Service { var pointer: UnsafeRawPointer; var name: String }

    private let api: API?
    private var client: UnsafeRawPointer?
    private var services: [Service] = []
    private var servicesLoadedAt = 0
    private var calls = 0
    private let lock = NSLock()

    private static let kIOHIDEventTypeTemperature: Int64 = 15

    public init() {
        api = Self.resolve()
    }

    private static func resolve() -> API? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let create = sym("IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = sym("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let getFloat = sym("IOHIDEventGetFloatValue", as: GetFloatFn.self) else { return nil }
        return API(create: create, setMatching: setMatching, copyServices: copyServices,
                   copyProperty: copyProperty, copyEvent: copyEvent, getFloat: getFloat)
    }

    /// Raw readings keyed by the HID "Product" name, filtered of nonsense values.
    public func readRaw() -> [(name: String, celsius: Double)] {
        lock.lock(); defer { lock.unlock() }
        guard let api else { return [] }
        calls += 1
        // The service list does not change at runtime; retry only occasionally when it came back empty.
        if services.isEmpty && (calls == 1 || calls - servicesLoadedAt >= 30) { loadServices(api) }

        var out: [(String, Double)] = []
        for service in services {
            guard let event = api.copyEvent(service.pointer, Self.kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let value = api.getFloat(event, Int32(Self.kIOHIDEventTypeTemperature << 16))
            Unmanaged<AnyObject>.fromOpaque(event).release()
            if value > 0 && value <= 130 && value.isFinite { out.append((service.name, value)) }
        }
        return out
    }

    private func loadServices(_ api: API) {
        servicesLoadedAt = calls
        if client == nil { client = api.create(kCFAllocatorDefault) }
        guard let client else { return }
        let match: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = api.setMatching(client, match as CFDictionary)
        guard let listPtr = api.copyServices(client) else { return }
        let list = Unmanaged<CFArray>.fromOpaque(listPtr).takeRetainedValue()
        let key = "Product" as CFString
        services = (0..<CFArrayGetCount(list)).compactMap { i in
            guard let service = CFArrayGetValueAtIndex(list, i) else { return nil }
            guard let namePtr = api.copyProperty(service, Unmanaged.passUnretained(key).toOpaque()),
                  let name = Unmanaged<AnyObject>.fromOpaque(namePtr).takeRetainedValue() as? String else { return nil }
            // The array owns the services; keep it alive for the life of the sampler by retaining each service.
            _ = Unmanaged<AnyObject>.fromOpaque(service).retain()
            return Service(pointer: service, name: name)
        }
    }

    /// Readings mapped to the shared model. Ids are "hid:<Product>" so they cannot collide with SMC keys.
    public func sample() -> [TemperatureReading] {
        var seen: [String: Int] = [:]
        return readRaw().map { raw in
            let n = seen[raw.name, default: 0]
            seen[raw.name] = n + 1
            let id = n == 0 ? "hid:\(raw.name)" : "hid:\(raw.name)#\(n)"
            return TemperatureReading(id: id, name: SensorCatalog.friendlyName(forHIDName: raw.name),
                                      celsius: raw.celsius, group: SensorCatalog.group(forSensorName: raw.name))
        }
    }
}
