// Renders the README banner: the mark and the app's name in black on white.
// Usage: swift Scripts/make-banner.swift Assets/logo-mark.svg Assets/banner.png
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let mark = NSImage(contentsOfFile: arguments[1]) else {
    print("usage: make-banner.swift <logo.svg> <out.png>")
    exit(1)
}
let size = NSSize(width: 1600, height: 400)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

let name = NSAttributedString(string: "Awaker", attributes: [
    .font: NSFont.systemFont(ofSize: 112, weight: .medium),
    .foregroundColor: NSColor.black,
    .kern: -2,
])
let markHeight: CGFloat = 132
let markSize = NSSize(width: markHeight * mark.size.width / mark.size.height, height: markHeight)
let gap: CGFloat = 36
let textSize = name.size()
let originX = (size.width - (markSize.width + gap + textSize.width)) / 2

mark.draw(in: NSRect(x: originX, y: (size.height - markSize.height) / 2, width: markSize.width, height: markSize.height))
name.draw(at: NSPoint(x: originX + markSize.width + gap, y: (size.height - textSize.height) / 2))

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("Wrote \(arguments[2])")
