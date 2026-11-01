import AppKit
import Carbon.HIToolbox

/// A global hotkey through Carbon `RegisterEventHotKey`: no Accessibility or Input Monitoring permission needed.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var current: HotKey?

    /// - Parameters: `keyCode` is a `kVK_*` constant, `modifiers` Carbon flags (`cmdKey | optionKey`).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.current?.action() } }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handler) == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4D52_4448), id: 1) // 'MRDH'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
        HotKey.current = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
        if HotKey.current === self { HotKey.current = nil }
    }
}
