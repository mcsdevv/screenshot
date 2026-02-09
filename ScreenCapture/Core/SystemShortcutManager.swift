import Foundation
import AppKit
import SwiftUI

/// Manages screenshot shortcut mode within the app.
/// Native macOS APIs do not support programmatic remapping of system screenshot shortcuts.
@MainActor
class SystemShortcutManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SystemShortcutManager()

    /// Key for tracking if user has been prompted for shortcut mode
    private let hasPromptedForRemapKey = "hasPromptedForShortcutRemap"

    /// Key for tracking whether ScreenCapture should use Cmd+Shift layout
    private let shortcutsRemappedKey = "systemShortcutsRemapped"

    /// Reference to the picker window (retained to prevent ARC release)
    private var pickerWindow: NSWindow?

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

    private static let pickerWindowIdentifier = NSUserInterfaceItemIdentifier("ShortcutModePickerWindow")

    private override init() { }

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
    @discardableResult
    func showRemapPromptIfNeeded(from window: NSWindow? = nil) -> Bool {
        guard !hasPromptedForRemap else { return false }

        let shown = showRemapAlert(from: window)
        if shown {
            hasPromptedForRemap = true
        }
        debugLog("ShortcutModePicker: promptIfNeeded shown=\(shown), hasPrompted=\(hasPromptedForRemap)")
        return shown
    }

    /// Show the shortcut mode picker dialog.
    @discardableResult
    func showRemapAlert(from window: NSWindow? = nil) -> Bool {
        if let existingWindow = pickerWindow {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            return true
        }

        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        let targetScreen = window?.screen ?? NSApp.keyWindow?.screen ?? mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return false }

        let pickerView = ShortcutModePickerView(
            onChooseStandard: { [weak self] in
                self?.applyShortcutModeSelection(useStandardShortcuts: true)
            },
            onChooseSafe: { [weak self] in
                self?.applyShortcutModeSelection(useStandardShortcuts: false)
            },
            onOpenSettings: { [weak self] in
                self?.openKeyboardShortcutsSettings()
            }
        )

        let windowSize = NSSize(width: 420, height: 380)
        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)

        let screenFrame = screen.visibleFrame
        let windowFrame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )

        let pickerWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        pickerWindow.isReleasedWhenClosed = false

        pickerWindow.titlebarAppearsTransparent = true
        pickerWindow.titleVisibility = .hidden
        pickerWindow.title = "Choose Shortcuts"
        pickerWindow.backgroundColor = .clear
        pickerWindow.isOpaque = false
        pickerWindow.contentView = hostingView
        pickerWindow.identifier = Self.pickerWindowIdentifier
        pickerWindow.delegate = self
        pickerWindow.level = .floating
        pickerWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        pickerWindow.hasShadow = true
        pickerWindow.isMovableByWindowBackground = true

        // Keep red close traffic light visible so users can dismiss.
        pickerWindow.standardWindowButton(.closeButton)?.isHidden = false
        pickerWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        pickerWindow.standardWindowButton(.zoomButton)?.isHidden = true

        self.pickerWindow = pickerWindow

        NSApp.activate(ignoringOtherApps: true)
        pickerWindow.makeKeyAndOrderFront(nil)
        pickerWindow.orderFrontRegardless()
        debugLog("ShortcutModePicker: shown at frame=\(NSStringFromRect(windowFrame))")
        return true
    }

    // MARK: - Private

    private func applyShortcutModeSelection(useStandardShortcuts: Bool) {
        let succeeded = useStandardShortcuts ? disableNativeShortcuts() : enableNativeShortcuts()

        if succeeded {
            NotificationCenter.default.post(name: .shortcutsRemapped, object: nil)
            ToastManager.shared.show(useStandardShortcuts ? .shortcutStandardEnabled : .shortcutSafeEnabled)
            dismissPickerWindow()
        } else {
            ToastManager.shared.show(.shortcutModeUpdateFailed)
        }
    }

    private func dismissPickerWindow() {
        guard let windowToClose = pickerWindow else { return }
        pickerWindow = nil
        windowToClose.delegate = nil
        windowToClose.orderOut(nil)
        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    func openKeyboardShortcutsSettings() {
        if let shortcutsURL = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"),
           NSWorkspace.shared.open(shortcutsURL) {
            return
        }

        let settingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        _ = NSWorkspace.shared.open(settingsAppURL)
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            window.identifier == Self.pickerWindowIdentifier
        else {
            return
        }

        window.contentView = nil
        if pickerWindow === window {
            pickerWindow = nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let shortcutsRemapped = Notification.Name("shortcutsRemapped")
}
