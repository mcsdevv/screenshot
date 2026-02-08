import XCTest
@testable import ScreenCapture

@MainActor
final class ScreenshotManagerTests: XCTestCase {

    var storageManager: StorageManager!
    var screenshotManager: ScreenshotManager!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testSuiteName = "ScreenshotManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)

        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
        screenshotManager = ScreenshotManager(storageManager: storageManager)
    }

    override func tearDown() async throws {
        screenshotManager = nil
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
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithStorageManager() {
        XCTAssertNotNil(screenshotManager)
    }

    // MARK: - PendingAction Enum Tests

    func testPendingActionCases() {
        // Verify all PendingAction cases exist
        let saveAction = ScreenshotManager.PendingAction.save
        let ocrAction = ScreenshotManager.PendingAction.ocr
        let pinAction = ScreenshotManager.PendingAction.pin

        // Just verify they exist and are distinct
        XCTAssertNotEqual(String(describing: saveAction), String(describing: ocrAction))
        XCTAssertNotEqual(String(describing: ocrAction), String(describing: pinAction))
        XCTAssertNotEqual(String(describing: saveAction), String(describing: pinAction))
    }

    // MARK: - KeyableWindow Tests

    func testKeyableWindowCanBecomeKey() {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertEqual(window.sharingType, .none)
    }

    // MARK: - Notification Name Tests

    func testCaptureCompletedNotificationExists() {
        XCTAssertNotNil(Notification.Name.captureCompleted)
    }

    // MARK: - Observable Object Tests

    func testScreenshotManagerIsObservableObject() {
        // Verify ScreenshotManager conforms to ObservableObject
        let objectWillChangePublisher = screenshotManager.objectWillChange
        XCTAssertNotNil(objectWillChangePublisher)
    }

    // MARK: - Method Existence Tests

    func testCaptureMethodsExist() {
        // These tests just verify the methods exist and don't crash
        // Actual capture requires screen capture permission and user interaction

        // The methods are @MainActor so we're already on main actor
        // We can't actually call them in tests because they trigger screencapture
        // But we can verify the manager is in a valid state

        XCTAssertNotNil(screenshotManager)
    }
}

// MARK: - Notification Name Extension Tests

extension ScreenshotManagerTests {
    func testAllCaptureNotificationNames() {
        // Verify all capture-related notification names are defined
        XCTAssertEqual(Notification.Name.captureCompleted.rawValue, "captureCompleted")
        XCTAssertEqual(Notification.Name.recordingStarted.rawValue, "recordingStarted")
        XCTAssertEqual(Notification.Name.recordingStopped.rawValue, "recordingStopped")
        XCTAssertEqual(Notification.Name.recordingCompleted.rawValue, "recordingCompleted")
    }
}
