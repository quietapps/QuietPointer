import AppKit

/// A transparent, click-through window that sits on a single display and hosts
/// the hand pointer. One is created per connected screen so the hand renders
/// reliably on every display (a single window spanning multiple screens can be
/// clipped by the window server). Because each floats above all app windows at
/// the shielding-window level and joins all Spaces, the hand appears in
/// full-screen captures (Zoom, Meet, Loom, OBS, QuickTime).
final class CursorOverlayWindow: NSWindow {

    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true                 // fully click-through
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = NSView()
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
