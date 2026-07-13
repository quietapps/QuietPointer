import AppKit

// Quiet Pointer runs as a menu-bar-only accessory (no dock icon). We build the
// app manually here rather than via @main so the activation policy is set
// before the app finishes launching.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
