import AppKit

/// Helper class for generating test images
enum TestImageGenerator {

    /// Creates a solid color test image
    static func createSolidColorImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    /// Creates a gradient test image
    static func createGradientImage(size: CGSize, startColor: NSColor, endColor: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let gradient = NSGradient(starting: startColor, ending: endColor)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 0)

        image.unlockFocus()
        return image
    }

    /// Creates a test image with text
    static func createImageWithText(_ text: String, size: CGSize, backgroundColor: NSColor = .white, textColor: NSColor = .black) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // Background
        backgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        // Text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(size.width, size.height) * 0.1),
            .foregroundColor: textColor
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        return image
    }

    /// Creates a pattern test image
    static func createPatternImage(size: CGSize, tileSize: CGFloat = 20) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let columns = Int(ceil(size.width / tileSize))
        let rows = Int(ceil(size.height / tileSize))

        for row in 0..<rows {
            for col in 0..<columns {
                let isEven = (row + col) % 2 == 0
                (isEven ? NSColor.white : NSColor.lightGray).setFill()

                let rect = NSRect(
                    x: CGFloat(col) * tileSize,
                    y: CGFloat(row) * tileSize,
                    width: tileSize,
                    height: tileSize
                )
                NSBezierPath(rect: rect).fill()
            }
        }

        image.unlockFocus()
        return image
    }

    /// Creates a CGImage from an NSImage
    static func cgImage(from nsImage: NSImage) -> CGImage? {
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Creates multiple frames for GIF testing
    static func createAnimationFrames(count: Int, size: CGSize) -> [CGImage] {
        return (0..<count).compactMap { index in
            let hue = CGFloat(index) / CGFloat(count)
            let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
            let image = createSolidColorImage(size: size, color: color)
            return cgImage(from: image)
        }
    }
}
