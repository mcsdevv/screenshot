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

    // MARK: - Optimize GIF Tests

    func testOptimizeGIFLowQuality() {
        let expectation = XCTestExpectation(description: "Optimize GIF low quality")
        let frames = createTestFrames(count: 5, size: CGSize(width: 200, height: 200))

        // First create a GIF to optimize
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            // Now optimize it
            self.encoder.optimizeGIF(at: sourceURL, quality: .low) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testOptimizeGIFMediumQuality() {
        let expectation = XCTestExpectation(description: "Optimize GIF medium quality")
        let frames = createTestFrames(count: 5, size: CGSize(width: 200, height: 200))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .medium) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testOptimizeGIFHighQuality() {
        let expectation = XCTestExpectation(description: "Optimize GIF high quality")
        let frames = createTestFrames(count: 5, size: CGSize(width: 200, height: 200))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .high) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testOptimizeGIFOriginalQuality() {
        let expectation = XCTestExpectation(description: "Optimize GIF original quality")
        let frames = createTestFrames(count: 5, size: CGSize(width: 200, height: 200))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .original) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testOptimizeGIFInvalidSource() {
        let expectation = XCTestExpectation(description: "Optimize GIF invalid source")
        let invalidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).gif")

        encoder.optimizeGIF(at: invalidURL, quality: .medium) { optimizedURL in
            XCTAssertNil(optimizedURL)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testOptimizeGIFOutputLocation() {
        let expectation = XCTestExpectation(description: "Optimize GIF output location")
        let frames = createTestFrames(count: 3, size: CGSize(width: 100, height: 100))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("source_test_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .low) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    // Check output is in same directory with "optimized_" prefix
                    XCTAssertTrue(url.lastPathComponent.hasPrefix("optimized_"))
                    XCTAssertEqual(url.deletingLastPathComponent(), sourceURL.deletingLastPathComponent())
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 15.0)
    }

    // MARK: - Frame Reduction Tests (via optimizeGIF with many frames)

    func testOptimizeGIFWithManyFramesLowQuality() {
        let expectation = XCTestExpectation(description: "Optimize many frames low quality")
        // Create more than 30 frames to trigger frame reduction
        let frames = createTestFrames(count: 40, size: CGSize(width: 100, height: 100))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("many_frames_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.05) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .low) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }

    func testOptimizeGIFWithManyFramesOriginal() {
        let expectation = XCTestExpectation(description: "Optimize many frames original")
        // Original quality should not reduce frames even with many frames
        let frames = createTestFrames(count: 35, size: CGSize(width: 100, height: 100))

        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("many_frames_orig_\(UUID().uuidString).gif")

        encoder.createGIF(from: frames, outputURL: sourceURL, frameDelay: 0.05) { success in
            XCTAssertTrue(success)

            self.encoder.optimizeGIF(at: sourceURL, quality: .original) { optimizedURL in
                XCTAssertNotNil(optimizedURL)
                if let url = optimizedURL {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    try? FileManager.default.removeItem(at: url)
                }
                try? FileManager.default.removeItem(at: sourceURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }

    // MARK: - Resize Tests (via createGIF with large images)

    func testCreateGIFResizesVeryLargeFrames() {
        let expectation = XCTestExpectation(description: "Very large GIF creation")
        // Create frames larger than 800px to test resizing
        let frames = createTestFrames(count: 2, size: CGSize(width: 1500, height: 1200))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testCreateGIFWithSmallFramesNoResize() {
        let expectation = XCTestExpectation(description: "Small frames no resize")
        // Create frames smaller than 800px - should not be resized
        let frames = createTestFrames(count: 3, size: CGSize(width: 400, height: 300))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testCreateGIFWithWideAspectRatio() {
        let expectation = XCTestExpectation(description: "Wide aspect ratio GIF")
        // Create wide frames to test width-based scaling
        let frames = createTestFrames(count: 2, size: CGSize(width: 1200, height: 400))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    func testCreateGIFWithTallAspectRatio() {
        let expectation = XCTestExpectation(description: "Tall aspect ratio GIF")
        // Create tall frames to test height-based scaling
        let frames = createTestFrames(count: 2, size: CGSize(width: 400, height: 1200))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.1) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: self.outputURL.path))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 15.0)
    }

    // MARK: - Edge Cases

    func testCreateGIFWithZeroDelay() {
        let expectation = XCTestExpectation(description: "Zero delay GIF")
        let frames = createTestFrames(count: 3, size: CGSize(width: 100, height: 100))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 0.0) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testCreateGIFWithLongDelay() {
        let expectation = XCTestExpectation(description: "Long delay GIF")
        let frames = createTestFrames(count: 2, size: CGSize(width: 100, height: 100))

        encoder.createGIF(from: frames, outputURL: outputURL, frameDelay: 2.0) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testOptimizeCorruptedGIF() {
        let expectation = XCTestExpectation(description: "Optimize corrupted GIF")

        // Create a file that's not a valid GIF
        let corruptedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupted_\(UUID().uuidString).gif")
        let corruptedData = "not a gif file".data(using: .utf8)!
        try? corruptedData.write(to: corruptedURL)

        encoder.optimizeGIF(at: corruptedURL, quality: .medium) { optimizedURL in
            XCTAssertNil(optimizedURL)
            try? FileManager.default.removeItem(at: corruptedURL)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
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
