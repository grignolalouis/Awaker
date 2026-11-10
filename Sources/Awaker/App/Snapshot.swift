import AppKit

/// Dev tool. `AWAKER_SNAPSHOT=<dir>` captures every screen to PNG as the window server composites it
/// (Liquid Glass included), then exits. Runs on demo data and never touches pmset or the real history.
/// With the display asleep or locked, the captures come out blank.
@MainActor
enum SnapshotRunner {
    static func run(show: @escaping (Screen) -> Void) async {
        let environment = AppEnvironment.shared
        guard let directory = environment.snapshotDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await pause()
        window?.setFrame(NSRect(origin: .zero, size: ContentView.defaultSize), display: true)

        environment.awake.previewSetActive(false)
        show(.home)
        await pause()
        capture(directory, "1-session-idle")
        environment.awake.previewSetActive(true)
        await pause()
        capture(directory, "2-session-active")
        show(.history)
        await pause()
        capture(directory, "3-history")
        show(.settings)
        await pause()
        capture(directory, "4-settings")
        // Tall enough to show the whole form, avatars included.
        window?.setFrame(NSRect(origin: .zero, size: CGSize(width: ContentView.defaultSize.width, height: 1_700)), display: true)
        await pause()
        capture(directory, "5-settings-whole")
        exit(0)
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.frame.width > 400 }
    }

    private static func pause() async {
        try? await Task.sleep(for: .milliseconds(900))
    }

    /// Asks the window server for the window as it is composited on screen, Liquid Glass included.
    /// `CGWindowListCreateImage` is no longer in the SDK headers but still ships in CoreGraphics;
    /// capturing the app's own window needs no Screen Recording permission. Dev tool only.
    private static func capture(_ directory: URL, _ name: String) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let includingWindow: UInt32 = 1 << 3
        let ignoreFraming: UInt32 = 1 << 0
        let currentProcess = UnsafeMutableRawPointer(bitPattern: -2)
        guard let window, let symbol = dlsym(currentProcess, "CGWindowListCreateImage") else { return }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = createImage(.null, includingWindow, UInt32(window.windowNumber), ignoreFraming)?.takeRetainedValue() else {
            print("snapshot: the window server returned no image for \(name)")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}
