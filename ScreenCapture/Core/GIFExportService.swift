import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum GIFExportError: LocalizedError {
    case sourceMissing(URL)
    case noVideoTrack
    case frameExtractionFailed(String)
    case gifEncodingFailed(String)
    case outputMissing(URL)

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(url):
            return "Source recording is missing: \(url.path)"
        case .noVideoTrack:
            return "The recording does not contain a video track."
        case let .frameExtractionFailed(message):
            return "Unable to extract frames for GIF export: \(message)"
        case let .gifEncodingFailed(message):
            return "GIF encoding failed: \(message)"
        case let .outputMissing(url):
            return "GIF export completed but no output file was found at \(url.path)."
        }
    }
}

@MainActor
final class GIFExportService {
    struct ProgressSnapshot: Sendable {
        let stage: String
        let progress: Double
    }

    func exportGIF(
        from sourceVideoURL: URL,
        to outputGIFURL: URL,
        fps: Int,
        quality: GIFExportQualityPreset,
        onProgress: ((ProgressSnapshot) -> Void)? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: sourceVideoURL.path) else {
            throw GIFExportError.sourceMissing(sourceVideoURL)
        }

        let sanitizedFPS = max(1, min(60, fps))
        let frameDelay = 1.0 / Double(sanitizedFPS)
        let asset = AVURLAsset(url: sourceVideoURL)

        let videoTrack: AVAssetTrack
        let durationSeconds: Double
        do {
            if #available(macOS 13.0, *) {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let firstTrack = tracks.first else { throw GIFExportError.noVideoTrack }
                videoTrack = firstTrack

                let duration = try await asset.load(.duration)
                durationSeconds = max(0.1, duration.seconds.isFinite ? duration.seconds : 0.1)
            } else {
                guard let firstTrack = asset.tracks(withMediaType: .video).first else { throw GIFExportError.noVideoTrack }
                videoTrack = firstTrack

                let duration = asset.duration
                durationSeconds = max(0.1, duration.seconds.isFinite ? duration.seconds : 0.1)
            }
        } catch let error as GIFExportError {
            throw error
        } catch {
            throw GIFExportError.frameExtractionFailed(error.localizedDescription)
        }

        let frameCount = max(1, Int((durationSeconds * Double(sanitizedFPS)).rounded(.up)))
        let frameTimes = buildFrameTimes(duration: durationSeconds, frameCount: frameCount)

        guard let destination = CGImageDestinationCreateWithURL(
            outputGIFURL as CFURL,
            UTType.gif.identifier as CFString,
            frameTimes.count,
            nil
        ) else {
            throw GIFExportError.gifEncodingFailed("Could not create GIF destination")
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = maximumFrameSize(for: quality, track: videoTrack)

        onProgress?(ProgressSnapshot(stage: "Preparing", progress: 0))

        for (index, time) in frameTimes.enumerated() {
            do {
                let image = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            } catch {
                throw GIFExportError.frameExtractionFailed(error.localizedDescription)
            }

            let frameProgress = Double(index + 1) / Double(frameTimes.count)
            onProgress?(ProgressSnapshot(stage: "Encoding GIF", progress: frameProgress))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExportError.gifEncodingFailed("Image destination finalize failed")
        }

        guard FileManager.default.fileExists(atPath: outputGIFURL.path) else {
            throw GIFExportError.outputMissing(outputGIFURL)
        }

        onProgress?(ProgressSnapshot(stage: "Done", progress: 1.0))
    }

    private func buildFrameTimes(duration: Double, frameCount: Int) -> [CMTime] {
        guard frameCount > 1 else {
            return [CMTime(seconds: 0, preferredTimescale: 600)]
        }

        let step = duration / Double(frameCount - 1)
        return (0..<frameCount).map { index in
            let seconds = min(duration, Double(index) * step)
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
    }

    private func maximumFrameSize(for quality: GIFExportQualityPreset, track: AVAssetTrack) -> CGSize {
        guard let targetWidth = quality.targetWidth else {
            return CGSize(width: 4_096, height: 4_096)
        }

        let naturalSize = track.naturalSize.applying(track.preferredTransform)
        let videoWidth = max(1, abs(naturalSize.width))
        let videoHeight = max(1, abs(naturalSize.height))
        let aspectRatio = videoHeight / videoWidth
        let targetHeight = CGFloat(targetWidth) * aspectRatio
        return CGSize(width: CGFloat(targetWidth), height: max(1, targetHeight))
    }
}
