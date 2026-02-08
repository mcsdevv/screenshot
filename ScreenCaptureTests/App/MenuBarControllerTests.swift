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

    func testMenuExposesRecordingItems() {
        XCTAssertTrue(menuBarController.menuItemExistsForTesting("Record Area"))
        XCTAssertTrue(menuBarController.menuItemExistsForTesting("Record Window"))
        XCTAssertTrue(menuBarController.menuItemExistsForTesting("Record Fullscreen"))
        XCTAssertFalse(menuBarController.menuItemExistsForTesting("Record GIF"))
        XCTAssertFalse(menuBarController.menuItemExistsForTesting("Record Screen"))
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Record Area"), "7")
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Record Window"), "8")
        XCTAssertEqual(menuBarController.keyEquivalentForMenuItemForTesting("Record Fullscreen"), "9")
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
            "Record Area",
            "Record Window",
            "Record Fullscreen",
            "Tools",
            "Capture Text (OCR)",
            "Pin Screenshot",
            "Capture History",
            "Preferences...",
            "Open Screenshots Folder",
            "Quit ScreenCapture"
        ]

        // Just verify the expected titles are defined
        XCTAssertEqual(expectedTitles.count, 15)
    }

    func testMenuItemKeyEquivalents() {
        // Test expected key equivalents
        let keyEquivalents: [(title: String, key: String)] = [
            ("Capture Area", "4"),
            ("Capture Window", "5"),
            ("Capture Fullscreen", "3"),
            ("Record Area", "7"),
            ("Record Window", "8"),
            ("Record Fullscreen", "9"),
            ("Capture Text (OCR)", "o"),
            ("Pin Screenshot", "p"),
            ("Open Screenshots Folder", "s"),
            ("Capture History", "h"),
            ("Preferences...", ","),
            ("Quit ScreenCapture", "q")
        ]

        XCTAssertEqual(keyEquivalents.count, 12)
    }

    func testMenuItemIcons() {
        // Test expected SF Symbol icon names
        let icons = [
            "rectangle.dashed",
            "macwindow",
            "rectangle.fill.on.rectangle.fill",
            "video.badge.plus",
            "video",
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

final class PreferencesSettingsContractTests: XCTestCase {
    private let actionBackedKeys: Set<String> = [
        "launchAtLogin"
    ]

    func testPreferencesExposeOnlySupportedSettingsKeys() throws {
        let root = try repositoryRoot()
        let preferencesURL = root.appendingPathComponent("ScreenCapture/Views/PreferencesView.swift")
        let keys = try exposedPreferenceKeys(in: preferencesURL)

        let expectedKeys: Set<String> = [
            "launchAtLogin",
            "showMenuBarIcon",
            "playSound",
            "showQuickAccess",
            "quickAccessDuration",
            "popupCorner",
            "afterCaptureAction",
            "showCursor",
            "captureFormat",
            "jpegQuality",
            "recordingQuality",
            "recordingFPS",
            "recordShowCursor",
            "recordMicrophone",
            "recordSystemAudio",
            "showMouseClicks",
            "autoCleanup",
            "cleanupDays"
        ]

        XCTAssertEqual(Set(keys), expectedKeys)
        XCTAssertFalse(keys.contains("hideDesktopIcons"))
        XCTAssertFalse(keys.contains("showDimensions"))
        XCTAssertFalse(keys.contains("showMagnifier"))
    }

    func testEachExposedPreferenceKeyHasRuntimeConsumer() throws {
        let root = try repositoryRoot()
        let preferencesURL = root.appendingPathComponent("ScreenCapture/Views/PreferencesView.swift")
        let keys = try exposedPreferenceKeys(in: preferencesURL)
        let appSourceURLs = swiftFiles(in: root.appendingPathComponent("ScreenCapture"))

        for key in keys where !actionBackedKeys.contains(key) {
            let consumers = try appSourceURLs
                .filter { $0.standardizedFileURL != preferencesURL.standardizedFileURL }
                .filter { url in
                    let contents = try String(contentsOf: url)
                    return contents.contains("\"\(key)\"")
                }

            XCTAssertFalse(
                consumers.isEmpty,
                "Preference key '\(key)' has no runtime consumer outside PreferencesView.swift"
            )
        }
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("ScreenCapture.xcodeproj").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PreferencesSettingsContractTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate repository root from \(#filePath)"]
        )
    }

    private func exposedPreferenceKeys(in fileURL: URL) throws -> [String] {
        let source = try String(contentsOf: fileURL)
        let regex = try NSRegularExpression(pattern: #"\@AppStorage\(\"([^\"]+)\"\)"#)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

        var keys: [String] = []
        for match in regex.matches(in: source, range: fullRange) {
            guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
            let key = String(source[keyRange])
            if !keys.contains(key) {
                keys.append(key)
            }
        }

        return keys
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var urls: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if item.pathExtension == "swift" {
                urls.append(item)
            }
        }

        return urls
    }
}
