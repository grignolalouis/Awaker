// Renders Assets/logo-mark.svg into a macOS app icon (paper squircle + ink mark).
// Usage: swift Scripts/make-icon.swift Assets/logo-mark.svg build/AppIcon.iconset
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let mark = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-icon.swift <logo.svg> <out.iconset>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824 pt squircle centered on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 186 * s, yRadius: 186 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Subtle paper gradient.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0)])!
        .draw(in: path, angle: -90)

    // Ink mark, about 74 % of the tile height, centered.
    let h = 824 * s * 0.74
    let w = h * mark.size.width / mark.size.height
    mark.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h),
              from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(outDir.path)")
