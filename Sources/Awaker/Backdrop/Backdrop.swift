import AppKit
import AVFoundation
import SwiftUI

/// One picture the window can sit on: a still (`<id>.jpg`) and, optionally, a short seamless loop made
/// from it (`<id>.mp4`), both in the bundle's `Backdrop` folder. See `Assets/Backdrop/README.md`.
struct BackdropScene: Identifiable, Equatable {
    let id: String
    let title: String
    /// How much black is laid over the picture so the characters, drawn in the picture's own colours,
    /// stand out against it, and the white text stays readable. Bright scenes need more.
    var dim = 0.5
}

/// The pictures behind the whole window. The user picks one in Settings.
@MainActor
enum Backdrop {
    static let scenes = [
        BackdropScene(id: "backdrop", title: "Meadow"),
        BackdropScene(id: "beach", title: "Beach", dim: 0.58),
        BackdropScene(id: "sunflowers", title: "Sunflowers", dim: 0.58),
        BackdropScene(id: "wheat", title: "Wheat field", dim: 0.58),
    ]

    /// The scene with this id, or the first one when the id is unknown (a scene removed by an update).
    static func scene(_ id: String) -> BackdropScene {
        scenes.first { $0.id == id } ?? scenes[0]
    }

    static func image(of scene: BackdropScene) -> CGImage? {
        if let image = images[scene.id] { return image }
        let image = url(scene, "jpg").flatMap { NSImage(contentsOf: $0) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        images[scene.id] = image
        return image
    }

    /// The scene's loop. Only one is kept: a player holds on to a video decoder.
    static func video(of scene: BackdropScene) -> VideoLoop? {
        if let current = video, current.scene == scene.id { return current.loop }
        video?.loop.pause()
        video = url(scene, "mp4").map { (scene.id, VideoLoop(url: $0)) }
        return video?.loop
    }

    /// A small version of the still, for the picker in Settings.
    static func thumbnail(of scene: BackdropScene) -> CGImage? {
        if let thumbnail = thumbnails[scene.id] { return thumbnail }
        guard let image = image(of: scene) else { return nil }
        let size = (width: 320, height: 320 * image.height / max(image.width, 1))
        let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let thumbnail = context?.makeImage()
        thumbnails[scene.id] = thumbnail
        return thumbnail
    }

    private static var images: [String: CGImage] = [:]
    private static var thumbnails: [String: CGImage] = [:]
    private static var video: (scene: String, loop: VideoLoop)?

    private static func url(_ scene: BackdropScene, _ fileExtension: String) -> URL? {
        Bundle.main.url(forResource: scene.id, withExtension: fileExtension, subdirectory: "Backdrop")
    }

    /// Created once for the app's single window, not on every view update.
    static let artist = AsciiArtist()

    /// Blur of the still image behind the characters, in points. The video has a matching blur baked in
    /// (radius 2.5 in its own pixels, see `Assets/Backdrop/README.md`): blurring a playing layer live costs too much.
    static let blurRadius: CGFloat = 3
    /// Playback speed of the loop. Well under 1 so the scene stays calm.
    static let playbackRate: Float = 0.4
}

/// The window's background: the illustration (animated when a loop is bundled), blurred and dimmed,
/// redrawn on top as ASCII art. The loop only plays while the window is visible, and not at all with Reduce Motion.
struct BackdropView: View {
    /// Nothing animates while nobody can see it: window covered or minimized, or the screen off
    /// (which is the normal state of a Mac kept awake with its lid closed).
    @State private var isWindowVisible = true
    @State private var isScreenAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings

    private var isAnimating: Bool { isWindowVisible && isScreenAwake && !reduceMotion }

    var body: some View {
        let scene = Backdrop.scene(settings.backdrop)
        let video = reduceMotion ? nil : Backdrop.video(of: scene)
        // GeometryReader takes exactly the offered size, so the overflowing image can't widen the layout.
        GeometryReader { proxy in
            if let image = Backdrop.image(of: scene) {
                ZStack {
                    // The still stays underneath: it shows until the first video frame, and when motion is off.
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: Backdrop.blurRadius, opaque: true)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    if let video {
                        VideoLoopView(video: video)
                    }
                    Color.black.opacity(scene.dim)
                    AsciiArtView(size: proxy.size, isPaused: !isAnimating) { video?.currentFrame() ?? image }
                        .mask { WindowButtonsClearing() }
                }
                // A different scene is a different picture and player: start the views afresh.
                .id(scene.id)
            } else {
                Color.black
            }
        }
        .onChange(of: isAnimating, initial: true) { _, animating in
            if animating { video?.play() } else { video?.pause() }
        }
        .onChange(of: scene) {
            if isAnimating { video?.play() }
        }
        .onDisappear { video?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow, window.styleMask.contains(.titled) else { return }
            isWindowVisible = window.occlusionState.contains(.visible)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
            isScreenAwake = false
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
            isScreenAwake = true
        }
        .accessibilityHidden(true)
    }
}

/// Everything but a soft-edged patch behind the window's close, minimize and zoom buttons.
/// The buttons are translucent (more so when the window is inactive): characters showing through them
/// made them hard to see, so no characters are drawn there.
private struct WindowButtonsClearing: View {
    /// Where the three buttons sit in a window with a unified toolbar, with a little room around them.
    private let patch = CGRect(x: 12, y: 12, width: 86, height: 44)

    var body: some View {
        Rectangle()
            .overlay(alignment: .topLeading) {
                Capsule()
                    .frame(width: patch.width, height: patch.height)
                    .offset(x: patch.minX, y: patch.minY)
                    .blur(radius: 5)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }
}

/// Plays a muted video in a gapless loop and hands out its current frame, downscaled, for the ASCII art.
@MainActor
final class VideoLoop {
    let player = AVQueuePlayer()
    private let looper: AVPlayerLooper
    /// The looper cycles through copies of the item; each copy needs its own frame output.
    private var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var lastFrame: CGImage?

    /// Enough for three sub-cells per character across a wide window, and no more.
    private let frameSize = (width: 640, height: 360)

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func play() { player.rate = Backdrop.playbackRate }
    func pause() { player.pause() }

    /// The frame on screen now, or the last one seen when no new frame is ready.
    func currentFrame() -> CGImage? {
        guard let item = player.currentItem else { return lastFrame }
        let output = output(for: item)
        let time = item.currentTime()
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
           let frame = Self.image(from: buffer) {
            lastFrame = frame
        }
        return lastFrame
    }

    private func output(for item: AVPlayerItem) -> AVPlayerItemVideoOutput {
        if let existing = outputs[ObjectIdentifier(item)] { return existing }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: frameSize.width,
            kCVPixelBufferHeightKey as String: frameSize.height,
        ])
        item.add(output)
        outputs[ObjectIdentifier(item)] = output
        return output
    }

    private static func image(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        return CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                         width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                         bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo)?
            .makeImage()
    }
}

/// Shows a `VideoLoop` filling its frame through an `AVPlayerLayer`.
private struct VideoLoopView: NSViewRepresentable {
    let video: VideoLoop

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = video.player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }
}

/// The image redrawn as ASCII art (see `AsciiArtist`), rebuilt from the current frame a few times per second
/// so it follows a video.
///
/// The art is rendered to a bitmap with CoreText and shown as a plain image. Drawing the glyphs
/// in a SwiftUI `Canvas` looked right in offscreen renders but never reached the screen.
private struct AsciiArtView: View {
    let size: CGSize
    /// A still picture is drawn once; nothing is redrawn while paused.
    let isPaused: Bool
    /// The image currently shown behind the art.
    let frame: () -> CGImage?

    @Environment(\.displayScale) private var displayScale

    private let frameInterval = 0.2

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { _ in
            if let image = frame(), let art = Backdrop.artist.render(image, size: size, scale: displayScale) {
                Image(decorative: art, scale: displayScale)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
            }
        }
    }
}
