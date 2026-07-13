import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via Carbon's `RegisterEventHotKey`,
/// which fires even when Quiet Pointer isn't focused and needs no Accessibility
/// permission. Re-registers whenever the configured combo changes.
final class HotKeyManager {

    static let shared = HotKeyManager()

    /// Called on the main thread when the hotkey fires.
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x51504e54 // 'QPNT'

    private init() {}

    func register(_ combo: HotKeyCombo) {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("Quiet Pointer: failed to register hotkey (status \(status))")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                HotKeyManager.shared.onFire?()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &spec,
                            nil,
                            &eventHandler)
    }
}
