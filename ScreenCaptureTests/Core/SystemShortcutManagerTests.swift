import XCTest
@testable import ScreenCapture

@MainActor
final class SystemShortcutManagerTests: XCTestCase {
    private let remapPromptKey = "hasPromptedForShortcutRemap"
    private let shortcutModeKey = "systemShortcutsRemapped"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: remapPromptKey)
        UserDefaults.standard.removeObject(forKey: shortcutModeKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: remapPromptKey)
        UserDefaults.standard.removeObject(forKey: shortcutModeKey)
        try await super.tearDown()
    }

    // MARK: - ScreenshotHotkeyID Enum Tests

    func testScreenshotHotkeyIDAllCases() {
        let allCases = SystemShortcutManager.ScreenshotHotkeyID.allCases
        XCTAssertEqual(allCases.count, 5)
    }

    func testScreenshotHotkeyIDRawValues() {
        XCTAssertEqual(SystemShortcutManager.ScreenshotHotkeyID.saveScreenAsFile.rawValue, 28)
        XCTAssertEqual(SystemShortcutManager.ScreenshotHotkeyID.copyScreenToClipboard.rawValue, 29)
        XCTAssertEqual(SystemShortcutManager.ScreenshotHotkeyID.saveAreaAsFile.rawValue, 30)
        XCTAssertEqual(SystemShortcutManager.ScreenshotHotkeyID.copyAreaToClipboard.rawValue, 31)
        XCTAssertEqual(SystemShortcutManager.ScreenshotHotkeyID.screenshotOptions.rawValue, 184)
    }

    func testScreenshotHotkeyIDDescriptionsAreUnique() {
        let descriptions = SystemShortcutManager.ScreenshotHotkeyID.allCases.map { $0.description }
        XCTAssertEqual(descriptions.count, Set(descriptions).count)
    }

    // MARK: - Shortcut Mode Tests

    func testDisableNativeShortcutsEnablesStandardLayoutMode() {
        let manager = SystemShortcutManager.shared

        XCTAssertTrue(manager.disableNativeShortcuts())
        XCTAssertTrue(manager.shortcutsRemapped)
        XCTAssertFalse(manager.areNativeShortcutsDisabled)
    }

    func testEnableNativeShortcutsEnablesSafeLayoutMode() {
        let manager = SystemShortcutManager.shared
        _ = manager.disableNativeShortcuts()

        XCTAssertTrue(manager.enableNativeShortcuts())
        XCTAssertFalse(manager.shortcutsRemapped)
        XCTAssertFalse(manager.areNativeShortcutsDisabled)
    }

    func testCheckNativeShortcutStatusUsesPublicAPIFallback() {
        let manager = SystemShortcutManager.shared
        manager.checkNativeShortcutStatus()
        XCTAssertFalse(manager.areNativeShortcutsDisabled)
    }

    func testHasPromptedForRemapPersistsToUserDefaults() {
        let manager = SystemShortcutManager.shared

        XCTAssertFalse(manager.hasPromptedForRemap)
        manager.hasPromptedForRemap = true
        XCTAssertTrue(manager.hasPromptedForRemap)
    }

    // MARK: - Notification Tests

    func testShortcutsRemappedNotificationName() {
        XCTAssertEqual(Notification.Name.shortcutsRemapped.rawValue, "shortcutsRemapped")
    }
}
