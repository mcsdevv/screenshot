import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var menuBarController: MenuBarController!
    var screenshotManager: ScreenshotManager!
    var screenRecordingManager: ScreenRecordingManager!
    var storageManager: StorageManager!
    var keyboardShortcuts: KeyboardShortcuts!
    var quickAccessWindow: NSWindow?
    var selectionOverlayWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize debug logger
        debugLog("Application launching...")
        debugLog("Log file at: \(DebugLogger.shared.logFilePath)")

        storageManager = StorageManager()
        screenshotManager = ScreenshotManager(storageManager: storageManager)
        screenRecordingManager = ScreenRecordingManager(storageManager: storageManager)
        keyboardShortcuts = KeyboardShortcuts()

        menuBarController = MenuBarController(
            screenshotManager: screenshotManager,
            screenRecordingManager: screenRecordingManager,
            storageManager: storageManager
        )

        setupKeyboardShortcuts()
        setupNotifications()

        requestPermissions()

        debugLog("Application finished launching")
    }

    private func setupKeyboardShortcuts() {
        keyboardShortcuts.register(shortcut: .captureArea) { [weak self] in
            Task { @MainActor in
                self?.screenshotManager.captureArea()
            }
        }

        keyboardShortcuts.register(shortcut: .captureWindow) { [weak self] in
            Task { @MainActor in
                self?.screenshotManager.captureWindow()
            }
        }

        keyboardShortcuts.register(shortcut: .captureFullscreen) { [weak self] in
            Task { @MainActor in
                self?.screenshotManager.captureFullscreen()
            }
        }

        keyboardShortcuts.register(shortcut: .captureScrolling) { [weak self] in
            Task { @MainActor in
                self?.screenshotManager.captureScrolling()
            }
        }

        keyboardShortcuts.register(shortcut: .recordScreen) { [weak self] in
            Task { @MainActor in
                self?.screenRecordingManager.toggleRecording()
            }
        }

        keyboardShortcuts.register(shortcut: .recordGIF) { [weak self] in
            Task { @MainActor in
                self?.screenRecordingManager.toggleGIFRecording()
            }
        }

        keyboardShortcuts.register(shortcut: .allInOne) { [weak self] in
            Task { @MainActor in
                self?.showAllInOneMenu()
            }
        }

        keyboardShortcuts.register(shortcut: .ocr) { [weak self] in
            Task { @MainActor in
                self?.screenshotManager.captureForOCR()
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .captureCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                self?.showQuickAccessOverlay(for: capture)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .recordingCompleted)
            .compactMap { $0.object as? CaptureItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capture in
                self?.showQuickAccessOverlay(for: capture)
            }
            .store(in: &cancellables)
    }

    private func requestPermissions() {
        // Don't proactively request screen capture permission
        // The system will automatically prompt when SCShareableContent is first used
        // Calling CGRequestScreenCaptureAccess() can cause repeated prompts on macOS
        _ = CGPreflightScreenCaptureAccess() // Just check, don't request
    }

    func showQuickAccessOverlay(for capture: CaptureItem) {
        let overlayView = QuickAccessOverlay(capture: capture, storageManager: storageManager) {
            self.closeQuickAccessOverlay()
        }

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 280)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = NSRect(
                x: screenFrame.maxX - 360,
                y: screenFrame.minY + 20,
                width: 340,
                height: 280
            )

            quickAccessWindow = NSWindow(
                contentRect: windowFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            quickAccessWindow?.contentView = hostingView
            quickAccessWindow?.isOpaque = false
            quickAccessWindow?.backgroundColor = .clear
            quickAccessWindow?.level = .floating
            quickAccessWindow?.hasShadow = true
            quickAccessWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary]
            quickAccessWindow?.makeKeyAndOrderFront(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.closeQuickAccessOverlay()
            }
        }
    }

    func closeQuickAccessOverlay() {
        guard let windowToClose = quickAccessWindow else { return }
        quickAccessWindow = nil
        windowToClose.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            windowToClose.close()
        }
    }

    func showAllInOneMenu() {
        guard let screen = NSScreen.main else { return }

        let menuView = AllInOneMenuView(
            onCaptureArea: { [weak self] in
                Task { @MainActor in
                    self?.screenshotManager.captureArea()
                }
            },
            onCaptureWindow: { [weak self] in
                Task { @MainActor in
                    self?.screenshotManager.captureWindow()
                }
            },
            onCaptureFullscreen: { [weak self] in
                Task { @MainActor in
                    self?.screenshotManager.captureFullscreen()
                }
            },
            onCaptureScrolling: { [weak self] in
                Task { @MainActor in
                    self?.screenshotManager.captureScrolling()
                }
            },
            onRecordVideo: { [weak self] in
                Task { @MainActor in
                    self?.screenRecordingManager.toggleRecording()
                }
            },
            onRecordGIF: { [weak self] in
                Task { @MainActor in
                    self?.screenRecordingManager.toggleGIFRecording()
                }
            },
            onOCR: { [weak self] in
                Task { @MainActor in
                    self?.screenshotManager.captureForOCR()
                }
            },
            onDismiss: { [weak self] in
                self?.selectionOverlayWindow?.close()
                self?.selectionOverlayWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: menuView)
        let menuSize = NSSize(width: 280, height: 360)
        hostingView.frame = NSRect(origin: .zero, size: menuSize)

        let centerX = screen.frame.midX - menuSize.width / 2
        let centerY = screen.frame.midY - menuSize.height / 2

        selectionOverlayWindow = NSWindow(
            contentRect: NSRect(x: centerX, y: centerY, width: menuSize.width, height: menuSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        selectionOverlayWindow?.contentView = hostingView
        selectionOverlayWindow?.isOpaque = false
        selectionOverlayWindow?.backgroundColor = .clear
        selectionOverlayWindow?.level = .screenSaver
        selectionOverlayWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcuts.unregisterAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
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
                MenuButton(icon: "rectangle.dashed", title: "Capture Area", shortcut: "⌘⇧4") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureArea() }
                }

                MenuButton(icon: "macwindow", title: "Capture Window", shortcut: "⌘⇧5") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureWindow() }
                }

                MenuButton(icon: "rectangle.fill.on.rectangle.fill", title: "Capture Fullscreen", shortcut: "⌘⇧3") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureFullscreen() }
                }

                MenuButton(icon: "scroll", title: "Scrolling Capture", shortcut: "⌘⇧6") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onCaptureScrolling() }
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                MenuButton(icon: "video.fill", title: "Record Video", shortcut: "⌘⇧7") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordVideo() }
                }

                MenuButton(icon: "photo.on.rectangle.angled", title: "Record GIF", shortcut: "⌘⇧8") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onRecordGIF() }
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                MenuButton(icon: "text.viewfinder", title: "Capture Text (OCR)", shortcut: "⌘⇧O") {
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
}
