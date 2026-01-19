import Foundation
import AppKit
import ScreenCaptureKit

/// Manages screen capture permission checking and user prompts
class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    /// Requests screen capture permission and checks if it has been granted.
    /// This also registers the app in System Settings > Privacy > Screen Recording,
    /// making it easy for users to toggle the permission on.
    /// - Returns: true if the app has screen recording permission
    func checkScreenCapturePermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings directly to the Screen Recording privacy pane
    func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows an alert informing the user that screen capture permission is required
    /// - Parameter completion: Called with true if user clicked "Open Settings", false if cancelled
    @MainActor
    func showPermissionAlert(completion: ((Bool) -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "ScreenCapture needs screen recording permission to capture screenshots and record your screen.\n\nClick \"Open Settings\" and toggle the switch next to ScreenCapture to grant permission."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openScreenCaptureSettings()
            completion?(true)
        } else {
            completion?(false)
        }
    }

    /// Checks permission and shows alert if not granted
    /// - Returns: true if permission is granted, false if not (alert will be shown)
    @MainActor
    func ensureScreenCapturePermission() -> Bool {
        if checkScreenCapturePermission() {
            return true
        }

        showPermissionAlert()
        return false
    }

    /// Handles a capture failure by checking if it's permission-related
    /// Shows the permission alert if permission is not granted
    /// - Parameter status: The termination status from screencapture command
    @MainActor
    func handleCaptureFailure(status: Int32) {
        // Status 1 from screencapture can mean user cancelled OR permission denied
        // Check if we have permission to distinguish between the two
        if status != 0 && !checkScreenCapturePermission() {
            showPermissionAlert()
        }
    }
}
