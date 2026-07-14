import Foundation
import AppKit
import Combine
import Carbon.HIToolbox
import ServiceManagement

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
        static let pointerColor = "pointerColor"
        static let hotKey = "hotKey"
        static let shadowScale = "shadowScale"
        static let handHeight = "handHeight"
        static let lastEnabled = "lastEnabled"
        static let burstDesign = "burstDesign"
        static let handStyle = "handStyle"
        static let clickMotion = "clickMotion"
    }

    /// Whether the hand was showing when the app last changed it on purpose.
    /// Persisted so a relaunch (or a launch-at-login start) restores the hand.
    var lastEnabled: Bool {
        get { defaults.bool(forKey: Key.lastEnabled) }
        set { defaults.set(newValue, forKey: Key.lastEnabled) }
    }

    /// Allowed range for the glove height, in points.
    static let handHeightRange: ClosedRange<Double> = 48...128
    static let defaultHandHeight: Double = 72

    @Published var mode: PokeMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }
    @Published var animateOnClick: Bool {
        didSet { defaults.set(animateOnClick, forKey: Key.animateOnClick) }
    }
    /// Which burst effect rapid clicks fire (comic shapes or ripple ring).
    @Published var burstDesign: BurstDesign {
        didSet { defaults.set(burstDesign.rawValue, forKey: Key.burstDesign) }
    }
    /// Which glove artwork the pointer uses (classic upright or comic diagonal).
    @Published var handStyle: HandStyle {
        didSet { defaults.set(handStyle.rawValue, forKey: Key.handStyle) }
    }
    /// What a click does to the hand (poke forward or press down the shadow).
    @Published var clickMotion: ClickMotion {
        didSet { defaults.set(clickMotion.rawValue, forKey: Key.clickMotion) }
    }
    @Published var speedReactive: Bool {
        didSet { defaults.set(speedReactive, forKey: Key.speedReactive) }
    }
    /// Shadow + burst ink (white = soft grey original look, black = dark).
    @Published var pointerColor: PointerColor {
        didSet { defaults.set(pointerColor.rawValue, forKey: Key.pointerColor) }
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
    /// Glove height in points (clamped to `handHeightRange`).
    @Published var handHeight: Double {
        didSet {
            let clamped = min(max(handHeight, Self.handHeightRange.lowerBound),
                              Self.handHeightRange.upperBound)
            if clamped != handHeight { handHeight = clamped; return }
            defaults.set(handHeight, forKey: Key.handHeight)
        }
    }
    /// Registers / unregisters the app as a login item. `SMAppService` is the
    /// source of truth, so nothing is persisted to UserDefaults.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Quiet Pointer: launch-at-login change failed: \(error)")
            }
        }
    }

    private init() {
        // `defaults.integer` returns 0 when the key is missing, which is a
        // valid PokeMode — check for presence explicitly so a fresh install
        // gets the intended default.
        if let raw = defaults.object(forKey: Key.mode) as? Int,
           let stored = PokeMode(rawValue: raw) {
            self.mode = stored
        } else {
            self.mode = .gentle
        }
        self.animateOnClick = defaults.object(forKey: Key.animateOnClick) as? Bool ?? true
        self.burstDesign = BurstDesign(rawValue: defaults.integer(forKey: Key.burstDesign))
            ?? .comic
        self.handStyle = HandStyle(rawValue: defaults.integer(forKey: Key.handStyle))
            ?? .classic
        self.clickMotion = ClickMotion(rawValue: defaults.integer(forKey: Key.clickMotion))
            ?? .poke
        self.speedReactive = defaults.object(forKey: Key.speedReactive) as? Bool ?? true
        self.pointerColor = PointerColor(rawValue: defaults.integer(forKey: Key.pointerColor))
            ?? .white
        self.shadowScale = defaults.object(forKey: Key.shadowScale) as? Double ?? 0.6
        let storedHeight = defaults.object(forKey: Key.handHeight) as? Double
            ?? Self.defaultHandHeight
        self.handHeight = min(max(storedHeight, Self.handHeightRange.lowerBound),
                              Self.handHeightRange.upperBound)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let data = defaults.data(forKey: Key.hotKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            self.hotKey = combo
        } else {
            self.hotKey = .default
        }
    }
}

