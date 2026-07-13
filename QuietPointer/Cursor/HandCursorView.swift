import AppKit
import QuartzCore

/// Draws the hand inside the overlay window and performs the click "poke":
/// a jab of the whole hand plus a radiating starburst at the fingertip (the
/// impact lines from the artwork). The hand layer's anchor sits at the
/// fingertip so every scale / jab pivots there.
final class HandCursorView: NSView {

    private let handLayer = CALayer()
    private var currentHandHeight: CGFloat = 150
    private var currentTint: NSColor?
    private var currentShadow: CGFloat = HandCursorRenderer.defaultShadowLength

    /// Output scale = requested hand height / the glove's canvas-unit height.
    private var scale: CGFloat { currentHandHeight / HandCursorRenderer.handHeightUnits }

    /// Fingertip as a fraction of the canvas — used as the layer anchor point.
    private var anchorFraction: CGPoint {
        CGPoint(x: HandCursorRenderer.fingertip.x / HandCursorRenderer.canvas.width,
                y: HandCursorRenderer.fingertip.y / HandCursorRenderer.canvas.height)
    }

    /// The fingertip offset (from the view's bottom-left) at the current size.
    var hotspotOffset: CGPoint {
        CGPoint(x: HandCursorRenderer.fingertip.x * scale,
                y: HandCursorRenderer.fingertip.y * scale)
    }

    var imageSize: CGSize {
        CGSize(width: HandCursorRenderer.canvas.width * scale,
               height: HandCursorRenderer.canvas.height * scale)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(handLayer)
        handLayer.actions = ["transform": NSNull(), "contents": NSNull(),
                             "bounds": NSNull(), "position": NSNull()]
        rebuild(handHeight: currentHandHeight, tint: currentTint, shadowLength: currentShadow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    /// Rebuilds the hand image for a new size / tint / shadow length.
    func rebuild(handHeight: CGFloat, tint: NSColor?, shadowLength: CGFloat) {
        currentHandHeight = handHeight
        currentTint = tint
        currentShadow = shadowLength

        let img = HandCursorRenderer.image(handHeight: handHeight, tint: tint,
                                           shadowLength: shadowLength)
        let size = img.size
        frame = NSRect(origin: frame.origin, size: size)

        handLayer.contentsGravity = .resizeAspect
        handLayer.contents = img
        handLayer.bounds = CGRect(origin: .zero, size: size)
        handLayer.anchorPoint = anchorFraction
        handLayer.position = CGPoint(x: anchorFraction.x * size.width,
                                     y: anchorFraction.y * size.height)
        handLayer.shadowColor = NSColor.black.cgColor
        handLayer.shadowOpacity = 0.28
        handLayer.shadowRadius = 5
        handLayer.shadowOffset = CGSize(width: 1, height: -2)
    }

    /// Advances every time a burst fires, so successive bursts always cycle
    /// through the different styles (never repeat the same one back-to-back).
    private var burstIndex = 0

    /// Runs a poke for a click. Every click taps the hand (jab of the glove +
    /// shadow); only a run of rapid clicks (count >= 2) also fires a burst,
    /// which cycles style each time and grows with the count.
    func poke(count: Int, mode: PokeMode, grow: Bool) {
        let level = max(0, count - 1)                          // 0 on a single click
        let sizeScale = grow ? min(1.0 + CGFloat(level) * 0.4, 3.4) : 1.0
        jab(mode: mode, intensity: sizeScale)                  // always tap the hand
        guard count >= 2 else { return }                       // single click: no burst
        let style = BurstStyle.allCases[burstIndex % BurstStyle.allCases.count]
        burstIndex += 1
        burst(style: style, mode: mode, sizeScale: sizeScale)
    }

    // MARK: - Jab (whole-hand thrust)

    private let bigFactor: CGFloat = 1.3

    private func jab(mode: PokeMode, intensity: CGFloat) {
        let distance = mode.jabDistance * intensity * bigFactor
        let scale = 1.0 + (mode.peakScale - 1.0) * intensity * bigFactor
        let wobble = mode.wobble * intensity

        // Jab travels along the direction the finger points.
        let a = HandCursorRenderer.fingerAngle
        let tx = cos(a) * distance
        let ty = sin(a) * distance

        var peak = CATransform3DIdentity
        peak = CATransform3DTranslate(peak, tx, ty, 0)
        peak = CATransform3DScale(peak, scale, scale, 1)
        peak = CATransform3DRotate(peak, wobble, 0, 0, 1)

        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [CATransform3DIdentity, peak, CATransform3DIdentity]
        anim.keyTimes = [0, 0.42, 1]
        anim.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                CAMediaTimingFunction(name: .easeIn)]
        anim.duration = mode.duration
        anim.isRemovedOnCompletion = true

        handLayer.removeAnimation(forKey: "poke")
        handLayer.add(anim, forKey: "poke")
    }

    // MARK: - Burst (comic impact at the fingertip)

    /// The four comic burst shapes cycled through on successive rapid clicks.
    enum BurstStyle: CaseIterable { case sparkle, spikes, comicRing, doubleSparkle }

    /// Grey so it reads on both light and dark backgrounds.
    private let burstInk = NSColor(white: 0.42, alpha: 1).cgColor
    private let burstHalo = NSColor(white: 0.95, alpha: 0.9).cgColor

    private func burst(style: BurstStyle, mode: PokeMode, sizeScale: CGFloat) {
        let s = scale
        let base = HandCursorRenderer.fingerAngle
        let outer = (46.0 + 26.0 * mode.jabDistance / 12.0) * s * sizeScale
        let inner = outer * 0.34
        let box = outer * 2.7
        let center = CGPoint(x: box / 2, y: box / 2)
        let lw = max(3.5, 6.0 * s * min(sizeScale, 2.0))

        let (path, filled) = burstPath(style: style, center: center,
                                       inner: inner, outer: outer, base: base)

        // A soft light halo behind a grey core keeps it visible on any colour.
        let halo = makeShapeLayer(box: box, path: path, filled: filled,
                                  color: burstHalo, lineWidth: lw + max(2.0, 2.5 * s))
        let core = makeShapeLayer(box: box, path: path, filled: filled,
                                  color: burstInk, lineWidth: lw)
        layer?.addSublayer(halo)
        layer?.addSublayer(core)

        let duration = mode.duration + 0.16
        for shape in [halo, core] { animateBurst(shape, duration: duration) }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            halo.removeFromSuperlayer()
            core.removeFromSuperlayer()
        }
    }

    private func makeShapeLayer(box: CGFloat, path: CGPath, filled: Bool,
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

    private func animateBurst(_ shape: CAShapeLayer, duration: CFTimeInterval) {
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

    /// Builds one burst shape. Returns the path and whether it should be filled.
    private func burstPath(style: BurstStyle, center: CGPoint,
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

    private func ray(_ c: CGPoint, _ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
    }
}
