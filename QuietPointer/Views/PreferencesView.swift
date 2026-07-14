import SwiftUI
import Carbon.HIToolbox

/// The preferences window content. Mirrors the menu options and adds a
/// configurable global hotkey recorder, reset, and an about footer.
struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var cursor = CursorManager.shared

    var body: some View {
        Form {
            Section("Pointer") {
                Toggle("Show hand pointer", isOn: Binding(
                    get: { cursor.isEnabled },
                    set: { $0 ? cursor.enable() : cursor.disable() }))

                Picker("Hand style", selection: $prefs.handStyle) {
                    ForEach(HandStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Ink color", selection: $prefs.pointerColor) {
                    ForEach(PointerColor.allCases, id: \.self) { color in
                        Text(color.title).tag(color)
                    }
                }
                .pickerStyle(.segmented)

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

            Section("Clicks") {
                Toggle("Animate on click", isOn: $prefs.animateOnClick)

                Group {
                    // Four tick stops, one per PokeMode — same scale as the
                    // menu's intensity slider, same row layout as the size /
                    // shadow sliders above.
                    Slider(value: Binding(
                        get: { Double(prefs.mode.rawValue) },
                        set: { prefs.mode = PokeMode(rawValue: Int($0.rounded())) ?? .gentle }
                    ), in: 0...Double(PokeMode.allCases.count - 1), step: 1) {
                        Text("Expressiveness")
                    } minimumValueLabel: {
                        Text(PokeMode.shy.shortTitle).font(.caption)
                    } maximumValueLabel: {
                        Text(PokeMode.inYourFace.shortTitle).font(.caption)
                    }

                    Picker("Click motion", selection: $prefs.clickMotion) {
                        ForEach(ClickMotion.allCases, id: \.self) { motion in
                            Text(motion.title).tag(motion)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Burst style", selection: $prefs.burstDesign) {
                        ForEach(BurstDesign.allCases, id: \.self) { design in
                            Text(design.title).tag(design)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Speed-reactive intensity", isOn: $prefs.speedReactive)

                    if prefs.speedReactive {
                        Text("Rapid clicks get one tier wilder per click, up to \"\(PokeMode.inYourFace.title)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!prefs.animateOnClick)
            }

            Section("Global Hotkey") {
                HotKeyRecorder(combo: $prefs.hotKey)
                Text("Toggles the hand pointer anywhere, even when Quiet Pointer isn't focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)

                LabeledContent("Preferences") {
                    Button("Reset to Defaults") {
                        prefs.resetToDefaults()
                    }
                }
            }

            Section {
                AboutFooter()
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// App icon, name, version, and project links shown at the bottom of the
/// preferences window.
private struct AboutFooter: View {
    private static let repoURL = URL(string: "https://github.com/quietapps/QuietPointer")!

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)

            Text("Quiet Pointer")
                .font(.headline)

            Text(versionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Link("What's New", destination: Self.repoURL.appendingPathComponent("releases"))
                Link("Report an Issue", destination: Self.repoURL.appendingPathComponent("issues"))
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
