import AppKit

/// The hand-drawn mark, bundled as `logo-mark.svg` (NSImage reads SVG natively), for the menu bar.
@MainActor
enum Brand {
    static let menuBarActive = menuBarImage(active: true)
    static let menuBarInactive = menuBarImage(active: false)

    /// A green dot shown next to the mark while a session runs. Not a template: it keeps its color in the menu bar.
    static let activeDot: NSImage = {
        let diameter: CGFloat = 7
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Active"
        return image
    }()

    private static let mark: NSImage? = Bundle.main.url(forResource: "logo-mark", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

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
