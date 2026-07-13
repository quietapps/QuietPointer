import AppKit

/// Draws the Quiet Pointer: a white cartoon glove (the public-domain "Mickey"
/// pointing hand, index up) atop a long, fading grey "shadow" rod whose width
/// matches the glove cuff. The glove silhouette comes from the SVG path data in
/// `HandArt`, parsed to `CGPath` and re-centred/scaled into the canvas — so it
/// stays crisp at any size / display scale. The index fingertip is the hotspot.
///
/// Art: "MultiTouch-Interface Mouse-theme 1-finger" by BenBois (openclipart.org),
/// released into the public domain.
enum HandCursorRenderer {

    // MARK: - Layout (canvas space, AppKit bottom-left origin)

    /// Canvas is fixed and tall enough for the longest shadow; unused space is
    /// transparent. Output is scaled by the requested *hand* height, so a longer
    /// rod just makes a taller image without shrinking the glove.
    static let canvas = CGSize(width: 460, height: 960)

    /// Where the cuff meets the rod. Hand is above; rod trails below.
    static let pivot = CGPoint(x: 220, y: 660)
    /// Glove height in canvas units (drives the output scale).
    static let handHeightUnits: CGFloat = 250
    /// Hand tilt (left) and matching rod lean, so the rod exits the tilted cuff.
    private static let tiltRadians: CGFloat = 10 * .pi / 180
    private static let leanRadians: CGFloat = 10 * .pi / 180
    /// Default / clamp range for the adjustable shadow length (canvas units).
    static let defaultShadowLength: CGFloat = 460
    static let minShadowLength: CGFloat = 150
    static let maxShadowLength: CGFloat = 620

    // MARK: - Public geometry (derived from the parsed art)

    static var fingertip: CGPoint { model.fingertip }
    static var cuffWidth: CGFloat { model.cuffWidth }
    static let fingerAngle: CGFloat = atan2(model.fingertip.y - pivot.y,
                                            model.fingertip.x - pivot.x)

    // MARK: - Render

    /// - Parameters:
    ///   - handHeight: output height of the *glove* in points (rod scales with it).
    ///   - tint: optional glove fill tint; `nil` keeps it white.
    ///   - drawArm: include the trailing rod (off for the tiny menu-bar glyph).
    ///   - shadowLength: rod length in canvas units (clamped).
    ///   - dropShadow: bake a soft drop shadow into the artwork. Doing it here
    ///     (instead of a live `CALayer` shadow) avoids an offscreen render pass
    ///     on every composite while the hand moves.
    ///   - watermark: text to run up the rod, or `nil` (default none).
    static func image(handHeight: CGFloat = 150,
                      tint: NSColor? = nil,
                      drawArm: Bool = true,
                      shadowLength: CGFloat = defaultShadowLength,
                      dropShadow: Bool = true,
                      watermark: String? = nil) -> NSImage {
        let scale = handHeight / handHeightUnits
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)

        // A drawing-handler image re-renders the vectors at whatever backing
        // scale the destination needs, so the hand is crisp on every display.
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)

            if dropShadow {
                // CGContext shadow geometry is specified in device space, so
                // convert the point-space values through the current transform.
                let dev = ctx.userSpaceToDeviceSpaceTransform
                let unitsToDevice = (dev.a * dev.a + dev.b * dev.b).squareRoot()
                let backing = unitsToDevice / max(scale, 0.0001)
                ctx.setShadow(offset: CGSize(width: 1 * backing, height: -2 * backing),
                              blur: 5 * backing,
                              color: NSColor.black.withAlphaComponent(0.28).cgColor)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }

            if drawArm { drawRod(ctx: ctx, length: shadowLength, watermark: watermark) }
            drawHand(ctx: ctx, tint: tint)

            if dropShadow { ctx.endTransparencyLayer() }
            ctx.restoreGState()
            return true
        }
    }

    // MARK: - Rod (attached to the cuff, cuff-width)

    private static func drawRod(ctx: CGContext, length: CGFloat, watermark: String?) {
        let len = max(minShadowLength, min(length, maxShadowLength))
        // Rod axis: down-right at `leanRadians`, matching the tilted cuff.
        let down = CGVector(dx: sin(leanRadians), dy: -cos(leanRadians))
        let up = CGVector(dx: -down.dx, dy: -down.dy)
        let overlap: CGFloat = 55        // start inside the cuff so it reads attached
        let start = CGPoint(x: pivot.x + up.dx * overlap, y: pivot.y + up.dy * overlap)
        let end = CGPoint(x: pivot.x + down.dx * len, y: pivot.y + down.dy * len)

        let px = -down.dy, py = down.dx  // perpendicular unit
        let wTop = cuffWidth / 2         // full cuff width at the top
        let wEnd = cuffWidth * 0.55 / 2  // gentle taper as it fades

        let path = CGMutablePath()
        path.move(to: CGPoint(x: start.x + px * wTop, y: start.y + py * wTop))
        path.addLine(to: CGPoint(x: end.x + px * wEnd, y: end.y + py * wEnd))
        path.addArc(center: end, radius: wEnd,
                    startAngle: atan2(py, px), endAngle: atan2(py, px) + .pi,
                    clockwise: true)
        path.addLine(to: CGPoint(x: start.x - px * wTop, y: start.y - py * wTop))
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [NSColor(white: 0.60, alpha: 0.85).cgColor,
                      NSColor(white: 0.45, alpha: 0.5).cgColor,
                      NSColor(white: 0.35, alpha: 0.0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
        ctx.restoreGState()

        if let watermark { drawWatermark(watermark, start: start, end: end) }
    }

    private static func drawWatermark(_ text: String, start: CGPoint, end: CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x) + .pi
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.9)])
        let h = str.size().height
        let t: CGFloat = 0.42
        let anchor = CGPoint(x: start.x + (end.x - start.x) * t,
                             y: start.y + (end.y - start.y) * t)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.rotate(by: angle)
        str.draw(at: CGPoint(x: 0, y: -h / 2))
        ctx.restoreGState()
    }

    // MARK: - Hand

    private static func drawHand(ctx: CGContext, tint: NSColor?) {
        let white = (tint ?? NSColor.white)
        let ink = NSColor(white: 0.12, alpha: 1)
        for part in model.parts {
            ctx.addPath(part.path)
            switch part.style {
            case .whiteFillStroke:
                ctx.setFillColor(white.cgColor)
                ctx.fillPath()
                ctx.addPath(part.path)
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(model.strokeWidth)
                ctx.setLineJoin(.round)
                ctx.setLineCap(.round)
                ctx.strokePath()
            case .blackFill:
                ctx.setFillColor(ink.cgColor)
                ctx.fillPath()
            case .strokeOnly:
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(model.strokeWidth)
                ctx.setLineJoin(.round)
                ctx.setLineCap(.round)
                ctx.strokePath()
            }
        }
    }

    // MARK: - Parsed model (built once)

    enum PartStyle { case whiteFillStroke, blackFill, strokeOnly }
    struct Part { let path: CGPath; let style: PartStyle }
    struct Model {
        let parts: [Part]
        let fingertip: CGPoint
        let cuffWidth: CGFloat
        let strokeWidth: CGFloat
    }

    private static let model: Model = buildModel()

    private static func buildModel() -> Model {
        // Parse raw SVG paths (SVG group transforms are irrelevant — we
        // re-centre and scale below).
        let raw = HandArt.parts.map { (SVGPath.parse($0.d), $0.style) }
        let outline = HandArt.parts.enumerated()
            .filter { $0.element.style == .whiteFillStroke }
            .map { raw[$0.offset].0 }

        var bbox = CGRect.null
        for p in outline { bbox = bbox.union(p.boundingBox) }

        let s = handHeightUnits / bbox.height
        // raw (y-down) -> canvas (y-up), bottom-centre of the hand at pivot.
        var affineBase = CGAffineTransform(a: s, b: 0, c: 0, d: -s,
                                           tx: pivot.x - s * bbox.midX,
                                           ty: pivot.y + s * bbox.maxY)

        // Tilt the whole glove 10° left, pivoting on the cuff.
        let tilt = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: tiltRadians))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        var affine = affineBase.concatenating(tilt)

        let parts = raw.map { Part(path: $0.0.copy(using: &affine) ?? $0.0, style: $0.1) }

        // Fingertip = the true apex of the pointing finger. Flatten the
        // transformed outline into dense samples and take the topmost one, so
        // the hotspot lands on the actual tip of the curve (not a node or a
        // control point, and correct under the tilt).
        var tip = CGPoint(x: pivot.x, y: pivot.y)
        for part in parts where part.style == .whiteFillStroke {
            for p in flatten(part.path) where p.y > tip.y { tip = p }
        }

        // Cuff width = true opening width (measured before the tilt).
        let cuffRaw = SVGPath.parse(HandArt.cuff.d)
        let cuff = cuffRaw.copy(using: &affineBase) ?? cuffRaw
        let cuffWidth = cuff.boundingBox.width

        let strokeWidth = HandArt.strokeWidth * s

        return Model(parts: parts, fingertip: tip, cuffWidth: cuffWidth,
                     strokeWidth: strokeWidth)
    }

    /// Flattens a path into dense sample points (curves subdivided) for
    /// finding geometric extremes like the fingertip apex.
    private static func flatten(_ path: CGPath, steps: Int = 20) -> [CGPoint] {
        var pts: [CGPoint] = []
        var cur = CGPoint.zero
        var start = CGPoint.zero
        path.applyWithBlock { elp in
            let p = elp.pointee.points
            switch elp.pointee.type {
            case .moveToPoint:
                cur = p[0]; start = p[0]; pts.append(cur)
            case .addLineToPoint:
                cur = p[0]; pts.append(cur)
            case .addQuadCurveToPoint:
                let c = p[0], e = p[1]
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    pts.append(CGPoint(x: u*u*cur.x + 2*u*t*c.x + t*t*e.x,
                                       y: u*u*cur.y + 2*u*t*c.y + t*t*e.y))
                }
                cur = e
            case .addCurveToPoint:
                let c1 = p[0], c2 = p[1], e = p[2]
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    let a = u*u*u, b = 3*u*u*t, c = 3*u*t*t, d = t*t*t
                    pts.append(CGPoint(x: a*cur.x + b*c1.x + c*c2.x + d*e.x,
                                       y: a*cur.y + b*c1.y + c*c2.y + d*e.y))
                }
                cur = e
            case .closeSubpath:
                cur = start; pts.append(start)
            @unknown default:
                break
            }
        }
        return pts
    }
}

// MARK: - SVG artwork (raw path data from the source file)

private enum HandArt {
    struct P { let d: String; let style: HandCursorRenderer.PartStyle }

    static let strokeWidth: CGFloat = 4.0614

    /// The cuff underside curve — also used to measure cuff width.
    static let cuff = P(
        d: "m89.471 1065.9c3.7268 6.1263-0.48379 10.049-6.16 12.947-8.0302 4.0988-27.898 2.1019-34.7-2.0136-6.2427-3.777-9.0128-9.3495-6.0403-14.184",
        style: .whiteFillStroke)

    /// All glove parts, in draw order (back to front).
    static let parts: [P] = [
        cuff,
        // Main hand silhouette.
        P(d: "m21.354 1021c-0.85728 15.682 13.892 40.298 31.364 46.018 9.0217 2.9538 29.326 3.8464 36.494-1.431 12.273-9.0365 18.48-20.686 21.285-35.088 0.99446-5.1051 1.707-10.986 0.95737-15.702-3.1898-20.064-14.951-20.048-19.514-20.76-2.7272-8.7246-12.699-15.044-26.068-12.391-0.1029-10.746 0.22553-17.365 1.1122-27.536 1.4832-17.013-27.986-20.845-26.491-0.0121 1.0183 14.187 0.02688 25.675-2.4993 39-3.4496 1.0381-15.746 11.529-16.641 27.901z",
          style: .whiteFillStroke),
        // Small black shading wedges near the finger base / knuckles.
        P(d: "m63.838 981.04c0.0308 10.253 1.2148 18.225 7.2258 26.105-2.5091-6.5752-3.3692-19.666-3.1766-27.939z",
          style: .blackFill),
        P(d: "m93.471 992.23-3.8091 1.4862c1.929 5.5768 4.0509 11.842 7.1137 15.183-1.0804-2.6051-2.0771-11.978-3.3046-16.669z",
          style: .blackFill),
        P(d: "m36.249 991.71c-1.7026 12.092-6.1967 31.682-4.8107 38.213 1.185-3.9899 8.356-33.636 9.1333-39.703z",
          style: .blackFill),
        // Three curled-finger crease lines.
        P(d: "m79.642 1058.3c4.0369-9.6783 3.976-12.465 5.1951-17.405", style: .strokeOnly),
        P(d: "m70.26 1059c1.6922-11.475 1.4242-17.152 1.8555-24.898", style: .strokeOnly),
        P(d: "m59.041 1059.5c0.0971-7.9806-0.59887-11.754-1.049-16.831", style: .strokeOnly),
    ]
}

// MARK: - Minimal SVG path parser (supports M/m L/l H/h V/v C/c S/s Z/z)

private enum SVGPath {
    static func parse(_ d: String) -> CGMutablePath {
        let path = CGMutablePath()
        let tokens = tokenize(d)
        var i = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var cmd: Character = " "
        var lastCtrl: CGPoint?

        func num() -> CGFloat? {
            guard i < tokens.count, case let .number(v) = tokens[i] else { return nil }
            i += 1; return CGFloat(v)
        }

        while i < tokens.count {
            if case let .command(c) = tokens[i] {
                cmd = c; i += 1
                if c == "z" || c == "Z" {
                    path.closeSubpath(); cur = start; lastCtrl = nil; continue
                }
            }
            let abs = cmd.isUppercase
            switch cmd {
            case "m", "M":
                guard let x = num(), let y = num() else { i += 1; continue }
                cur = abs ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.move(to: cur); start = cur; lastCtrl = nil
                cmd = abs ? "L" : "l"          // subsequent pairs are lineto
            case "l", "L":
                guard let x = num(), let y = num() else { i += 1; continue }
                cur = abs ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.addLine(to: cur); lastCtrl = nil
            case "h", "H":
                guard let x = num() else { i += 1; continue }
                cur = abs ? CGPoint(x: x, y: cur.y) : CGPoint(x: cur.x + x, y: cur.y)
                path.addLine(to: cur); lastCtrl = nil
            case "v", "V":
                guard let y = num() else { i += 1; continue }
                cur = abs ? CGPoint(x: cur.x, y: y) : CGPoint(x: cur.x, y: cur.y + y)
                path.addLine(to: cur); lastCtrl = nil
            case "c", "C":
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(),
                      let x = num(), let y = num() else { i += 1; continue }
                let c1 = abs ? CGPoint(x: x1, y: y1) : CGPoint(x: cur.x + x1, y: cur.y + y1)
                let c2 = abs ? CGPoint(x: x2, y: y2) : CGPoint(x: cur.x + x2, y: cur.y + y2)
                let end = abs ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCtrl = c2; cur = end
            case "s", "S":
                guard let x2 = num(), let y2 = num(), let x = num(), let y = num()
                else { i += 1; continue }
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = abs ? CGPoint(x: x2, y: y2) : CGPoint(x: cur.x + x2, y: cur.y + y2)
                let end = abs ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCtrl = c2; cur = end
            default:
                i += 1
            }
        }
        return path
    }

    private enum Token { case command(Character); case number(Double) }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var numStr = ""
        func flush() {
            if !numStr.isEmpty, let v = Double(numStr) { tokens.append(.number(v)) }
            numStr = ""
        }
        for ch in d {
            if ch.isLetter {
                flush(); tokens.append(.command(ch))
            } else if ch.isNumber {
                numStr.append(ch)
            } else if ch == "." {
                if numStr.contains(".") { flush(); numStr = "." } else { numStr.append(ch) }
            } else if ch == "-" || ch == "+" {
                if numStr.isEmpty || numStr.hasSuffix("e") || numStr.hasSuffix("E") {
                    numStr.append(ch)
                } else { flush(); numStr = String(ch) }
            } else if ch == "e" || ch == "E" {
                numStr.append(ch)
            } else {
                flush()   // whitespace or comma
            }
        }
        flush()
        return tokens
    }
}
