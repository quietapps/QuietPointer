import Foundation
import Carbon.HIToolbox

/// Maps virtual key codes to short display names for the preferences UI.
enum KeyCodeNames {
    static func name(for keyCode: UInt32) -> String {
        if let special = special[Int(keyCode)] { return special }
        // Try to translate to a character via the current keyboard layout.
        if let ch = character(for: keyCode) { return ch.uppercased() }
        return "Key\(keyCode)"
    }

    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// Best-effort character lookup using the active keyboard layout.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let keyLayout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(keyLayout,
                                        UInt16(keyCode),
                                        UInt16(kUCKeyActionDisplay),
                                        0, UInt32(LMGetKbdType()),
                                        UInt32(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState,
                                        chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
