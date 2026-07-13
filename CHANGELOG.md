# Changelog

All notable changes to Quiet Pointer are documented here.

Format: version **X.Y.Z**, build **N** — newest first.

---

## 1.1.0 — build 2 (2026-07-13)

Performance and smoothness release.

### Fixed

- **Toggle-off stall** — the cursor-hide reference count grew by 60 every second the hand was enabled, and disabling drained it with one window-server call per count. After an hour that meant ~216,000 synchronous calls — a multi-second beachball when hiding the hand. Re-hides are now gated on the cursor actually being visible, so the count stays tiny and toggle-off is instant regardless of session length
- **Blurry hand on Retina displays** — the hand bitmap was handed to Core Animation without a backing scale, so it could rasterize at 1×. It now renders at the highest backing scale among connected displays and re-renders when displays change
- **Wrong default expressiveness on fresh installs** — a missing-key read defaulted to *Shy finger* instead of the intended *Gentle nudge*
- **Wrong menu shortcut for special hotkeys** — remapping the hotkey to Space (or any named key) showed and armed the first letter of the key's name as a local menu shortcut (e.g. `⌃⌥S` for Space). Special keys now show no equivalent instead of a wrong one
- **Stale menu shortcut after remapping** — the toggle item's displayed shortcut now updates the moment the hotkey is changed, not on the next show/hide
- **Burst drawn over the glove** — the rapid-click starburst rendered on top of the hand, partially covering it at the moment of impact. Bursts now render beneath the glove (halo, then core, then hand)

### Performance

- **Frame-synced tracking** — hand movement is now driven by a display link instead of raw mouse events: high-rate mice (500–1000 Hz) coalesce to exactly one update per screen refresh, and the update cadence always matches the refresh rate of the display the hand is on (e.g. 120 Hz built-in vs 60 Hz external)
- **Zero idle cost** — the display link pauses about a second after the mouse stops moving; verified 0.0 % CPU with the hand enabled and the mouse still
- **Drop shadow baked into the artwork** — the hand layer previously used a live `CALayer` shadow with no `shadowPath`, forcing an offscreen render pass on every composite. The shadow is now drawn once into the hand image
- **60 Hz cursor-hide timer removed** — replaced by re-hides on movement frames, clicks, and app activation, plus a cheap 4 Hz visibility-gated backstop
- **Hand keeps moving while a menu is open** — the display link runs in `.common` run-loop modes, so menu tracking no longer freezes the pointer

### Changed

- **Comic burst cleaned up** — the white halo outline behind the rapid-click shapes is gone; the four cycling comic shapes now draw as a single clean ink stroke and render beneath the glove

### Added

- **Burst style option** — Preferences → Pointer → Burst style: *Comic pop* (default) or *Ripple ring*, a shockwave ring plus rays drawn in the glove tint (Quiet Blue on the classic white glove) with a calm settle curve
- **Hand size** — slider in Preferences (48–128 pt glove height)
- **Launch at login** — toggle in Preferences (uses `SMAppService`, no helper app)
- **State restore** — if the hand was showing when the app quit, it comes back on the next launch; pairs with launch at login

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
