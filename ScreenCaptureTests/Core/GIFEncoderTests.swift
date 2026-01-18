import XCTest
@testable import ScreenCapture

final class GIFEncoderTests: XCTestCase {

    var encoder: GIFEncoder!
    var outputURL: URL!

    override func setUp() {
        super.setUp()
        encoder = GIFEncoder()
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).gif")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputURL)
        encoder = nil
        super.tearDown()
    }

    // MARK: - GIF Creation Tests

    func testCreateGIFWithFrames() {
        let expectation = XCTestExpectation(description: "GIF creation")
        let frames = createTestFrames(count: 5, size: CGSize(width: 100, height: 100))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testCreateGIFWithSingleFrame() {
        let expectation = XCTestExpectation(description: "Single frame GIF creation")
        let frames = createTestFrames(count: 1, size: CGSize(width: 50, height: 50))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.5) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testCreateGIFWithEmptyFrames() {
        let expectation = XCTestExpectation(description: "Empty GIF creation")

        encoder.createGIF(from: [], outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testCreateGIFWithDifferentDelays() {
        let expectation = XCTestExpectation(description: "GIF with custom delay")
        let frames = createTestFrames(count: 3, size: CGSize(width: 100, height: 100))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.5) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testCreateGIFResizesLargeFrames() {
        let expectation = XCTestExpectation(description: "Large GIF creation")
        // Create frames larger than 800px to test resizing
        let frames = createTestFrames(count: 3, size: CGSize(width: 1000, height: 1000))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            // Verify file was created
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testCreateGIFWithManyFrames() {
        let expectation = XCTestExpectation(description: "Many frames GIF creation")
        let frames = createTestFrames(count: 20, size: CGSize(width: 50, height: 50))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.05) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)
    }

    // MARK: - GIFQuality Tests

    func testGIFQualityAllCases() {
        XCTAssertEqual(GIFQuality.allCases.count, 4)
        XCTAssertTrue(GIFQuality.allCases.contains(.low))
        XCTAssertTrue(GIFQuality.allCases.contains(.medium))
        XCTAssertTrue(GIFQuality.allCases.contains(.high))
        XCTAssertTrue(GIFQuality.allCases.contains(.original))
    }

    func testGIFQualityDescriptions() {
        for quality in GIFQuality.allCases {
            XCTAssertFalse(quality.description.isEmpty, "Quality \(quality) should have a description")
        }
    }

    func testGIFQualityRawValues() {
        XCTAssertEqual(GIFQuality.low.rawValue, "Low")
        XCTAssertEqual(GIFQuality.medium.rawValue, "Medium")
        XCTAssertEqual(GIFQuality.high.rawValue, "High")
        XCTAssertEqual(GIFQuality.original.rawValue, "Original")
    }

    func testGIFQualitySpecificDescriptions() {
        XCTAssertTrue(GIFQuality.low.description.lowercased().contains("smaller"))
        XCTAssertTrue(GIFQuality.medium.description.lowercased().contains("balanced"))
        XCTAssertTrue(GIFQuality.high.description.lowercased().contains("better"))
        XCTAssertTrue(GIFQuality.original.description.lowercased().contains("original"))
    }

    // MARK: - Helper Methods

    private func createTestFrames(count: Int, size: CGSize) -> [CGImage] {
        return (0..<count).compactMap { index in
            let image = NSImage(size: size)
            image.lockFocus()

            // Different color for each frame to create visible animation
            let hue = CGFloat(index) / CGFloat(count)
            NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

            // Add some visual element
            NSColor.white.setFill()
            let dotSize = min(size.width, size.height) * 0.1
            let dotX = (size.width - dotSize) * CGFloat(index) / CGFloat(max(count - 1, 1))
            NSBezierPath(ovalIn: NSRect(x: dotX, y: size.height / 2 - dotSize / 2, width: dotSize, height: dotSize)).fill()

            image.unlockFocus()
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
}
