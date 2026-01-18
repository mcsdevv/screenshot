import XCTest
@testable import ScreenCapture

final class CaptureItemTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")

        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.type, .screenshot)
        XCTAssertEqual(item.filename, "test.png")
        XCTAssertFalse(item.isFavorite)
        XCTAssertNil(item.annotations)
    }

    func testCustomInitialization() {
        let date = Date()
        let id = UUID()
        let item = CaptureItem(
            id: id,
            type: .recording,
            filename: "video.mp4",
            createdAt: date,
            isFavorite: true
        )

        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.type, .recording)
        XCTAssertEqual(item.createdAt, date)
        XCTAssertTrue(item.isFavorite)
    }

    // MARK: - File Extension Tests

    func testFileExtensionScreenshot() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        XCTAssertEqual(item.fileExtension, "png")
    }

    func testFileExtensionScrollingCapture() {
        let item = CaptureItem(type: .scrollingCapture, filename: "test.png")
        XCTAssertEqual(item.fileExtension, "png")
    }

    func testFileExtensionRecording() {
        let item = CaptureItem(type: .recording, filename: "test.mp4")
        XCTAssertEqual(item.fileExtension, "mp4")
    }

    func testFileExtensionGIF() {
        let item = CaptureItem(type: .gif, filename: "test.gif")
        XCTAssertEqual(item.fileExtension, "gif")
    }

    // MARK: - Display Name Tests

    func testDisplayNameContainsTypePrefix() {
        let screenshotItem = CaptureItem(type: .screenshot, filename: "test.png")
        XCTAssertTrue(screenshotItem.displayName.contains("Screenshot"))

        let recordingItem = CaptureItem(type: .recording, filename: "test.mp4")
        XCTAssertTrue(recordingItem.displayName.contains("Recording"))

        let gifItem = CaptureItem(type: .gif, filename: "test.gif")
        XCTAssertTrue(gifItem.displayName.contains("GIF"))

        let scrollingItem = CaptureItem(type: .scrollingCapture, filename: "test.png")
        XCTAssertTrue(scrollingItem.displayName.contains("Scrolling"))
    }

    func testDisplayNameContainsFormattedDate() {
        let date = Date()
        let item = CaptureItem(type: .screenshot, filename: "test.png", createdAt: date)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let expectedDateString = formatter.string(from: date)

        XCTAssertTrue(item.displayName.contains(expectedDateString))
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = CaptureItem(
            type: .gif,
            filename: "animation.gif",
            isFavorite: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureItem.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.filename, decoded.filename)
        XCTAssertEqual(original.isFavorite, decoded.isFavorite)
    }

    func testEncodeDecodeWithAnnotations() throws {
        var original = CaptureItem(type: .screenshot, filename: "test.png")
        original.annotations = "test data".data(using: .utf8)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)

        XCTAssertEqual(original.annotations, decoded.annotations)
    }

    // MARK: - Equatable Tests

    func testEquatableSameId() {
        let id = UUID()
        let date = Date()
        let item1 = CaptureItem(id: id, type: .screenshot, filename: "a.png", createdAt: date)
        let item2 = CaptureItem(id: id, type: .screenshot, filename: "a.png", createdAt: date)

        XCTAssertEqual(item1, item2)
    }

    func testEquatableDifferentId() {
        let item1 = CaptureItem(type: .screenshot, filename: "a.png")
        let item2 = CaptureItem(type: .screenshot, filename: "a.png")

        XCTAssertNotEqual(item1, item2)
    }

    // MARK: - Static Methods Tests

    func testPreview() {
        let preview = CaptureItem.preview()

        XCTAssertEqual(preview.type, .screenshot)
        XCTAssertEqual(preview.filename, "preview.png")
    }

    func testSamples() {
        let samples = CaptureItem.samples()

        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(samples[0].type, .screenshot)
        XCTAssertEqual(samples[1].type, .recording)
        XCTAssertEqual(samples[2].type, .gif)
        XCTAssertEqual(samples[3].type, .scrollingCapture)
    }
}
