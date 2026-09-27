import AppKit
import CoreGraphics

struct SaberState {
    var ext: Double = 1
    var time: Double = 0
}

struct RenderedImage {
    let image: CGImage
    /// Size in points.
    let size: CGSize
    /// Anchor in points, measured from the image's bottom-left corner.
    let anchor: CGPoint
}

/// Local drawing frame: x runs across the saber, +y runs from the emitter (y = 0) toward the blade tip;
/// the hilt occupies negative y.
enum SaberRenderer {
    /// Tilt from vertical so the blade points up-left like a normal arrow pointer.
    static let angle: CGFloat = 35 * .pi / 180
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func bladeLength(_ c: SaberConfig) -> CGFloat {
        44 * CGFloat(c.bladeLength) * (c.bladeStyle == .darksaber ? 1.15 : 1)
    }

    /// Unit vector (y-up screen space) from the emitter toward the tip.
    static var direction: CGVector { CGVector(dx: -sin(angle), dy: cos(angle)) }

    static func smooth(_ x: Double) -> CGFloat {
        let t = CGFloat(min(1, max(0, x)))
        return t * t * (3 - 2 * t)
    }

    static func layout(_ c: SaberConfig, scale: CGFloat, tight: Bool = false) -> (size: CGSize, hotspot: CGPoint) {
        let total = bladeLength(c) + c.hilt.length + 2
        let pad = tight ? 7 : 18 + 26 * CGFloat(c.glowRadius)
        let w = (total * sin(angle) + 2 * pad) * scale
        let h = (total * cos(angle) + 2 * pad) * scale
        return (CGSize(width: ceil(w), height: ceil(h)), CGPoint(x: pad * scale, y: ceil(h) - pad * scale))
    }

    static func makeContext(_ size: CGSize, backing: CGFloat) -> CGContext? {
        let pw = max(1, Int(ceil(size.width * backing)))
        let ph = max(1, Int(ceil(size.height * backing)))
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.scaleBy(x: backing, y: backing)
        ctx?.setShouldAntialias(true)
        ctx?.interpolationQuality = .high
        return ctx
    }

    /// Renders the whole saber; the returned anchor is the hotspot (the fully extended blade tip).
    static func render(_ c: SaberConfig, _ s: SaberState, scale: CGFloat, backing: CGFloat, tight: Bool = false) -> RenderedImage? {
        let (size, hot) = layout(c, scale: scale, tight: tight)
        guard let ctx = makeContext(size, backing: backing) else { return nil }
        draw(c, s, in: ctx, hotspot: hot, scale: scale, px: scale * backing)
        guard let img = ctx.makeImage() else { return nil }
        return RenderedImage(image: img, size: size, anchor: hot)
    }

    static func draw(_ c: SaberConfig, _ s: SaberState, in ctx: CGContext, hotspot: CGPoint, scale: CGFloat, px: CGFloat) {
        let L = bladeLength(c)
        ctx.saveGState()
        ctx.translateBy(x: hotspot.x, y: hotspot.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: angle)
        ctx.translateBy(x: 0, y: -L)
        drawBlade(c, s, ctx, L: L, px: px)
        drawHilt(c, ctx, time: c.animated ? s.time : 0)
        drawHotspotMarker(c, s, ctx, L: L, px: px)
        ctx.restoreGState()
    }

    /// Horizontal hilt-only icon (emitter pointing right) for pickers.
    static func renderHiltIcon(_ c: SaberConfig, height: CGFloat, backing: CGFloat) -> RenderedImage? {
        let s = height / 12
        let size = CGSize(width: ceil((c.hilt.length + 6) * s), height: ceil(height))
        guard let ctx = makeContext(size, backing: backing) else { return nil }
        ctx.translateBy(x: size.width - 3 * s, y: size.height / 2)
        ctx.scaleBy(x: s, y: s)
        ctx.rotate(by: -.pi / 2)
        drawHilt(c, ctx)
        guard let img = ctx.makeImage() else { return nil }
        return RenderedImage(image: img, size: size, anchor: .zero)
    }

    // MARK: Blade

    static func capsule(_ y0: CGFloat, _ y1: CGFloat, _ w: CGFloat) -> CGPath {
        let h = max(0.01, y1 - y0)
        let r = min(w / 2, h / 2)
        return CGPath(roundedRect: CGRect(x: -w / 2, y: y0, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    static func hash(_ i: Int, _ seed: Int) -> CGFloat {
        var x = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ seed &* 668_265_263 &+ 1_013_904_223)
        x = (x ^ (x >> 13)) &* 1_274_126_177
        x ^= x >> 16
        return CGFloat(x & 0xFFFF) / 65535
    }

    static func unstablePath(_ len: CGFloat, _ w: CGFloat, seed: Int) -> CGPath {
        let n = max(4, Int(len / 2.2))
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...n {
            let y = len * CGFloat(i) / CGFloat(n)
            let k1 = hash(i, seed) - 0.3
            let k2 = hash(i + 97, seed) - 0.3
            left.append(CGPoint(x: -w / 2 * (1 + 0.55 * k1), y: y))
            right.append(CGPoint(x: w / 2 * (1 + 0.55 * k2), y: y))
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -0.5))
        p.addLines(between: [CGPoint(x: 0, y: -0.5)] + left)
        p.addLine(to: CGPoint(x: 0, y: len + w * 0.35))
        p.addLines(between: [CGPoint(x: 0, y: len + w * 0.35)] + right.reversed())
        p.closeSubpath()
        return p
    }

    static func darksaberHalfWidth(_ w: CGFloat) -> CGFloat { w * 0.92 }

    /// Flat, wide blade with a chisel-cut tip whose point sits on the upper edge, like a katana.
    static func darksaberPath(_ len: CGFloat, _ w: CGFloat) -> CGPath {
        let hw = darksaberHalfWidth(w)
        let cut = min(len, hw * 2.6)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -hw, y: -0.5))
        p.addLine(to: CGPoint(x: -hw, y: len - cut))
        p.addLine(to: CGPoint(x: hw * 0.55, y: len))
        p.addLine(to: CGPoint(x: hw, y: len - cut * 0.35))
        p.addLine(to: CGPoint(x: hw, y: -0.5))
        p.closeSubpath()
        return p
    }

    /// White lightning pattern running down the middle of the Darksaber.
    static func darksaberCrackle(_ ctx: CGContext, len: CGFloat, w: CGFloat, seed: Int, px: CGFloat) {
        let hw = darksaberHalfWidth(w)
        let top = len - hw * 2.6
        guard top > 2 else { return }
        let n = max(6, Int(top / 0.9))
        ctx.saveGState()
        ctx.setLineJoin(.miter)
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 1.6 * px, color: RGB(0.85, 0.92, 1).cg(0.9))
        ctx.setStrokeColor(RGB(0.95, 0.97, 1).cg(0.9))
        ctx.setLineWidth(0.26)
        for strand in 0..<2 {
            ctx.move(to: CGPoint(x: (hash(strand, seed) - 0.5) * hw, y: 1))
            for i in 1...n {
                let y = 1 + (top - 1) * CGFloat(i) / CGFloat(n)
                let x = (hash(i * 3 + strand * 101, seed) - 0.5) * hw * 0.95
                ctx.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Wide, flat metal blade with a symmetric point so the hotspot stays exactly at the tip.
    static func swordPath(_ len: CGFloat, _ w: CGFloat) -> CGPath {
        let hw = w * 0.95
        let taper = min(len, hw * 3.2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -hw, y: -0.5))
        p.addLine(to: CGPoint(x: -hw, y: len - taper))
        p.addLine(to: CGPoint(x: 0, y: len))
        p.addLine(to: CGPoint(x: hw, y: len - taper))
        p.addLine(to: CGPoint(x: hw, y: -0.5))
        p.closeSubpath()
        return p
    }

    /// Polished metal blade: sheen across the width, etched fishbone lines, and (when animated) a gleam that travels up it.
    static func drawSword(_ c: SaberConfig, _ ctx: CGContext, len: CGFloat, w: CGFloat, t: Double, px: CGFloat) {
        let hw = w * 0.95
        let taper = min(len, hw * 3.2)
        let body = swordPath(len, w)
        let base = c.blade
        let light = base.mix(.white, 0.5)
        let dark = base.mix(.black, 0.45)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: (3 + 5 * CGFloat(c.glowRadius)) * px,
                      color: base.mix(.white, 0.3).cg(min(1, 0.4 * CGFloat(c.glowIntensity))))
        ctx.addPath(body)
        ctx.setFillColor(base.cg())
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let sheen = CGGradient(colorsSpace: srgb, colors: [dark.cg(), light.cg(), base.cg(), light.mix(base, 0.5).cg(), dark.cg()] as CFArray,
                               locations: [0, 0.22, 0.5, 0.78, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: -hw, y: 0), end: CGPoint(x: hw, y: 0), options: [])

        let etchTop = len - taper * 0.8
        if etchTop > 2 {
            ctx.setStrokeColor(dark.mix(.black, 0.2).cg(0.75))
            ctx.setLineWidth(0.22)
            ctx.setLineJoin(.miter)
            for side in [CGFloat(-1), 1] {
                var y: CGFloat = 1
                var out = true
                ctx.move(to: CGPoint(x: side * hw * 0.42, y: y))
                while y < etchTop {
                    y = min(etchTop, y + 0.7)
                    ctx.addLine(to: CGPoint(x: side * hw * (out ? 0.64 : 0.2), y: y))
                    out.toggle()
                }
                ctx.strokePath()
            }
            ctx.setStrokeColor(light.cg(0.6))
            ctx.setLineWidth(0.18)
            ctx.move(to: CGPoint(x: 0, y: 0.5))
            ctx.addLine(to: CGPoint(x: 0, y: len - taper * 0.6))
            ctx.strokePath()
        }

        if c.animated {
            let travel = len + 8
            let gy = CGFloat((t * 0.55).truncatingRemainder(dividingBy: 1)) * travel - 4
            let gleam = CGGradient(colorsSpace: srgb, colors: [RGB.white.cg(0), RGB.white.cg(0.55), RGB.white.cg(0)] as CFArray,
                                   locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(gleam, start: CGPoint(x: 0, y: gy - 2.5), end: CGPoint(x: 0, y: gy + 2.5), options: [])
        }
        ctx.restoreGState()

        ctx.addPath(body)
        ctx.setStrokeColor(dark.mix(.black, 0.35).cg(0.95))
        ctx.setLineWidth(0.35)
        ctx.setLineJoin(.miter)
        ctx.strokePath()
    }

    static func glowShape(_ ctx: CGContext, body: CGPath, halo: CGPath, core: CGPath?, c: SaberConfig,
                          intensity I: CGFloat, radius R: CGFloat, px: CGFloat) {
        let dark = c.bladeStyle == .darksaber
        let glowRGB = dark ? RGB(0.9, 0.94, 1) : c.blade

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: R * 2.2 * px, color: glowRGB.cg(min(1, 0.6 * I)))
        ctx.addPath(halo)
        ctx.setFillColor(glowRGB.cg(dark ? 0.35 : 0.85))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: R * 0.8 * px, color: glowRGB.cg(min(1, 0.95 * I)))
        ctx.addPath(body)
        ctx.setFillColor(dark ? RGB(0.12, 0.13, 0.15).cg() : c.blade.cg())
        ctx.fillPath()
        ctx.restoreGState()

        if dark {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 2.5 * px, color: RGB(0.85, 0.92, 1).cg(min(1, 0.9 * I)))
            ctx.addPath(body)
            ctx.setStrokeColor(RGB(0.9, 0.93, 0.97).cg(0.95))
            ctx.setLineWidth(0.6)
            ctx.setLineJoin(.miter)
            ctx.strokePath()
            ctx.restoreGState()
        } else if let core {
            let whiten = min(1, 0.5 + 0.45 * c.coreWhiteness)
            ctx.addPath(core)
            ctx.setFillColor(c.blade.mix(.white, whiten).cg())
            ctx.fillPath()
        }
    }

    static func drawBlade(_ c: SaberConfig, _ s: SaberState, _ ctx: CGContext, L: CGFloat, px: CGFloat) {
        let e = smooth(s.ext)
        guard e > 0.005 else { return }
        let len = L * e
        let t = s.time
        let unstable = c.bladeStyle == .unstable
        let dark = c.bladeStyle == .darksaber
        var flick: CGFloat = 1
        if c.animated || unstable {
            flick = 1 + 0.08 * sin(t * 29) + 0.05 * sin(t * 67 + 1.3) + 0.04 * sin(t * 143 + 0.7)
        }
        let w = 3.3 * CGFloat(c.thickness)
        let I = CGFloat(c.glowIntensity) * flick
        let R = 4 + 8 * CGFloat(c.glowRadius)
        let seed = (c.animated || unstable) ? Int(t * 24) : 0

        if c.bladeStyle == .sword {
            drawSword(c, ctx, len: len, w: w, t: t, px: px)
            return
        }

        let body = dark ? darksaberPath(len, w)
            : unstable ? unstablePath(len, w, seed: seed) : capsule(-0.5, len, w)
        let core = capsule(0, len - w * 0.2, w * (0.4 + 0.22 * CGFloat(c.coreWhiteness)))
        glowShape(ctx, body: body, halo: dark ? body : capsule(-0.5, len, w * 0.9), core: core, c: c,
                  intensity: I, radius: R, px: px)

        if dark { darksaberCrackle(ctx, len: len, w: w, seed: seed, px: px) }

        if unstable {
            let sparkRGB = c.blade
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(sparkRGB.mix(.white, 0.35).cg(0.9))
            ctx.setShadow(offset: .zero, blur: 3 * px, color: sparkRGB.cg())
            ctx.setLineWidth(0.45)
            for i in 0..<5 {
                let y = len * (0.12 + 0.8 * hash(i, seed + 7))
                let side: CGFloat = hash(i, seed + 3) > 0.5 ? 1 : -1
                let x0 = side * w * 0.5
                ctx.move(to: CGPoint(x: x0, y: y))
                ctx.addLine(to: CGPoint(x: x0 + side * (1.2 + 2.2 * hash(i, seed + 11)), y: y + 1.5 * (hash(i, seed + 5) - 0.5)))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        if c.hilt == .crossguard {
            let qlen = 7.5 * e
            let qw = w * 0.72
            for sign in [CGFloat(-1), 1] {
                let x0 = sign * 4.0
                let x1 = sign * (4.0 + qlen)
                let rect = CGRect(x: min(x0, x1), y: -3.2 - qw / 2, width: abs(x1 - x0), height: qw)
                let r = min(qw / 2, rect.width / 2)
                let qb = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
                let cr = rect.insetBy(dx: 0.3, dy: qw * 0.28)
                let qc = CGPath(roundedRect: cr, cornerWidth: min(cr.height / 2, cr.width / 2), cornerHeight: min(cr.height / 2, cr.width / 2), transform: nil)
                glowShape(ctx, body: qb, halo: qb, core: qc, c: c, intensity: I * 0.8, radius: R * 0.7, px: px)
            }
        }
    }

    static func drawHotspotMarker(_ c: SaberConfig, _ s: SaberState, _ ctx: CGContext, L: CGFloat, px: CGFloat) {
        let e = smooth(s.ext)
        guard e < 0.98 else { return }
        let a = (1 - e) * 0.75
        let color = c.bladeStyle == .darksaber ? RGB(0.9, 0.94, 1) : c.blade
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 4 * px, color: color.cg(a))
        ctx.setFillColor(color.cg(a))
        ctx.fillEllipse(in: CGRect(x: -1.5, y: L - 1.5, width: 3, height: 3))
        ctx.restoreGState()
        ctx.setFillColor(RGB.white.cg(a))
        ctx.fillEllipse(in: CGRect(x: -0.6, y: L - 0.6, width: 1.2, height: 1.2))
    }

    // MARK: Hilt helpers

    static let rubber = RGB(0.07, 0.07, 0.08)
    static let leather = RGB(0.36, 0.22, 0.12)
    static let rag = RGB(0.38, 0.33, 0.27)

    static func metal(_ ctx: CGContext, _ path: CGPath, _ f: HiltFinish, halfWidth hw: CGFloat = 4) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [f.dark.cg(), f.light.cg(), f.base.cg(), f.dark.mix(f.base, 0.5).cg(), f.dark.cg()] as CFArray
        let g = CGGradient(colorsSpace: srgb, colors: colors, locations: [0, 0.28, 0.55, 0.8, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: -hw, y: 0), end: CGPoint(x: hw, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(f.dark.mix(.black, 0.5).cg(0.9))
        ctx.setLineWidth(0.3)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func rrect(_ x: CGFloat, top: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0.6) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: top - h, width: w, height: h),
               cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil)
    }

    static func seg(_ ctx: CGContext, _ top: CGFloat, _ h: CGFloat, _ w: CGFloat, _ f: HiltFinish, r: CGFloat = 0.6) {
        metal(ctx, rrect(-w / 2, top: top, w, h, r: r), f, halfWidth: w / 2)
    }

    static func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    static func fill(_ ctx: CGContext, _ path: CGPath, _ color: RGB, _ a: CGFloat = 1) {
        ctx.addPath(path)
        ctx.setFillColor(color.cg(a))
        ctx.fillPath()
    }

    static func hRidges(_ ctx: CGContext, top: CGFloat, bottom: CGFloat, width w: CGFloat, count: Int, color: RGB, thickness: CGFloat = 0.6) {
        let step = (top - bottom) / CGFloat(count)
        for i in 0..<count {
            let y = top - step * (CGFloat(i) + 0.5)
            fill(ctx, rrect(-w / 2 - 0.05, top: y + thickness / 2, w + 0.1, thickness, r: 0.2), color, 0.85)
        }
    }

    static func vStrips(_ ctx: CGContext, top: CGFloat, bottom: CGFloat, xs: [CGFloat], width sw: CGFloat, color: RGB) {
        for x in xs {
            fill(ctx, rrect(x - sw / 2, top: top, sw, top - bottom, r: sw / 2), color, 0.92)
        }
    }

    static func diagWraps(_ ctx: CGContext, top: CGFloat, bottom: CGFloat, width w: CGFloat, count: Int, color: RGB, clip: CGPath) {
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        ctx.setStrokeColor(color.cg(0.85))
        ctx.setLineWidth(0.55)
        let step = (top - bottom) / CGFloat(count)
        for i in 0...count {
            let y = top - step * CGFloat(i)
            ctx.move(to: CGPoint(x: -w / 2 - 0.5, y: y + 1.1))
            ctx.addLine(to: CGPoint(x: w / 2 + 0.5, y: y - 1.1))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func scratches(_ ctx: CGContext, top: CGFloat, bottom: CGFloat, width w: CGFloat, seed: Int) {
        ctx.saveGState()
        ctx.setStrokeColor(RGB.white.cg(0.28))
        ctx.setLineWidth(0.18)
        for i in 0..<5 {
            let y = bottom + (top - bottom) * hash(i, seed)
            let x = (hash(i, seed + 1) - 0.5) * w * 0.8
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + 1.2 * (hash(i, seed + 2) - 0.3), y: y - 0.8))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func dot(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: RGB) {
        ctx.setFillColor(color.cg())
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(RGB.white.cg(0.45))
        ctx.fillEllipse(in: CGRect(x: x - r * 0.45, y: y + r * 0.05, width: r * 0.6, height: r * 0.6))
    }

    // MARK: Hilts

    static func drawHilt(_ c: SaberConfig, _ ctx: CGContext, time: Double = 0) {
        let f = c.finish
        let a = c.accent
        switch c.hilt {
        case .classic:
            seg(ctx, 0, 4.6, 7.2, f, r: 1)
            for x in [-2.6, -0.6, 1.4] as [CGFloat] {
                fill(ctx, rrect(x, top: -1.2, 1.2, 1.8, r: 0.3), rubber, 0.8)
            }
            seg(ctx, -4.6, 1.8, 5.0, f)
            seg(ctx, -6.4, 5.2, 6.0, f)
            metal(ctx, rrect(2.9, top: -6.9, 2.3, 4.2, r: 0.4), f.alt, halfWidth: 1.2)
            dot(ctx, 1.2, -8.8, 0.8, a)
            seg(ctx, -11.6, 9.4, 5.6, f)
            vStrips(ctx, top: -12.0, bottom: -20.6, xs: [-1.9, 0, 1.9], width: 0.95, color: rubber)
            seg(ctx, -21.0, 3.0, 5.0, f, r: 1)
            ctx.setStrokeColor(f.dark.cg())
            ctx.setLineWidth(0.55)
            ctx.strokeEllipse(in: CGRect(x: -1.1, y: -25.3, width: 2.2, height: 2.2))

        case .ribbed:
            metal(ctx, poly([(-3.7, 0.3), (3.7, -1.5), (3.7, -5.2), (-3.7, -5.2)]), f)
            seg(ctx, -5.2, 5.4, 6.2, f.alt)
            for (i, y) in ([-6.6, -8.1, -9.6] as [CGFloat]).enumerated() {
                dot(ctx, 1.7, y, 0.55, i == 1 ? RGB(hex: 0xC8CCD2) : a)
            }
            fill(ctx, rrect(-2.6, top: -6.0, 2.2, 3.8, r: 0.3), rubber, 0.8)
            seg(ctx, -10.6, 10.6, 5.4, f.alt)
            hRidges(ctx, top: -11.0, bottom: -20.8, width: 5.4, count: 8, color: rubber, thickness: 0.75)
            seg(ctx, -21.2, 3.8, 6.2, f, r: 0.8)

        case .slim:
            metal(ctx, poly([(-3.1, 0), (3.1, 0), (2.2, -4), (-2.2, -4)]), f)
            seg(ctx, -4, 3, 4.4, f)
            seg(ctx, -7, 1.1, 5.2, f.alt)
            seg(ctx, -8.1, 5.4, 4.4, f)
            fill(ctx, rrect(0.9, top: -9.2, 1.2, 1.6, r: 0.3), a)
            seg(ctx, -13.5, 9.5, 4.7, f)
            hRidges(ctx, top: -14, bottom: -22.6, width: 4.7, count: 9, color: rubber, thickness: 0.5)
            metal(ctx, poly([(-2.35, -23), (2.35, -23), (1.8, -27), (-1.8, -27)]), f)

        case .curved:
            seg(ctx, 0, 3.6, 5.8, f)
            fill(ctx, rrect(-2.9, top: -2.8, 5.8, 0.8, r: 0.2), a)
            let curve = CGMutablePath()
            curve.move(to: CGPoint(x: 0, y: -3.6))
            curve.addCurve(to: CGPoint(x: 4.8, y: -21.5), control1: CGPoint(x: 0, y: -11), control2: CGPoint(x: 1.4, y: -17))
            let body = curve.copy(strokingWithWidth: 5.2, lineCap: .butt, lineJoin: .round, miterLimit: 4)
            metal(ctx, body, f, halfWidth: 7)
            let grip = curve.copy(dashingWithPhase: 0, lengths: [0.55, 0.85])
            let ribs = grip.copy(strokingWithWidth: 4.4, lineCap: .butt, lineJoin: .round, miterLimit: 4)
            ctx.saveGState()
            ctx.addPath(rrect(-8, top: -8, 20, 12))
            ctx.clip()
            fill(ctx, ribs, a, 0.55)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: 4.8, y: -21.5)
            metal(ctx, CGPath(ellipseIn: CGRect(x: -2.9, y: -2.9, width: 5.8, height: 5.8), transform: nil), f.alt, halfWidth: 3)
            ctx.restoreGState()
            dot(ctx, 4.8, -21.5, 0.9, a)

        case .crossguard:
            let block = poly([(-4.2, 0.3), (4.3, 0), (4.4, -6.8), (-4.3, -7.0)])
            metal(ctx, block, f, halfWidth: 4.5)
            metal(ctx, rrect(-5.4, top: -2.1, 1.3, 2.3, r: 0.2), f.alt, halfWidth: 5)
            metal(ctx, rrect(4.1, top: -2.1, 1.3, 2.3, r: 0.2), f.alt, halfWidth: 5)
            fill(ctx, rrect(-1.4, top: -1.6, 2.8, 3.6, r: 0.4), rubber, 0.7)
            scratches(ctx, top: 0, bottom: -7, width: 8, seed: 3)
            let grip = rrect(-2.8, top: -7, 5.6, 10.6)
            metal(ctx, grip, f, halfWidth: 2.8)
            diagWraps(ctx, top: -7.4, bottom: -17.2, width: 5.6, count: 7, color: rubber, clip: grip)
            metal(ctx, poly([(-3.2, -17.6), (3.3, -17.6), (3.5, -20), (2.1, -21.8), (-2.2, -21.6), (-3.4, -19.8)]), f)
            scratches(ctx, top: -17.6, bottom: -21.6, width: 6, seed: 9)

        case .shoto:
            seg(ctx, 0, 3.4, 6.2, f, r: 0.9)
            seg(ctx, -3.4, 8.6, 5.2, f)
            hRidges(ctx, top: -6.2, bottom: -11.6, width: 5.2, count: 5, color: rubber, thickness: 0.7)
            dot(ctx, 1.4, -4.8, 0.6, a)
            seg(ctx, -12, 3.8, 6.0, f, r: 1.8)

        case .jagged:
            metal(ctx, poly([(-2.6, -3), (-4.7, 2.8), (-1.1, -0.6)]), f)
            metal(ctx, poly([(2.6, -3), (4.7, 2.8), (1.1, -0.6)]), f)
            seg(ctx, -0.6, 10.2, 5.2, f)
            fill(ctx, rrect(-1.3, top: -2.4, 0.5, 6.8, r: 0.25), a)
            fill(ctx, rrect(0.8, top: -2.4, 0.5, 6.8, r: 0.25), a)
            let grip = rrect(-2.3, top: -10.8, 4.6, 8.4)
            metal(ctx, grip, f.alt, halfWidth: 2.3)
            diagWraps(ctx, top: -11.2, bottom: -18.8, width: 4.6, count: 6, color: rubber, clip: grip)
            metal(ctx, poly([(-2.8, -19.2), (2.8, -19.2), (0, -25)]), f)
            dot(ctx, 0, -20.6, 0.6, a)

        case .angular:
            metal(ctx, poly([(-3.1, 1.0), (3.1, -1.4), (3.1, -5), (-3.1, -5)]), f)
            seg(ctx, -5, 12.6, 6.2, f, r: 0.25)
            fill(ctx, rrect(-1.8, top: -6.4, 3.6, 5, r: 0.3), f.dark, 0.75)
            fill(ctx, rrect(-0.3, top: -6.9, 0.6, 4, r: 0.3), a, 0.9)
            hRidges(ctx, top: -12.2, bottom: -17.4, width: 6.2, count: 5, color: rubber, thickness: 0.7)
            metal(ctx, poly([(-3.1, -17.6), (3.1, -17.6), (3.1, -21.6), (-3.1, -23.2)]), f)

        case .ornate:
            seg(ctx, 0, 4, 6.2, f, r: 0.9)
            fill(ctx, rrect(-3.1, top: -0.4, 6.2, 0.9, r: 0.2), a)
            let hg = CGMutablePath()
            hg.move(to: CGPoint(x: -2.9, y: -4))
            hg.addQuadCurve(to: CGPoint(x: -2.9, y: -20), control: CGPoint(x: -1.1, y: -12))
            hg.addLine(to: CGPoint(x: 2.9, y: -20))
            hg.addQuadCurve(to: CGPoint(x: 2.9, y: -4), control: CGPoint(x: 1.1, y: -12))
            hg.closeSubpath()
            metal(ctx, hg, f, halfWidth: 2.9)
            ctx.saveGState()
            ctx.addPath(hg)
            ctx.clip()
            fill(ctx, rrect(-3, top: -8, 6, 1, r: 0.2), a)
            fill(ctx, rrect(-3, top: -15.6, 6, 1, r: 0.2), a)
            ctx.restoreGState()
            seg(ctx, -20, 4, 5.8, f, r: 1.2)
            fill(ctx, rrect(-2.9, top: -23.2, 5.8, 0.8, r: 0.3), a)

        case .banded:
            seg(ctx, 0, 4, 6.4, f, r: 1)
            fill(ctx, rrect(-3.3, top: -4, 6.6, 1.4, r: 0.3), a)
            let wrap = rrect(-2.95, top: -5.4, 5.9, 8.2, r: 0.4)
            fill(ctx, wrap, leather)
            diagWraps(ctx, top: -5.6, bottom: -13.4, width: 5.9, count: 6, color: leather.mix(.black, 0.45), clip: wrap)
            fill(ctx, rrect(-3.2, top: -13.6, 6.4, 1.2, r: 0.3), a)
            seg(ctx, -14.8, 5.4, 6.4, f, r: 1.4)
            ctx.setStrokeColor(a.cg())
            ctx.setLineWidth(0.4)
            ctx.strokeEllipse(in: CGRect(x: -1.3, y: -18.8, width: 2.6, height: 2.6))
            dot(ctx, 0, -17.5, 0.4, a)

        case .worn:
            metal(ctx, poly([(-3.6, 0.1), (-1, 0.6), (3.5, 0.2), (3.9, -4.6), (-3.4, -4.9)]), f)
            seg(ctx, -4.9, 5.2, 5.8, f)
            ctx.setFillColor(f.dark.cg(0.7))
            ctx.fillEllipse(in: CGRect(x: -2.2, y: -7.6, width: 1.3, height: 0.9))
            ctx.fillEllipse(in: CGRect(x: 1.1, y: -9.2, width: 0.9, height: 0.7))
            dot(ctx, 1.6, -6.4, 0.5, a)
            let wrap = rrect(-2.95, top: -10.1, 5.9, 9.6, r: 0.5)
            fill(ctx, wrap, rag)
            diagWraps(ctx, top: -10.3, bottom: -19.5, width: 5.9, count: 7, color: rag.mix(.black, 0.5), clip: wrap)
            metal(ctx, poly([(-3, -19.7), (3.1, -19.7), (3.3, -22.4), (-2.6, -23.6)]), f)
            scratches(ctx, top: 0, bottom: -10, width: 6, seed: 21)

        case .darksaber:
            // Silver guard with a curved hook, silver upper body with stepped panel lines,
            // darker grip with thin accent stripes, flat silver end cap.
            let hook = CGMutablePath()
            hook.move(to: CGPoint(x: 3.2, y: -0.4))
            hook.addCurve(to: CGPoint(x: 3.0, y: -6.2), control1: CGPoint(x: 6.4, y: -1.2), control2: CGPoint(x: 6.2, y: -5.6))
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineWidth(0.75)
            ctx.setStrokeColor(f.dark.mix(.black, 0.4).cg())
            ctx.addPath(hook)
            ctx.strokePath()
            ctx.setLineWidth(0.45)
            ctx.setStrokeColor(f.light.cg())
            ctx.addPath(hook)
            ctx.strokePath()
            ctx.restoreGState()
            seg(ctx, 0.3, 2.6, 7.2, f, r: 0.3)
            for x in [-2.4, -0.8, 0.8, 2.4] as [CGFloat] {
                fill(ctx, rrect(x - 0.18, top: 0.0, 0.36, 2.0, r: 0.1), f.dark, 0.8)
            }
            seg(ctx, -2.3, 9.2, 5.8, f, r: 0.3)
            ctx.saveGState()
            ctx.setStrokeColor(RGB(0.06, 0.06, 0.07).cg(0.9))
            ctx.setLineWidth(0.4)
            ctx.setLineJoin(.miter)
            ctx.addLines(between: [CGPoint(x: -1.6, y: -3.2), CGPoint(x: -1.6, y: -7.4), CGPoint(x: 0.9, y: -8.4), CGPoint(x: 0.9, y: -11.0)])
            ctx.addLines(between: [CGPoint(x: -0.4, y: -3.2), CGPoint(x: -0.4, y: -6.6), CGPoint(x: 2.0, y: -7.6), CGPoint(x: 2.0, y: -11.0)])
            ctx.strokePath()
            ctx.restoreGState()
            let grip = rrect(-2.8, top: -11.5, 5.6, 8.0, r: 0.3)
            metal(ctx, grip, .black, halfWidth: 2.8)
            hRidges(ctx, top: -11.8, bottom: -14.6, width: 5.6, count: 3, color: rubber, thickness: 0.5)
            for y in [-15.6, -16.5, -17.4] as [CGFloat] {
                fill(ctx, rrect(-2.8, top: y, 5.6, 0.32, r: 0.1), a, 0.95)
            }
            seg(ctx, -19.5, 2.6, 5.3, f, r: 0.9)

        case .ancient:
            // Gold crossguard with upturned curls, tapered brown grip with gold scrollwork, flared crescent pommel.
            let grip = RGB(0.33, 0.19, 0.09)
            let gold = f.base.mix(f.light, 0.3)
            for sx in [CGFloat(-1), 1] {
                let curl = CGMutablePath()
                curl.move(to: CGPoint(x: sx * 3.0, y: -0.4))
                curl.addCurve(to: CGPoint(x: sx * 4.5, y: 1.6), control1: CGPoint(x: sx * 4.6, y: -0.6), control2: CGPoint(x: sx * 4.9, y: 0.6))
                curl.addCurve(to: CGPoint(x: sx * 3.7, y: 2.3), control1: CGPoint(x: sx * 4.2, y: 2.4), control2: CGPoint(x: sx * 3.8, y: 2.5))
                ctx.saveGState()
                ctx.setLineCap(.round)
                ctx.addPath(curl)
                ctx.setStrokeColor(f.dark.mix(.black, 0.3).cg())
                ctx.setLineWidth(0.95)
                ctx.strokePath()
                ctx.addPath(curl)
                ctx.setStrokeColor(gold.cg())
                ctx.setLineWidth(0.6)
                ctx.strokePath()
                ctx.restoreGState()
                dot(ctx, sx * 3.7, 2.3, 0.45, gold)
            }
            metal(ctx, rrect(-3.4, top: 0.3, 6.8, 1.6, r: 0.6), f, halfWidth: 3.4)
            let gp = poly([(-2.1, -1.3), (2.1, -1.3), (1.75, -12.6), (-1.75, -12.6)])
            ctx.saveGState()
            ctx.addPath(gp)
            ctx.clip()
            let gg = CGGradient(colorsSpace: srgb, colors: [grip.mix(.black, 0.4).cg(), grip.mix(.white, 0.25).cg(), grip.cg(), grip.mix(.black, 0.3).cg()] as CFArray,
                                locations: [0, 0.3, 0.6, 1])!
            ctx.drawLinearGradient(gg, start: CGPoint(x: -2.1, y: 0), end: CGPoint(x: 2.1, y: 0), options: [])
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setStrokeColor(a.cg(0.95))
            ctx.setLineWidth(0.35)
            ctx.setLineCap(.round)
            ctx.strokeEllipse(in: CGRect(x: -0.8, y: -3.8, width: 1.6, height: 1.6))
            ctx.strokeEllipse(in: CGRect(x: -0.8, y: -5.3, width: 1.6, height: 1.6))
            for top in [CGFloat(-6.3), -9.3] {
                ctx.move(to: CGPoint(x: -1.1, y: top))
                ctx.addCurve(to: CGPoint(x: 1.1, y: top - 2.4), control1: CGPoint(x: 1.6, y: top - 0.2), control2: CGPoint(x: -1.6, y: top - 2.2))
            }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(gp)
            ctx.setStrokeColor(grip.mix(.black, 0.6).cg(0.9))
            ctx.setLineWidth(0.3)
            ctx.strokePath()
            metal(ctx, rrect(-2.0, top: -12.4, 4.0, 1.0, r: 0.4), f, halfWidth: 2)
            let pommel = CGMutablePath()
            pommel.move(to: CGPoint(x: -1.5, y: -13.2))
            pommel.addLine(to: CGPoint(x: -1.8, y: -14.2))
            pommel.addCurve(to: CGPoint(x: -3.4, y: -16.4), control1: CGPoint(x: -2.6, y: -14.6), control2: CGPoint(x: -3.4, y: -15.4))
            pommel.addCurve(to: CGPoint(x: 0, y: -15.6), control1: CGPoint(x: -2.2, y: -16.6), control2: CGPoint(x: -1.0, y: -15.6))
            pommel.addCurve(to: CGPoint(x: 3.4, y: -16.4), control1: CGPoint(x: 1.0, y: -15.6), control2: CGPoint(x: 2.2, y: -16.6))
            pommel.addCurve(to: CGPoint(x: 1.8, y: -14.2), control1: CGPoint(x: 3.4, y: -15.4), control2: CGPoint(x: 2.6, y: -14.6))
            pommel.addLine(to: CGPoint(x: 1.5, y: -13.2))
            pommel.closeSubpath()
            metal(ctx, pommel, f, halfWidth: 3.4)

        case .inquisitor:
            let center = CGPoint(x: 0, y: -8.2)
            let ring = CGMutablePath()
            ring.addEllipse(in: CGRect(x: center.x - 7.4, y: center.y - 7.4, width: 14.8, height: 14.8))
            ring.addEllipse(in: CGRect(x: center.x - 5.2, y: center.y - 5.2, width: 10.4, height: 10.4))
            ctx.saveGState()
            ctx.addPath(ring)
            ctx.clip(using: .evenOdd)
            let g = CGGradient(colorsSpace: srgb, colors: [f.light.cg(), f.base.cg(), f.dark.cg()] as CFArray, locations: [0, 0.45, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: -7, y: center.y + 7), end: CGPoint(x: 7, y: center.y - 7), options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(f.dark.mix(.black, 0.5).cg(0.9))
            ctx.setLineWidth(0.3)
            ctx.addPath(ring)
            ctx.strokePath()
            let spin = CGFloat(time * 2.2)
            for i in 0..<6 {
                let ang = spin + CGFloat(i) * .pi / 3
                let dotR: CGFloat = i % 2 == 0 ? 0.75 : 0.5
                dot(ctx, center.x + cos(ang) * 6.3, center.y + sin(ang) * 6.3, dotR, i % 2 == 0 ? a : f.dark)
            }
            metal(ctx, rrect(-1.6, top: -1.6, 3.2, 13.2, r: 0.8), f.alt, halfWidth: 1.6)
            hRidges(ctx, top: -5, bottom: -11.4, width: 3.2, count: 5, color: rubber, thickness: 0.55)
            seg(ctx, 0.2, 2.8, 4.6, f, r: 0.6)

        case .staff:
            seg(ctx, 0, 3.6, 6.4, f, r: 0.8)
            fill(ctx, rrect(-2.2, top: -1.0, 4.4, 1.2, r: 0.3), rubber, 0.8)
            seg(ctx, -3.6, 26.2, 5.4, f)
            for y in [-6.0, -9.0, -24.0, -27.0] as [CGFloat] {
                fill(ctx, rrect(-2.85, top: y, 5.7, 0.9, r: 0.3), a, 0.9)
            }
            hRidges(ctx, top: -11.6, bottom: -21.4, width: 5.4, count: 9, color: rubber, thickness: 0.6)
            dot(ctx, 1.4, -7.5, 0.55, RGB(hex: 0xE0332B))
            seg(ctx, -29.8, 3.6, 6.4, f, r: 0.8)
            fill(ctx, rrect(-2.2, top: -31.4, 4.4, 1.2, r: 0.3), rubber, 0.8)

        case .clawed:
            let left = CGMutablePath()
            left.move(to: CGPoint(x: -2.2, y: -3.2))
            left.addCurve(to: CGPoint(x: -4.2, y: 2.4), control1: CGPoint(x: -4.6, y: -2.2), control2: CGPoint(x: -5.2, y: 0.6))
            left.addCurve(to: CGPoint(x: -1.6, y: -1.0), control1: CGPoint(x: -3.4, y: 0.8), control2: CGPoint(x: -2.4, y: -0.2))
            left.closeSubpath()
            var mirror = CGAffineTransform(scaleX: -1, y: 1)
            let right = left.copy(using: &mirror)!
            metal(ctx, left, f, halfWidth: 4.5)
            metal(ctx, right, f, halfWidth: 4.5)
            seg(ctx, 0, 3.4, 4.2, f, r: 0.6)
            seg(ctx, -3.4, 6.2, 5.6, f)
            metal(ctx, poly([(0, -4.4), (1.5, -6.5), (0, -8.6), (-1.5, -6.5)]), f.alt, halfWidth: 1.5)
            dot(ctx, 0, -6.5, 0.5, a)
            let grip = rrect(-2.5, top: -9.6, 5.0, 10)
            metal(ctx, grip, f.alt, halfWidth: 2.5)
            diagWraps(ctx, top: -9.8, bottom: -19.4, width: 5.0, count: 7, color: rubber, clip: grip)
            metal(ctx, poly([(-2.8, -19.6), (2.8, -19.6), (2.1, -22.8), (0, -25), (-2.1, -22.8)]), f)
            fill(ctx, rrect(-2.8, top: -19.6, 5.6, 0.8, r: 0.2), a, 0.9)
        }
    }

    // MARK: Click spark

    static func renderSpark(progress p: Double, color: RGB, scale: CGFloat, backing: CGFloat) -> RenderedImage? {
        let side = ceil(56 * scale)
        let size = CGSize(width: side, height: side)
        guard let ctx = makeContext(size, backing: backing) else { return nil }
        let q = CGFloat(min(1, max(0, p)))
        let center = CGPoint(x: side / 2, y: side / 2)
        let fade = 1 - q
        let hot = color.mix(.white, 0.55)
        ctx.setShadow(offset: .zero, blur: 5 * scale * backing, color: color.cg(fade))
        ctx.setLineCap(.round)
        for i in 0..<10 {
            let ang = CGFloat(i) * (.pi / 5) + (hash(i, 42) - 0.5) * 0.5
            let r0 = (2 + 12 * q) * scale
            let r1 = r0 + (7 * (1 - q) + 2 + 3 * hash(i, 8)) * scale
            ctx.setStrokeColor(hot.cg(fade))
            ctx.setLineWidth((1.4 * (1 - q) + 0.3) * scale)
            ctx.move(to: CGPoint(x: center.x + cos(ang) * r0, y: center.y + sin(ang) * r0))
            ctx.addLine(to: CGPoint(x: center.x + cos(ang) * r1, y: center.y + sin(ang) * r1))
            ctx.strokePath()
        }
        let fr = 5.5 * scale * (1 - q)
        ctx.setFillColor(RGB.white.cg(0.9 * fade))
        ctx.fillEllipse(in: CGRect(x: center.x - fr, y: center.y - fr, width: 2 * fr, height: 2 * fr))
        guard let img = ctx.makeImage() else { return nil }
        return RenderedImage(image: img, size: size, anchor: center)
    }
}
