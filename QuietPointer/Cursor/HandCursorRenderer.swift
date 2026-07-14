import AppKit

/// Draws the Quiet Pointer glove atop a long, fading grey "shadow" rod whose
/// width matches the glove cuff. Two artworks are available (`HandStyle`):
/// the classic upright glove and the diagonal "comic" mouse-cursor glove.
/// Silhouettes come from SVG path data (`HandArt` / `ComicHandArt`), parsed to
/// `CGPath` and re-centred/scaled into the canvas — so they stay crisp at any
/// size / display scale. The index fingertip is the hotspot.
///
/// Classic art: "MultiTouch-Interface Mouse-theme 1-finger" by BenBois
/// (openclipart.org), released into the public domain.
enum HandCursorRenderer {

    // MARK: - Layout (canvas space, AppKit bottom-left origin)

    /// Glove height in canvas units (drives the output scale).
    static let handHeightUnits: CGFloat = 250
    /// Classic hand tilt (left) and matching rod lean, so the rod exits the
    /// tilted cuff.
    private static let tiltRadians: CGFloat = 10 * .pi / 180
    private static let leanRadians: CGFloat = 10 * .pi / 180
    /// Default / clamp range for the adjustable shadow length (canvas units).
    static let defaultShadowLength: CGFloat = 460
    static let minShadowLength: CGFloat = 80
    static let maxShadowLength: CGFloat = 900

    // MARK: - Public geometry (derived from the parsed art)

    /// Canvas is fixed per style and tall enough for the longest shadow; unused
    /// space is transparent. Output is scaled by the requested *hand* height,
    /// so a longer rod just makes a taller image without shrinking the glove.
    static func canvas(for style: HandStyle) -> CGSize { model(for: style).canvas }
    static func fingertip(for style: HandStyle) -> CGPoint { model(for: style).fingertip }
    /// Direction the index finger points (from the cuff pivot to the tip).
    static func fingerAngle(for style: HandStyle) -> CGFloat {
        let m = model(for: style)
        return atan2(m.fingertip.y - m.pivot.y, m.fingertip.x - m.pivot.x)
    }
    /// Unit vector the shadow rod travels along (canvas space, y-up).
    static func rodDirection(for style: HandStyle) -> CGVector {
        model(for: style).rodDirection
    }

    // MARK: - Render

    /// - Parameters:
    ///   - style: which glove artwork to draw.
    ///   - handHeight: output height of the *glove* in points (rod scales with it).
    ///   - color: shadow-rod ink (white = the original soft grey, black = dark).
    ///   - drawArm: include the trailing rod (off for the tiny menu-bar glyph).
    ///   - shadowLength: rod length in canvas units (clamped).
    ///   - dropShadow: bake a soft drop shadow into the artwork. Doing it here
    ///     (instead of a live `CALayer` shadow) avoids an offscreen render pass
    ///     on every composite while the hand moves.
    ///   - watermark: text to run up the rod, or `nil` (default none).
    static func image(style: HandStyle = .classic,
                      handHeight: CGFloat = 150,
                      color: PointerColor = .white,
                      drawArm: Bool = true,
                      shadowLength: CGFloat = defaultShadowLength,
                      dropShadow: Bool = true,
                      watermark: String? = nil) -> NSImage {
        let model = model(for: style)
        let scale = handHeight / handHeightUnits
        let size = CGSize(width: model.canvas.width * scale,
                          height: model.canvas.height * scale)

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

            if drawArm { drawRod(ctx: ctx, model: model, length: shadowLength,
                                 color: color, watermark: watermark) }
            drawHand(ctx: ctx, model: model)

            if dropShadow { ctx.endTransparencyLayer() }
            ctx.restoreGState()
            return true
        }
    }

    // MARK: - Rod (attached to the cuff, cuff-width)

    private static func drawRod(ctx: CGContext, model: Model, length: CGFloat,
                                color: PointerColor, watermark: String?) {
        let len = max(minShadowLength, min(length, maxShadowLength))
        // Rod axis: straight out of the cuff along the arm's own direction
        // (classic: 10° lean matching the tilted cuff; comic: the diagonal arm).
        let down = model.rodDirection
        let up = CGVector(dx: -down.dx, dy: -down.dy)
        let pivot = model.pivot
        let overlap: CGFloat = 55        // start inside the cuff so it reads attached
        let start = CGPoint(x: pivot.x + up.dx * overlap, y: pivot.y + up.dy * overlap)
        let end = CGPoint(x: pivot.x + down.dx * len, y: pivot.y + down.dy * len)

        let px = -down.dy, py = down.dx  // perpendicular unit
        let wTop = model.rodStartWidth / 2
        let wEnd = model.rodEndWidth / 2   // taper as it fades

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
        // White: the original soft grey beam. Black: a dark beam that reads
        // stronger on light desktops. Both fade out toward the tail.
        let stops: [NSColor] = switch color {
        case .white: [NSColor(white: 0.60, alpha: 0.85),
                      NSColor(white: 0.45, alpha: 0.5),
                      NSColor(white: 0.35, alpha: 0.0)]
        case .black: [NSColor(white: 0.10, alpha: 0.9),
                      NSColor(white: 0.08, alpha: 0.55),
                      NSColor(white: 0.05, alpha: 0.0)]
        }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: stops.map(\.cgColor) as CFArray,
                                  locations: [0, 0.5, 1])!
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

    private static func drawHand(ctx: CGContext, model: Model) {
        let white = NSColor.white
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
            case .whiteFill:
                ctx.setFillColor(white.cgColor)
                ctx.fillPath()
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

    // MARK: - Parsed models (built once per style)

    enum PartStyle { case whiteFillStroke, whiteFill, blackFill, strokeOnly }
    struct Part { let path: CGPath; let style: PartStyle }
    struct Model {
        let canvas: CGSize
        /// Where the cuff meets the rod. Hand is above; rod trails below.
        let pivot: CGPoint
        /// Unit vector the rod travels along (canvas space, y-up).
        let rodDirection: CGVector
        /// Rod width where it leaves the cuff / at the fading tail.
        let rodStartWidth: CGFloat
        let rodEndWidth: CGFloat
        let parts: [Part]
        let fingertip: CGPoint
        let cuffWidth: CGFloat
        let strokeWidth: CGFloat
    }

    static func model(for style: HandStyle) -> Model {
        switch style {
        case .classic: return classicModel
        case .comic: return comicModel
        }
    }

    private static let classicModel: Model = buildClassicModel()
    private static let comicModel: Model = buildComicModel()

    private static func buildClassicModel() -> Model {
        // Tall canvas so the longest shadow still fits below the glove.
        let canvas = CGSize(width: 460, height: 1260)
        let pivot = CGPoint(x: 220, y: 960)
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

        return Model(canvas: canvas, pivot: pivot,
                     rodDirection: CGVector(dx: sin(leanRadians), dy: -cos(leanRadians)),
                     rodStartWidth: cuffWidth, rodEndWidth: cuffWidth * 0.55,
                     parts: parts, fingertip: tip, cuffWidth: cuffWidth,
                     strokeWidth: strokeWidth)
    }

    /// Builds the comic (diagonal) glove: traced compound path with the white
    /// silhouette filled first, then the ink details (outline ring + cuff
    /// stripes) on top. The rod continues straight along the arm's axis.
    private static func buildComicModel() -> Model {
        // Tall + wide canvas so the longest diagonal shadow still fits.
        let canvas = CGSize(width: 760, height: 1240)
        let pivot = CGPoint(x: 340, y: 940)

        // Raw art constants (y-down pt space, measured from the traced source):
        // cuff-bottom centre, silhouette height, cuff opening width, arm axis.
        let anchor = CGPoint(x: 1104.9, y: 1477.5)
        let rawHeight: CGFloat = 1357.0
        let rawCuffWidth: CGFloat = 479.7
        let rodDirection = CGVector(dx: 0.3896, dy: -0.9210)   // canvas y-up

        let s = handHeightUnits / rawHeight
        // raw (y-down) -> canvas (y-up), cuff-bottom centre at the pivot.
        var affine = CGAffineTransform(a: s, b: 0, c: 0, d: -s,
                                       tx: pivot.x - s * anchor.x,
                                       ty: pivot.y + s * anchor.y)

        let silhouette = SVGPath.parse(ComicHandArt.silhouette)
        // Ink compound: silhouette ring with the two interiors as holes
        // (opposite winding, so a plain fill leaves them open).
        let ink = CGMutablePath()
        ink.addPath(silhouette)
        ink.addPath(SVGPath.parse(ComicHandArt.handInterior))
        ink.addPath(SVGPath.parse(ComicHandArt.cuffInterior))

        var parts: [Part] = [
            Part(path: silhouette.copy(using: &affine) ?? silhouette, style: .whiteFill),
            Part(path: ink.copy(using: &affine) ?? ink, style: .blackFill),
        ]
        for d in ComicHandArt.stripes {
            let p = SVGPath.parse(d)
            parts.append(Part(path: p.copy(using: &affine) ?? p, style: .blackFill))
        }

        // Fingertip = apex of the pointing finger (topmost silhouette sample).
        var tip = pivot
        if let sil = parts.first?.path {
            for p in flatten(sil) where p.y > tip.y { tip = p }
        }

        // The beam is narrower than the flared cuff (it exits the wrist, not
        // the cuff hem) and keeps a constant width; only the fade ends it.
        let cuffWidth = rawCuffWidth * s
        let beamWidth = cuffWidth * 0.75
        return Model(canvas: canvas, pivot: pivot, rodDirection: rodDirection,
                     rodStartWidth: beamWidth, rodEndWidth: beamWidth,
                     parts: parts, fingertip: tip, cuffWidth: cuffWidth,
                     strokeWidth: 4 * s)
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

// MARK: - Comic glove artwork (traced path data, y-down pt space)

/// The diagonal "mouse cursor" glove: index pointing up-left, striped cuff.
/// One white silhouette fill underneath, then an ink compound path whose two
/// interior subpaths (hand + cuff) are wound opposite, so a plain fill leaves
/// them open as holes; the five cuff stripes fill on top.
private enum ComicHandArt {
    static let silhouette =
        "M435.8 194.5C435.6 194.8 433.3 195.3 430.9 195.6C392.1 200.4 354.2 224.5 330.9 259.3C298.0 308.4" +
        " 295.6 382.5 323.6 481.9C334.7 521.4 361.9 583.3 390.3 633.8C392.9 638.3 395.0 642.2 395.0 642.4" +
        "C395.0 642.8 402.0 654.9 414.5 676.0C419.9 685.1 425.9 695.4 428.0 699.0C430.0 702.6 434.8 710.7" +
        " 438.7 717.0C442.5 723.3 448.3 733.2 451.4 739.0C454.6 744.8 459.8 753.8 463.0 759.0C466.1 764.2" +
        " 470.0 770.7 471.5 773.5C473.1 776.2 478.1 785.2 482.8 793.5C498.3 820.8 502.3 828.4 510.1 844.5" +
        "C520.6 866.4 533.1 898.0 531.2 898.0C530.5 898.0 525.0 894.4 511.0 884.9C497.0 875.4 470.3 858.2" +
        " 452.9 847.6C428.9 833.0 395.1 818.9 372.5 814.2C346.3 808.7 345.1 808.6 324.0 808.6C291.0 808.7" +
        " 266.0 813.7 239.0 825.5C222.4 832.8 204.1 843.6 196.1 850.9C194.2 852.6 192.4 854.0 192.0 854.0" +
        "C190.7 854.0 171.9 873.7 166.7 880.6C139.6 916.0 135.1 964.8 155.8 998.8C173.6 1028.1 209.2 1047" +
        ".2 276.0 1063.4C281.8 1064.8 294.2 1067.8 303.5 1070.0C348.6 1080.9 382.5 1093.7 419.5 1113.8C45" +
        "4.4 1132.7 489.8 1163.7 523.7 1204.8C546.6 1232.6 559.6 1246.8 575.5 1261.2C581.6 1266.7 588.3 1" +
        "272.9 590.5 1275.0C598.3 1282.2 628.3 1303.1 646.0 1313.7C657.8 1320.8 701.3 1339.5 710.2 1341.4" +
        "C711.5 1341.7 718.7 1343.5 726.3 1345.4C734.0 1347.3 742.1 1349.2 744.4 1349.5L748.7 1350.2L748." +
        "8 1360.8C749.1 1378.9 751.8 1387.4 764.1 1408.9C770.5 1420.2 802.3 1465.0 818.8 1485.9C827.9 149" +
        "7.5 831.3 1501.9 837.8 1510.8C852.6 1530.9 867.7 1543.0 884.3 1548.0C894.3 1550.9 895.7 1551.1 9" +
        "08.4 1551.1C921.3 1551.2 930.8 1548.9 971.9 1536.0C992.2 1529.6 993.8 1529.0 1009.5 1523.0C1017." +
        "8 1519.8 1031.3 1514.7 1039.5 1511.7C1057.1 1505.2 1061.9 1503.3 1064.1 1502.1C1065.0 1501.6 107" +
        "4.4 1497.7 1085.1 1493.5C1095.8 1489.3 1105.4 1485.4 1106.5 1484.9C1109.4 1483.6 1126.9 1476.5 1" +
        "138.5 1471.9C1150.2 1467.2 1159.1 1463.2 1179.1 1453.9C1187.2 1450.1 1194.0 1447.0 1194.4 1447.0" +
        "C1195.3 1447.0 1213.7 1438.4 1219.0 1435.5C1221.5 1434.1 1232.7 1428.5 1244.0 1422.9C1255.3 1417" +
        ".4 1265.4 1412.4 1266.5 1411.8C1293.3 1396.7 1302.8 1387.5 1309.7 1369.5C1317.1 1350.2 1317.6 13" +
        "38.3 1312.1 1310.0C1308.5 1291.8 1306.3 1280.4 1302.6 1260.5C1302.3 1258.8 1300.9 1251.6 1299.6 " +
        "1244.5C1298.2 1237.3 1295.7 1223.2 1294.0 1213.2C1290.7 1193.4 1288.9 1187.0 1282.9 1174.4C1277." +
        "9 1163.8 1266.2 1148.8 1261.9 1147.5C1259.4 1146.7 1259.5 1144.8 1262.1 1142.4C1265.4 1139.5 127" +
        "4.3 1123.7 1283.4 1104.7C1295.9 1079.0 1300.7 1068.6 1301.5 1065.9C1302.4 1062.8 1309.8 1043.2 1" +
        "311.1 1040.5C1318.8 1024.3 1334.7 958.5 1337.9 929.5C1343.3 881.5 1342.9 848.8 1336.4 805.0C1333" +
        ".5 785.2 1325.0 748.6 1318.8 729.0C1295.3 655.1 1244.5 605.8 1184.8 599.0C1164.9 596.7 1144.5 59" +
        "8.2 1127.9 603.1L1117.6 606.1L1112.5 600.8C1066.3 553.0 1006.5 538.3 947.0 560.1C940.4 562.5 923" +
        ".4 571.4 916.7 575.9L912.0 579.1L903.1 571.7C874.8 547.9 840.4 535.7 806.5 537.4C769.9 539.2 741" +
        ".7 551.3 716.3 576.2C705.5 586.7 698.4 595.4 694.6 602.7C693.7 604.5 692.6 606.0 692.1 606.0C691" +
        ".3 606.0 680.0 587.0 680.0 585.7C680.0 585.4 677.6 581.0 674.7 575.8C665.1 558.8 641.4 507.9 633" +
        ".5 487.5C631.0 480.9 628.4 474.4 627.8 473.0C618.7 452.0 607.0 418.5 583.1 345.0C567.2 296.1 564" +
        ".2 287.6 556.8 272.0C554.0 266.2 551.4 260.6 551.0 259.5C546.6 248.8 530.3 230.2 511.5 214.5C504" +
        ".2 208.3 483.3 199.8 467.5 196.5C459.8 194.8 436.9 193.4 435.8 194.5Z"

    static let handInterior =
        "M464.2 236.9C486.4 242.6 505.4 259.3 518.0 284.0C522.9 293.8 532.2 319.6 545.0 359.0C562.7 413.7" +
        " 567.6 427.8 583.2 470.0C605.6 530.5 637.1 594.8 676.1 659.9C679.9 666.2 683.0 671.6 683.0 672.0" +
        "C683.0 672.9 690.3 679.6 692.5 680.8C702.5 685.7 716.9 679.5 718.4 669.8C718.7 668.0 719.4 662.6" +
        " 720.0 657.8C725.6 613.2 755.3 583.3 799.5 577.9C831.3 574.0 860.3 585.4 890.0 613.5C907.1 629.6" +
        " 912.1 630.0 929.3 616.7C953.3 598.0 972.9 590.7 999.5 590.6C1033.7 590.4 1056.6 601.4 1087.5 63" +
        "2.6C1106.8 652.1 1109.7 653.1 1125.1 646.1C1157.3 631.5 1197.2 635.8 1224.7 656.8C1255.9 680.6 1" +
        "275.6 715.9 1289.2 772.0C1310.5 860.5 1304.6 943.7 1270.2 1038.0C1261.6 1061.5 1244.6 1096.2 123" +
        "1.1 1117.8C1226.5 1125.0 1222.5 1131.1 1222.1 1131.3C1221.8 1131.5 1215.0 1131.3 1207.0 1130.9C1" +
        "168.9 1128.9 1118.8 1133.9 1080.7 1143.5C1073.7 1145.2 1067.8 1146.5 1067.5 1146.2C1067.3 1146.0" +
        " 1070.4 1141.0 1074.4 1135.1C1103.9 1092.5 1125.0 1044.4 1134.5 998.3C1138.4 979.3 1137.6 974.5 " +
        "1129.5 970.9C1118.8 966.2 1111.8 971.8 1109.5 987.0C1099.3 1055.5 1041.1 1152.6 1001.8 1166.8C99" +
        "0.8 1170.7 979.1 1168.3 974.2 1161.0C965.7 1148.4 966.1 1114.5 975.4 1066.2C984.3 1020.3 987.3 9" +
        "94.6 987.4 963.5C987.5 941.5 987.3 938.1 985.7 935.0C981.9 927.2 971.7 925.5 965.2 931.4L961.5 9" +
        "34.9L961.7 947.2C962.2 977.3 958.8 1010.0 950.4 1056.5C942.9 1098.1 941.7 1107.5 941.7 1128.5C94" +
        "1.6 1154.1 945.2 1168.2 954.6 1179.7L958.2 1184.0L951.3 1187.1C879.5 1219.5 821.0 1259.0 776.0 1" +
        "305.5L768.5 1313.3L758.0 1311.6C705.3 1303.1 652.9 1277.3 608.5 1238.1C597.0 1227.8 580.2 1209.8" +
        " 557.4 1183.0C503.8 1120.0 471.7 1093.8 414.5 1066.4C381.4 1050.6 355.5 1042.1 292.6 1026.6C234." +
        "7 1012.2 211.1 1002.2 196.2 985.4C173.2 959.6 179.9 921.3 212.7 889.9C254.7 849.8 317.6 837.5 37" +
        "9.1 857.5C411.5 868.0 439.8 884.5 516.0 937.5C549.1 960.5 553.9 963.0 564.0 963.0C585.9 963.0 58" +
        "9.2 944.5 575.4 900.0C560.9 853.0 538.8 808.1 487.1 720.0C474.8 699.2 474.2 698.1 465.5 683.0C46" +
        "1.6 676.1 455.2 665.3 451.4 659.0C447.5 652.7 441.9 643.0 438.8 637.5C435.8 632.0 429.4 620.5 42" +
        "4.6 612.0C371.4 517.0 344.5 432.0 344.6 359.0C344.6 328.5 347.4 314.5 357.5 293.5C371.2 264.9 39" +
        "8.2 242.6 426.4 236.5C436.0 234.4 455.2 234.6 464.2 236.9Z"

    static let cuffInterior =
        "M1216.0 1166.5C1233.2 1170.6 1245.9 1183.7 1251.4 1203.0C1253.4 1210.1 1261.5 1252.3 1273.0 1316" +
        ".0C1278.5 1346.2 1275.4 1361.1 1261.7 1369.7C1240.5 1383.1 1143.9 1427.5 1079.1 1453.7C980.0 149" +
        "3.7 927.6 1511.2 906.5 1511.4C890.1 1511.6 884.7 1507.5 863.6 1479.5C855.4 1468.7 848.2 1459.3 8" +
        "47.6 1458.7C844.7 1455.6 816.3 1415.9 802.8 1396.0C790.0 1377.0 787.8 1371.7 787.6 1359.5C787.4 " +
        "1342.5 792.9 1333.8 818.8 1309.8C903.7 1231.6 1050.8 1170.7 1169.5 1164.6C1183.3 1163.9 1209.4 1" +
        "165.0 1216.0 1166.5Z"

    static let stripes: [String] = [
        "M1184.5 1201.7C1179.1 1203.2 1175.0 1208.8 1175.0 1215.0C1175.0 1217.9 1191.7 1294.9 1196.0 " +
            "1312.1C1197.1 1316.2 1199.3 1325.6 1201.0 1333.0C1204.1 1346.9 1205.5 1349.6 1211.2 1352.6C1" +
            "216.7 1355.4 1224.2 1353.3 1227.3 1348.1C1229.8 1343.9 1229.4 1338.6 1225.5 1322.2C1219.5 12" +
            "96.6 1201.0 1214.9 1201.0 1213.7C1201.0 1211.6 1197.0 1204.5 1195.2 1203.3C1192.8 1201.9 118" +
            "7.2 1201.0 1184.5 1201.7Z",
        "M1096.2 1218.7C1095.0 1218.9 1092.4 1220.6 1090.5 1222.4C1085.6 1227.1 1085.8 1231.6 1091.4 " +
            "1248.4C1093.9 1255.6 1104.4 1287.6 1114.9 1319.5C1125.4 1351.4 1134.6 1378.2 1135.3 1379.0C1" +
            "140.7 1385.9 1151.8 1385.6 1156.5 1378.4C1160.2 1372.6 1159.6 1370.2 1136.1 1299.0C1110.6 12" +
            "21.9 1110.6 1221.8 1105.0 1219.6C1100.9 1218.0 1100.3 1217.9 1096.2 1218.7Z",
        "M1004.9 1249.7C996.6 1254.8 997.0 1259.5 1008.6 1286.7C1013.9 1299.1 1018.6 1310.5 1019.1 13" +
            "11.9C1019.7 1313.3 1021.6 1317.9 1023.5 1322.0C1025.3 1326.1 1031.3 1340.1 1036.8 1353.0C106" +
            "2.6 1413.4 1061.7 1411.5 1067.8 1414.2C1073.8 1416.9 1079.2 1415.4 1082.7 1410.1C1087.3 1403" +
            ".2 1088.5 1406.9 1058.5 1336.5C1054.5 1327.1 1045.1 1304.9 1037.5 1287.0C1021.7 1249.9 1020." +
            "4 1248.0 1012.4 1248.0C1009.7 1248.0 1006.3 1248.8 1004.9 1249.7Z",
        "M924.6 1289.0C918.1 1291.0 914.1 1298.3 915.9 1304.8C916.8 1307.6 919.7 1313.5 932.0 1336.5C" +
            "934.1 1340.3 938.0 1347.9 940.9 1353.2C950.4 1371.3 955.7 1381.4 964.5 1398.0C969.3 1407.1 9" +
            "76.4 1420.5 980.2 1427.7C984.0 1435.0 988.3 1441.9 989.7 1443.0C998.2 1449.7 1011.0 1443.5 1" +
            "011.0 1432.7C1011.0 1428.8 1010.0 1426.5 994.5 1397.5C992.7 1394.2 988.1 1385.4 984.2 1378.0" +
            "C960.4 1332.5 938.2 1292.5 936.0 1290.9C932.8 1288.7 928.3 1287.9 924.6 1289.0Z",
        "M845.8 1339.5C838.9 1343.4 838.1 1352.5 843.8 1361.5C856.5 1381.8 915.9 1469.5 917.8 1470.8C" +
            "926.2 1476.3 936.8 1471.2 937.8 1461.2C938.3 1455.1 937.6 1453.7 923.2 1432.5C917.9 1424.8 9" +
            "02.2 1401.4 888.2 1380.5C874.2 1359.6 861.9 1341.6 860.9 1340.6C858.5 1338.0 849.5 1337.4 84" +
            "5.8 1339.5Z",
    ]
}
