import Foundation
import AppKit

/// Manages remapping of macOS system screenshot shortcuts to ScreenCapture
/// Based on research from CleanShot X implementation approach
/// See: https://zameermanji.com/blog/2021/6/8/applying-com-apple-symbolichotkeys-changes-instantaneously/
class SystemShortcutManager: ObservableObject {
    static let shared = SystemShortcutManager()

    /// Key for tracking if user has been prompted for shortcut remapping
    private let hasPromptedForRemapKey = "hasPromptedForShortcutRemap"

    /// Key for tracking if shortcuts have been remapped
    private let shortcutsRemappedKey = "systemShortcutsRemapped"

    /// macOS symbolic hotkey IDs for screenshot shortcuts
    /// See: https://github.com/andyjakubowski/dotfiles/blob/main/AppleSymbolicHotKeys%20Mappings
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

    @Published var areNativeShortcutsDisabled: Bool = false

    private init() {
        checkNativeShortcutStatus()
    }

    /// Check if user has already been prompted for shortcut remapping
    var hasPromptedForRemap: Bool {
        get { UserDefaults.standard.bool(forKey: hasPromptedForRemapKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasPromptedForRemapKey) }
    }

    /// Check if shortcuts have been remapped to ScreenCapture
    var shortcutsRemapped: Bool {
        get { UserDefaults.standard.bool(forKey: shortcutsRemappedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: shortcutsRemappedKey)
            objectWillChange.send()
        }
    }

    /// Check the current status of native screenshot shortcuts
    func checkNativeShortcutStatus() {
        // Read the current state from the symbolic hotkeys plist
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Check if key screenshot shortcuts are disabled
                // We primarily check 28 (⌘⇧3), 30 (⌘⇧4), and 184 (⌘⇧5)
                let mainShortcutsDisabled = checkIfShortcutDisabled(id: 28, in: output) &&
                                            checkIfShortcutDisabled(id: 30, in: output) &&
                                            checkIfShortcutDisabled(id: 184, in: output)

                DispatchQueue.main.async {
                    self.areNativeShortcutsDisabled = mainShortcutsDisabled
                    debugLog("SystemShortcutManager: Native shortcuts disabled = \(mainShortcutsDisabled)")
                }
            }
        } catch {
            errorLog("SystemShortcutManager: Failed to read symbolic hotkeys: \(error)")
        }
    }

    /// Parse plist output to check if a specific shortcut is disabled
    private func checkIfShortcutDisabled(id: Int, in plistOutput: String) -> Bool {
        // Look for the pattern indicating the shortcut is disabled
        // The plist format shows: 28 = { enabled = 0; ... } when disabled
        let pattern = "\(id) =\\s*\\{[^}]*enabled\\s*=\\s*0"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(plistOutput.startIndex..., in: plistOutput)
            return regex.firstMatch(in: plistOutput, options: [], range: range) != nil
        }
        return false
    }

    /// Disable macOS native screenshot shortcuts and remap to ScreenCapture
    /// Returns true if successful
    @discardableResult
    func disableNativeShortcuts() -> Bool {
        debugLog("SystemShortcutManager: Disabling native screenshot shortcuts...")

        var success = true

        // Disable each screenshot hotkey
        for hotkeyID in ScreenshotHotkeyID.allCases {
            if !disableHotkey(id: hotkeyID.rawValue) {
                success = false
                errorLog("SystemShortcutManager: Failed to disable hotkey \(hotkeyID.rawValue)")
            }
        }

        if success {
            // Apply the changes immediately using activateSettings
            success = applyHotkeyChanges()
        }

        if success {
            shortcutsRemapped = true
            DispatchQueue.main.async {
                self.areNativeShortcutsDisabled = true
            }
            debugLog("SystemShortcutManager: Successfully disabled native shortcuts")
        }

        return success
    }

    /// Re-enable macOS native screenshot shortcuts
    /// Returns true if successful
    @discardableResult
    func enableNativeShortcuts() -> Bool {
        debugLog("SystemShortcutManager: Re-enabling native screenshot shortcuts...")

        var success = true

        // Re-enable each screenshot hotkey with their default parameters
        let hotkeyParams: [(id: Int, keyCode: Int, modifiers: Int)] = [
            (28, 20, 1179648),   // ⌘⇧3 - Save screen as file
            (29, 20, 1441792),   // ⌘⌃⇧3 - Copy screen to clipboard
            (30, 21, 1179648),   // ⌘⇧4 - Save area as file
            (31, 21, 1441792),   // ⌘⌃⇧4 - Copy area to clipboard
            (184, 23, 1179648),  // ⌘⇧5 - Screenshot options
        ]

        for params in hotkeyParams {
            if !enableHotkey(id: params.id, keyCode: params.keyCode, modifiers: params.modifiers) {
                success = false
                errorLog("SystemShortcutManager: Failed to enable hotkey \(params.id)")
            }
        }

        if success {
            success = applyHotkeyChanges()
        }

        if success {
            shortcutsRemapped = false
            DispatchQueue.main.async {
                self.areNativeShortcutsDisabled = false
            }
            debugLog("SystemShortcutManager: Successfully re-enabled native shortcuts")
        }

        return success
    }

    /// Disable a specific hotkey by ID
    private func disableHotkey(id: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = [
            "write",
            "com.apple.symbolichotkeys",
            "AppleSymbolicHotKeys",
            "-dict-add",
            "\(id)",
            "<dict><key>enabled</key><false/></dict>"
        ]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            errorLog("SystemShortcutManager: Failed to disable hotkey \(id): \(error)")
            return false
        }
    }

    /// Enable a specific hotkey by ID with given parameters
    private func enableHotkey(id: Int, keyCode: Int, modifiers: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")

        // ASCII code 65535 is used when no ASCII representation exists
        let asciiCode = 65535

        task.arguments = [
            "write",
            "com.apple.symbolichotkeys",
            "AppleSymbolicHotKeys",
            "-dict-add",
            "\(id)",
            "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>\(asciiCode)</integer><integer>\(keyCode)</integer><integer>\(modifiers)</integer></array><key>type</key><string>standard</string></dict></dict>"
        ]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            errorLog("SystemShortcutManager: Failed to enable hotkey \(id): \(error)")
            return false
        }
    }

    /// Apply hotkey changes immediately using activateSettings
    /// See: https://zameermanji.com/blog/2021/6/8/applying-com-apple-symbolichotkeys-changes-instantaneously/
    private func applyHotkeyChanges() -> Bool {
        // First, force a read to ensure the plist is synced
        let readTask = Process()
        readTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        readTask.arguments = ["read", "com.apple.symbolichotkeys"]
        readTask.standardOutput = FileHandle.nullDevice
        readTask.standardError = FileHandle.nullDevice

        do {
            try readTask.run()
            readTask.waitUntilExit()
        } catch {
            debugLog("SystemShortcutManager: Read task warning: \(error)")
        }

        // Now apply the changes using activateSettings
        let activateTask = Process()
        let activateSettingsPath = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

        // Check if activateSettings exists
        if !FileManager.default.fileExists(atPath: activateSettingsPath) {
            errorLog("SystemShortcutManager: activateSettings not found at expected path")
            // Changes will still apply after logout/restart
            return true
        }

        activateTask.executableURL = URL(fileURLWithPath: activateSettingsPath)
        activateTask.arguments = ["-u"]
        activateTask.standardOutput = FileHandle.nullDevice
        activateTask.standardError = FileHandle.nullDevice

        do {
            try activateTask.run()
            activateTask.waitUntilExit()

            let success = activateTask.terminationStatus == 0
            if success {
                debugLog("SystemShortcutManager: Successfully applied hotkey changes")
            } else {
                errorLog("SystemShortcutManager: activateSettings returned non-zero status")
            }
            return success
        } catch {
            errorLog("SystemShortcutManager: Failed to run activateSettings: \(error)")
            // Changes will still apply after logout/restart
            return true
        }
    }

    /// Show the initial prompt asking user to remap shortcuts
    func showRemapPromptIfNeeded(from window: NSWindow? = nil) {
        guard !hasPromptedForRemap else { return }

        hasPromptedForRemap = true

        // Check if shortcuts are already disabled
        checkNativeShortcutStatus()

        // Small delay to allow the check to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            if self.areNativeShortcutsDisabled {
                // Already disabled, just mark as remapped
                self.shortcutsRemapped = true
                return
            }

            self.showRemapAlert()
        }
    }

    /// Show the remap alert dialog
    func showRemapAlert() {
        let alert = NSAlert()
        alert.messageText = "Use Standard Screenshot Shortcuts?"
        alert.informativeText = """
            ScreenCapture can replace the native macOS screenshot shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5) so you can use familiar shortcuts.

            This will disable the built-in Screenshot app shortcuts and let ScreenCapture handle them instead.

            You can change this later in Preferences → Shortcuts.
            """
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)

        alert.addButton(withTitle: "Use Standard Shortcuts")
        alert.addButton(withTitle: "Keep Current Shortcuts")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            if disableNativeShortcuts() {
                // Notify that shortcuts need to be re-registered
                NotificationCenter.default.post(name: .shortcutsRemapped, object: nil)

                // Show success message
                let successAlert = NSAlert()
                successAlert.messageText = "Shortcuts Updated"
                successAlert.informativeText = "You can now use ⌘⇧3, ⌘⇧4, and ⌘⇧5 to capture with ScreenCapture."
                successAlert.alertStyle = .informational
                successAlert.runModal()
            } else {
                // Show error message
                let errorAlert = NSAlert()
                errorAlert.messageText = "Could Not Update Shortcuts"
                errorAlert.informativeText = "There was an error disabling the native shortcuts. You may need to disable them manually in System Settings → Keyboard → Keyboard Shortcuts → Screenshots."
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let shortcutsRemapped = Notification.Name("shortcutsRemapped")
}
