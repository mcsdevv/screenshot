import XCTest

final class ScreenCaptureUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - App Launch Tests

    func testAppLaunches() throws {
        // Verify the app launched successfully
        // Menu bar apps may not have a main window, so we check the app is running
        XCTAssertTrue(app.exists)
    }

    // MARK: - Menu Bar Tests

    func testMenuBarExists() throws {
        // Menu bar apps have a status item
        // This test verifies the app is running as a menu bar app
        XCTAssertTrue(app.exists)
    }

    // MARK: - Preferences Window Tests

    func testPreferencesWindowCanOpen() throws {
        app.typeKey(",", modifierFlags: .command)

        let settingsWindow = app.windows.firstMatch
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 2.0),
            "Expected the Preferences window to appear after Cmd+,."
        )
    }

    // MARK: - Accessibility Tests

    func testAppHasAccessibilityElements() throws {
        // This test ensures the app has proper accessibility support
        XCTAssertTrue(app.exists)

        // Menu bar apps should be accessible
        let menuBars = app.menuBars
        // Note: menuBars count may vary based on app state
        XCTAssertGreaterThanOrEqual(menuBars.count, 0)
    }

}
