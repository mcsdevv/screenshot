import AppKit
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private let screenshotManager: ScreenshotManager
    private let screenRecordingManager: ScreenRecordingManager
    private let storageManager: StorageManager

    private var recordingMenuItem: NSMenuItem?
    private var isRecording = false
    private var visibilityTimer: Timer?

    init(screenshotManager: ScreenshotManager, screenRecordingManager: ScreenRecordingManager, storageManager: StorageManager) {
        self.screenshotManager = screenshotManager
        self.screenRecordingManager = screenRecordingManager
        self.storageManager = storageManager
        super.init()
        setupStatusItem()
        setupMenu()
        setupNotifications()
        setupVisibilityMonitor()
    }

    deinit {
        visibilityTimer?.invalidate()
    }

    private func setupVisibilityMonitor() {
        // Periodically ensure the status item remains visible
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.ensureVisible()
            }
        }
    }

    private func setupStatusItem() {
        // Use variableLength for standard macOS menu bar icon spacing (not squareLength which adds extra padding)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCapture")?.withSymbolConfiguration(config)
            image?.isTemplate = true  // Ensures proper rendering in light/dark mode
            button.image = image
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            debugLog("MenuBarController: Status item created and configured")
        } else {
            errorLog("MenuBarController: Failed to get status item button")
        }
    }

    /// Ensures the menu bar item is visible
    func ensureVisible() {
        guard statusItem != nil else {
            debugLog("MenuBarController: Status item was nil, recreating...")
            setupStatusItem()
            return
        }

        if !statusItem.isVisible {
            statusItem.isVisible = true
            debugLog("MenuBarController: Restored status item visibility")
        }

        // Ensure button is properly configured
        if statusItem.button?.image == nil {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCapture")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            statusItem.button?.image = image
            debugLog("MenuBarController: Restored status item image")
        }
    }

#if DEBUG
    func menuItemExistsForTesting(_ title: String) -> Bool {
        menu.items.contains { $0.title == title }
    }

    func keyEquivalentForMenuItemForTesting(_ title: String) -> String? {
        menu.items.first { $0.title == title }?.keyEquivalent
    }
#endif

    private func setupMenu() {
        menu = NSMenu()

        let captureHeader = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureHeader.isEnabled = false
        menu.addItem(captureHeader)

        addMenuItem(title: "Capture Area", icon: "rectangle.dashed", action: #selector(captureArea), keyEquivalent: "4", modifiers: [.control, .shift])
        addMenuItem(title: "Capture Window", icon: "macwindow", action: #selector(captureWindow), keyEquivalent: "5", modifiers: [.control, .shift])
        addMenuItem(title: "Capture Fullscreen", icon: "rectangle.fill.on.rectangle.fill", action: #selector(captureFullscreen), keyEquivalent: "3", modifiers: [.control, .shift])
        menu.addItem(NSMenuItem.separator())

        let recordHeader = NSMenuItem(title: "Record", action: nil, keyEquivalent: "")
        recordHeader.isEnabled = false
        menu.addItem(recordHeader)

        recordingMenuItem = addMenuItem(title: "Record Screen", icon: "video.fill", action: #selector(toggleRecording), keyEquivalent: "7", modifiers: [.control, .shift])
        addMenuItem(title: "Record Window", icon: "video", action: #selector(recordWindow), keyEquivalent: "8", modifiers: [.option, .shift])

        menu.addItem(NSMenuItem.separator())

        let toolsHeader = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsHeader.isEnabled = false
        menu.addItem(toolsHeader)

        addMenuItem(title: "Capture Text (OCR)", icon: "text.viewfinder", action: #selector(captureOCR), keyEquivalent: "o", modifiers: [.control, .shift])
        addMenuItem(title: "Pin Screenshot", icon: "pin.fill", action: #selector(pinScreenshot), keyEquivalent: "p", modifiers: [.control, .shift])
        addMenuItem(title: "Fake Screenshot", icon: "photo.fill", action: #selector(fakeScreenshot), keyEquivalent: "f", modifiers: [.control, .shift])

        menu.addItem(NSMenuItem.separator())

        addMenuItem(title: "Capture History", icon: "clock.arrow.circlepath", action: #selector(showHistory), keyEquivalent: "h", modifiers: [.command, .shift])

        menu.addItem(NSMenuItem.separator())

        addMenuItem(title: "Preferences...", icon: "gear", action: #selector(showPreferences), keyEquivalent: ",", modifiers: [.command])
        addMenuItem(title: "Open Screenshots Folder", icon: "folder", action: #selector(openScreenshotsFolder), keyEquivalent: "s", modifiers: [.control, .shift])

        menu.addItem(NSMenuItem.separator())

        addMenuItem(title: "Quit ScreenCapture", icon: "power", action: #selector(quitApp), keyEquivalent: "q", modifiers: [.command])
    }

    @discardableResult
    private func addMenuItem(title: String, icon: String, action: Selector, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = self

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?.withSymbolConfiguration(config)

        menu.addItem(item)
        return item
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(recordingDidStart), name: .recordingStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recordingDidStop), name: .recordingStopped, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidFinishLaunching), name: NSApplication.didFinishLaunchingNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        ensureVisible()
    }

    @objc private func appDidFinishLaunching() {
        ensureVisible()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    @objc private func captureArea() {
        screenshotManager.captureArea()
    }

    @objc private func captureWindow() {
        screenshotManager.captureWindow()
    }

    @objc private func captureFullscreen() {
        screenshotManager.captureFullscreen()
    }

    @objc private func toggleRecording() {
        screenRecordingManager.toggleRecording()
    }

    @objc private func recordWindow() {
        screenRecordingManager.startWindowRecordingSelection()
    }

    @objc private func captureOCR() {
        screenshotManager.captureForOCR()
    }

    @objc private func pinScreenshot() {
        screenshotManager.captureForPinning()
    }

    @objc private func fakeScreenshot() {
        guard let lastScreenshot = storageManager.history.items.first(where: { $0.type == .screenshot }) else {
            return
        }
        NotificationCenter.default.post(name: .openAnnotationEditor, object: lastScreenshot)
    }

    @objc private func showHistory() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "history" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            if let url = URL(string: "screencapture://history") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func showPreferences() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openSettings()
        }
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(storageManager.screenshotsDirectory)
    }

    @objc private func quitApp() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.requestQuit()
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func recordingDidStart() {
        isRecording = true
        recordingMenuItem?.title = "Stop Recording"

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
            // Don't set isTemplate for recording icon so it shows in red
            button.image = image
            button.contentTintColor = .systemRed
        }
    }

    @objc private func recordingDidStop() {
        isRecording = false
        recordingMenuItem?.title = "Record Screen"

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCapture")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = nil
        }
    }
}
