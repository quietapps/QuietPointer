# Changelog

All notable changes to Quiet Pointer are documented here.

Format: version **X.Y.Z**, build **N** — newest first.

---

## 1.1.3 — build 5 (2026-07-13)

Livelier poke: the faster you click, the wilder the hand.

### Changed

- **Poke motion reworked** — every poke now plays a full gesture: a small anticipation pull-back, a thrust along the finger axis, then a damped bounce settle with a slight twist. The hand no longer swells on click — the motion reads as a stab, not a zoom — and pokes run longer (360–700 ms) so the settle is visible
- **Click speed escalates the poke** — with *Speed-reactive intensity* on, each rapid click bumps the poke one expressiveness tier wilder, starting from your chosen mode and capping at *In your face* (e.g. from *Gentle nudge*: first click a nudge, second bold, third+ the full 92-pt jab). Your mode is now the starting tier for an isolated click rather than a fixed multiplier base
- **Click streaks measured click-to-click** — a streak now continues as long as each click lands within 0.8 s of the previous one (previously a fixed 0.7 s window from the newest click, which capped how far steady clicking could build). Bursts keep their v1.1.2 look, sizing, and growth

---

## 1.1.2 — build 4 (2026-07-13)

Second glove, simpler colors, better shadow, new click motion.

### Added

- **Hand style** — Preferences → Appearance → Hand style (also in the menu bar menu): *Classic glove* (the original upright pointer) or *Comic glove*, a new diagonal "mouse cursor" glove with a striped cuff, traced as vector paths so it stays crisp at any size. The comic glove's shadow beam continues straight along the arm's own axis
- **Click motion** — Preferences → Pointer → Click motion: *Poke* (the original forward jab + swell) or *Press*, where the whole hand + shadow recoils down along the shadow's axis and bounces back like a ball against the clicked point — the fingertip never travels past the click while settling

### Changed

- **Color replaces glove tints** — the seven glove color options are gone; the glove is always white. A new two-option *Color* setting (White / Black) drives the shadow beam and burst ink instead: White keeps the soft grey shadow with grey/blue bursts, Black switches to a dark beam and black bursts that read stronger on light desktops
- **Shadow length range widened** — the slider now spans a much shorter minimum and a much longer maximum (80–900 canvas units, previously 150–620), and the drawing canvas grew so the longest shadow never clips
- **Comic glove shadow shape** — constant-width beam (narrower than the flared cuff, exiting the wrist) that only ends in a fade, instead of tapering

### Fixed

- **Release packaging** — the 1.1.1 zip was rebuilt and re-uploaded shortly after release: the original asset came from a stale incremental build and did not actually contain the menu bar icon fix. Release builds are now always produced from a clean build and verified against the binary's symbols before upload

---

## 1.1.1 — build 3 (2026-07-13)

### Fixed

- **Menu bar icon visibility** — the active state tinted the icon with the accent color, which broke the template rendering and could leave the icon solid black (invisible against dark wallpapers) or washed out. The icon is now always a template image so macOS matches it to the menu bar in light and dark mode, and the active/inactive state is shown by the glyph itself: filled hand when the pointer is showing, outline hand when idle

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
