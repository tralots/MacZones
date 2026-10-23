// Renders the MacZones app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: ~824/1024 body, continuous-ish corners.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.22, blue: 0.85, alpha: 1),
                        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)])!
        .draw(in: shape, angle: -55)

    // Subtle top sheen.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Priority-grid zones: left, big highlighted center, right split in two.
    let area = body.insetBy(dx: body.width * 0.15, dy: body.width * 0.17)
    let gap = body.width * 0.04
    let r = body.width * 0.045
    let side = (area.width - gap * 2) * 0.25
    let center = area.width - gap * 2 - side * 2
    let half = (area.height - gap) / 2

    func zone(_ rect: NSRect, _ alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
    }
    zone(NSRect(x: area.minX, y: area.minY, width: side, height: area.height), 0.30)
    zone(NSRect(x: area.minX + side + gap, y: area.minY, width: center, height: area.height), 0.96)
    zone(NSRect(x: area.maxX - side, y: area.minY + half + gap, width: side, height: half), 0.30)
    zone(NSRect(x: area.maxX - side, y: area.minY, width: side, height: half), 0.48)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: output.appendingPathComponent(name))
    }
}
print("Wrote \(output.path)")
