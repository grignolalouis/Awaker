import AppKit

/// The hand-drawn mark, bundled as `logo-mark.svg` (NSImage reads SVG natively), for the menu bar.
@MainActor
enum Brand {
    /// The mark with a green dot on its corner, like a notification badge: the Mac is being kept awake.
    static let menuBarActive = badgedImage()
    static let menuBarInactive = menuBarImage(active: false)

    private static let mark: NSImage? = Bundle.main.url(forResource: "logo-mark", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

    /// Not a template image, or the dot would lose its green. So the mark is tinted by hand with the label
    /// color, inside the drawing handler: AppKit runs it with the menu bar's own appearance, light or dark.
    private static func badgedImage() -> NSImage {
        let height: CGFloat = 17, dot: CGFloat = 7, gap: CGFloat = 1.5
        guard let mark else { return menuBarImage(active: true) }
        let markSize = NSSize(width: height * mark.size.width / mark.size.height, height: height)
        // Room on the right so the dot can sit on the mark's top corner without being clipped.
        let size = NSSize(width: markSize.width + dot / 2, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let markRect = NSRect(origin: .zero, size: markSize)
            mark.draw(in: markRect)
            NSColor.labelColor.setFill()
            markRect.fill(using: .sourceIn)
            let dotRect = NSRect(x: size.width - dot, y: height - dot, width: dot, height: dot)
            // A thin ring cut out of the mark around the dot keeps the two apart.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -gap, dy: -gap)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Awaker active"
        return image
    }

    /// Template image: full ink when active, faded when inactive.
    private static func menuBarImage(active: Bool) -> NSImage {
        let height: CGFloat = 17
        guard let mark else { return NSImage(systemSymbolName: "eye", accessibilityDescription: nil) ?? NSImage() }
        let size = NSSize(width: height * mark.size.width / mark.size.height, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: active ? 1 : 0.45)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Awaker active" : "Awaker inactive"
        return image
    }
}
