import AppKit
import ImageIO
import UniformTypeIdentifiers

/// `LightsaberCursor --render-sheet out.png` draws every preset, hilt and state for visual review.
enum ContactSheet {
    static func render(to path: String) {
        let presets = Presets.all
        let cols = 6
        let cellW: CGFloat = 190
        let cellH: CGFloat = 200
        let sabersRows = Int(ceil(Double(presets.count) / Double(cols)))
        let hiltRowH: CGFloat = 70
        let stateRowH: CGFloat = 200
        let width = CGFloat(cols) * cellW
        let hiltRows = Int(ceil(Double(HiltStyle.allCases.count) / Double(cols)))
        let height = CGFloat(sabersRows) * cellH + hiltRowH * CGFloat(hiltRows) + stateRowH
        let backing: CGFloat = 2
        guard let ctx = SaberRenderer.makeContext(CGSize(width: width, height: height), backing: backing) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = ns

        func label(_ s: String, _ x: CGFloat, _ y: CGFloat) {
            (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            ])
        }

        func place(_ r: RenderedImage?, in cell: CGRect) {
            guard let r else { return }
            let x = cell.midX - r.size.width / 2
            let y = cell.midY - r.size.height / 2 + 8
            ctx.draw(r.image, in: CGRect(x: x, y: y, width: r.size.width, height: r.size.height))
        }

        for (i, p) in presets.enumerated() {
            let col = i % cols
            let row = i / cols
            let cell = CGRect(x: CGFloat(col) * cellW, y: height - CGFloat(row + 1) * cellH, width: cellW, height: cellH)
            place(SaberRenderer.render(p, SaberState(ext: 1, time: 0.3), scale: 1.25, backing: backing), in: cell)
            label(p.name, cell.minX + 6, cell.minY + 4)
        }

        let hiltTop = height - CGFloat(sabersRows) * cellH
        var base = Presets.defaultSaber
        for (i, h) in HiltStyle.allCases.enumerated() {
            base.hilt = h
            base.finish = HiltFinish.allCases[i % HiltFinish.allCases.count]
            let col = i % cols
            let row = i / cols
            let cell = CGRect(x: CGFloat(col) * cellW, y: hiltTop - CGFloat(row + 1) * hiltRowH, width: cellW, height: hiltRowH)
            place(SaberRenderer.renderHiltIcon(base, height: 36, backing: backing), in: cell)
            label("\(h.displayName) / \(base.finish.displayName)", cell.minX + 6, cell.minY + 4)
        }

        let states: [(String, SaberState)] = [
            ("Extended", SaberState(ext: 1)),
            ("Retracting", SaberState(ext: 0.45)),
            ("Retracted", SaberState(ext: 0)),
        ]
        let stateTop = hiltTop - hiltRowH * CGFloat(hiltRows)
        for (i, (name, st)) in states.enumerated() {
            let cell = CGRect(x: CGFloat(i) * cellW, y: stateTop - stateRowH, width: cellW, height: stateRowH)
            place(SaberRenderer.render(Presets.vader, st, scale: 1.25, backing: backing), in: cell)
            label("Vader – \(name)", cell.minX + 6, cell.minY + 4)
        }
        let sparkCell = CGRect(x: 3 * cellW, y: stateTop - stateRowH, width: cellW, height: stateRowH)
        place(SaberRenderer.renderSpark(progress: 0.3, color: Presets.obiWan.blade, scale: 1.5, backing: backing), in: sparkCell)
        label("Click spark", sparkCell.minX + 6, sparkCell.minY + 4)

        NSGraphicsContext.current = nil
        guard let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(path)")
    }
}
