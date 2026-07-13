import AppKit
import Combine
import Carbon.HIToolbox

/// Wires together the status-bar item, the menu, the global hotkey, and the
/// preferences window. No dock icon (see `LSUIElement` in Info.plist).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let cursor = CursorManager.shared
    private let prefs = Preferences.shared
    private var cancellables = Set<AnyCancellable>()
    private var prefsWindow: NSWindow?

    // Menu items we mutate as state changes.
    private var toggleItem: NSMenuItem!
    private var animateItem: NSMenuItem!
    private var intensitySlider: NSSlider!
    private var shadowSlider: NSSlider!
    private var colorMenu: NSMenu!

    private let releasesURL = URL(string: "https://github.com/quietapps/QuietPointer/releases")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        buildMenu()

        HotKeyManager.shared.onFire = { [weak self] in self?.cursor.toggle() }
        HotKeyManager.shared.register(prefs.hotKey)

        // Keep the UI in sync with state / preference changes.
        cursor.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.refreshToggleUI(enabled: on) }
            .store(in: &cancellables)

        prefs.$hotKey
            .dropFirst()
            .sink { [weak self] combo in
                HotKeyManager.shared.register(combo)
                if let self, let item = self.toggleItem {
                    self.applyHotKeyEquivalent(to: item)   // keep the menu in sync
                }
            }
            .store(in: &cancellables)

        prefs.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] m in self?.intensitySlider?.integerValue = m.rawValue }
            .store(in: &cancellables)

        // Restore the hand if it was showing when the app last quit (also what
        // makes launch-at-login pick up right where the user left off).
        if prefs.lastEnabled {
            cursor.enable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cursor.shutdown()           // keep lastEnabled as the user set it
        HotKeyManager.shared.unregister()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusBarIcon()
            button.image?.isTemplate = true
            button.toolTip = "Quiet Pointer"
        }
    }

    /// A small hand glyph for the menu bar. Falls back to an SF Symbol.
    private func statusBarIcon() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "hand.point.up.left.fill",
                                accessibilityDescription: "Quiet Pointer") {
            return symbol
        }
        return HandCursorRenderer.image(handHeight: 18, drawArm: false, dropShadow: false)
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        toggleItem = NSMenuItem(title: "Show hand",
                                action: #selector(toggleCursor),
                                keyEquivalent: "")
        toggleItem.target = self
        applyHotKeyEquivalent(to: toggleItem)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        animateItem = NSMenuItem(title: "Animate on click",
                                 action: #selector(toggleAnimate),
                                 keyEquivalent: "")
        animateItem.target = self
        animateItem.state = prefs.animateOnClick ? .on : .off
        menu.addItem(animateItem)

        // Pointer color submenu.
        let colorItem = NSMenuItem(title: "Pointer color", action: nil, keyEquivalent: "")
        colorMenu = buildColorMenu()
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        // Intensity slider row (maps to the four PokeModes).
        menu.addItem(makeIntensityItem())

        // Shadow length slider row.
        menu.addItem(makeShadowItem())

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences…",
                                   action: #selector(openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…",
                                     action: #selector(checkForUpdates),
                                     keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let quitItem = NSMenuItem(title: "Quit",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshToggleUI(enabled: cursor.isEnabled)
    }

    private func buildColorMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let options: [(String, String)] = [
            ("Classic white", "clear"),
            ("Orange", "#F57C1F"),
            ("Red", "#E23D3D"),
            ("Green", "#33B25A"),
            ("Blue", "#2F7CF5"),
            ("Purple", "#8A4FE0"),
            ("Yellow", "#F5C518")
        ]
        for (name, hex) in options {
            let item = NSMenuItem(title: name, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hex
            item.state = (prefs.tintHex.caseInsensitiveCompare(hex) == .orderedSame) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func makeIntensityItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))

        let slider = NSSlider(value: Double(prefs.mode.rawValue),
                              minValue: 0, maxValue: 3,
                              target: self, action: #selector(changeMode(_:)))
        slider.numberOfTickMarks = 4
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.frame = NSRect(x: 16, y: 24, width: 228, height: 24)
        intensitySlider = slider
        container.addSubview(slider)

        let left = menuLabel("Shy finger", align: .left)
        left.frame = NSRect(x: 16, y: 4, width: 120, height: 16)
        container.addSubview(left)

        let right = menuLabel("In your face", align: .right)
        right.frame = NSRect(x: 124, y: 4, width: 120, height: 16)
        container.addSubview(right)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func makeShadowItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))

        let header = menuLabel("Shadow length", align: .left)
        header.font = .systemFont(ofSize: 12)
        header.textColor = .labelColor
        header.frame = NSRect(x: 16, y: 40, width: 200, height: 16)
        container.addSubview(header)

        let slider = NSSlider(value: prefs.shadowScale, minValue: 0, maxValue: 1,
                              target: self, action: #selector(changeShadow(_:)))
        slider.isContinuous = true               // fire while dragging
        slider.frame = NSRect(x: 16, y: 18, width: 228, height: 20)
        shadowSlider = slider
        container.addSubview(slider)

        let left = menuLabel("Short", align: .left)
        left.frame = NSRect(x: 16, y: 2, width: 100, height: 14)
        container.addSubview(left)

        let right = menuLabel("Long", align: .right)
        right.frame = NSRect(x: 144, y: 2, width: 100, height: 14)
        container.addSubview(right)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func menuLabel(_ text: String, align: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = align
        return label
    }

    /// Displays the configured hotkey next to the toggle item (also acts as a
    /// local shortcut while the app is active; the Carbon hotkey covers global).
    /// Only single printable characters can be shown as a menu key equivalent;
    /// special keys (Space, arrows, F-keys, …) clear it so the menu never shows
    /// a wrong shortcut (e.g. "Space" must not become "S").
    private func applyHotKeyEquivalent(to item: NSMenuItem) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []

        let combo = prefs.hotKey
        let name = KeyCodeNames.name(for: combo.keyCode)
        guard name.count == 1,
              let ch = name.lowercased().first,
              ch.isLetter || ch.isNumber else { return }

        item.keyEquivalent = String(ch)
        var flags: NSEvent.ModifierFlags = []
        if combo.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if combo.modifiers & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if combo.modifiers & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if combo.modifiers & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        item.keyEquivalentModifierMask = flags
    }

    // MARK: - Actions

    @objc private func toggleCursor() { cursor.toggle() }

    @objc private func toggleAnimate() {
        prefs.animateOnClick.toggle()
        animateItem.state = prefs.animateOnClick ? .on : .off
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        prefs.tintHex = hex
        for item in colorMenu.items {
            let h = item.representedObject as? String ?? ""
            item.state = (h.caseInsensitiveCompare(hex) == .orderedSame) ? .on : .off
        }
        cursor.refreshHand()
    }

    @objc private func changeMode(_ sender: NSSlider) {
        if let mode = PokeMode(rawValue: sender.integerValue) {
            prefs.mode = mode
        }
    }

    @objc private func changeShadow(_ sender: NSSlider) {
        prefs.shadowScale = sender.doubleValue
        cursor.refreshHand()          // update live (menu blocks the Combine sink)
    }

    @objc private func openPreferences() {
        if prefsWindow == nil {
            prefsWindow = PreferencesWindowController.makeWindow()
        }
        NSApp.activate()
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(releasesURL)
    }

    private func refreshToggleUI(enabled: Bool) {
        toggleItem?.title = enabled ? "Hide hand" : "Show hand"
        applyHotKeyEquivalent(to: toggleItem)
        if let button = statusItem.button {
            button.appearsDisabled = false
            button.contentTintColor = enabled ? .controlAccentColor : nil
        }
    }
}
