import Foundation
import AppKit

/// Manages screenshot shortcut mode within the app.
/// Native macOS APIs do not support programmatic remapping of system screenshot shortcuts.
@MainActor
class SystemShortcutManager: ObservableObject {
    static let shared = SystemShortcutManager()

    /// Key for tracking if user has been prompted for shortcut mode
    private let hasPromptedForRemapKey = "hasPromptedForShortcutRemap"

    /// Key for tracking whether ScreenCapture should use Cmd+Shift layout
    private let shortcutsRemappedKey = "systemShortcutsRemapped"

    /// macOS symbolic hotkey IDs for screenshot shortcuts (reference only).
    enum ScreenshotHotkeyID: Int, CaseIterable {
        case saveScreenAsFile = 28           // Cmd+Shift+3
        case copyScreenToClipboard = 29      // Cmd+Ctrl+Shift+3
        case saveAreaAsFile = 30             // Cmd+Shift+4
        case copyAreaToClipboard = 31        // Cmd+Ctrl+Shift+4
        case screenshotOptions = 184         // Cmd+Shift+5

        var description: String {
            switch self {
            case .saveScreenAsFile: return "Save picture of screen as file (⌘⇧3)"
            case .copyScreenToClipboard: return "Copy picture of screen to clipboard (⌘⌃⇧3)"
            case .saveAreaAsFile: return "Save picture of selected area as file (⌘⇧4)"
            case .copyAreaToClipboard: return "Copy picture of selected area to clipboard (⌘⌃⇧4)"
            case .screenshotOptions: return "Screenshot and recording options (⌘⇧5)"
            }
        }
    }

    /// We cannot reliably introspect this value using public APIs.
    @Published private(set) var areNativeShortcutsDisabled: Bool = false

    private init() { }

    /// Check if user has already been prompted for shortcut remapping
    var hasPromptedForRemap: Bool {
        get { UserDefaults.standard.bool(forKey: hasPromptedForRemapKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasPromptedForRemapKey) }
    }

    /// Whether ScreenCapture should use the standard Cmd+Shift layout.
    var shortcutsRemapped: Bool {
        get { UserDefaults.standard.bool(forKey: shortcutsRemappedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: shortcutsRemappedKey)
            objectWillChange.send()
        }
    }

    /// Public API kept for compatibility. This app no longer modifies system shortcut settings.
    func checkNativeShortcutStatus() {
        areNativeShortcutsDisabled = false
    }

    /// Enables ScreenCapture's Cmd+Shift shortcut mode.
    @discardableResult
    func disableNativeShortcuts() -> Bool {
        shortcutsRemapped = true
        areNativeShortcutsDisabled = false
        return true
    }

    /// Enables ScreenCapture's Ctrl+Shift safe mode.
    @discardableResult
    func enableNativeShortcuts() -> Bool {
        shortcutsRemapped = false
        areNativeShortcutsDisabled = false
        return true
    }

    /// Show the initial prompt asking user to choose shortcut mode.
    func showRemapPromptIfNeeded(from window: NSWindow? = nil) {
        guard !hasPromptedForRemap else { return }
        hasPromptedForRemap = true
        showRemapAlert(from: window)
    }

    /// Show the shortcut mode alert dialog.
    func showRemapAlert(from window: NSWindow? = nil) {
        let alert = NSAlert()
        alert.messageText = "Use Standard Screenshot Shortcuts?"
        alert.informativeText = """
            ScreenCapture can use ⌘⇧3, ⌘⇧4, and ⌘⇧5 for capture actions.

            macOS does not provide a public API for apps to disable the built-in Screenshot shortcuts automatically. If you enable standard shortcuts here, disable the native Screenshot shortcuts manually in:
            System Settings → Keyboard → Keyboard Shortcuts → Screenshots.
            """
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)

        alert.addButton(withTitle: "Use Standard Shortcuts")
        alert.addButton(withTitle: "Keep Current Shortcuts")
        alert.addButton(withTitle: "Open Keyboard Shortcuts")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            shortcutsRemapped = true
            NotificationCenter.default.post(name: .shortcutsRemapped, object: nil)

        case .alertSecondButtonReturn:
            shortcutsRemapped = false
            NotificationCenter.default.post(name: .shortcutsRemapped, object: nil)

        default:
            openKeyboardShortcutsSettings()
        }
    }

    private func openKeyboardShortcutsSettings() {
        if let shortcutsURL = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"),
           NSWorkspace.shared.open(shortcutsURL) {
            return
        }

        let settingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        _ = NSWorkspace.shared.open(settingsAppURL)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let shortcutsRemapped = Notification.Name("shortcutsRemapped")
}
