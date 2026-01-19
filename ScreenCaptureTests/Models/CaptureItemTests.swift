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

    // MARK: - CaptureType Tests

    func testCaptureTypePrefixes() {
        XCTAssertEqual(CaptureType.screenshot.prefix, "Screenshot")
        XCTAssertEqual(CaptureType.scrollingCapture.prefix, "Scrolling Capture")
        XCTAssertEqual(CaptureType.recording.prefix, "Recording")
        XCTAssertEqual(CaptureType.gif.prefix, "GIF")
    }

    func testCaptureTypeIcons() {
        XCTAssertEqual(CaptureType.screenshot.icon, "camera.fill")
        XCTAssertEqual(CaptureType.scrollingCapture.icon, "scroll.fill")
        XCTAssertEqual(CaptureType.recording.icon, "video.fill")
        XCTAssertEqual(CaptureType.gif.icon, "photo.on.rectangle.angled")
    }

    func testCaptureTypeColors() {
        XCTAssertEqual(CaptureType.screenshot.color, .systemBlue)
        XCTAssertEqual(CaptureType.scrollingCapture.color, .systemPurple)
        XCTAssertEqual(CaptureType.recording.color, .systemRed)
        XCTAssertEqual(CaptureType.gif.color, .systemOrange)
    }

    func testCaptureTypeRawValues() {
        XCTAssertEqual(CaptureType.screenshot.rawValue, "Screenshot")
        XCTAssertEqual(CaptureType.scrollingCapture.rawValue, "Scrolling")
        XCTAssertEqual(CaptureType.recording.rawValue, "Recording")
        XCTAssertEqual(CaptureType.gif.rawValue, "GIF")
    }

    func testCaptureTypeAllCases() {
        XCTAssertEqual(CaptureType.allCases.count, 4)
        XCTAssertTrue(CaptureType.allCases.contains(.screenshot))
        XCTAssertTrue(CaptureType.allCases.contains(.scrollingCapture))
        XCTAssertTrue(CaptureType.allCases.contains(.recording))
        XCTAssertTrue(CaptureType.allCases.contains(.gif))
    }

    func testCaptureTypeCodable() throws {
        for type in CaptureType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(CaptureType.self, from: data)
            XCTAssertEqual(type, decoded)
        }
    }
}

// MARK: - CaptureMetadata Tests

final class CaptureMetadataTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        let metadata = CaptureMetadata()

        XCTAssertEqual(metadata.width, 0)
        XCTAssertEqual(metadata.height, 0)
        XCTAssertNil(metadata.duration)
        XCTAssertNil(metadata.frameCount)
        XCTAssertEqual(metadata.fileSize, 0)
        XCTAssertNil(metadata.colorSpace)
    }

    func testCustomInitialization() {
        let metadata = CaptureMetadata(
            width: 1920,
            height: 1080,
            duration: 60.5,
            frameCount: 1800,
            fileSize: 1048576,
            colorSpace: "sRGB"
        )

        XCTAssertEqual(metadata.width, 1920)
        XCTAssertEqual(metadata.height, 1080)
        XCTAssertEqual(metadata.duration, 60.5)
        XCTAssertEqual(metadata.frameCount, 1800)
        XCTAssertEqual(metadata.fileSize, 1048576)
        XCTAssertEqual(metadata.colorSpace, "sRGB")
    }

    // MARK: - File Size String Tests

    func testFileSizeStringZeroBytes() {
        let metadata = CaptureMetadata(fileSize: 0)
        XCTAssertTrue(metadata.fileSizeString.contains("Zero") || metadata.fileSizeString.contains("0"))
    }

    func testFileSizeStringBytes() {
        let metadata = CaptureMetadata(fileSize: 500)
        XCTAssertTrue(metadata.fileSizeString.contains("bytes") || metadata.fileSizeString.contains("500"))
    }

    func testFileSizeStringKilobytes() {
        let metadata = CaptureMetadata(fileSize: 1024)
        // Should be approximately 1 KB
        XCTAssertFalse(metadata.fileSizeString.isEmpty)
    }

    func testFileSizeStringMegabytes() {
        let metadata = CaptureMetadata(fileSize: 1048576) // 1 MB
        XCTAssertTrue(metadata.fileSizeString.contains("MB") || metadata.fileSizeString.contains("1"))
    }

    func testFileSizeStringGigabytes() {
        let metadata = CaptureMetadata(fileSize: 1073741824) // 1 GB
        XCTAssertTrue(metadata.fileSizeString.contains("GB") || metadata.fileSizeString.contains("1"))
    }

    // MARK: - Dimensions String Tests

    func testDimensionsStringBasic() {
        let metadata = CaptureMetadata(width: 1920, height: 1080)
        XCTAssertEqual(metadata.dimensionsString, "1920 x 1080")
    }

    func testDimensionsStringZero() {
        let metadata = CaptureMetadata(width: 0, height: 0)
        XCTAssertEqual(metadata.dimensionsString, "0 x 0")
    }

    func testDimensionsStringSquare() {
        let metadata = CaptureMetadata(width: 1024, height: 1024)
        XCTAssertEqual(metadata.dimensionsString, "1024 x 1024")
    }

    func testDimensionsStringPortrait() {
        let metadata = CaptureMetadata(width: 1080, height: 1920)
        XCTAssertEqual(metadata.dimensionsString, "1080 x 1920")
    }

    // MARK: - Duration String Tests

    func testDurationStringNil() {
        let metadata = CaptureMetadata()
        XCTAssertNil(metadata.durationString)
    }

    func testDurationStringZero() {
        let metadata = CaptureMetadata(duration: 0)
        XCTAssertEqual(metadata.durationString, "0:00")
    }

    func testDurationStringSeconds() {
        let metadata = CaptureMetadata(duration: 30)
        XCTAssertEqual(metadata.durationString, "0:30")
    }

    func testDurationStringMinutesAndSeconds() {
        let metadata = CaptureMetadata(duration: 90)
        XCTAssertEqual(metadata.durationString, "1:30")
    }

    func testDurationStringMultipleMinutes() {
        let metadata = CaptureMetadata(duration: 185)
        XCTAssertEqual(metadata.durationString, "3:05")
    }

    func testDurationStringOneHour() {
        let metadata = CaptureMetadata(duration: 3600)
        XCTAssertEqual(metadata.durationString, "60:00")
    }

    func testDurationStringFractionalSeconds() {
        let metadata = CaptureMetadata(duration: 65.7)
        XCTAssertEqual(metadata.durationString, "1:05")
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = CaptureMetadata(
            width: 1920,
            height: 1080,
            duration: 120.5,
            frameCount: 3600,
            fileSize: 5242880,
            colorSpace: "Display P3"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CaptureMetadata.self, from: data)

        XCTAssertEqual(original.width, decoded.width)
        XCTAssertEqual(original.height, decoded.height)
        XCTAssertEqual(original.duration, decoded.duration)
        XCTAssertEqual(original.frameCount, decoded.frameCount)
        XCTAssertEqual(original.fileSize, decoded.fileSize)
        XCTAssertEqual(original.colorSpace, decoded.colorSpace)
    }

    func testEncodeDecodeWithNilOptionals() throws {
        let original = CaptureMetadata(width: 800, height: 600, fileSize: 1024)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CaptureMetadata.self, from: data)

        XCTAssertEqual(original.width, decoded.width)
        XCTAssertEqual(original.height, decoded.height)
        XCTAssertNil(decoded.duration)
        XCTAssertNil(decoded.frameCount)
        XCTAssertNil(decoded.colorSpace)
    }
}
