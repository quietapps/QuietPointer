import AppKit
import QuartzCore

/// Draws the hand inside the overlay window and performs the click "poke":
/// a jab of the whole hand plus a radiating starburst at the fingertip (the
/// impact lines from the artwork). The hand layer's anchor sits at the
/// fingertip so every scale / jab pivots there.
final class HandCursorView: NSView {

    private let handLayer = CALayer()
    private var currentHandHeight: CGFloat = 150
    private var currentColor: PointerColor = .white
    private var currentShadow: CGFloat = HandCursorRenderer.defaultShadowLength
    private var currentContentsScale: CGFloat = 2
    private var currentStyle: HandStyle = .classic

    /// Output scale = requested hand height / the glove's canvas-unit height.
    private var scale: CGFloat { currentHandHeight / HandCursorRenderer.handHeightUnits }

    private var canvas: CGSize { HandCursorRenderer.canvas(for: currentStyle) }
    private var fingertip: CGPoint { HandCursorRenderer.fingertip(for: currentStyle) }
    private var fingerAngle: CGFloat { HandCursorRenderer.fingerAngle(for: currentStyle) }

    /// Fingertip as a fraction of the canvas — used as the layer anchor point.
    private var anchorFraction: CGPoint {
        CGPoint(x: fingertip.x / canvas.width, y: fingertip.y / canvas.height)
    }

    /// The fingertip offset (from the view's bottom-left) at the current size.
    var hotspotOffset: CGPoint {
        CGPoint(x: fingertip.x * scale, y: fingertip.y * scale)
    }

    var imageSize: CGSize {
        CGSize(width: canvas.width * scale, height: canvas.height * scale)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The view is repositioned every frame while the mouse moves; nobody
        // observes its geometry, so skip the frame-change notification work.
        postsFrameChangedNotifications = false
        postsBoundsChangedNotifications = false
        layer?.addSublayer(handLayer)
        handLayer.actions = ["transform": NSNull(), "contents": NSNull(),
                             "bounds": NSNull(), "position": NSNull()]
        rebuild(handHeight: currentHandHeight, color: currentColor,
                shadowLength: currentShadow, style: currentStyle,
                contentsScale: currentContentsScale)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    /// Rebuilds the hand image for a new size / color / shadow length / style.
    /// `contentsScale` should be the highest backing scale among the connected
    /// displays so the bitmap is Retina-crisp everywhere.
    func rebuild(handHeight: CGFloat, color: PointerColor, shadowLength: CGFloat,
                 style: HandStyle, contentsScale: CGFloat) {
        currentHandHeight = handHeight
        currentColor = color
        currentShadow = shadowLength
        currentStyle = style
        currentContentsScale = max(1, contentsScale)

        // The drop shadow is baked into the artwork (see HandCursorRenderer),
        // so the layer composites a plain bitmap — no offscreen shadow pass.
        let img = HandCursorRenderer.image(style: style, handHeight: handHeight,
                                           color: color, shadowLength: shadowLength)
        let size = img.size
        frame = NSRect(origin: frame.origin, size: size)

        handLayer.contentsGravity = .resizeAspect
        handLayer.contents = img.layerContents(forContentsScale: currentContentsScale)
        handLayer.contentsScale = currentContentsScale
        handLayer.bounds = CGRect(origin: .zero, size: size)
        handLayer.anchorPoint = anchorFraction
        handLayer.position = CGPoint(x: anchorFraction.x * size.width,
                                     y: anchorFraction.y * size.height)
    }

    /// Advances every time a burst fires. Comic bursts use it to cycle through
    /// the shape styles; ripple bursts use it to rotate by the golden angle —
    /// either way, no two bursts in a row look identical.
    private var burstIndex = 0

    /// Runs a poke for a click. Every click taps the hand (jab of the glove +
    /// shadow); a run of rapid clicks escalates the motion tier (when `grow`
    /// is on) and, from the second click, also fires a burst that grows with
    /// the count.
    func poke(count: Int, mode: PokeMode, grow: Bool, design: BurstDesign,
              motion: ClickMotion) {
        let tier = grow ? mode.escalated(clicks: count) : mode
        switch motion {                                        // always tap the hand
        case .poke:  jab(tier: tier)
        case .press: press(tier: tier)
        }
        guard count >= 2 else { return }                       // single click: no burst
        let level = max(0, count - 1)
        let sizeScale = grow ? min(1.0 + CGFloat(level) * 0.4, 3.4) : 1.0
        switch design {
        case .comic:
            let style = ComicStyle.allCases[burstIndex % ComicStyle.allCases.count]
            burstIndex += 1
            comicBurst(style: style, mode: mode, sizeScale: sizeScale)
        case .ripple:
            rippleBurst(mode: mode, sizeScale: sizeScale)
        }
    }

    /// Pokey's motion values are tuned against a 150 pt-tall hand; everything
    /// distance-based scales by this to fit the user's glove size.
    private var pokeyScale: CGFloat { currentHandHeight / 150.0 }

    // MARK: - Jab (whole-hand thrust)

    private let bigFactor: CGFloat = 1.3

    private func jab(tier: PokeMode) {
        let s = pokeyScale
        let a = fingerAngle
        let frames = tier.pokeKeyframes

        // Pure travel along the finger axis plus a small twist — the hand
        // never scales, so the motion reads as a stab, not a swell.
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = frames.map { kf -> CATransform3D in
            let d = kf.travel * s
            var t = CATransform3DMakeTranslation(cos(a) * d, sin(a) * d, 0)
            t = CATransform3DRotate(t, kf.twist * .pi / 180, 0, 0, 1)
            return t
        }
        anim.keyTimes = frames.map { NSNumber(value: $0.time) }
        if tier == .shy {
            anim.timingFunctions = Array(
                repeating: CAMediaTimingFunction(name: .easeOut),
                count: frames.count - 1)
        }
        anim.duration = tier.pokeDuration
        anim.isRemovedOnCompletion = true

        handLayer.removeAnimation(forKey: "poke")
        handLayer.add(anim, forKey: "poke")
    }

    /// The whole hand + shadow recoils down along the shadow's axis (like the
    /// arm being pushed back by the click), then springs back to the clicked
    /// position with a small overshoot.
    private func press(tier: PokeMode) {
        let distance = tier.jabDistance * 2.2 * bigFactor
        let wobble = tier.wobble * 0.5

        // Recoil travels down the shadow's own axis (already a unit vector).
        let dir = HandCursorRenderer.rodDirection(for: currentStyle)
        let tx = dir.dx * distance
        let ty = dir.dy * distance

        var pushed = CATransform3DIdentity
        pushed = CATransform3DTranslate(pushed, tx, ty, 0)
        pushed = CATransform3DRotate(pushed, -wobble, 0, 0, 1)

        // Bounce like a dropped ball, but inverted: the clicked point is the
        // "floor". Down, back up to the click, down smaller, up, tiny dip,
        // settle — never past the clicked point.
        func offset(_ f: CGFloat) -> CATransform3D {
            CATransform3DMakeTranslation(tx * f, ty * f, 0)
        }

        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [CATransform3DIdentity, pushed,
                       CATransform3DIdentity, offset(0.30),
                       CATransform3DIdentity, offset(0.10),
                       CATransform3DIdentity]
        anim.keyTimes = [0, 0.24, 0.48, 0.66, 0.82, 0.92, 1]
        anim.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeIn),
                                CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeIn),
                                CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeIn)]
        anim.duration = tier.pressDuration
        anim.isRemovedOnCompletion = true

        handLayer.removeAnimation(forKey: "poke")
        handLayer.add(anim, forKey: "poke")
    }

    // MARK: - Comic burst (default — cycling impact shapes at the fingertip)

    /// The four comic burst shapes cycled through on successive rapid clicks.
    enum ComicStyle: CaseIterable { case sparkle, spikes, comicRing, doubleSparkle }

    /// Follows the pointer color: grey (reads on both light and dark
    /// backgrounds) for white, near-black for black.
    private var burstInk: CGColor {
        switch currentColor {
        case .white: NSColor(white: 0.42, alpha: 1).cgColor
        case .black: NSColor(white: 0.08, alpha: 1).cgColor
        }
    }

    private func comicBurst(style: ComicStyle, mode: PokeMode, sizeScale: CGFloat) {
        let s = scale
        let base = fingerAngle
        let outer = (46.0 + 26.0 * mode.jabDistance / 12.0) * s * sizeScale
        let inner = outer * 0.34
        let box = outer * 2.7
        let center = CGPoint(x: box / 2, y: box / 2)
        let lw = max(3.5, 6.0 * s * min(sizeScale, 2.0))

        let (path, filled) = comicPath(style: style, center: center,
                                       inner: inner, outer: outer, base: base)
        let core = makeComicLayer(box: box, path: path, filled: filled,
                                  color: burstInk, lineWidth: lw)
        // Beneath the hand so the glove is never obscured.
        layer?.insertSublayer(core, below: handLayer)

        let duration = mode.burstBaseDuration + 0.16
        animateComic(core, duration: duration)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            core.removeFromSuperlayer()
        }
    }

    private func makeComicLayer(box: CGFloat, path: CGPath, filled: Bool,
                                color: CGColor, lineWidth: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        shape.position = hotspotOffset
        shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        shape.path = path
        shape.lineJoin = .round
        shape.lineCap = .round
        shape.opacity = 0
        if filled {
            shape.fillColor = color
            shape.strokeColor = color
            shape.lineWidth = lineWidth * 0.5
        } else {
            shape.fillColor = NSColor.clear.cgColor
            shape.strokeColor = color
            shape.lineWidth = lineWidth
        }
        return shape
    }

    private func animateComic(_ shape: CAShapeLayer, duration: CFTimeInterval) {
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.2, 1.15, 1.0]          // pop then settle
        grow.keyTimes = [0, 0.55, 1]
        grow.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeInEaseOut)]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.15, 0.55, 1]
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.isRemovedOnCompletion = true
        shape.add(group, forKey: "burst")
    }

    /// Builds one comic shape. Returns the path and whether it should be filled.
    private func comicPath(style: ComicStyle, center: CGPoint,
                           inner: CGFloat, outer: CGFloat, base: CGFloat) -> (CGPath, Bool) {
        let path = CGMutablePath()
        switch style {
        case .sparkle:
            // Thin rays of alternating length radiating all around.
            let n = 12
            for i in 0..<n {
                let a = base + CGFloat(i) / CGFloat(n) * 2 * .pi
                let r = (i % 2 == 0) ? outer : outer * 0.62
                path.move(to: ray(center, a, inner))
                path.addLine(to: ray(center, a, r))
            }
            return (path, false)

        case .doubleSparkle:
            // Long rays plus a second offset set of short rays (dense sparkle).
            let n = 10
            for i in 0..<n {
                let a = base + CGFloat(i) / CGFloat(n) * 2 * .pi
                path.move(to: ray(center, a, inner))
                path.addLine(to: ray(center, a, outer))
                let a2 = a + .pi / CGFloat(n)
                path.move(to: ray(center, a2, inner * 1.1))
                path.addLine(to: ray(center, a2, outer * 0.5))
            }
            return (path, false)

        case .comicRing:
            // Jagged zig-zag star ring (comic explosion outline).
            let spikes = 11
            for i in 0...(spikes * 2) {
                let a = base + CGFloat(i) / CGFloat(spikes * 2) * 2 * .pi
                let r = (i % 2 == 0) ? outer : inner * 1.5
                let p = ray(center, a, r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return (path, false)

        case .spikes:
            // Bold filled triangular spikes radiating outward.
            let spikes = 10
            let halfW = CGFloat.pi / CGFloat(spikes) * 0.55
            for i in 0..<spikes {
                let a = base + CGFloat(i) / CGFloat(spikes) * 2 * .pi
                path.move(to: ray(center, a - halfW, inner))
                path.addLine(to: ray(center, a, outer))
                path.addLine(to: ray(center, a + halfW, inner))
                path.closeSubpath()
            }
            // Inner core polygon to tie the spikes together.
            for i in 0..<spikes {
                let a = base + CGFloat(i) / CGFloat(spikes) * 2 * .pi
                let p = ray(center, a, inner)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return (path, true)
        }
    }

    // MARK: - Ripple burst (optional — shockwave ring + rays)

    /// Quiet Blue — the brand accent, used for the white pointer color.
    private static let quietBlue = NSColor(srgbRed: 30/255, green: 136/255,
                                           blue: 229/255, alpha: 1)

    /// Quiet Apps "calm settle" curve — quick to start, decelerates to a stop.
    private static let calmEase = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    /// One confident color, no outline. White pointer: the brand blue,
    /// deepened slightly toward ink so it reads on light desktops. Black
    /// pointer: straight ink.
    private var burstColor: CGColor {
        switch currentColor {
        case .white:
            let base = Self.quietBlue
            return (base.blended(withFraction: 0.2, of: .black) ?? base).cgColor
        case .black:
            return NSColor(white: 0.08, alpha: 1).cgColor
        }
    }

    /// A thin shockwave ring expanding from the fingertip while six short rays
    /// shoot outward and dissolve. Successive bursts rotate by the golden
    /// angle so runs of clicks feel alive.
    private func rippleBurst(mode: PokeMode, sizeScale: CGFloat) {
        let s = scale
        let outer = (46.0 + 26.0 * mode.jabDistance / 12.0) * s * sizeScale
        let color = burstColor
        let duration = mode.burstBaseDuration + 0.18
        let rotation = fingerAngle + CGFloat(burstIndex) * 2.399963
        burstIndex += 1

        let ringWidth = max(2.5, 4.5 * s * min(sizeScale, 2.0))
        let rayWidth = max(2.0, 3.2 * s * min(sizeScale, 2.0))

        let ring = makeRing(radius: outer * 0.9, lineWidth: ringWidth, color: color)
        let rays = makeRays(outer: outer, rotation: rotation,
                            lineWidth: rayWidth, color: color)

        // Beneath the hand so the glove is never obscured.
        layer?.insertSublayer(ring, below: handLayer)
        for ray in rays { layer?.insertSublayer(ray, below: handLayer) }

        animateRing(ring, lineWidth: ringWidth, duration: duration)
        rays.forEach { animateRay($0, duration: duration) }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            ring.removeFromSuperlayer()
            rays.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func makeRing(radius: CGFloat, lineWidth: CGFloat, color: CGColor) -> CAShapeLayer {
        let box = (radius + lineWidth * 2.5) * 2
        let shape = CAShapeLayer()
        shape.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        shape.position = hotspotOffset
        shape.path = CGPath(ellipseIn: CGRect(x: box / 2 - radius, y: box / 2 - radius,
                                              width: radius * 2, height: radius * 2),
                            transform: nil)
        shape.fillColor = NSColor.clear.cgColor
        shape.strokeColor = color
        shape.lineWidth = lineWidth
        shape.opacity = 0
        return shape
    }

    /// Six round-capped rays, alternating long / slightly shorter, one layer
    /// each so their stroke animations run independently.
    private func makeRays(outer: CGFloat, rotation: CGFloat,
                          lineWidth: CGFloat, color: CGColor) -> [CAShapeLayer] {
        let count = 6
        let box = outer * 2.6
        let center = CGPoint(x: box / 2, y: box / 2)
        return (0..<count).map { i in
            let angle = rotation + CGFloat(i) / CGFloat(count) * 2 * .pi
            let reach = (i % 2 == 0) ? outer * 1.15 : outer * 0.95
            // Short segments that live mostly outside the ring's path — keeps
            // mid-flight frames from reading as a crosshair.
            let path = CGMutablePath()
            path.move(to: ray(center, angle, outer * 0.5))
            path.addLine(to: ray(center, angle, reach))

            let shape = CAShapeLayer()
            shape.bounds = CGRect(x: 0, y: 0, width: box, height: box)
            shape.position = hotspotOffset
            shape.path = path
            shape.fillColor = NSColor.clear.cgColor
            shape.strokeColor = color
            shape.lineWidth = lineWidth
            shape.lineCap = .round
            shape.opacity = 0
            return shape
        }
    }

    /// The ring expands with the calm-settle curve while its stroke thins —
    /// energy dissipating outward, not a bounce.
    private func animateRing(_ shape: CAShapeLayer, lineWidth: CGFloat,
                             duration: CFTimeInterval) {
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.25
        grow.toValue = 1.0
        grow.timingFunction = Self.calmEase

        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = lineWidth * 2.0
        thin.toValue = lineWidth * 0.35
        thin.timingFunction = Self.calmEase

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.85, 0.85, 0.0]
        fade.keyTimes = [0, 0.08, 0.5, 1]

        let group = CAAnimationGroup()
        group.animations = [grow, thin, fade]
        group.duration = duration
        shape.add(group, forKey: "burst")
    }

    /// Each ray "shoots": the tip races out first, the tail chases it, and the
    /// segment is fully dissolved by ~3/4 of the burst — the ring gets the
    /// last beat to itself, so the effect ends on a single calm shape.
    private func animateRay(_ shape: CAShapeLayer, duration: CFTimeInterval) {
        let tip = CAKeyframeAnimation(keyPath: "strokeEnd")
        tip.values = [0.15, 1.0, 1.0]
        tip.keyTimes = [0, 0.5, 1]
        tip.timingFunctions = [Self.calmEase, Self.calmEase]

        let tail = CAKeyframeAnimation(keyPath: "strokeStart")
        tail.values = [0.0, 0.0, 1.0, 1.0]
        tail.keyTimes = [0, 0.2, 0.75, 1]
        tail.timingFunctions = [Self.calmEase, Self.calmEase, Self.calmEase]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.9, 0.9, 0.0, 0.0]
        fade.keyTimes = [0, 0.06, 0.55, 0.75, 1]

        let group = CAAnimationGroup()
        group.animations = [tip, tail, fade]
        group.duration = duration
        shape.add(group, forKey: "burst")
    }

    private func ray(_ c: CGPoint, _ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
    }
}
