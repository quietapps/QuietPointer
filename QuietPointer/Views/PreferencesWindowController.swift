import AppKit
import SwiftUI

/// Builds a standard titled window hosting the SwiftUI `PreferencesView`.
enum PreferencesWindowController {
    static func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Quiet Pointer Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
