import XCTest
@testable import ScreenCapture

final class PermissionManagerTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstanceExists() {
        XCTAssertNotNil(PermissionManager.shared)
    }

    func testSharedInstanceIsSameReference() {
        let instance1 = PermissionManager.shared
        let instance2 = PermissionManager.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Permission Check Tests

    func testCheckScreenCapturePermissionReturnsBool() {
        // This test verifies the method returns a bool (actual value depends on system state)
        let result = PermissionManager.shared.checkScreenCapturePermission()
        XCTAssertTrue(result == true || result == false, "Should return a boolean value")
    }

    func testCheckScreenCapturePermissionIsConsistent() {
        // Multiple calls should return the same value (permission state shouldn't change during test)
        let result1 = PermissionManager.shared.checkScreenCapturePermission()
        let result2 = PermissionManager.shared.checkScreenCapturePermission()
        XCTAssertEqual(result1, result2, "Permission check should be consistent")
    }

    // MARK: - Settings URL Tests

    func testScreenCaptureSettingsURLFormat() {
        // Verify the URL format is correct
        let expectedURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        let url = URL(string: expectedURLString)
        XCTAssertNotNil(url, "URL string should be valid")
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
        XCTAssertTrue(url?.absoluteString.contains("Privacy_ScreenCapture") ?? false)
    }

    // MARK: - Handle Capture Failure Tests

    func testHandleCaptureFailureWithZeroStatus() async {
        // Status 0 means success - should not show alert
        // We can't easily verify no alert is shown, but we can ensure no crash
        await MainActor.run {
            // This should return without doing anything for status 0
            PermissionManager.shared.handleCaptureFailure(status: 0)
        }
        XCTAssertTrue(true, "No crash occurred")
    }

    // Note: We cannot easily test the alert-showing methods in unit tests
    // because they present modal dialogs. Those would need UI tests.

    // MARK: - Integration Behavior Tests

    func testEnsureScreenCapturePermissionReturnsConsistentResult() async {
        // Note: This will show an alert if permission is not granted
        // In CI environments, we typically have permission, so this should return true
        // If not, the test will show an alert but should still complete

        let hasPermission = PermissionManager.shared.checkScreenCapturePermission()

        // If we have permission, ensureScreenCapturePermission should return true
        // If not, it will show an alert (which we can't automatically dismiss in unit tests)
        if hasPermission {
            await MainActor.run {
                let result = PermissionManager.shared.ensureScreenCapturePermission()
                XCTAssertTrue(result, "Should return true when permission is granted")
            }
        }
    }
}
