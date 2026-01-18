import XCTest
@testable import ScreenCapture

final class StorageManagerTests: XCTestCase {

    var storageManager: StorageManager!

    override func setUp() {
        super.setUp()
        storageManager = StorageManager()
    }

    override func tearDown() {
        // Clean up test items from history
        for item in storageManager.history.items {
            storageManager.deleteCapture(item)
        }
        storageManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(storageManager)
        XCTAssertNotNil(storageManager.history)
        XCTAssertNotNil(storageManager.defaultDirectory)
    }

    func testDefaultDirectoryExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageManager.defaultDirectory.path))
    }

    // MARK: - Save Capture Tests

    func testSaveCaptureScreenshot() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)

        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertEqual(capture.type, .screenshot)
        XCTAssertTrue(capture.filename.hasSuffix(".png"))
        XCTAssertTrue(capture.filename.contains("Screenshot"))
        XCTAssertEqual(storageManager.history.items.count, 1)
    }

    func testSaveCaptureScrolling() {
        let testImage = createTestImage(size: CGSize(width: 200, height: 800), color: .blue)

        let capture = storageManager.saveCapture(image: testImage, type: .scrollingCapture)

        XCTAssertEqual(capture.type, .scrollingCapture)
        XCTAssertTrue(capture.filename.contains("Scrolling"))
    }

    func testSaveCaptureAddsToHistory() {
        let initialCount = storageManager.history.items.count
        let testImage = createTestImage(size: CGSize(width: 50, height: 50), color: .green)

        _ = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertEqual(storageManager.history.items.count, initialCount + 1)
    }

    // MARK: - Get Capture Tests

    func testGetCaptureById() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let saved = storageManager.saveCapture(image: testImage, type: .screenshot)

        let retrieved = storageManager.getCapture(id: saved.id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, saved.id)
        XCTAssertEqual(retrieved?.type, saved.type)
    }

    func testGetCaptureByInvalidId() {
        let result = storageManager.getCapture(id: UUID())

        XCTAssertNil(result)
    }

    // MARK: - Delete Capture Tests

    func testDeleteCapture() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        storageManager.deleteCapture(capture)

        XCTAssertNil(storageManager.getCapture(id: capture.id))
    }

    func testDeleteCaptureRemovesFromHistory() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)
        let countAfterSave = storageManager.history.items.count

        storageManager.deleteCapture(capture)

        XCTAssertEqual(storageManager.history.items.count, countAfterSave - 1)
    }

    // MARK: - Favorite Tests

    func testToggleFavorite() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertFalse(storageManager.getCapture(id: capture.id)?.isFavorite ?? true)

        storageManager.toggleFavorite(capture)

        XCTAssertTrue(storageManager.getCapture(id: capture.id)?.isFavorite ?? false)
    }

    // MARK: - Annotations Tests

    func testUpdateAnnotations() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let annotationData = "test annotation data".data(using: .utf8)!
        storageManager.updateAnnotations(for: capture, annotations: annotationData)

        let retrieved = storageManager.getCapture(id: capture.id)
        XCTAssertEqual(retrieved?.annotations, annotationData)
    }

    // MARK: - Metadata Tests

    func testGetMetadata() {
        let testImage = createTestImage(size: CGSize(width: 200, height: 150), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let metadata = storageManager.getMetadata(for: capture)

        XCTAssertEqual(metadata.width, 200)
        XCTAssertEqual(metadata.height, 150)
        XCTAssertGreaterThan(metadata.fileSize, 0)
    }

    // MARK: - URL Generation Tests

    func testGenerateRecordingURL() {
        let recordingURL = storageManager.generateRecordingURL()

        XCTAssertEqual(recordingURL.pathExtension, "mp4")
        XCTAssertTrue(recordingURL.lastPathComponent.contains("Recording"))
    }

    func testGenerateGIFURL() {
        let gifURL = storageManager.generateGIFURL()

        XCTAssertEqual(gifURL.pathExtension, "gif")
        XCTAssertTrue(gifURL.lastPathComponent.contains("GIF"))
    }

    // MARK: - Storage Location Tests

    func testGetStorageLocationDefault() {
        let location = storageManager.getStorageLocation()

        // Should be "default" or whatever was set
        XCTAssertFalse(location.isEmpty)
    }

    func testSetStorageLocation() {
        storageManager.setStorageLocation("desktop")
        XCTAssertEqual(storageManager.getStorageLocation(), "desktop")

        // Reset to default
        storageManager.setStorageLocation("default")
        XCTAssertEqual(storageManager.getStorageLocation(), "default")
    }

    // MARK: - Export/Import Tests

    func testExportCapture() throws {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).png")

        defer {
            try? FileManager.default.removeItem(at: exportURL)
        }

        try storageManager.exportCapture(capture, to: exportURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    // MARK: - Storage Usage Tests

    func testTotalStorageUsed() {
        // Save a capture to ensure there's something to measure
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        _ = storageManager.saveCapture(image: testImage, type: .screenshot)

        let storage = storageManager.totalStorageUsed

        XCTAssertGreaterThanOrEqual(storage, 0)
    }

    func testFormattedStorageUsed() {
        let formatted = storageManager.formattedStorageUsed

        XCTAssertFalse(formatted.isEmpty)
        // Should contain a unit (bytes, KB, MB, etc.)
        let containsUnit = formatted.contains("bytes") ||
                          formatted.contains("KB") ||
                          formatted.contains("MB") ||
                          formatted.contains("GB") ||
                          formatted.contains("Zero")
        XCTAssertTrue(containsUnit)
    }

    // MARK: - Helper Methods

    private func createTestImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
