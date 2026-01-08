import AppKit
import ImageIO
import UniformTypeIdentifiers

class GIFEncoder {
    func createGIF(from frames: [CGImage], outputURL: URL, frameDelay: Double, completion: @escaping (Bool) -> Void) {
        guard !frames.isEmpty else {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let fileProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFLoopCount as String: 0
                ]
            ]

            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: frameDelay
                ]
            ]

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.gif.identifier as CFString,
                frames.count,
                nil
            ) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

            for frame in frames {
                let resizedFrame = self.resizeImageIfNeeded(frame, maxDimension: 800)
                CGImageDestinationAddImage(destination, resizedFrame, frameProperties as CFDictionary)
            }

            let success = CGImageDestinationFinalize(destination)
            DispatchQueue.main.async { completion(success) }
        }
    }

    private func resizeImageIfNeeded(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height

        guard width > maxDimension || height > maxDimension else {
            return image
        }

        let scale: CGFloat
        if width > height {
            scale = CGFloat(maxDimension) / CGFloat(width)
        } else {
            scale = CGFloat(maxDimension) / CGFloat(height)
        }

        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }

    func optimizeGIF(at url: URL, quality: GIFQuality, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let frameCount = CGImageSourceGetCount(source)
            var frames: [CGImage] = []
            var delays: [Double] = []

            for i in 0..<frameCount {
                guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

                let resizedImage = self.resizeForQuality(image, quality: quality)
                frames.append(resizedImage)

                if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
                   let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double {
                    delays.append(delay)
                } else {
                    delays.append(0.1)
                }
            }

            let optimizedFrames = self.reduceFramesIfNeeded(frames, delays: delays, quality: quality)

            let outputURL = url.deletingLastPathComponent()
                .appendingPathComponent("optimized_\(url.lastPathComponent)")

            self.createOptimizedGIF(
                frames: optimizedFrames.frames,
                delays: optimizedFrames.delays,
                outputURL: outputURL,
                quality: quality
            ) { success in
                DispatchQueue.main.async {
                    completion(success ? outputURL : nil)
                }
            }
        }
    }

    private func resizeForQuality(_ image: CGImage, quality: GIFQuality) -> CGImage {
        let maxDimension: Int
        switch quality {
        case .low: maxDimension = 400
        case .medium: maxDimension = 600
        case .high: maxDimension = 800
        case .original: return image
        }

        return resizeImageIfNeeded(image, maxDimension: maxDimension)
    }

    private func reduceFramesIfNeeded(_ frames: [CGImage], delays: [Double], quality: GIFQuality) -> (frames: [CGImage], delays: [Double]) {
        guard quality != .original && frames.count > 30 else {
            return (frames, delays)
        }

        let skipRate: Int
        switch quality {
        case .low: skipRate = 3
        case .medium: skipRate = 2
        case .high: skipRate = 1
        case .original: skipRate = 1
        }

        var reducedFrames: [CGImage] = []
        var reducedDelays: [Double] = []

        for (index, frame) in frames.enumerated() {
            if index % (skipRate + 1) == 0 {
                reducedFrames.append(frame)
                reducedDelays.append(delays[index] * Double(skipRate + 1))
            }
        }

        return (reducedFrames, reducedDelays)
    }

    private func createOptimizedGIF(frames: [CGImage], delays: [Double], outputURL: URL, quality: GIFQuality, completion: @escaping (Bool) -> Void) {
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            completion(false)
            return
        }

        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        for (index, frame) in frames.enumerated() {
            let delay = index < delays.count ? delays[index] : 0.1
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay
                ]
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        completion(CGImageDestinationFinalize(destination))
    }
}

enum GIFQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case original = "Original"

    var description: String {
        switch self {
        case .low: return "Smaller file, lower quality"
        case .medium: return "Balanced quality and size"
        case .high: return "Better quality, larger file"
        case .original: return "Original quality"
        }
    }
}
