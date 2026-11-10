// Renders the picture shown behind the icons when Awaker.dmg is opened: the app's backdrop, blurred,
// with an arrow from the app (left) to the Applications folder (right).
// Usage: swift Scripts/make-dmg-background.swift Assets/Backdrop/backdrop.jpg Assets/dmg-background.png
// Writes the picture and its @2x version. The sizes and icon positions match Scripts/dmg-settings.py.
import AppKit
import CoreImage

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = CIImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    print("usage: make-dmg-background.swift <backdrop.jpg> <out.png>")
    exit(1)
}

/// The window's content, in points. Icons are centred at y = 180 from the top, x = 170 and x = 490.
let window = CGSize(width: 660, height: 400)
let iconRow: CGFloat = 180

func render(scale: CGFloat, to path: String) {
    let pixels = CGSize(width: window.width * scale, height: window.height * scale)
    // Fill the window with the upper part of the illustration (the sky), blurred until it is only colour.
    // Zoomed in so the pale horizon stays below the icons' names: Finder writes them in black or in white
    // depending on the Mac's appearance, not on the picture, so the picture must be mid-toned behind them.
    let fill = max(pixels.width / source.extent.width, pixels.height / source.extent.height) * 1.6
    let scaled = source.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
    let crop = CGRect(x: (scaled.extent.width - pixels.width) / 2, y: scaled.extent.height - pixels.height,
                      width: pixels.width, height: pixels.height)
    let blurred = scaled.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28 * scale])
        .cropped(to: crop)
    let context = CIContext()
    guard let background = context.createCGImage(blurred, from: crop) else { fatalError("could not render the backdrop") }

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = window
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let drawing = NSGraphicsContext.current!.cgContext
    drawing.draw(background, in: CGRect(origin: .zero, size: window))
    NSColor.black.withAlphaComponent(0.22).setFill()
    NSRect(origin: .zero, size: window).fill()

    // The arrow, halfway between the two icons. AppKit's origin is at the bottom.
    let y = window.height - iconRow
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 290, y: y))
    arrow.line(to: NSPoint(x: 366, y: y))
    arrow.move(to: NSPoint(x: 346, y: y + 20))
    arrow.line(to: NSPoint(x: 368, y: y))
    arrow.line(to: NSPoint(x: 346, y: y - 20))
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 8
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.white.withAlphaComponent(0.92).setStroke()
    arrow.stroke()

    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

let output = arguments[2]
render(scale: 1, to: output)
render(scale: 2, to: output.replacingOccurrences(of: ".png", with: "@2x.png"))
