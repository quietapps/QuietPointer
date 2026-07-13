import SwiftUI
import Carbon.HIToolbox

/// The preferences window content. Mirrors the menu options and adds a
/// configurable global hotkey recorder.
struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var cursor = CursorManager.shared

    var body: some View {
        Form {
            Section("Pointer") {
                Toggle("Show hand pointer", isOn: Binding(
                    get: { cursor.isEnabled },
                    set: { $0 ? cursor.enable() : cursor.disable() }))

                Picker("Expressiveness", selection: $prefs.mode) {
                    ForEach(PokeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Animate on click", isOn: $prefs.animateOnClick)

                Picker("Burst style", selection: $prefs.burstDesign) {
                    ForEach(BurstDesign.allCases, id: \.self) { design in
                        Text(design.title).tag(design)
                    }
                }

                Toggle("Speed-reactive intensity", isOn: $prefs.speedReactive)
            }

            Section("Appearance") {
                Picker("Glove color", selection: $prefs.tintHex) {
                    Text("Classic white").tag("clear")
                    Text("Orange").tag("#F57C1F")
                    Text("Red").tag("#E23D3D")
                    Text("Green").tag("#33B25A")
                    Text("Blue").tag("#2F7CF5")
                    Text("Purple").tag("#8A4FE0")
                    Text("Yellow").tag("#F5C518")
                }

                Slider(value: $prefs.handHeight, in: Preferences.handHeightRange) {
                    Text("Hand size")
                } minimumValueLabel: {
                    Text("Small").font(.caption)
                } maximumValueLabel: {
                    Text("Large").font(.caption)
                }

                Slider(value: $prefs.shadowScale, in: 0...1) {
                    Text("Shadow length")
                } minimumValueLabel: {
                    Text("Short").font(.caption)
                } maximumValueLabel: {
                    Text("Long").font(.caption)
                }
            }

            Section("Global Hotkey") {
                HotKeyRecorder(combo: $prefs.hotKey)
                Text("Toggles the hand pointer anywhere, even when Quiet Pointer isn't focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A click-to-record control that captures the next key combination.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Toggle shortcut")
            Spacer()
            Button(recording ? "Press keys…" : combo.displayString) {
                recording ? stop() : start()
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording and keeps the previous shortcut.
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let carbonMods = Self.carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier to avoid clobbering plain typing.
            guard carbonMods != 0 else { return event }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}
