import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

/// A serializable global hotkey (key code + Carbon modifier flags).
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask (cmdKey, optionKey, ...)

    /// Default: ⌃⌥P (Control-Option-P), matching the menu screenshot.
    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_P),
                                       modifiers: UInt32(controlKey | optionKey))

    /// Human-readable rendering, e.g. "⌃⌥P".
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

/// App-wide preferences, persisted to `UserDefaults`. Publishes changes so
/// SwiftUI preference views and the managers stay in sync.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let mode = "pokeMode"
        static let animateOnClick = "animateOnClick"
        static let speedReactive = "speedReactive"
        static let tintHex = "pointerTintHex"
        static let hotKey = "hotKey"
        static let launchEnabled = "startEnabled"
        static let shadowScale = "shadowScale"
    }

    @Published var mode: PokeMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }
    @Published var animateOnClick: Bool {
        didSet { defaults.set(animateOnClick, forKey: Key.animateOnClick) }
    }
    @Published var speedReactive: Bool {
        didSet { defaults.set(speedReactive, forKey: Key.speedReactive) }
    }
    /// Glove tint as a hex string ("#RRGGBB"). "clear" keeps the plain white glove.
    @Published var tintHex: String {
        didSet { defaults.set(tintHex, forKey: Key.tintHex) }
    }
    @Published var hotKey: HotKeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Key.hotKey)
            }
        }
    }
    /// Shadow (rod) length as a 0...1 fraction between the renderer's min / max.
    @Published var shadowScale: Double {
        didSet { defaults.set(shadowScale, forKey: Key.shadowScale) }
    }

    var tintColor: NSColor? {
        NSColor(hex: tintHex)
    }

    private init() {
        self.mode = PokeMode(rawValue: defaults.integer(forKey: Key.mode)) ?? .gentle
        self.animateOnClick = defaults.object(forKey: Key.animateOnClick) as? Bool ?? true
        self.speedReactive = defaults.object(forKey: Key.speedReactive) as? Bool ?? true
        self.tintHex = defaults.string(forKey: Key.tintHex) ?? "clear"
        self.shadowScale = defaults.object(forKey: Key.shadowScale) as? Double ?? 0.6
        if let data = defaults.data(forKey: Key.hotKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            self.hotKey = combo
        } else {
            self.hotKey = .default
        }
    }
}

// MARK: - Color helpers

extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB". Returns nil for "clear" or malformed input.
    convenience init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.lowercased() == "clear" { return nil }
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let value = UInt32(str, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
