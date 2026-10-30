// Renders Resources/Clipt.iconset (then `make icon` turns it into Clipt.icns):
// a white clipboard on a blue-to-violet glass squircle.
import AppKit

let iconset = URL(fileURLWithPath: "Resources/Clipt.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ h: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

/// The macOS icon grid: an 824-pt squircle centred on a 1024-pt canvas, with the
/// continuous (superellipse-like) corner Apple uses rather than a plain rounded rect.
func squircle(_ s: CGFloat) -> NSBezierPath {
    let inset = s * 100 / 1024
    let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let n = 5.0, steps = 240
    let p = NSBezierPath()
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), sn = sin(t)
        let x = r.midX + r.width / 2 * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = r.midY + r.height / 2 * CGFloat(copysign(pow(abs(sn), 2 / n), sn))
        if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
    }
    p.close()
    return p
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func icon(_ s: CGFloat) {
    let body = squircle(s)
    let ctx = NSGraphicsContext.current!.cgContext

    // Contact shadow under the tile.
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    rgb(0x4B4FE0).setFill()
    body.fill()
    ctx.restoreGState()

    // Blue-to-violet base.
    NSGradient(colors: [rgb(0x38A0FF), rgb(0x5B63F2), rgb(0x8F4DEB)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -55)

    // Everything else is glass, clipped to the tile.
    ctx.saveGState()
    body.addClip()

    // Soft light bloom from the top left.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: s * 0.30, y: s * 0.86), radius: 0,
              toCenter: NSPoint(x: s * 0.30, y: s * 0.86), radius: s * 0.62, options: [])
    // Glass sheen: a pale cap over the upper half with a curved lower edge.
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: 0, y: s))
    sheen.line(to: NSPoint(x: s, y: s))
    sheen.line(to: NSPoint(x: s, y: s * 0.66))
    sheen.curve(to: NSPoint(x: 0, y: s * 0.60),
                controlPoint1: NSPoint(x: s * 0.70, y: s * 0.52), controlPoint2: NSPoint(x: s * 0.30, y: s * 0.52))
    sheen.close()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: sheen, angle: -90)
    // Darker lower edge for depth.
    NSGradient(colors: [NSColor.black.withAlphaComponent(0), rgb(0x1B1470, 0.35)])!
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s * 0.45), angle: -90)
    ctx.restoreGState()

    // Glass rim: bright at the top, faint at the bottom.
    ctx.saveGState()
    body.addClip()
    let rim = squircle(s)
    rim.lineWidth = s * 0.008
    ctx.setBlendMode(.normal)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setStroke()
    rim.stroke()
    ctx.setBlendMode(.sourceIn)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0.30)])!
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // The clipboard.
    let bw = s * 0.42, bh = s * 0.53
    let board = NSRect(x: (s - bw) / 2, y: s * 0.5 - bh / 2 - s * 0.015, width: bw, height: bh)
    ctx.saveGState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = rgb(0x1B1470, 0.45)
    glyphShadow.shadowBlurRadius = s * 0.035
    glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.016)
    glyphShadow.set()
    let boardPath = rounded(board, s * 0.055)
    NSGradient(colors: [NSColor.white, rgb(0xE8EBFF)])!.draw(in: boardPath, angle: -90)
    ctx.restoreGState()

    // Clip: a plate that overlaps the top edge, with the metal jaw cut into it.
    let cw = s * 0.21, ch = s * 0.10
    let clip = NSRect(x: (s - cw) / 2, y: board.maxY - ch * 0.58, width: cw, height: ch)
    ctx.saveGState()
    let clipShadow = NSShadow()
    clipShadow.shadowColor = rgb(0x1B1470, 0.35)
    clipShadow.shadowBlurRadius = s * 0.012
    clipShadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
    clipShadow.set()
    NSGradient(colors: [rgb(0x7F8CF5), rgb(0x5B4FDB)])!.draw(in: rounded(clip, s * 0.03), angle: -90)
    ctx.restoreGState()
    NSColor.white.setFill()
    rounded(NSRect(x: s / 2 - s * 0.028, y: clip.maxY - s * 0.045, width: s * 0.056, height: s * 0.026), s * 0.013).fill()

    // Text lines, tinted from the tile so the glyph feels part of it.
    let lineH = s * 0.032, left = board.minX + bw * 0.16
    let widths: [CGFloat] = [0.68, 0.68, 0.68, 0.40]
    for (i, w) in widths.enumerated() {
        let y = board.maxY - bh * 0.31 - CGFloat(i) * s * 0.078
        let r = NSRect(x: left, y: y, width: bw * w, height: lineH)
        NSGradient(colors: [rgb(0x5B63F2, 0.55), rgb(0x8F4DEB, 0.55)])!.draw(in: rounded(r, lineH / 2), angle: 0)
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    let data = render(px)
    if px <= 512 { try data.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try data.write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
    if px == 1024 { try data.write(to: URL(fileURLWithPath: "docs/icon.png")) }
}
