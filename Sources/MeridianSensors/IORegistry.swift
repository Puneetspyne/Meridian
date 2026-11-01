import Foundation
import IOKit

/// Thin helpers over the IORegistry. Everything returns nil or empty on failure so callers fail soft.
enum IORegistry {
    static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() else { return nil }
        return dict as? [String: Any]
    }

    /// Calls `body` for each service of `className` (subclasses included) with its properties, releasing every entry.
    static func forEachService(_ className: String, _ body: (io_registry_entry_t, [String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let props = properties(of: entry) { body(entry, props) }
        }
    }

    /// Properties of the first service of `className`.
    static func firstService(_ className: String) -> [String: Any]? {
        var result: [String: Any]?
        forEachService(className) { _, props in if result == nil { result = props } }
        return result
    }

    /// Walks the subtree below `entry` in the service plane and hands each descendant to `body`.
    static func forEachDescendant(of entry: io_registry_entry_t, _ body: (io_registry_entry_t, [String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(entry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if let props = properties(of: child) { body(child, props) }
        }
    }
}

/// Registry numbers arrive as NSNumber of varying width; this reads them without trapping on sign.
extension Dictionary where Key == String, Value == Any {
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func uint64(_ key: String) -> UInt64? { (self[key] as? NSNumber)?.uint64Value }
    /// Some drivers store negative values as huge unsigned 64-bit numbers (battery Amperage does).
    func signedInt64(_ key: String) -> Int64? {
        guard let n = self[key] as? NSNumber else { return nil }
        return Int64(bitPattern: n.uint64Value)
    }
}
