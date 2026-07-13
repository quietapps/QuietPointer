# Changelog

All notable changes to Quiet Pointer are documented here.

Format: version **X.Y.Z**, build **N** — newest first.

---

## 1.0.0 — build 1 (2026-07-13)

Initial public release.

### Added

- System-wide hand-pointer cursor replacement — transparent, click-through overlay per display; real cursor hidden via `CGDisplayHideCursor`, fingertip pinned to the mouse location
- Click "poke" animation — `CAKeyframeAnimation` jab plus starburst; rapid clicks cycle four burst styles (sparkle → spikes → jagged ring → double-sparkle) and grow with click count
- Four expressiveness modes — Shy finger, Gentle nudge, Bold poke, In your face — with per-mode jab distance, scale, speed, and wobble
- Speed-reactive intensity — sliding window of recent clicks scales the poke up to 3×
- Glove color picker — Classic white, Orange, Red, Green, Blue, Purple, Yellow
- Shadow-length slider (menu bar and Preferences)
- Global hotkey (default ⌃⌥P) via Carbon `RegisterEventHotKey` — no Accessibility permission needed, remappable in Preferences
- Menu bar agent — show/hide, animate-on-click toggle, color menu, expressiveness slider, Preferences, Check for Updates, Quit; no Dock icon
- Multi-monitor support — one overlay per `NSScreen`, rebuilt on display changes
- Vector-drawn hand (`HandCursorRenderer`) — crisp at any size and scale, no bundled images
- SwiftUI Preferences window with hotkey recorder
- Zero permissions, zero network calls
