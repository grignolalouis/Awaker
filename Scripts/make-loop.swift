// Turns a short clip into a seamless loop by playing it forward, then backward ("ping-pong").
// The last frame of the output leads back into its first, so a looping player shows no jump.
//
// An optional Gaussian blur (radius in source pixels) is baked into the frames, so playback pays nothing for it.
//
// Usage: swift Scripts/make-loop.swift <input.mp4> <output.mp4> [blur radius]
import AVFoundation
import CoreGraphics
import CoreImage

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: make-loop.swift <input.mp4> <output.mp4> [blur radius]")
    exit(1)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let blurRadius = arguments.count > 3 ? Double(arguments[3]) ?? 0 : 0
try? FileManager.default.removeItem(at: outputURL)

let imageContext = CIContext()

/// Blurs a frame, extending its edges first so the borders don't darken.
func blurred(_ image: CGImage) -> CGImage {
    guard blurRadius > 0 else { return image }
    let source = CIImage(cgImage: image)
    let output = source.clampedToExtent().applyingGaussianBlur(sigma: blurRadius).cropped(to: source.extent)
    return imageContext.createCGImage(output, from: source.extent) ?? image
}

func makePixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

let done = DispatchSemaphore(value: 0)
Task {
    do {
        let asset = AVURLAsset(url: inputURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            print("No video track in \(inputURL.path)")
            exit(1)
        }
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let frameCount = Int((duration * Double(frameRate)).rounded(.down))

        // Forward, then backward without repeating the two end frames.
        let order = Array(0..<frameCount) + Array((1..<(frameCount - 1)).reversed())

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timescale = CMTimeScale(frameRate.rounded())
        for (position, frame) in order.enumerated() {
            let sourceTime = CMTime(value: CMTimeValue(frame), timescale: timescale)
            let (image, _) = try await generator.image(at: sourceTime)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool, let buffer = makePixelBuffer(from: blurred(image), pool: pool) else {
                print("Couldn't create a frame buffer")
                exit(1)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(position), timescale: timescale))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .completed {
            print("Wrote \(outputURL.path): \(order.count) frames at \(Int(frameRate)) fps, \(Int(size.width))×\(Int(size.height))")
        } else {
            print("Writing failed: \(writer.error?.localizedDescription ?? "unknown error")")
            exit(1)
        }
    } catch {
        print("Failed: \(error.localizedDescription)")
        exit(1)
    }
    done.signal()
}
done.wait()
