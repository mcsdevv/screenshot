import XCTest
@testable import ScreenCapture

final class CaptureHistoryTests: XCTestCase {

    var history: CaptureHistory!

    override func setUp() {
        super.setUp()
        history = CaptureHistory()
    }

    override func tearDown() {
        history = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertNotNil(history.lastCleanup)
    }

    func testInitializationWithItems() {
        let items = [
            CaptureItem(type: .screenshot, filename: "1.png"),
            CaptureItem(type: .recording, filename: "2.mp4")
        ]
        let customHistory = CaptureHistory(items: items)

        XCTAssertEqual(customHistory.items.count, 2)
    }

    // MARK: - Add Tests

    func testAddItem() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)

        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.id, item.id)
    }

    func testAddItemInsertsAtBeginning() {
        let item1 = CaptureItem(type: .screenshot, filename: "first.png")
        let item2 = CaptureItem(type: .screenshot, filename: "second.png")

        history.add(item1)
        history.add(item2)

        XCTAssertEqual(history.items.first?.id, item2.id)
        XCTAssertEqual(history.items.last?.id, item1.id)
    }

    func testAddMultipleItems() {
        for i in 1...10 {
            history.add(CaptureItem(type: .screenshot, filename: "\(i).png"))
        }

        XCTAssertEqual(history.items.count, 10)
    }

    // MARK: - Remove Tests

    func testRemoveItem() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)
        history.remove(id: item.id)

        XCTAssertTrue(history.items.isEmpty)
    }

    func testRemoveNonExistentItem() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)
        history.remove(id: UUID())

        XCTAssertEqual(history.items.count, 1)
    }

    func testRemoveFromMultipleItems() {
        let item1 = CaptureItem(type: .screenshot, filename: "1.png")
        let item2 = CaptureItem(type: .screenshot, filename: "2.png")
        let item3 = CaptureItem(type: .screenshot, filename: "3.png")

        history.add(item1)
        history.add(item2)
        history.add(item3)

        history.remove(id: item2.id)

        XCTAssertEqual(history.items.count, 2)
        XCTAssertNil(history.items.first { $0.id == item2.id })
    }

    // MARK: - Favorite Tests

    func testToggleFavorite() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)

        XCTAssertFalse(history.items.first!.isFavorite)

        history.toggleFavorite(id: item.id)
        XCTAssertTrue(history.items.first!.isFavorite)

        history.toggleFavorite(id: item.id)
        XCTAssertFalse(history.items.first!.isFavorite)
    }

    func testToggleFavoriteNonExistentItem() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)

        history.toggleFavorite(id: UUID())

        XCTAssertFalse(history.items.first!.isFavorite)
    }

    // MARK: - Cleanup Tests

    func testCleanupRemovesOldItems() {
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60) // 40 days ago
        let oldItem = CaptureItem(type: .screenshot, filename: "old.png", createdAt: oldDate)
        let newItem = CaptureItem(type: .screenshot, filename: "new.png")

        history.items = [oldItem, newItem]
        history.cleanup(olderThan: 30)

        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.id, newItem.id)
    }

    func testCleanupPreservesFavorites() {
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        var oldItem = CaptureItem(type: .screenshot, filename: "old.png", createdAt: oldDate)
        oldItem.isFavorite = true

        history.items = [oldItem]
        history.cleanup(olderThan: 30)

        XCTAssertEqual(history.items.count, 1)
    }

    func testCleanupUpdatesLastCleanupDate() {
        let beforeCleanup = history.lastCleanup
        Thread.sleep(forTimeInterval: 0.01)

        history.cleanup()

        XCTAssertGreaterThan(history.lastCleanup, beforeCleanup)
    }

    func testCleanupWithCustomDays() {
        let oldDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let oldItem = CaptureItem(type: .screenshot, filename: "old.png", createdAt: oldDate)

        history.items = [oldItem]

        history.cleanup(olderThan: 15)
        XCTAssertEqual(history.items.count, 1)

        history.cleanup(olderThan: 5)
        XCTAssertEqual(history.items.count, 0)
    }

    // MARK: - Filter Tests

    func testFilterByType() {
        history.add(CaptureItem(type: .screenshot, filename: "ss.png"))
        history.add(CaptureItem(type: .recording, filename: "rec.mp4"))
        history.add(CaptureItem(type: .gif, filename: "anim.gif"))
        history.add(CaptureItem(type: .screenshot, filename: "ss2.png"))

        let screenshots = history.filter(by: .screenshot)
        XCTAssertEqual(screenshots.count, 2)

        let recordings = history.filter(by: .recording)
        XCTAssertEqual(recordings.count, 1)

        let gifs = history.filter(by: .gif)
        XCTAssertEqual(gifs.count, 1)
    }

    func testFilterByNilReturnsAll() {
        history.add(CaptureItem(type: .screenshot, filename: "ss.png"))
        history.add(CaptureItem(type: .recording, filename: "rec.mp4"))
        history.add(CaptureItem(type: .gif, filename: "anim.gif"))

        let all = history.filter(by: nil)
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Search Tests

    func testSearchByDisplayName() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))
        history.add(CaptureItem(type: .recording, filename: "test.mp4"))

        let results = history.search(query: "Screenshot")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchCaseInsensitive() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))

        let results = history.search(query: "screenshot")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchEmptyQuery() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))
        history.add(CaptureItem(type: .recording, filename: "test.mp4"))

        let results = history.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchNoResults() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))

        let results = history.search(query: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        history.add(CaptureItem(type: .screenshot, filename: "1.png"))
        history.add(CaptureItem(type: .recording, filename: "2.mp4"))

        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(CaptureHistory.self, from: data)

        XCTAssertEqual(decoded.items.count, 2)
    }

    // MARK: - File Loading Tests

    func testLoadFromValidJSONFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_history_\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Create and save a history
        let originalHistory = CaptureHistory()
        originalHistory.add(CaptureItem(type: .screenshot, filename: "test1.png"))
        originalHistory.add(CaptureItem(type: .recording, filename: "test2.mp4"))

        let data = try JSONEncoder().encode(originalHistory)
        try data.write(to: fileURL)

        // Load the history from file
        let loadedHistory = CaptureHistory(fileURL: fileURL)

        XCTAssertEqual(loadedHistory.items.count, 2)
        XCTAssertEqual(loadedHistory.items[0].filename, "test1.png")
        XCTAssertEqual(loadedHistory.items[1].filename, "test2.mp4")
    }

    func testLoadFromInvalidJSONFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("invalid_history_\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Write invalid JSON
        let invalidData = "not valid json".data(using: .utf8)!
        try invalidData.write(to: fileURL)

        // Should fall back to empty history
        let loadedHistory = CaptureHistory(fileURL: fileURL)

        XCTAssertTrue(loadedHistory.items.isEmpty)
    }

    func testLoadFromNonExistentFile() {
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).json")

        // Should fall back to empty history
        let loadedHistory = CaptureHistory(fileURL: nonExistentURL)

        XCTAssertTrue(loadedHistory.items.isEmpty)
        XCTAssertNotNil(loadedHistory.lastCleanup)
    }

    func testLoadFromEmptyFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("empty_history_\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Write empty data
        try Data().write(to: fileURL)

        // Should fall back to empty history
        let loadedHistory = CaptureHistory(fileURL: fileURL)

        XCTAssertTrue(loadedHistory.items.isEmpty)
    }

    func testLoadPreservesAllFields() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("full_history_\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Create history with all fields populated
        let originalHistory = CaptureHistory()
        var favoriteItem = CaptureItem(type: .gif, filename: "fav.gif")
        favoriteItem.isFavorite = true
        originalHistory.add(favoriteItem)
        originalHistory.add(CaptureItem(type: .scrollingCapture, filename: "scroll.png"))

        let data = try JSONEncoder().encode(originalHistory)
        try data.write(to: fileURL)

        // Load and verify all fields
        let loadedHistory = CaptureHistory(fileURL: fileURL)

        XCTAssertEqual(loadedHistory.items.count, 2)
        XCTAssertTrue(loadedHistory.items[0].isFavorite)
        XCTAssertEqual(loadedHistory.items[0].type, .gif)
        XCTAssertEqual(loadedHistory.items[1].type, .scrollingCapture)
    }

    // MARK: - Filter Edge Cases Tests

    func testFilterScrollingCapture() {
        history.add(CaptureItem(type: .scrollingCapture, filename: "scroll1.png"))
        history.add(CaptureItem(type: .scrollingCapture, filename: "scroll2.png"))
        history.add(CaptureItem(type: .screenshot, filename: "ss.png"))

        let scrolling = history.filter(by: .scrollingCapture)
        XCTAssertEqual(scrolling.count, 2)
    }

    func testFilterEmptyHistory() {
        let results = history.filter(by: .screenshot)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Search Edge Cases Tests

    func testSearchPartialMatch() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))

        let results = history.search(query: "Screen")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchWhitespace() {
        history.add(CaptureItem(type: .screenshot, filename: "test.png"))

        let results = history.search(query: "   ")
        // Whitespace is not empty, so search should run but likely no match
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchDatePortion() {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let yearString = formatter.string(from: date)

        history.add(CaptureItem(type: .screenshot, filename: "test.png", createdAt: date))

        let results = history.search(query: yearString)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Cleanup Edge Cases Tests

    func testCleanupAllItems() {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        history.items = [
            CaptureItem(type: .screenshot, filename: "1.png", createdAt: oldDate),
            CaptureItem(type: .screenshot, filename: "2.png", createdAt: oldDate),
            CaptureItem(type: .screenshot, filename: "3.png", createdAt: oldDate)
        ]

        history.cleanup(olderThan: 30)

        XCTAssertTrue(history.items.isEmpty)
    }

    func testCleanupMixedFavorites() {
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        var fav1 = CaptureItem(type: .screenshot, filename: "fav1.png", createdAt: oldDate)
        fav1.isFavorite = true
        var fav2 = CaptureItem(type: .screenshot, filename: "fav2.png", createdAt: oldDate)
        fav2.isFavorite = true
        let notFav = CaptureItem(type: .screenshot, filename: "notfav.png", createdAt: oldDate)

        history.items = [fav1, notFav, fav2]
        history.cleanup(olderThan: 30)

        XCTAssertEqual(history.items.count, 2)
        XCTAssertTrue(history.items.allSatisfy { $0.isFavorite })
    }

    func testCleanupZeroDays() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)

        history.cleanup(olderThan: 0)

        // Even a fresh item is older than 0 days
        XCTAssertTrue(history.items.isEmpty)
    }

    // MARK: - Add/Remove Edge Cases Tests

    func testAddSameItemTwice() {
        let item = CaptureItem(type: .screenshot, filename: "test.png")
        history.add(item)
        history.add(item)

        XCTAssertEqual(history.items.count, 2)
        // Both have the same ID
        XCTAssertEqual(history.items[0].id, history.items[1].id)
    }

    func testRemoveAllItems() {
        let item1 = CaptureItem(type: .screenshot, filename: "1.png")
        let item2 = CaptureItem(type: .screenshot, filename: "2.png")

        history.add(item1)
        history.add(item2)
        history.remove(id: item1.id)
        history.remove(id: item2.id)

        XCTAssertTrue(history.items.isEmpty)
    }

    func testRemoveFromEmptyHistory() {
        history.remove(id: UUID())
        XCTAssertTrue(history.items.isEmpty)
    }
}
