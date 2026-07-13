import AppKit
import Combine

/// Owns the whole cursor-replacement lifecycle: one overlay window per display,
/// the hand view, global mouse tracking, click pokes, and hiding/showing the
/// real system cursor. Toggling `isEnabled` swaps the pointer on/off system-wide.
final class CursorManager: ObservableObject {

    static let shared = CursorManager()

    @Published private(set) var isEnabled = false

    private var overlays: [CursorOverlayWindow] = []
    private let handView = HandCursorView()
    private let clicks = ClickMonitor()
    private let prefs = Preferences.shared

    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    /// Glove height in points (the rod scales from this + the shadow length).
    /// Small, and it sits alongside the real cursor (never replaces it).
    private let handHeight: CGFloat = 72

    /// Current shadow (rod) length in canvas units, from the shadow preference.
    private var shadowLength: CGFloat {
        let r = HandCursorRenderer.maxShadowLength - HandCursorRenderer.minShadowLength
        return HandCursorRenderer.minShadowLength + CGFloat(prefs.shadowScale) * r
    }

    /// Re-renders the hand for the current tint / shadow length. Safe to call
    /// directly from menu actions — the Combine subscriptions below only fire
    /// in the default run-loop mode, which is paused while an NSMenu is open.
    func refreshHand() {
        handView.rebuild(handHeight: handHeight, tint: prefs.tintColor,
                         shadowLength: shadowLength)
        repositionToCurrentMouse()
    }

    private init() {
        handView.rebuild(handHeight: handHeight, tint: prefs.tintColor,
                         shadowLength: shadowLength)

        // Live-update the hand when tint or shadow length changes (covers the
        // Preferences window; menu actions call refreshHand() directly).
        prefs.$tintHex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)

        prefs.$shadowScale
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)
    }

    // MARK: - Toggle

    func toggle() { isEnabled ? disable() : enable() }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true

        rebuildOverlays()
        installMonitors()
        observeScreenChanges()
        repositionToCurrentMouse()
        startHidingCursor()         // hand replaces the system arrow
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false

        removeMonitors()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        handView.removeFromSuperview()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        clicks.reset()
        stopHidingCursor()
    }

    // MARK: - Overlay windows (one per display)

    private func rebuildOverlays() {
        handView.removeFromSuperview()
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let w = CursorOverlayWindow(screenFrame: screen.frame)
            w.orderFrontRegardless()
            return w
        }
    }

    /// The overlay window whose screen currently contains the mouse.
    private func overlay(containing point: NSPoint) -> CursorOverlayWindow? {
        overlays.first { NSPointInRect(point, $0.frame) } ?? overlays.first
    }

    // MARK: - Mouse tracking

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        let clickMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]

        globalMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
                self?.repositionToCurrentMouse()
            }!)
        globalMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
                self?.handleClick()
            }!)

        localMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] e in
                self?.repositionToCurrentMouse(); return e
            }!)
        localMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] e in
                self?.handleClick(); return e
            }!)
    }

    private func removeMonitors() {
        (globalMonitors + localMonitors).forEach { NSEvent.removeMonitor($0) }
        globalMonitors.removeAll()
        localMonitors.removeAll()
    }

    /// Moves the hand to the display under the mouse and places the fingertip
    /// exactly at the mouse location, in that window's coordinate space.
    private func repositionToCurrentMouse() {
        guard isEnabled else { return }
        let mouse = NSEvent.mouseLocation                 // global, bottom-left origin

        guard let window = overlay(containing: mouse),
              let content = window.contentView else { return }

        if handView.superview !== content {
            handView.removeFromSuperview()
            content.addSubview(handView)
        }

        let hotspot = handView.hotspotOffset
        handView.frame.origin = CGPoint(x: mouse.x - window.frame.minX - hotspot.x,
                                        y: mouse.y - window.frame.minY - hotspot.y)
    }

    private func handleClick() {
        guard isEnabled else { return }
        repositionToCurrentMouse()
        reassertHidden()             // re-hide instantly after the click
        guard prefs.animateOnClick else { return }
        // Every click taps the hand; only rapid repeat clicks add the burst.
        let count = clicks.registerClickAndCount()
        handView.poke(count: count, mode: prefs.mode, grow: prefs.speedReactive)
    }

    // MARK: - Multi-monitor

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.rebuildOverlays()
                self.repositionToCurrentMouse()
                self.reassertHidden()            // display reconfigure resets it
            }
    }

    // MARK: - System cursor visibility

    /// Other apps re-show the arrow whenever they become active or handle the
    /// first click (via their cursor rects), which flashes the default cursor.
    /// We counter this by (a) establishing one baseline hide, and (b) a 60 Hz
    /// timer + app-activation hook that continuously re-assert the hidden state.
    /// The re-assert is a balanced hide/show pair, so the reference count never
    /// grows and `disable()` reliably restores the cursor with a single show.
    private var cursorHidden = false
    private var hideCount = 0
    private var hideTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?

    private func startHidingCursor() {
        allowBackgroundCursorChanges()          // required for a background app
        guard !cursorHidden else { return }
        cursorHidden = true
        reassertHidden()

        // Runs in .common modes so it keeps firing even while a menu is open.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.reassertHidden()
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reassertHidden() }
    }

    private func stopHidingCursor() {
        hideTimer?.invalidate()
        hideTimer = nil
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
        guard cursorHidden else { return }
        cursorHidden = false
        // Drain every hide we issued (plus a margin); extra shows are no-ops.
        for _ in 0..<(hideCount + 16) { CGDisplayShowCursor(CGMainDisplayID()) }
        hideCount = 0
    }

    /// Re-hides the cursor, overriding any app that just reset it to the arrow.
    /// `CGDisplayHideCursor` is reference-counted, so each call is tracked and
    /// drained in `stopHidingCursor()`.
    private func reassertHidden() {
        guard cursorHidden else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    /// macOS ignores cursor changes made by a non-foreground app, so as a
    /// menu-bar (accessory) app our `CGDisplayHideCursor` would do nothing.
    /// Setting the window-server connection's `SetsCursorInBackground` property
    /// lets our cursor changes take effect even while another app is frontmost.
    /// (Uses the long-standing private CoreGraphics/SkyLight SPI via `dlsym`.)
    private var backgroundCursorAllowed = false

    private func allowBackgroundCursorChanges() {
        guard !backgroundCursorAllowed else { return }
        typealias MainConnFn = @convention(c) () -> Int32
        typealias SetPropFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        guard let mainSym = dlsym(RTLD_DEFAULT, "CGSMainConnectionID"),
              let setSym = dlsym(RTLD_DEFAULT, "CGSSetConnectionProperty") else { return }
        let mainConn = unsafeBitCast(mainSym, to: MainConnFn.self)
        let setProp = unsafeBitCast(setSym, to: SetPropFn.self)
        let cid = mainConn()
        _ = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        backgroundCursorAllowed = true
    }
}
