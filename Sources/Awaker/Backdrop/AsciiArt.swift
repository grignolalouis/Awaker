import AppKit
import CoreText

// Shape-aware ASCII art.
//
// Each character cell is split into 3 × 5 sub-cells. Where the picture has structure inside a cell
// (an edge, a stroke), the cell gets the character whose own strokes best match it, so a cloud's
// edge becomes `/`, `\`, `(` or `_` rather than a denser dot. Flat cells use a classic density ramp.
// Each character is drawn in the color of the pixels it covers.
//
// The approach follows asciify-engine's "shape" mode (github.com/ayangabryl/asciify-engine, MIT);
// the code and the glyph table, measured here from the system monospaced font, are our own.

/// The characters available, with where each one puts its ink.
struct GlyphSet {
    static let subColumns = 3
    static let subRows = 5
    static let subCount = subColumns * subRows

    /// Symbols with enough ink to fill their cell. Dots, commas, quotes and dashes are left out: the owner
    /// found they left the picture looking empty. The space stays first: the code relies on index 0 being blank.
    private static let characters: [Character] = Array(" =+*<>|/\\()[]{}#%@&$")
    /// Density ramp for flat areas, from lightest to fullest. No space: every cell gets a character,
    /// so the darkest parts of the picture are drawn too (in their own dark color) instead of left empty.
    private static let rampCharacters: [Character] = Array("+*#%&@")

    let cell: CGSize
    let font: NSFont
    /// Offset of a glyph's baseline origin inside its cell, from the cell's bottom-left corner.
    let inset: CGPoint
    /// One laid-out line per character. The color comes from the drawing context.
    let lines: [CTLine]
    /// Per character, its ink in each sub-cell scaled to its own peak: a stroke compares as a stroke.
    let shapes: [[Float]]
    /// The same, end to end (`subCount` values per character), for the inner loop of the renderer.
    let flatShapes: [Float]
    /// Per character, its overall ink, scaled so the densest character is 1.
    let ink: [Float]
    /// Indices of the density ramp, in ramp order.
    let ramp: [Int]

    init(cell: CGSize, font: NSFont) {
        self.cell = cell
        self.font = font
        let glyphInset = CGPoint(x: (cell.width - font.maximumAdvancement.width) / 2, y: (cell.height - font.capHeight) / 2)
        inset = glyphInset
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let glyphLines = Self.characters.map {
            CTLineCreateWithAttributedString(NSAttributedString(string: String($0), attributes: attributes))
        }
        lines = glyphLines
        let coverage = glyphLines.map { Self.coverage(of: $0, cell: cell, inset: glyphInset) }
        shapes = coverage.map { values in
            let peak = values.max() ?? 0
            return peak > 0 ? values.map { $0 / peak } : values
        }
        flatShapes = shapes.flatMap { $0 }
        let means = coverage.map { $0.reduce(0, +) / Float(Self.subCount) }
        let densest = max(means.max() ?? 1, 0.0001)
        ink = means.map { $0 / densest }
        ramp = Self.rampCharacters.compactMap { Self.characters.firstIndex(of: $0) }
    }

    /// Every glyph as an alpha mask at pixel size, drawn once per display scale. Frames are then composed
    /// by copying these masks, which is far cheaper than asking CoreText to draw each character every frame.
    func masks(scale: CGFloat) -> GlyphMasks {
        let width = Int((cell.width * scale).rounded()), height = Int((cell.height * scale).rounded())
        let alphas = lines.map { line -> [UInt8] in
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return [UInt8](repeating: 0, count: width * height)
            }
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(gray: 1, alpha: 1)
            context.textPosition = inset
            CTLineDraw(line, context)
            guard let data = context.data?.bindMemory(to: UInt8.self, capacity: width * height) else {
                return [UInt8](repeating: 0, count: width * height)
            }
            return Array(UnsafeBufferPointer(start: data, count: width * height))
        }
        return GlyphMasks(scale: scale, width: width, height: height, alphas: alphas)
    }

    /// Draws the glyph enlarged in its cell and measures the ink in each sub-cell (0…1, row by row from the top).
    private static func coverage(of line: CTLine, cell: CGSize, inset: CGPoint) -> [Float] {
        let scale: CGFloat = 8
        let width = Int(cell.width * scale), height = Int(cell.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return [Float](repeating: 0, count: subCount)
        }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(gray: 1, alpha: 1)
        context.textPosition = inset
        CTLineDraw(line, context)
        guard let data = context.data?.bindMemory(to: UInt8.self, capacity: width * height) else {
            return [Float](repeating: 0, count: subCount)
        }
        var values = [Float](repeating: 0, count: subCount)
        let subWidth = width / subColumns, subHeight = height / subRows
        for subRow in 0..<subRows {
            for subColumn in 0..<subColumns {
                var total = 0
                for y in (subRow * subHeight)..<((subRow + 1) * subHeight) {
                    for x in (subColumn * subWidth)..<((subColumn + 1) * subWidth) {
                        total += Int(data[y * width + x])
                    }
                }
                values[subRow * subColumns + subColumn] = Float(total) / Float(subWidth * subHeight * 255)
            }
        }
        return values
    }
}

/// Alpha masks of every glyph for one display scale. Row 0 is the top.
struct GlyphMasks {
    let scale: CGFloat
    let width: Int
    let height: Int
    let alphas: [[UInt8]]
}

/// Turns frames into ASCII art bitmaps. Keeps the previous frame's characters to avoid flicker on video.
@MainActor
final class AsciiArtist {
    private let glyphs: GlyphSet
    private var previous: [Int] = []
    private var previousSize: (columns: Int, rows: Int) = (0, 0)
    private var masks: GlyphMasks?
    /// The last bitmap drawn (premultiplied RGBA, row 0 at the top), kept so a frame only repaints the cells
    /// that changed. On a slow video most of the picture is the same from one frame to the next.
    private var canvas: [UInt8] = []
    /// Per cell, what the canvas shows: the glyph and the ink color packed as `glyph << 24 | red << 16 | green << 8 | blue`.
    private var painted: [UInt32] = []
    private var canvasSize: (width: Int, height: Int) = (0, 0)
    /// A cell keeps its paint while its glyph is the same and no color channel moved by more than this (out of 255).
    /// Video compression makes flat areas shimmer by a step or two; repainting them would cost a lot for nothing.
    private let colorTolerance = 3
    /// The screen's colors for the picture's colors. See `ColorTable`.
    private var colors: ColorTable?
    /// The picture's brightness range, measured every few frames rather than on each one.
    private var range: (darkest: Float, brightest: Float)?
    private var framesSinceRange = 0
    private let framesPerRange = 25

    /// A cell has structure when its sub-cells differ by more than this share of its brightness.
    private let structureThreshold: Float = 0.04
    /// Weight of matching the cell's overall brightness against matching its shape.
    private let toneWeight: Float = 3
    /// A character from the previous frame is kept unless a new one beats it by this margin.
    private let keepMargin: Float = 1.12
    /// Characters take the color of the pixels under them, slightly less saturated (below 1 pulls a color
    /// toward its own gray) and a little lighter, so they read as ink on the dimmed image.
    /// Tuned with the owner: 1.8 was garish, 0.6 dull, 0.8 a bit flat, 1 a bit much.
    private let saturation: CGFloat = 0.9
    private let brightness: CGFloat = 1.3

    /// Cells large enough for each character to be read as a character, not as a grain.
    /// Whole points, so cells land on whole pixels at any display scale.
    init(cell: CGSize = CGSize(width: 3, height: 6),
         font: NSFont = .monospacedSystemFont(ofSize: 5, weight: .heavy)) {
        glyphs = GlyphSet(cell: cell, font: font)
    }

    /// The image as ASCII art on a transparent background, for a view of `size` points at `scale`.
    /// The image is cropped as an aspect-fill image centered in the view would be. The bitmap covers whole
    /// cells, so it can be slightly larger than the view: anchor it top-leading and clip.
    func render(_ image: CGImage, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let columns = Int(size.width / glyphs.cell.width) + 1
        let rows = Int(size.height / glyphs.cell.height) + 1
        if framesSinceRange >= framesPerRange { range = nil }
        guard let samples = Samples(image: image, cell: glyphs.cell, columns: columns, rows: rows, knownRange: range) else { return nil }
        if range == nil { framesSinceRange = 0 }
        range = samples.range
        framesSinceRange += 1
        if masks?.scale != scale { masks = glyphs.masks(scale: scale) }
        guard let masks else { return nil }
        // The bitmap is made in the screen's own color space, so showing it costs a copy and no conversion.
        let screenSpace = NSScreen.main?.colorSpace?.cgColorSpace ?? ColorTable.sRGB
        if colors?.space != screenSpace {
            colors = ColorTable(space: screenSpace)
            painted = []
        }
        guard let colors else { return nil }
        if previousSize != (columns, rows) {
            previous = [Int](repeating: -1, count: columns * rows)
            previousSize = (columns, rows)
        }

        let width = columns * masks.width, height = rows * masks.height
        if canvasSize != (width, height) || painted.count != columns * rows {
            canvas = [UInt8](repeating: 0, count: width * height * 4)
            painted = [UInt32](repeating: .max, count: columns * rows)
            canvasSize = (width, height)
        }
        var sub = [Float](repeating: 0, count: GlyphSet.subCount)
        let tolerance = colorTolerance
        canvas.withUnsafeMutableBufferPointer { buffer in
            guard let output = buffer.baseAddress else { return }
            for row in 0..<rows {
                for column in 0..<columns {
                    let cellIndex = row * columns + column
                    let color = samples.read(column: column, row: row, into: &sub)
                    let mean = sub.reduce(0, +) / Float(GlyphSet.subCount)
                    let level = samples.level(of: mean)
                    let glyph = pick(sub: sub, mean: mean, level: level, kept: previous[cellIndex])
                    previous[cellIndex] = glyph

                    let (red, green, blue) = colors.screenColor(for: vivid(color))
                    let old = painted[cellIndex]
                    if Int(old >> 24) == glyph,
                       abs(Int((old >> 16) & 0xFF) - red) <= tolerance,
                       abs(Int((old >> 8) & 0xFF) - green) <= tolerance,
                       abs(Int(old & 0xFF) - blue) <= tolerance {
                        continue
                    }
                    painted[cellIndex] = UInt32(glyph) << 24 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)

                    // Opaque characters, premultiplied: each pixel is the ink color times the glyph's coverage,
                    // and the coverage itself as alpha. `(x * 0x8081) >> 23` is x / 255 for products of two bytes.
                    masks.alphas[glyph].withUnsafeBufferPointer { mask in
                        for y in 0..<masks.height {
                            var target = output + ((row * masks.height + y) * width + column * masks.width) * 4
                            var source = y * masks.width
                            for _ in 0..<masks.width {
                                let coverage = Int(mask[source])
                                target[0] = UInt8((red * coverage * 0x8081) >> 23)
                                target[1] = UInt8((green * coverage * 0x8081) >> 23)
                                target[2] = UInt8((blue * coverage * 0x8081) >> 23)
                                target[3] = UInt8(coverage)
                                target += 4
                                source += 1
                            }
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(canvas) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colors.space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Moves a color away from its own gray or toward it (`saturation` above or below 1), then brightens it,
    /// clamped to the displayable range.
    private func vivid(_ color: Samples.Color) -> Samples.Color {
        let gray = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        func channel(_ value: CGFloat) -> CGFloat {
            min(max((gray + (value - gray) * saturation) * brightness, 0), 1)
        }
        return Samples.Color(red: channel(color.red), green: channel(color.green), blue: channel(color.blue))
    }

    /// The character for one cell: by shape where the cell has structure, by density where it is flat.
    private func pick(sub: [Float], mean: Float, level: Float, kept: Int) -> Int {
        let low = sub.min() ?? 0, high = sub.max() ?? 0
        let variance = sub.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(GlyphSet.subCount)
        guard variance.squareRoot() > structureThreshold * (mean + 0.08), high > low else {
            let position = Int((level * Float(glyphs.ramp.count - 1)).rounded())
            return glyphs.ramp[min(max(position, 0), glyphs.ramp.count - 1)]
        }

        // Push the cell's own contrast to the full range, then find the closest glyph shape.
        // This runs for every structured cell of every frame: plain buffers, no array checks.
        let scale = 1 / (high - low)
        let count = GlyphSet.subCount
        return sub.withUnsafeBufferPointer { cell in
            glyphs.flatShapes.withUnsafeBufferPointer { shapes in
                glyphs.ink.withUnsafeBufferPointer { ink in
                    func score(_ glyph: Int) -> Float {
                        var distance: Float = 0
                        let shape = glyph * count
                        for index in 0..<count {
                            let difference = shapes[shape + index] - (cell[index] - low) * scale
                            distance += difference * difference
                        }
                        let toneMiss = ink[glyph] - level
                        return distance + toneWeight * toneMiss * toneMiss
                    }
                    var best = 1, bestScore = Float.infinity
                    // Index 0 is the space: a structured cell always gets ink.
                    for glyph in 1..<ink.count {
                        let candidate = score(glyph)
                        if candidate < bestScore {
                            best = glyph
                            bestScore = candidate
                        }
                    }
                    if kept > 0, kept != best, score(kept) <= bestScore * keepMargin { return kept }
                    return best
                }
            }
        }
    }
}

/// sRGB colors translated to a screen's color space, by table.
///
/// Handing the window server an sRGB bitmap made it convert every pixel of every frame to the screen's
/// colors, which cost about half of the app's processor time. The art has one color per character, so the
/// conversion is done here per character instead, through a table CoreGraphics fills once per screen.
private struct ColorTable {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    let space: CGColorSpace
    /// `steps`³ entries of red, green, blue in the screen's space. Empty when the screen is sRGB already.
    private let entries: [UInt8]
    /// Levels per channel: steps of 4 out of 255, finer than the eye or `colorTolerance` can tell.
    private static let steps = 64

    init?(space: CGColorSpace) {
        self.space = space
        guard space != Self.sRGB else {
            entries = []
            return
        }
        // Every table color as one pixel of an sRGB image, drawn into a bitmap in the screen's space.
        let steps = Self.steps, width = steps * steps, height = steps
        var source = [UInt8](repeating: 255, count: width * height * 4)
        for blue in 0..<steps {
            for green in 0..<steps {
                for red in 0..<steps {
                    let index = (blue * width + green * steps + red) * 4
                    source[index] = UInt8(red * 255 / (steps - 1))
                    source[index + 1] = UInt8(green * 255 / (steps - 1))
                    source[index + 2] = UInt8(blue * 255 / (steps - 1))
                }
            }
        }
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(source) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: Self.sRGB, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }
        // Both bitmaps store their top row first, so entries are found where they were put.
        entries = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
    }

    /// The bytes that show `color` (sRGB) on the screen.
    func screenColor(for color: Samples.Color) -> (red: Int, green: Int, blue: Int) {
        guard !entries.isEmpty else { return (Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255)) }
        let last = CGFloat(Self.steps - 1)
        let red = Int((color.red * last).rounded()), green = Int((color.green * last).rounded()), blue = Int((color.blue * last).rounded())
        let index = ((blue * Self.steps + green) * Self.steps + red) * 4
        return (Int(entries[index]), Int(entries[index + 1]), Int(entries[index + 2]))
    }
}

/// The part of an image a view shows, reduced to one pixel per sub-cell.
private struct Samples {
    struct Color {
        let red, green, blue: CGFloat
    }

    private let width: Int
    /// RGBA, row 0 at the top.
    private let pixels: [UInt8]
    private let darkest: Float
    private let brightest: Float

    var range: (darkest: Float, brightest: Float) { (darkest, brightest) }

    /// `knownRange` skips measuring the picture's brightness range, which needs a sort.
    init?(image: CGImage, cell: CGSize, columns: Int, rows: Int, knownRange: (darkest: Float, brightest: Float)?) {
        let width = columns * GlyphSet.subColumns, height = rows * GlyphSet.subRows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // The grid covers whole cells from the view's top-left corner. Place the image as the aspect-fill
        // image behind is placed: scaled to cover the view, centered.
        let gridSize = CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)
        let viewSize = CGSize(width: gridSize.width - cell.width, height: gridSize.height - cell.height)
        let imageSize = CGSize(width: image.width, height: image.height)
        let fill = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let origin = CGPoint(x: (viewSize.width - drawn.width) / 2, y: (viewSize.height - drawn.height) / 2)
        // To grid pixels. Sub-cells are not square (a cell is 3 × 5 of them), so each axis has its own scale:
        // one scale for both stretched the art vertically and slid it off the picture behind.
        // CGContext's origin is bottom-left; the view's is top-left.
        let toPixelsX = CGFloat(width) / gridSize.width
        let toPixelsY = CGFloat(height) / gridSize.height
        // Nearest neighbour: the frames are small and already blurred, and smooth resampling cost
        // as much as everything else in this file together.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: origin.x * toPixelsX,
                                       y: (gridSize.height - origin.y - drawn.height) * toPixelsY,
                                       width: drawn.width * toPixelsX, height: drawn.height * toPixelsY))
        guard let data = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }
        let cells = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
        self.width = width
        pixels = cells

        if let knownRange {
            (darkest, brightest) = knownRange
        } else {
            // The image's own brightness range, ignoring the extreme 5 % and 2 %, sampled sparsely.
            let sorted = stride(from: 0, to: cells.count, by: 4 * 7).map { Self.luminance(cells, at: $0) }.sorted()
            darkest = sorted.isEmpty ? 0 : sorted[sorted.count / 20]
            brightest = sorted.isEmpty ? 1 : sorted[sorted.count - 1 - sorted.count / 50]
        }
    }

    /// Fills `sub` with the cell's sub-cell brightness (0…1) and returns the cell's average color.
    func read(column: Int, row: Int, into sub: inout [Float]) -> Color {
        var red = 0, green = 0, blue = 0
        for subRow in 0..<GlyphSet.subRows {
            for subColumn in 0..<GlyphSet.subColumns {
                let index = ((row * GlyphSet.subRows + subRow) * width + column * GlyphSet.subColumns + subColumn) * 4
                sub[subRow * GlyphSet.subColumns + subColumn] = Self.luminance(pixels, at: index)
                red += Int(pixels[index])
                green += Int(pixels[index + 1])
                blue += Int(pixels[index + 2])
            }
        }
        let scale = CGFloat(GlyphSet.subCount * 255)
        return Color(red: CGFloat(red) / scale, green: CGFloat(green) / scale, blue: CGFloat(blue) / scale)
    }

    /// Brightness stretched over the image's own range: 0 (its darkest) to 1 (its brightest).
    func level(of luminance: Float) -> Float {
        min(max((luminance - darkest) / max(brightest - darkest, 0.001), 0), 1)
    }

    private static func luminance(_ pixels: [UInt8], at index: Int) -> Float {
        (0.2126 * Float(pixels[index]) + 0.7152 * Float(pixels[index + 1]) + 0.0722 * Float(pixels[index + 2])) / 255
    }
}
