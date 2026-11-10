// Renders the mascot wearing each skin of a skins.json file to a PNG contact sheet:
// a large view to judge the drawing and a small one at about the size it has in the app.
//
// Usage: swift Scripts/preview-skins.swift <skins.json> <out.png>
import AppKit

struct Skin: Decodable {
    struct Layer: Decodable {
        let color: String
        let rows: [String]
    }
    let name: String
    let layers: [Layer]
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let data = FileManager.default.contents(atPath: arguments[1]),
      let skins = try? JSONDecoder().decode([Skin].self, from: data) else {
    print("usage: preview-skins.swift <skins.json> <out.png>  (or the JSON is invalid)")
    exit(1)
}

let columns = 18, gridRows = 14
let head = "...############...", eyes = "...##.######.##...", arms = ".################.", legs = "....#.#....#.#...."
let body = Array(repeating: String(repeating: ".", count: columns), count: 4) + [head, head, eyes, eyes, arms, arms, head, head, legs, legs]

for skin in skins {
    for layer in skin.layers {
        if layer.rows.count > gridRows || layer.rows.contains(where: { $0.count != columns }) {
            print("warning: \(skin.name) has a layer that is not \(columns) wide or has more than \(gridRows) rows")
        }
    }
}

func color(_ hex: String) -> NSColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

let perRow = 4, large: CGFloat = 12, small: CGFloat = 3.5, pad: CGFloat = 24
let tile = CGSize(width: CGFloat(columns) * large + pad * 2, height: CGFloat(gridRows) * large + pad * 2 + 80)
let sheetRows = (skins.count + perRow - 1) / perRow
let size = NSSize(width: tile.width * CGFloat(perRow), height: tile.height * CGFloat(sheetRows))
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// The app's glass panel over the backdrop is roughly this dark teal.
NSColor(srgbRed: 0.13, green: 0.30, blue: 0.34, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func draw(_ rows: [String], _ fill: NSColor, at origin: CGPoint, cell: CGFloat) {
    fill.setFill()
    for (y, row) in rows.enumerated() {
        for (x, character) in row.enumerated() where character == "#" {
            // Flipped by hand: row 0 is the top.
            NSRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(gridRows - 1 - y) * cell, width: cell, height: cell).fill()
        }
    }
}

let orange = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
for (index, skin) in skins.enumerated() {
    let tileOrigin = CGPoint(x: CGFloat(index % perRow) * tile.width, y: size.height - CGFloat(index / perRow + 1) * tile.height)
    for (cell, origin) in [(large, CGPoint(x: tileOrigin.x + pad, y: tileOrigin.y + 80)),
                           (small, CGPoint(x: tileOrigin.x + pad, y: tileOrigin.y + 22))] {
        draw(body, orange, at: origin, cell: cell)
        for layer in skin.layers { draw(layer.rows, color(layer.color), at: origin, cell: cell) }
    }
    (skin.name as NSString).draw(at: CGPoint(x: tileOrigin.x + pad + 80, y: tileOrigin.y + 36),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white])
}
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("Wrote \(arguments[2]) (\(skins.count) skins)")
