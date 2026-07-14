import AppKit
import Combine
import QuartzCore

/// Owns the whole cursor-replacement lifecycle: one overlay window per display,
/// the hand view, global mouse tracking, click pokes, and hiding/showing the
/// real system cursor. Toggling `isEnabled` swaps the pointer on/off system-wide.
///
/// Tracking is display-link driven: mouse events only mark activity, and the
/// hand's position is applied once per screen refresh from the link callback.
/// This coalesces high-rate mice (500–1000 Hz report rates) down to one
/// Core Animation commit per frame, keeps motion frame-synced, and — because
/// the link runs in `.common` run-loop modes — keeps the hand moving even
/// while a menu is open. The link pauses when the mouse goes idle, so the app
/// costs nothing while nothing moves.
final class CursorManager: ObservableObject {

    static let shared = CursorManager()

    @Published private(set) var isEnabled = false

    private var overlays: [CursorOverlayWindow] = []
    private weak var activeOverlay: CursorOverlayWindow?
    private let handView = HandCursorView()
    private let clicks = ClickMonitor()
    private let prefs = Preferences.shared

    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    /// Glove height in points, user-adjustable in Preferences.
    private var handHeight: CGFloat { CGFloat(prefs.handHeight) }

    /// Current shadow (rod) length in canvas units, from the shadow preference.
    private var shadowLength: CGFloat {
        let r = HandCursorRenderer.maxShadowLength - HandCursorRenderer.minShadowLength
        return HandCursorRenderer.minShadowLength + CGFloat(prefs.shadowScale) * r
    }

    /// Highest backing scale among connected displays — render the hand once
    /// at this scale so it is crisp on every screen it crosses.
    private var maxBackingScale: CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// Re-renders the hand for the current size / color / shadow length. Safe to
    /// call directly from menu actions — the Combine subscriptions below only
    /// fire in the default run-loop mode, which is paused while an NSMenu is open.
    func refreshHand() {
        handView.rebuild(handHeight: handHeight, color: prefs.pointerColor,
                         shadowLength: shadowLength, style: prefs.handStyle,
                         contentsScale: maxBackingScale)
        repositionToCurrentMouse()
    }

    private init() {
        handView.rebuild(handHeight: handHeight, color: prefs.pointerColor,
                         shadowLength: shadowLength, style: prefs.handStyle,
                         contentsScale: maxBackingScale)

        // Live-update the hand when its appearance preferences change (covers
        // the Preferences window; menu actions call refreshHand() directly).
        prefs.$pointerColor
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)

        prefs.$shadowScale
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)

        prefs.$handHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)

        prefs.$handStyle
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHand() }
            .store(in: &cancellables)
    }

    // MARK: - Toggle

    func toggle() { isEnabled ? disable() : enable() }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        prefs.lastEnabled = true

        rebuildOverlays()
        installMonitors()
        observeScreenChanges()
        repositionToCurrentMouse()
        startHidingCursor()         // hand replaces the system arrow
        startMaintenanceTimer()
    }

    func disable() {
        prefs.lastEnabled = false
        shutdown()
    }

    /// Tears the overlay down without recording it as a user choice — used at
    /// app termination so the next launch can restore the hand.
    func shutdown() {
        guard isEnabled else { return }
        isEnabled = false

        removeMonitors()
        stopMaintenanceTimer()
        displayLink?.invalidate()
        displayLink = nil
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        handView.removeFromSuperview()
        activeOverlay = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        clicks.reset()
        stopHidingCursor()
    }

    // MARK: - Overlay windows (one per display)

    private func rebuildOverlays() {
        handView.removeFromSuperview()
        activeOverlay = nil
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

    /// The hand goes to sleep this long after the mouse stops moving.
    private let idleDelay: TimeInterval = 1.0

    private var displayLink: CADisplayLink?
    private var lastMouse = NSPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    private var lastActivity: TimeInterval = 0

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        let clickMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]

        // Move events only wake the display link — the actual repositioning
        // happens at most once per frame in tick(_:).
        globalMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
                self?.noteActivity()
            }!)
        globalMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
                self?.handleClick()
            }!)

        localMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] e in
                self?.noteActivity(); return e
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

    private func noteActivity() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        displayLink?.isPaused = false
    }

    /// Once-per-frame update: follow the mouse while it moves, keep the real
    /// cursor hidden, and pause when it has been still for a while.
    @objc private func tick(_ link: CADisplayLink) {
        guard isEnabled else { return }
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastActivity = ProcessInfo.processInfo.systemUptime
            reposition(to: mouse)
            reassertHidden()        // moving over cursor rects can re-show it
        } else if ProcessInfo.processInfo.systemUptime - lastActivity > idleDelay {
            link.isPaused = true
        }
    }

    /// (Re)creates the display link on the screen hosting `window`, so the
    /// update cadence always matches the refresh rate of the display the hand
    /// is actually on (e.g. 120 Hz built-in vs 60 Hz external).
    private func retargetDisplayLink(to window: NSWindow) {
        displayLink?.invalidate()
        displayLink = nil
        guard let screen = window.screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        // .common keeps the hand moving while menus / modal loops are running.
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Moves the hand to the display under `mouse` and places the fingertip
    /// exactly at the mouse location, in that window's coordinate space.
    private func reposition(to mouse: NSPoint) {
        guard isEnabled,
              let window = overlay(containing: mouse),
              let content = window.contentView else { return }

        if window !== activeOverlay {
            activeOverlay = window
            handView.removeFromSuperview()
            content.addSubview(handView)
            retargetDisplayLink(to: window)
        }

        let hotspot = handView.hotspotOffset
        handView.setFrameOrigin(NSPoint(x: mouse.x - window.frame.minX - hotspot.x,
                                        y: mouse.y - window.frame.minY - hotspot.y))
    }

    private func repositionToCurrentMouse() {
        guard isEnabled else { return }
        lastMouse = NSEvent.mouseLocation
        reposition(to: lastMouse)
    }

    private func handleClick() {
        guard isEnabled else { return }
        noteActivity()
        repositionToCurrentMouse()
        reassertHidden(force: true)  // apps set their cursor on click — re-hide
        guard prefs.animateOnClick else { return }
        // Every click taps the hand; only rapid repeat clicks add the burst.
        let count = clicks.registerClickAndCount()
        handView.poke(count: count, mode: prefs.mode, grow: prefs.speedReactive,
                      design: prefs.burstDesign, motion: prefs.clickMotion)
    }

    // MARK: - Multi-monitor

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.rebuildOverlays()
                self.refreshHand()               // backing scale may have changed
                self.repositionToCurrentMouse()
                self.reassertHidden(force: true) // display reconfigure resets it
            }
    }

    // MARK: - Maintenance timer

    /// A slow (4 Hz) backstop that re-hides the cursor if some app re-showed it
    /// while the mouse was idle, and wakes the display link if the mouse moved
    /// without us receiving an event (e.g. during menu tracking after an idle
    /// pause). Runs in .common modes so it keeps firing while a menu is open.
    private var maintenanceTimer: Timer?
    private var maintenanceTickCount = 0

    private func startMaintenanceTimer() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            if self.displayLink?.isPaused == true, NSEvent.mouseLocation != self.lastMouse {
                self.noteActivity()
            }
            self.maintenanceTickCount += 1
            // Every 16th tick (~4 s) force a re-hide in case the visibility
            // query ever misses a re-shown cursor; the rest are cheap checks.
            self.reassertHidden(force: self.maintenanceTickCount % 16 == 0)
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    private func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    // MARK: - System cursor visibility

    /// Other apps re-show the arrow whenever they become active or handle the
    /// first click (via their cursor rects), which flashes the default cursor.
    /// We counter this by (a) establishing one baseline hide, and (b) re-hiding
    /// on movement frames, clicks, app activation, and a slow timer backstop.
    /// Re-hides are gated on the cursor actually being visible, so the hide
    /// reference count stays small and `disable()` restores the cursor
    /// instantly — even after hours of use.
    private var cursorHidden = false
    private var hideCount = 0
    private var appActivationObserver: NSObjectProtocol?

    private func startHidingCursor() {
        allowBackgroundCursorChanges()          // required for a background app
        guard !cursorHidden else { return }
        cursorHidden = true
        reassertHidden(force: true)

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.reassertHidden(force: true)
            }
    }

    private func stopHidingCursor() {
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
        guard cursorHidden else { return }
        cursorHidden = false
        // Drain every hide we issued; stop as soon as the cursor is back.
        for _ in 0..<(hideCount + 2) {
            CGDisplayShowCursor(CGMainDisplayID())
            if Self.cursorIsVisible?() == true { break }
        }
        hideCount = 0
    }

    /// Re-hides the cursor, overriding any app that just reset it to the arrow.
    /// `CGDisplayHideCursor` is reference-counted, so each call is tracked and
    /// drained in `stopHidingCursor()`. Unless `force` is set, the call is
    /// skipped while the cursor is already hidden, keeping the count bounded.
    private func reassertHidden(force: Bool = false) {
        guard cursorHidden else { return }
        if !force, let visible = Self.cursorIsVisible, !visible() { return }
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
    }

    /// `CGCursorIsVisible`, resolved at runtime. The symbol is deprecated (no
    /// replacement exists) but fully functional; resolving via `dlsym` keeps
    /// the build warning-free. `nil` if the symbol ever disappears — callers
    /// then fall back to unconditional re-hides.
    private static let cursorIsVisible: (() -> Bool)? = {
        guard let sym = dlsym(rtldDefault, "CGCursorIsVisible") else { return nil }
        typealias Fn = @convention(c) () -> boolean_t
        let fn = unsafeBitCast(sym, to: Fn.self)
        return { fn() != 0 }
    }()

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

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
        guard let mainSym = dlsym(Self.rtldDefault, "CGSMainConnectionID"),
              let setSym = dlsym(Self.rtldDefault, "CGSSetConnectionProperty") else { return }
        let mainConn = unsafeBitCast(mainSym, to: MainConnFn.self)
        let setProp = unsafeBitCast(setSym, to: SetPropFn.self)
        let cid = mainConn()
        _ = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        backgroundCursorAllowed = true
    }
}
