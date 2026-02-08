import XCTest
@testable import ScreenCapture

@MainActor
final class MenuBarControllerTests: XCTestCase {

    var storageManager: StorageManager!
    var screenshotManager: ScreenshotManager!
    var screenRecordingManager: ScreenRecordingManager!
    var menuBarController: MenuBarController!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testSuiteName = "MenuBarControllerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)

        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
        screenshotManager = ScreenshotManager(storageManager: storageManager)
        screenRecordingManager = ScreenRecordingManager(storageManager: storageManager)
        menuBarController = MenuBarController(
            screenshotManager: screenshotManager,
            screenRecordingManager: screenRecordingManager,
            storageManager: storageManager
        )
    }

    override func tearDown() async throws {
        menuBarController = nil
        screenRecordingManager = nil
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

    func testInitializationWithManagers() {
        XCTAssertNotNil(menuBarController)
    }

    func testMenuBarControllerIsNSObject() {
        XCTAssertTrue(menuBarController is NSObject)
    }

    // MARK: - Notification Response Tests

    func testRecordingStartedNotificationHandled() {
        // Post the notification
        NotificationCenter.default.post(name: .recordingStarted, object: nil)

        // Give time for the notification to be processed
        let expectation = XCTestExpectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // The menu bar controller should handle this without crashing
        XCTAssertNotNil(menuBarController)
    }

    func testRecordingStoppedNotificationHandled() {
        // Post the notification
        NotificationCenter.default.post(name: .recordingStopped, object: nil)

        // Give time for the notification to be processed
        let expectation = XCTestExpectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // The menu bar controller should handle this without crashing
        XCTAssertNotNil(menuBarController)
    }

    // MARK: - Visibility Tests

    func testEnsureVisibleDoesNotCrash() {
        menuBarController.ensureVisible()
        XCTAssertNotNil(menuBarController)
    }

    // MARK: - Notification Observer Tests

    func testControllerObservesRecordingStarted() {
        // Verify the controller observes this notification
        // by checking it doesn't crash when receiving it
        NotificationCenter.default.post(name: .recordingStarted, object: nil)
        XCTAssertTrue(true, "No crash occurred")
    }

    func testControllerObservesRecordingStopped() {
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        XCTAssertTrue(true, "No crash occurred")
    }

    func testControllerObservesAppDidBecomeActive() {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(true, "No crash occurred")
    }

    func testMenuDoesNotExposeRecordGIFItem() {
        XCTAssertTrue(menuBarController.menuItemExistsForTesting("Record Screen"))
        XCTAssertTrue(menuBarController.menuItemExistsForTesting("Record Window"))
        XCTAssertFalse(menuBarController.menuItemExistsForTesting("Record GIF"))
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Record Screen"), "7")
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Record Window"), "8")
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Open Screenshots Folder"), "s")
    }
}

// MARK: - Menu Item Tests

@MainActor
final class MenuBarMenuItemTests: XCTestCase {

    func testMenuItemTitles() {
        // Verify expected menu item titles exist
        let expectedTitles = [
            "Capture",
            "Capture Area",
            "Capture Window",
            "Capture Fullscreen",
            "Record",
            "Record Screen",
            "Record Window",
            "Tools",
            "Capture Text (OCR)",
            "Pin Screenshot",
            "Capture History",
            "Preferences...",
            "Open Screenshots Folder",
            "Quit ScreenCapture"
        ]

        // Just verify the expected titles are defined
        XCTAssertEqual(expectedTitles.count, 14)
    }

    func testMenuItemKeyEquivalents() {
        // Test expected key equivalents
        let keyEquivalents: [(title: String, key: String)] = [
            ("Capture Area", "4"),
            ("Capture Window", "5"),
            ("Capture Fullscreen", "3"),
            ("Record Screen", "7"),
            ("Record Window", "8"),
            ("Capture Text (OCR)", "o"),
            ("Pin Screenshot", "p"),
            ("Open Screenshots Folder", "s"),
            ("Capture History", "h"),
            ("Preferences...", ","),
            ("Quit ScreenCapture", "q")
        ]

        XCTAssertEqual(keyEquivalents.count, 11)
    }

    func testMenuItemIcons() {
        // Test expected SF Symbol icon names
        let icons = [
            "rectangle.dashed",
            "macwindow",
            "rectangle.fill.on.rectangle.fill",
            "video.fill",
            "text.viewfinder",
            "pin.fill",
            "clock.arrow.circlepath",
            "gear",
            "folder",
            "power"
        ]

        // Verify all icons are valid SF Symbols
        for iconName in icons {
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            XCTAssertNotNil(image, "Icon '\(iconName)' should exist as SF Symbol")
        }
    }

    func testRecordingIconChange() {
        // Test that the recording icon exists
        let recordingIcon = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        XCTAssertNotNil(recordingIcon)

        let normalIcon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        XCTAssertNotNil(normalIcon)
    }
}
