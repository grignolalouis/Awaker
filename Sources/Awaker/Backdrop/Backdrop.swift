import AppKit
import AVFoundation
import ImageIO
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
        BackdropScene(id: "clouds", title: "Above the clouds", dim: 0.58),
        BackdropScene(id: "forest", title: "Misty forest", dim: 0.58),
        BackdropScene(id: "lagoon", title: "Lagoon", dim: 0.58),
        BackdropScene(id: "desert", title: "Two moons", dim: 0.58),
        BackdropScene(id: "colossus", title: "Stone giant", dim: 0.58),
        BackdropScene(id: "dusk", title: "Red sky", dim: 0.58),
        BackdropScene(id: "wonders", title: "Wonders", dim: 0.58),
        BackdropScene(id: "orbit", title: "Orbit", dim: 0.58),
    ]

    /// The scene with this id, or the first one when the id is unknown (a scene removed by an update).
    static func scene(_ id: String) -> BackdropScene {
        scenes.first { $0.id == id } ?? scenes[0]
    }

    /// The scene's still, at full size. Only the scene on screen is kept: the others are a few megabytes each.
    static func image(of scene: BackdropScene) -> CGImage? {
        if let still, still.scene == scene.id { return still.image }
        let image = url(scene, "jpg").flatMap { NSImage(contentsOf: $0) }?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        // A failed load is remembered too, so a missing file is not looked up on every view update.
        still = (scene.id, image)
        return image
    }

    /// The scene's loop, or nil to let go of the player (Reduce Motion). Only one is kept: a player holds on
    /// to a video decoder. Called when the scene or the setting changes, never while a view is being drawn.
    static func video(of scene: BackdropScene?) -> VideoLoop? {
        if let current = video, current.scene == scene?.id { return current.loop }
        video?.loop.pause()
        video = scene.flatMap { scene in url(scene, "mp4").map { (scene.id, VideoLoop(url: $0)) } }
        return video?.loop
    }

    /// A small version of the still, for the picker in Settings.
    static func thumbnail(of scene: BackdropScene) -> CGImage? {
        if let known = thumbnails[scene.id] { return known }
        // Decoded straight to thumbnail size: the full picture is never loaded for this.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        let thumbnail = url(scene, "jpg")
            .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        thumbnails[scene.id] = .some(thumbnail)
        return thumbnail
    }

    private static var still: (scene: String, image: CGImage?)?
    /// Nil inside means the thumbnail could not be made; it is not tried again.
    private static var thumbnails: [String: CGImage?] = [:]
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
/// redrawn on top as ASCII art. The loop only plays while the window is visible, and not at all with Reduce Motion or when switched off in Settings.
struct BackdropView: View {
    /// Nothing animates while nobody can see it: window covered or minimized, or the screen off
    /// (which is the normal state of a Mac kept awake with its lid closed).
    @State private var isWindowVisible = true
    @State private var isScreenAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    /// The loop of the scene on screen. Nil when motion is off, and for a scene without a loop.
    @State private var video: VideoLoop?

    /// The picture stays still with the system's Reduce Motion, or when the user switched the animation off in Settings.
    private var isStill: Bool { reduceMotion || !settings.animatedBackdrop }
    private var isAnimating: Bool { isWindowVisible && isScreenAwake && !isStill }

    /// Everything the player depends on. When any of it changes, `updateVideo` puts the player in step.
    private struct Playback: Equatable {
        let scene: BackdropScene
        let isAnimating: Bool
        let isStill: Bool
    }

    private func updateVideo(_ playback: Playback) {
        // Asking for another scene (or none) pauses and releases the previous player.
        video = Backdrop.video(of: playback.isStill ? nil : playback.scene)
        if playback.isAnimating { video?.play() } else { video?.pause() }
    }

    var body: some View {
        let scene = Backdrop.scene(settings.backdrop)
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
                            // A new scene brings a new player: the layer must be rebuilt around it.
                            .id(ObjectIdentifier(video))
                    }
                    Color.black.opacity(scene.dim)
                    AsciiArtView(size: proxy.size, isPaused: !isAnimating) { video?.currentFrame() ?? image }
                        .mask { WindowButtonsClearing() }
                }
                // A different scene is a different picture and player: start the views afresh.
                // The same goes for switching motion off, so the art is redrawn from the still picture.
                .id("\(scene.id) \(isStill)")
            } else {
                Color.black
            }
        }
        .onChange(of: Playback(scene: scene, isAnimating: isAnimating, isStill: isStill), initial: true) { _, playback in
            updateVideo(playback)
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

/// Everything but three small discs, exactly under the window's close, minimize and zoom buttons.
/// The buttons are translucent when the window is inactive: characters showing through made them hard to see.
/// One wide soft patch around the three did the job but read as a dark smudge on the picture, so each
/// button now hides only what is under itself.
private struct WindowButtonsClearing: View {
    /// Centers of the three buttons in a window with a unified toolbar on macOS 26, and the disc cleared under each.
    private let centers: [CGFloat] = [26, 49, 72]
    private let centerY: CGFloat = 26
    private let diameter: CGFloat = 15

    var body: some View {
        Rectangle()
            .overlay(alignment: .topLeading) {
                ForEach(centers, id: \.self) { x in
                    Circle()
                        .frame(width: diameter, height: diameter)
                        .offset(x: x - diameter / 2, y: centerY - diameter / 2)
                        .blendMode(.destinationOut)
                }
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

    /// Four pictures a second: the loop plays slowly, and each picture costs a few milliseconds of processor.
    private let frameInterval = 0.25

    var body: some View {
        TimelineView(SteadySchedule(interval: frameInterval, paused: isPaused)) { _ in
            if let image = frame(), let art = Backdrop.artist.render(image, size: size, scale: displayScale) {
                Image(decorative: art, scale: displayScale)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
            }
        }
    }
}
