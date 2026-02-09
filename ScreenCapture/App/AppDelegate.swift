import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine

final class QuickAccessWindow: NSWindow {
    var onHorizontalSwipe: (() -> Void)?

    private var accumulatedHorizontalScroll: CGFloat = 0
    private let horizontalDismissThreshold: CGFloat = 60

    override func sendEvent(_ event: NSEvent) {
        if handleHorizontalDismissGesture(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handleHorizontalDismissGesture(_ event: NSEvent) -> Bool {
        switch event.type {
        case .swipe:
            if abs(event.deltaX) > abs(event.deltaY), abs(event.deltaX) > 0 {
                onHorizontalSwipe?()
                return true
            }
        case .scrollWheel:
            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            guard abs(horizontal) > abs(vertical), abs(horizontal) > 0 else {
                resetAccumulatedHorizontalScrollIfNeeded(for: event)
                return false
            }

            if event.phase == .began || event.phase == .mayBegin {
                accumulatedHorizontalScroll = 0
            }

            accumulatedHorizontalScroll += horizontal
            if abs(accumulatedHorizontalScroll) >= horizontalDismissThreshold {
                accumulatedHorizontalScroll = 0
                onHorizontalSwipe?()
                return true
            }

            resetAccumulatedHorizontalScrollIfNeeded(for: event)
        default:
            break
        }

        return false
    }

    private func resetAccumulatedHorizontalScrollIfNeeded(for event: NSEvent) {
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
            accumulatedHorizontalScroll = 0
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private static let quickAccessDurationKey = "quickAccessDuration"
    private static let quickAccessDurationConfiguredKey = "quickAccessDurationConfigured"
    private static let legacyQuickAccessDefaultDuration: TimeInterval = 5.0

    lazy var storageManager = StorageManager()
    lazy var screenshotManager = ScreenshotManager(storageManager: storageManager)
    lazy var screenRecordingManager = ScreenRecordingManager(storageManager: storageManager)
    lazy var keyboardShortcuts = KeyboardShortcuts()
    var quickAccessWindow: NSWindow?
    var quickAccessController: QuickAccessOverlayController?
    var selectionOverlayWindow: NSWindow?
    var settingsWindow: NSWindow?
    var annotationWindow: NSWindow?
    var keyboardShortcutsWindow: NSWindow?
    private var toastController: ToastWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var terminationHandled = false
    private var userInitiatedQuit = false
    private var terminationReplyPending = false
    private var quickAccessDismissWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateQuickAccessAutoDismissDefaultsIfNeeded()

        // Initialize debug logger
        debugLog("Application launching...")
        debugLog("Log file at: \(DebugLogger.shared.logFilePath)")

        setupKeyboardShortcuts()
        setupNotifications()
        setupMainMenu()
        setupToastWindow()

        // Preflight screen capture permission (warms cache, triggers dialog once at launch)
        Task { await ScreenCaptureContentProvider.shared.preflight() }

        // Show shortcut remapping prompt on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.attemptShortcutModePrompt(trigger: "launch-delay")
        }

        debugLog("Application finished launching")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Retry when app becomes active in case launch timing missed the visible/active space.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.attemptShortcutModePrompt(trigger: "didBecomeActive")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reason = userInitiatedQuit ? "user-initiated quit" : "system termination request"

        if terminationReplyPending {
            return .terminateLater
        }

        if screenRecordingManager.isRecording {
            terminationReplyPending = true
            performTerminationCleanup(reason: reason) { [weak self] in
                guard let self = self else { return }
                if self.terminationReplyPending {
                    self.terminationReplyPending = false
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }

        performTerminationCleanup(reason: reason)
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        performTerminationCleanup(reason: "applicationWillTerminate")
        storageManager.saveHistory()
        keyboardShortcuts.unregisterAll()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "About ScreenCapture", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)

        let shortcutPreferencesItem = NSMenuItem(title: "Shortcut Preferences...", action: #selector(openShortcutPreferences), keyEquivalent: "")
        shortcutPreferencesItem.target = self
        appMenu.addItem(shortcutPreferencesItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide ScreenCapture", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))

        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit ScreenCapture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    func requestQuit() {
        userInitiatedQuit = true
        debugLog("User requested quit")
        NSApp.terminate(nil)
    }

    private func performTerminationCleanup(reason: String, completion: (() -> Void)? = nil) {
        guard !terminationHandled else {
            completion?()
            return
        }
        terminationHandled = true
        debugLog("Termination cleanup started (\(reason))")
        screenshotManager.cancelPendingCapture(reason: reason)
        screenRecordingManager.stopActiveRecordingIfNeeded(reason: reason) {
            completion?()
        }
        quickAccessDismissWorkItem?.cancel()
        quickAccessDismissWorkItem = nil
        toastController?.teardown()
        storageManager.saveHistory()
        storageManager.releaseSecurityScopedAccess()
        keyboardShortcuts.unregisterAll()
        DebugLogger.shared.flush()
    }

    private func setupKeyboardShortcuts() {
        keyboardShortcuts.register(shortcut: .captureArea) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureArea()
            }
        }

        keyboardShortcuts.register(shortcut: .captureWindow) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureWindow()
            }
        }

        keyboardShortcuts.register(shortcut: .captureFullscreen) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureFullscreen()
            }
        }

        keyboardShortcuts.register(shortcut: .recordArea) { [weak self] in
            DispatchQueue.main.async {
                self?.screenRecordingManager.toggleRecording()
            }
        }

        keyboardShortcuts.register(shortcut: .recordWindow) { [weak self] in
            DispatchQueue.main.async {
                self?.screenRecordingManager.startWindowRecordingSelection()
            }
        }

        keyboardShortcuts.register(shortcut: .recordFullscreen) { [weak self] in
            DispatchQueue.main.async {
                self?.screenRecordingManager.startFullscreenRecording()
            }
        }

        keyboardShortcuts.register(shortcut: .allInOne) { [weak self] in
            DispatchQueue.main.async {
                self?.showAllInOneMenu()
            }
        }

        keyboardShortcuts.register(shortcut: .ocr) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureForOCR()
            }
        }

        keyboardShortcuts.register(shortcut: .pinScreenshot) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureForPinning()
            }
        }

        keyboardShortcuts.register(shortcut: .openScreenshotsFolder) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                NSWorkspace.shared.open(self.storageManager.screenshotsDirectory)
            }
        }

        keyboardShortcuts.register(shortcut: .showKeyboardShortcuts) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleKeyboardShortcutsOverlay()
            }
        }

        debugLog("AppDelegate: All keyboard shortcuts registered")
    }

    private func setupToastWindow() {
        toastController = ToastWindowController()
        toastController?.setup()
        debugLog("AppDelegate: Toast window initialized")
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .captureCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                // Defer overlay display to ensure capture processing is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.handleCaptureCompleted(capture)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                // Defer overlay display to ensure recording processing is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.handleCaptureCompleted(capture)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openAnnotationEditor)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                self?.showAnnotationEditor(for: capture)
            }
            .store(in: &cancellables)

        // Listen for shortcut remap changes
        NotificationCenter.default.publisher(for: .shortcutsRemapped)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let useNative = SystemShortcutManager.shared.shortcutsRemapped
                self?.keyboardShortcuts.reregisterAllShortcuts(useNativeShortcuts: useNative)
                debugLog("AppDelegate: Re-registered shortcuts after remap, useNative=\(useNative)")
            }
            .store(in: &cancellables)
    }

    private func handleCaptureCompleted(_ capture: CaptureItem) {
        switch afterCaptureAction {
        case "clipboard":
            if copyCaptureToClipboard(capture) {
                return
            }
        case "save":
            revealCaptureInFinder(capture)
            return
        case "editor":
            if canOpenEditor(for: capture) {
                showAnnotationEditor(for: capture)
                return
            }
        default:
            break
        }

        guard shouldShowQuickAccessOverlay else { return }
        showQuickAccessOverlay(for: capture)
    }

    private var afterCaptureAction: String {
        UserDefaults.standard.string(forKey: "afterCaptureAction") ?? "quickAccess"
    }

    private func canOpenEditor(for capture: CaptureItem) -> Bool {
        capture.type == .screenshot
    }

    private func copyCaptureToClipboard(_ capture: CaptureItem) -> Bool {
        guard canOpenEditor(for: capture) else { return false }

        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        guard let image = NSImage(contentsOf: url) else {
            return false
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        ToastManager.shared.show(.copy)
        return true
    }

    private func revealCaptureInFinder(_ capture: CaptureItem) {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        ToastManager.shared.show(.save)
    }

    private var shouldShowQuickAccessOverlay: Bool {
        guard UserDefaults.standard.object(forKey: "showQuickAccess") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "showQuickAccess")
    }

    private var quickAccessDismissDelay: TimeInterval {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.quickAccessDurationConfiguredKey) else { return 0 }
        return max(0, defaults.double(forKey: Self.quickAccessDurationKey))
    }

    private func migrateQuickAccessAutoDismissDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.quickAccessDurationConfiguredKey) == nil else { return }

        let storedDuration = defaults.object(forKey: Self.quickAccessDurationKey) as? Double
        switch storedDuration {
        case nil:
            // New installs should default to no timed auto-dismiss.
            defaults.set(0.0, forKey: Self.quickAccessDurationKey)
            defaults.set(false, forKey: Self.quickAccessDurationConfiguredKey)
        case let value? where value == Self.legacyQuickAccessDefaultDuration:
            // Migrate legacy implicit 5s default to "never" unless user explicitly reconfigures.
            defaults.set(0.0, forKey: Self.quickAccessDurationKey)
            defaults.set(false, forKey: Self.quickAccessDurationConfiguredKey)
        default:
            // Preserve non-default legacy values as explicit user intent.
            defaults.set(true, forKey: Self.quickAccessDurationConfiguredKey)
        }
    }

    func showQuickAccessOverlay(for capture: CaptureItem) {
        closeQuickAccessOverlay()

        // Read corner preference
        let cornerRawValue = UserDefaults.standard.string(forKey: "popupCorner") ?? ScreenCorner.bottomLeft.rawValue
        let corner = ScreenCorner(rawValue: cornerRawValue) ?? .bottomLeft

        let controller = QuickAccessOverlayController(capture: capture, storageManager: storageManager)
        quickAccessController = controller

        controller.setDismissAction { [weak self] dismissMode in
            DispatchQueue.main.async {
                self?.closeQuickAccessOverlay(mode: dismissMode)
            }
        }

        let overlayView = QuickAccessOverlay(controller: controller, corner: corner)

        let windowSize = NSSize(width: 360, height: 340)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]

            // Calculate the actual window frame size (includes title bar)
            let contentRect = NSRect(origin: .zero, size: windowSize)
            let frameRect = NSWindow.frameRect(forContentRect: contentRect, styleMask: styleMask)

            // Position using the full frame size so title bar doesn't push content down
            let origin = corner.windowOrigin(screenFrame: screenFrame, windowSize: frameRect.size, padding: DSSpacing.lg)

            let window = QuickAccessWindow(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )

            window.onHorizontalSwipe = { [weak controller] in
                debugLog("QuickAccessOverlay: Horizontal swipe detected, dismissing preview")
                controller?.dismissWithSwipeAnimation()
            }

            // Set the actual window frame position
            window.setFrameOrigin(origin)

            // CRITICAL: Prevent double-release crash under ARC
            // NSWindow defaults to isReleasedWhenClosed=true, which causes
            // AppKit to release the window on close. Combined with ARC's
            // automatic release, this causes EXC_BAD_ACCESS in objc_release.
            window.isReleasedWhenClosed = false

            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Screenshot Preview"
            window.backgroundColor = .clear
            window.isOpaque = false

            window.contentView = hostingView
            window.level = .floating
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            window.delegate = self

            // Hide system traffic lights - we use custom SwiftUI buttons inside the content area
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            quickAccessWindow = window

            // CRITICAL: For LSUIElement/accessory apps, we must activate the app
            // AND make the window key for keyboard shortcuts to work immediately.
            // Without activation, the window appears but doesn't receive keyboard focus.
            // See: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
            // See: https://ar.al/2018/09/17/workaround-for-unclickable-app-menu-bug-with-window.makekeyandorderfront-and-nsapp.activate-on-macos/

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()

            debugLog("QuickAccessOverlay: Window shown and app activated for keyboard focus")

            let dismissDelay = quickAccessDismissDelay
            if dismissDelay > 0 {
                let dismissWorkItem = DispatchWorkItem { [weak self] in
                    self?.closeQuickAccessOverlay()
                }
                quickAccessDismissWorkItem = dismissWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: dismissWorkItem)
            }
        }
    }

    func closeQuickAccessOverlay(mode: QuickAccessOverlayController.DismissMode = .immediate) {
        quickAccessDismissWorkItem?.cancel()
        quickAccessDismissWorkItem = nil

        guard let windowToClose = quickAccessWindow else { return }
        quickAccessWindow = nil

        // Mark controller as not visible to prevent any further actions
        quickAccessController?.isVisible = false

        if mode == .swipeToNearestEdge {
            animateQuickAccessOverlayDismissal(windowToClose)
        } else {
            cleanupQuickAccessOverlayWindow(windowToClose)
        }
    }

    private func animateQuickAccessOverlayDismissal(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            cleanupQuickAccessOverlayWindow(window)
            return
        }

        let screenFrame = screen.frame
        let currentFrame = window.frame
        let distanceToLeftEdge = abs(currentFrame.minX - screenFrame.minX)
        let distanceToRightEdge = abs(screenFrame.maxX - currentFrame.maxX)
        let shouldExitLeft = distanceToLeftEdge <= distanceToRightEdge
        let horizontalPadding: CGFloat = 24

        var targetFrame = currentFrame
        targetFrame.origin.x = shouldExitLeft
            ? screenFrame.minX - currentFrame.width - horizontalPadding
            : screenFrame.maxX + horizontalPadding

        window.ignoresMouseEvents = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.cleanupQuickAccessOverlayWindow(window)
            }
        }
    }

    private func cleanupQuickAccessOverlayWindow(_ window: NSWindow) {
        // Hide window immediately
        window.orderOut(nil)

        // Defer cleanup to next run loop to allow SwiftUI to finish
        DispatchQueue.main.async { [weak self] in
            window.contentView = nil
            window.close()
            self?.quickAccessController = nil
        }
    }

    func showAllInOneMenu() {
        guard let screen = NSScreen.main else { return }

        // Close any existing overlay first
        closeSelectionOverlay()

        let menuView = AllInOneMenuView(
            onCaptureArea: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenshotManager.captureArea()
                }
            },
            onCaptureWindow: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenshotManager.captureWindow()
                }
            },
            onCaptureFullscreen: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenshotManager.captureFullscreen()
                }
            },
            onRecordArea: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenRecordingManager.toggleRecording()
                }
            },
            onRecordWindow: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenRecordingManager.startWindowRecordingSelection()
                }
            },
            onRecordFullscreen: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenRecordingManager.startFullscreenRecording()
                }
            },
            onOCR: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenshotManager.captureForOCR()
                }
            },
            onDismiss: { [weak self] in
                DispatchQueue.main.async {
                    self?.closeSelectionOverlay()
                }
            }
        )

        let hostingView = NSHostingView(rootView: menuView)
        let menuSize = NSSize(width: 280, height: 420)
        hostingView.frame = NSRect(origin: .zero, size: menuSize)

        let centerX = screen.frame.midX - menuSize.width / 2
        let centerY = screen.frame.midY - menuSize.height / 2

        let window = KeyableWindow(
            contentRect: NSRect(x: centerX, y: centerY, width: menuSize.width, height: menuSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.onEscapeKey = { [weak self] in
            self?.closeSelectionOverlay()
        }

        selectionOverlayWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func closeSelectionOverlay() {
        guard let windowToClose = selectionOverlayWindow else { return }
        selectionOverlayWindow = nil

        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    // MARK: - Keyboard Shortcuts Overlay

    func toggleKeyboardShortcutsOverlay() {
        if let existingWindow = keyboardShortcutsWindow, existingWindow.isVisible {
            closeKeyboardShortcutsOverlay()
        } else {
            showKeyboardShortcutsOverlay()
        }
    }

    func showKeyboardShortcutsOverlay() {
        // Close existing window if any
        closeKeyboardShortcutsOverlay()

        guard let anchorWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            debugLog("KeyboardShortcutsOverlay: Skipped (no active window)")
            return
        }

        let overlayView = KeyboardShortcutsOverlay(
            useNativeShortcuts: keyboardShortcuts.useNativeShortcuts,
            onClose: { [weak self] in
                self?.closeKeyboardShortcutsOverlay()
            }
        )

        let windowSize = NSSize(width: 560, height: 680)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)

        guard let screen = anchorWindow.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Center on screen
        let windowFrame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Keyboard Shortcuts"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces]
        window.delegate = self

        // Hide system traffic lights - we use custom SwiftUI buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        keyboardShortcutsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        debugLog("KeyboardShortcutsOverlay: Window shown")
    }

    func closeKeyboardShortcutsOverlay() {
        guard let windowToClose = keyboardShortcutsWindow else { return }
        keyboardShortcutsWindow = nil

        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Handle QuickAccessOverlay window close
        if window === quickAccessWindow {
            quickAccessWindow = nil
            quickAccessController?.isVisible = false
            quickAccessController = nil
        }

        // Handle Settings window close
        if window === settingsWindow {
            settingsWindow = nil
        }

        // Handle Annotation Editor window close
        if window === annotationWindow {
            annotationWindow = nil
        }

        // Handle Keyboard Shortcuts window close
        if window === keyboardShortcutsWindow {
            keyboardShortcutsWindow = nil
        }
    }

    // MARK: - Settings

    private func bringSettingsWindowToFront(_ window: NSWindow) {
        // Accessory apps can be activated programmatically; make the Settings window key
        // and force it to the front so menu-triggered opens are immediately visible.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc func openSettings() {
        if let existingWindow = settingsWindow {
            bringSettingsWindowToFront(existingWindow)
            return
        }

        let preferencesView = PreferencesView()
        let hostingView = NSHostingView(rootView: preferencesView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.toolbar = toolbar
        window.contentView = hostingView
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 700, height: 550)
        window.maxSize = NSSize(width: 1200, height: 900)

        settingsWindow = window
        bringSettingsWindowToFront(window)
    }

    @objc func openShortcutPreferences() {
        let shown = SystemShortcutManager.shared.showRemapAlert(from: settingsWindow ?? NSApp.keyWindow)
        debugLog("ShortcutModePicker: manual open shown=\(shown)")
    }

    // MARK: - Annotation Editor

    func showAnnotationEditor(for capture: CaptureItem) {
        debugLog("AppDelegate: Opening annotation editor for \(capture.filename)")

        if let existingWindow = annotationWindow {
            existingWindow.close()
            annotationWindow = nil
        }

        let annotationView = AnnotationEditor(capture: capture)
            .environmentObject(storageManager)

        let hostingView = NSHostingView(rootView: annotationView)

        // Get screen size
        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)

        // Get actual image size to fit window appropriately
        let imageURL = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        var imageSize = NSSize(width: 800, height: 600) // Default fallback
        if let image = NSImage(contentsOf: imageURL) {
            imageSize = image.size
        }

        // Calculate window size based on image
        // Add space for toolbar (52pt) + status bar (28pt) + margins
        let chromeHeight: CGFloat = 100
        let margin: CGFloat = 40

        // Target window size to fit image with chrome
        let targetWidth = imageSize.width + margin
        let targetHeight = imageSize.height + chromeHeight + margin

        // Constrain to screen bounds (max 90% of screen)
        // But also ensure minimum size for toolbar (700px wide minimum)
        let windowSize = NSSize(
            width: min(max(targetWidth, 700), screenSize.width * 0.9),
            height: min(max(targetHeight, 500), screenSize.height * 0.9)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.title = "Annotate Screenshot"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 800, height: 500) // Ensure toolbar fits

        // Hide system traffic lights - we use custom SwiftUI buttons in the toolbar
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        annotationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Position traffic lights to align with toolbar center (26pt from top)
        repositionTrafficLights(in: window)

        debugLog("AppDelegate: Annotation editor window shown, size: \(windowSize)")
    }

    // MARK: - Traffic Light Positioning

    /// Repositions the traffic light buttons (close, minimize, zoom) to align with the 52pt toolbar
    /// The toolbar content is vertically centered, so buttons should be centered at 26pt from top
    private func repositionTrafficLights(in window: NSWindow) {
        let toolbarHeight: CGFloat = 52
        let buttonCenterY = toolbarHeight / 2  // 26pt from top of window
        let buttonDiameter: CGFloat = 12

        // Standard horizontal positions for traffic lights
        let closeX: CGFloat = 14
        let miniaturizeX: CGFloat = 34
        let zoomX: CGFloat = 54

        // Get the buttons and their container
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let containerView = closeButton.superview else {
            return
        }

        // Calculate Y position in superview coordinates (origin at bottom-left)
        // We want button center at 26pt from top of window
        // In container coordinates: y = containerHeight - buttonCenterY - (buttonDiameter/2)
        let containerHeight = containerView.frame.height
        let buttonY = containerHeight - buttonCenterY - (buttonDiameter / 2)

        closeButton.setFrameOrigin(NSPoint(x: closeX, y: buttonY))
        miniaturizeButton.setFrameOrigin(NSPoint(x: miniaturizeX, y: buttonY))
        zoomButton.setFrameOrigin(NSPoint(x: zoomX, y: buttonY))
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // Reposition traffic lights after resize (they tend to reset)
        if let window = notification.object as? NSWindow, window == annotationWindow {
            repositionTrafficLights(in: window)
        }
    }
}

struct AllInOneMenuView: View {
    let onCaptureArea: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureFullscreen: () -> Void
    let onRecordArea: () -> Void
    let onRecordWindow: () -> Void
    let onRecordFullscreen: () -> Void
    let onOCR: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("ScreenCapture")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            VStack(spacing: 4) {
                MenuButton(icon: "rectangle.dashed", title: "Capture Area", shortcut: "⌃⇧4") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureArea() }
                }

                MenuButton(icon: "macwindow", title: "Capture Window", shortcut: "⌃⇧5") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureWindow() }
                }

                MenuButton(icon: "rectangle.fill.on.rectangle.fill", title: "Capture Fullscreen", shortcut: "⌃⇧3") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureFullscreen() }
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                MenuButton(icon: "video.badge.plus", title: "Record Area", shortcut: "⌃⇧7") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordArea() }
                }

                MenuButton(icon: "video", title: "Record Window", shortcut: "⌥⇧8") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordWindow() }
                }

                MenuButton(icon: "video.fill", title: "Record Fullscreen", shortcut: "⌃⇧9") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordFullscreen() }
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                MenuButton(icon: "text.viewfinder", title: "Capture Text (OCR)", shortcut: "⌃⇧O") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onOCR() }
                }
            }
            .padding(.vertical, 12)

            Spacer()

            Text("Press Esc to cancel")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: 280, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onExitCommand {
            onDismiss()
        }
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(.accentColor)

                Text(title)
                    .font(.system(size: 13))

                Spacer()

                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.horizontal, 8)
    }
}

private extension AppDelegate {
    func attemptShortcutModePrompt(trigger: String) {
        let shown = SystemShortcutManager.shared.showRemapPromptIfNeeded()
        debugLog("ShortcutModePicker: trigger=\(trigger), shown=\(shown), hasPrompted=\(SystemShortcutManager.shared.hasPromptedForRemap), hasChosen=\(SystemShortcutManager.shared.hasChosenShortcutMode)")
    }
}

extension Notification.Name {
    static let captureCompleted = Notification.Name("captureCompleted")
    static let recordingCompleted = Notification.Name("recordingCompleted")
    static let recordingStarted = Notification.Name("recordingStarted")
    static let recordingStopped = Notification.Name("recordingStopped")
    static let openAnnotationEditor = Notification.Name("openAnnotationEditor")
}
