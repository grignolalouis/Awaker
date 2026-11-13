import AppKit

/// Turns frames into a dithered picture: every dot takes one of a few colours, and an ordered (Bayer)
/// pattern decides which, so mixes of neighbouring dots read as the colours in between.
///
/// Ordered rather than error-diffused: a dot's choice depends only on its own place and colour, so a
/// slow video doesn't make the whole pattern crawl from one frame to the next.
@MainActor
final class Ditherer {
    /// Sides of a dot the user can pick, in screen pixels. 1 is the finest a screen can show.
    static let dotChoices = [1, 2, 3, 4]
    /// Contrast applied before choosing colours (1 leaves the picture as it is): values are pushed away from
    /// mid-grey, so more dots land on the pure palette colours and the pattern reads more clearly.
    private let contrast = 1.2
    /// Levels per colour channel: 2 gives 8 colours in all, 3 gives 27.
    private let levels = 3

    /// The 8 × 8 Bayer matrix: thresholds 0…63 spread as evenly as possible.
    private static let bayer: [UInt8] = [
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21,
    ]

    /// Per threshold (0…63) and channel value (0…255), the level the dot gets.
    private lazy var levelTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 64 * 256)
        for threshold in 0..<64 {
            for value in 0..<256 {
                let level = min(max((Double(value) / 255 - 0.5) * contrast + 0.5, 0), 1)
                let scaled = level * Double(levels - 1) + (Double(threshold) + 0.5) / 64
                table[threshold * 256 + value] = UInt8(min(Int(scaled), levels - 1))
            }
        }
        return table
    }()

    /// The palette in the screen's colours (red, green, blue, opaque alpha per entry). See `ColorTable`.
    private var palette: [UInt8] = []
    private var paletteSpace: CGColorSpace?

    /// The image as an opaque dithered bitmap for a view of `size` points, cropped as an aspect-fill image
    /// centered in the view would be, with the scale to show it at. `dot` is the side of a dot in screen pixels.
    func render(_ image: CGImage, size: CGSize, scale: CGFloat, dot: Int) -> (image: CGImage, scale: CGFloat)? {
        let dotsPerPoint = max(scale, 1) / CGFloat(max(dot, 1))
        let width = Int((size.width * dotsPerPoint).rounded(.up)), height = Int((size.height * dotsPerPoint).rounded(.up))
        guard width > 0, height > 0 else { return nil }
        let screenSpace = NSScreen.main?.colorSpace?.cgColorSpace ?? ColorTable.sRGB
        if paletteSpace != screenSpace {
            guard let colors = ColorTable(space: screenSpace) else { return nil }
            let last = CGFloat(levels - 1)
            palette = []
            for red in 0..<levels {
                for green in 0..<levels {
                    for blue in 0..<levels {
                        let color = colors.screenColor(for: .init(red: CGFloat(red) / last, green: CGFloat(green) / last, blue: CGFloat(blue) / last))
                        palette += [UInt8(color.red), UInt8(color.green), UInt8(color.blue), 255]
                    }
                }
            }
            paletteSpace = screenSpace
        }

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: ColorTable.sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let fill = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * fill, height: CGFloat(image.height) * fill)
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: (CGFloat(width) - drawn.width) / 2, y: (CGFloat(height) - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
        guard let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }

        let levels = levels
        Self.bayer.withUnsafeBufferPointer { bayer in
            levelTable.withUnsafeBufferPointer { table in
                palette.withUnsafeBufferPointer { palette in
                    for y in 0..<height {
                        var pixel = pixels + y * width * 4
                        let bayerRow = (y & 7) * 8
                        for x in 0..<width {
                            let row = Int(bayer[bayerRow + (x & 7)]) * 256
                            let red = Int(table[row + Int(pixel[0])])
                            let green = Int(table[row + Int(pixel[1])])
                            let blue = Int(table[row + Int(pixel[2])])
                            let entry = ((red * levels + green) * levels + blue) * 4
                            pixel[0] = palette[entry]
                            pixel[1] = palette[entry + 1]
                            pixel[2] = palette[entry + 2]
                            pixel += 4
                        }
                    }
                }
            }
        }
        // The same bytes, now read as the screen's own colours: showing them costs a copy and no conversion.
        guard let provider = CGDataProvider(data: Data(bytes: pixels, count: width * height * 4) as CFData),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                   space: screenSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return (result, dotsPerPoint)
    }
}
