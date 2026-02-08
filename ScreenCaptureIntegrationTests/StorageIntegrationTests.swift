import XCTest
@testable import ScreenCapture

@MainActor
final class StorageIntegrationTests: XCTestCase {

    var storageManager: StorageManager!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        testSuiteName = "StorageIntegrationTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
    }

    override func tearDown() {
        storageManager = nil
        if let testSuiteName {
            testDefaults?.removePersistentDomain(forName: testSuiteName)
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        testDefaults = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - Full Workflow Tests

    func testFullCaptureWorkflow() throws {
        // Step 1: Create and save image
        let image = createTestImage()
        let capture = storageManager.saveCapture(image: image, type: .screenshot)

        // Verify it was added to history
        XCTAssertEqual(storageManager.history.items.count, 1)
        XCTAssertEqual(storageManager.getCapture(id: capture.id)?.id, capture.id)

        // Step 2: Update annotations
        let annotationData = "test annotation data".data(using: .utf8)!
        storageManager.updateAnnotations(for: capture, annotations: annotationData)

        let updatedCapture = storageManager.getCapture(id: capture.id)
        XCTAssertEqual(updatedCapture?.annotations, annotationData)

        // Step 3: Toggle favorite
        storageManager.toggleFavorite(capture)
        XCTAssertTrue(storageManager.getCapture(id: capture.id)?.isFavorite ?? false)

        // Step 4: Get metadata
        let metadata = storageManager.getMetadata(for: capture)
        XCTAssertGreaterThan(metadata.width, 0)
        XCTAssertGreaterThan(metadata.height, 0)
        XCTAssertGreaterThan(metadata.fileSize, 0)

        // Step 5: Export
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).png")

        defer {
            try? FileManager.default.removeItem(at: exportURL)
        }

        try storageManager.exportCapture(capture, to: exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        // Step 6: Cleanup
        storageManager.deleteCapture(capture)
        XCTAssertNil(storageManager.getCapture(id: capture.id))
        XCTAssertEqual(storageManager.history.items.count, 0)
    }

    func testMultipleCapturesWorkflow() {
        // Save multiple captures of different types
        let screenshot = storageManager.saveCapture(
            image: createTestImage(color: .red),
            type: .screenshot
        )
        let gif = storageManager.saveCapture(
            image: createTestImage(color: .blue),
            type: .screenshot
        )

        XCTAssertEqual(storageManager.history.items.count, 2)

        // Filter by type
        let screenshots = storageManager.history.filter(by: .screenshot)
        XCTAssertEqual(screenshots.count, 2)
        XCTAssertEqual(screenshots.last?.id, screenshot.id)

        // Search
        let searchResults = storageManager.history.search(query: "Screenshot")
        XCTAssertEqual(searchResults.count, 2)
    }

    func testFavoritesPersistence() {
        // Create captures
        let capture1 = storageManager.saveCapture(
            image: createTestImage(color: .red),
            type: .screenshot
        )
        let capture2 = storageManager.saveCapture(
            image: createTestImage(color: .blue),
            type: .screenshot
        )

        // Favorite one
        storageManager.toggleFavorite(capture1)

        // Verify favorites
        let favorites = storageManager.history.items.filter { $0.isFavorite }
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.id, capture1.id)

        // Unfavorite
        storageManager.toggleFavorite(capture1)
        let favoritesAfter = storageManager.history.items.filter { $0.isFavorite }
        XCTAssertEqual(favoritesAfter.count, 0)

        // Cleanup
        storageManager.deleteCapture(capture1)
        storageManager.deleteCapture(capture2)
    }

    func testStorageUsageTracking() {
        let initialStorage = storageManager.totalStorageUsed

        // Add a capture
        let capture = storageManager.saveCapture(
            image: createTestImage(size: CGSize(width: 500, height: 500), color: .green),
            type: .screenshot
        )

        let storageAfterAdd = storageManager.totalStorageUsed
        XCTAssertGreaterThan(storageAfterAdd, initialStorage)

        // Delete the capture
        storageManager.deleteCapture(capture)

        let storageAfterDelete = storageManager.totalStorageUsed
        XCTAssertLessThanOrEqual(storageAfterDelete, storageAfterAdd)
    }

    // MARK: - Error Handling Tests

    func testExportNonExistentCapture() {
        let fakeCapture = CaptureItem(type: .screenshot, filename: "nonexistent.png")
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test.png")

        XCTAssertThrowsError(try storageManager.exportCapture(fakeCapture, to: exportURL))
    }

    // MARK: - Helper Methods

    private func createTestImage(size: CGSize = CGSize(width: 200, height: 150), color: NSColor = .blue) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
