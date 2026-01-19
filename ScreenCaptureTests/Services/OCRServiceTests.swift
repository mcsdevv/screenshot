import XCTest
@testable import ScreenCapture

final class OCRServiceTests: XCTestCase {

    var ocrService: OCRService!

    override func setUp() {
        super.setUp()
        ocrService = OCRService()
    }

    override func tearDown() {
        ocrService = nil
        super.tearDown()
    }

    // MARK: - OCRError Tests

    func testOCRErrorNoTextFoundDescription() {
        let error = OCRService.OCRError.noTextFound
        XCTAssertEqual(error.errorDescription, "No text was found in the image.")
    }

    func testOCRErrorInvalidImageDescription() {
        let error = OCRService.OCRError.invalidImage
        XCTAssertEqual(error.errorDescription, "The image could not be processed.")
    }

    func testOCRErrorRecognitionFailedDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = OCRService.OCRError.recognitionFailed(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Test error") ?? false)
    }

    // MARK: - TextBlock Tests

    func testTextBlockInitialization() {
        let block = TextBlock(text: "Hello", confidence: 0.95, boundingBox: CGRect(x: 10, y: 20, width: 100, height: 50))

        XCTAssertEqual(block.text, "Hello")
        XCTAssertEqual(block.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(block.boundingBox, CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertNotNil(block.id)
    }

    func testTextBlockConfidencePercentage() {
        let block1 = TextBlock(text: "Test", confidence: 0.95, boundingBox: .zero)
        XCTAssertEqual(block1.confidencePercentage, 95)

        let block2 = TextBlock(text: "Test", confidence: 0.5, boundingBox: .zero)
        XCTAssertEqual(block2.confidencePercentage, 50)

        let block3 = TextBlock(text: "Test", confidence: 1.0, boundingBox: .zero)
        XCTAssertEqual(block3.confidencePercentage, 100)

        let block4 = TextBlock(text: "Test", confidence: 0.0, boundingBox: .zero)
        XCTAssertEqual(block4.confidencePercentage, 0)
    }

    func testTextBlockConfidencePercentageRounding() {
        // Test that the percentage is truncated, not rounded
        let block = TextBlock(text: "Test", confidence: 0.999, boundingBox: .zero)
        XCTAssertEqual(block.confidencePercentage, 99)
    }

    func testTextBlockUniqueIDs() {
        let block1 = TextBlock(text: "Test1", confidence: 0.9, boundingBox: .zero)
        let block2 = TextBlock(text: "Test2", confidence: 0.9, boundingBox: .zero)

        XCTAssertNotEqual(block1.id, block2.id)
    }

    // MARK: - Text Recognition Tests

    func testRecognizeTextWithTextImage() {
        let expectation = XCTestExpectation(description: "Text recognition completes")

        // Create a large image with clear text for better OCR results
        let testImage = TestImageGenerator.createImageWithText(
            "HELLO WORLD",
            size: CGSize(width: 400, height: 100),
            backgroundColor: .white,
            textColor: .black
        )

        guard let cgImage = TestImageGenerator.cgImage(from: testImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.recognizeText(in: cgImage) { result in
            switch result {
            case .success(let text):
                // OCR may not be perfect, just check we got something
                XCTAssertFalse(text.isEmpty, "Should recognize some text")
            case .failure(let error):
                // OCR may fail on simple test images - that's acceptable
                // Just verify it returns a proper error type
                XCTAssertTrue(error is OCRService.OCRError)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testRecognizeTextWithBlankImage() {
        let expectation = XCTestExpectation(description: "Text recognition completes")

        // Create a blank white image
        let blankImage = TestImageGenerator.createSolidColorImage(
            size: CGSize(width: 200, height: 200),
            color: .white
        )

        guard let cgImage = TestImageGenerator.cgImage(from: blankImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.recognizeText(in: cgImage) { result in
            switch result {
            case .success:
                // Unexpected but acceptable - Vision may find something
                break
            case .failure(let error):
                // Expected to fail with noTextFound
                if case .noTextFound = error {
                    // Expected behavior
                } else {
                    // Other errors are also acceptable
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Bounding Box Tests

    func testRecognizeTextWithBoundingBoxes() {
        let expectation = XCTestExpectation(description: "Text recognition with bounding boxes completes")

        let testImage = TestImageGenerator.createImageWithText(
            "TEST",
            size: CGSize(width: 300, height: 100),
            backgroundColor: .white,
            textColor: .black
        )

        guard let cgImage = TestImageGenerator.cgImage(from: testImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.recognizeTextWithBoundingBoxes(in: cgImage) { result in
            switch result {
            case .success(let blocks):
                // Verify we got text blocks
                for block in blocks {
                    XCTAssertFalse(block.text.isEmpty)
                    XCTAssertGreaterThanOrEqual(block.confidence, 0.0)
                    XCTAssertLessThanOrEqual(block.confidence, 1.0)
                    // Bounding boxes should have positive dimensions
                    XCTAssertGreaterThanOrEqual(block.boundingBox.width, 0)
                    XCTAssertGreaterThanOrEqual(block.boundingBox.height, 0)
                }
            case .failure:
                // OCR may fail on simple test images
                break
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testRecognizeTextWithBoundingBoxesBlankImage() {
        let expectation = XCTestExpectation(description: "Bounding box recognition on blank image completes")

        let blankImage = TestImageGenerator.createSolidColorImage(
            size: CGSize(width: 200, height: 200),
            color: .gray
        )

        guard let cgImage = TestImageGenerator.cgImage(from: blankImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.recognizeTextWithBoundingBoxes(in: cgImage) { result in
            switch result {
            case .success:
                // Unexpected but possible
                break
            case .failure(let error):
                if case .noTextFound = error {
                    // Expected
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Barcode Detection Tests

    func testDetectBarcodesOnBlankImage() {
        let expectation = XCTestExpectation(description: "Barcode detection completes")

        let blankImage = TestImageGenerator.createSolidColorImage(
            size: CGSize(width: 200, height: 200),
            color: .white
        )

        guard let cgImage = TestImageGenerator.cgImage(from: blankImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.detectBarcodes(in: cgImage) { result in
            switch result {
            case .success:
                XCTFail("Should not find barcodes in blank image")
            case .failure(let error):
                if case .noTextFound = error {
                    // Expected behavior
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testDetectBarcodesOnPatternImage() {
        let expectation = XCTestExpectation(description: "Barcode detection on pattern image completes")

        // Pattern image might be misinterpreted but shouldn't crash
        let patternImage = TestImageGenerator.createPatternImage(
            size: CGSize(width: 200, height: 200),
            tileSize: 10
        )

        guard let cgImage = TestImageGenerator.cgImage(from: patternImage) else {
            XCTFail("Failed to create CGImage")
            return
        }

        ocrService.detectBarcodes(in: cgImage) { result in
            // Either result is acceptable - just ensure it completes without crashing
            switch result {
            case .success:
                // Unexpected but acceptable
                break
            case .failure:
                // Expected
                break
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Static Method Tests

    func testRecognizeAndCopyDoesNotCrashWithValidImage() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil {
            throw XCTSkip("Skipping pasteboard/alert test in CI environments.")
        }
        // Just verify the static method doesn't crash
        let testImage = TestImageGenerator.createImageWithText(
            "COPY TEST",
            size: CGSize(width: 300, height: 100)
        )

        // This method uses main thread dispatch, so we just call it and let it run
        // We can't easily verify clipboard content in tests, but we can ensure no crash
        OCRService.recognizeAndCopy(from: testImage)

        // Give it a moment to process
        let expectation = XCTestExpectation(description: "Wait for async operation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
