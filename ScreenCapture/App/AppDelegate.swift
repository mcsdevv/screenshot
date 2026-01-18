import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    var screenshotManager: ScreenshotManager!
    var screenRecordingManager: ScreenRecordingManager!
    var storageManager: StorageManager!
    var webcamManager: WebcamManager?
    var keyboardShortcuts: KeyboardShortcuts!
    var quickAccessWindow: NSWindow?
    var quickAccessController: QuickAccessOverlayController?
    var selectionOverlayWindow: NSWindow?
    var settingsWindow: NSWindow?
    var annotationWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize debug logger
        debugLog("Application launching...")
        debugLog("Log file at: \(DebugLogger.shared.logFilePath)")

        storageManager = StorageManager()
        screenshotManager = ScreenshotManager(storageManager: storageManager)
        screenRecordingManager = ScreenRecordingManager(storageManager: storageManager)
        webcamManager = WebcamManager()
        keyboardShortcuts = KeyboardShortcuts()

        setupKeyboardShortcuts()
        setupNotifications()
        setupMainMenu()

        requestPermissions()

        // Show shortcut remapping prompt on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SystemShortcutManager.shared.showRemapPromptIfNeeded()
        }

        debugLog("Application finished launching")
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

        keyboardShortcuts.register(shortcut: .captureScrolling) { [weak self] in
            DispatchQueue.main.async {
                self?.screenshotManager.captureScrolling()
            }
        }

        keyboardShortcuts.register(shortcut: .recordScreen) { [weak self] in
            DispatchQueue.main.async {
                self?.screenRecordingManager.toggleRecording()
            }
        }

        keyboardShortcuts.register(shortcut: .recordGIF) { [weak self] in
            DispatchQueue.main.async {
                self?.screenRecordingManager.toggleGIFRecording()
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

        debugLog("AppDelegate: All keyboard shortcuts registered")
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .captureCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                // Defer overlay display to ensure capture processing is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.showQuickAccessOverlay(for: capture)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                // Defer overlay display to ensure recording processing is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.showQuickAccessOverlay(for: capture)
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

    private func requestPermissions() {
        // Check screen capture permission at startup and show alert if not granted
        // This gives users a clear path to enable the permission before trying to capture
        DispatchQueue.main.async {
            _ = PermissionManager.shared.ensureScreenCapturePermission()
        }
    }

    func showQuickAccessOverlay(for capture: CaptureItem) {
        closeQuickAccessOverlay()

        let controller = QuickAccessOverlayController(capture: capture, storageManager: storageManager)
        quickAccessController = controller

        controller.setDismissAction { [weak self] in
            DispatchQueue.main.async {
                self?.closeQuickAccessOverlay()
            }
        }

        let overlayView = QuickAccessOverlay(controller: controller)

        let windowSize = NSSize(width: 340, height: 340)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let padding: CGFloat = 20

            let windowFrame = NSRect(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding,
                width: windowSize.width,
                height: windowSize.height
            )

            let window = NSWindow(
                contentRect: windowFrame,
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

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
        }
    }

    func closeQuickAccessOverlay() {
        guard let windowToClose = quickAccessWindow else { return }
        quickAccessWindow = nil

        // Mark controller as not visible to prevent any further actions
        quickAccessController?.isVisible = false

        // Hide window immediately
        windowToClose.orderOut(nil)

        // Defer cleanup to next run loop to allow SwiftUI to finish
        DispatchQueue.main.async { [weak self] in
            windowToClose.contentView = nil
            windowToClose.close()
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
            onCaptureScrolling: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenshotManager.captureScrolling()
                }
            },
            onRecordVideo: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenRecordingManager.toggleRecording()
                }
            },
            onRecordGIF: { [weak self] in
                DispatchQueue.main.async {
                    self?.screenRecordingManager.toggleGIFRecording()
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
        let menuSize = NSSize(width: 280, height: 360)
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

    func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcuts.unregisterAll()
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
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 700, height: 550)
        window.maxSize = NSSize(width: 1200, height: 900)

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    let onCaptureScrolling: () -> Void
    let onRecordVideo: () -> Void
    let onRecordGIF: () -> Void
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

                MenuButton(icon: "scroll", title: "Scrolling Capture", shortcut: "⌃⇧6") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureScrolling() }
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                MenuButton(icon: "video.fill", title: "Record Video", shortcut: "⌃⇧7") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordVideo() }
                }

                MenuButton(icon: "photo.on.rectangle.angled", title: "Record GIF", shortcut: "⌃⇧8") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordGIF() }
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
        .frame(width: 280, height: 360)
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

extension Notification.Name {
    static let captureCompleted = Notification.Name("captureCompleted")
    static let recordingCompleted = Notification.Name("recordingCompleted")
    static let recordingStarted = Notification.Name("recordingStarted")
    static let recordingStopped = Notification.Name("recordingStopped")
    static let openAnnotationEditor = Notification.Name("openAnnotationEditor")
}
