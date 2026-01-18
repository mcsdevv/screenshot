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
}
