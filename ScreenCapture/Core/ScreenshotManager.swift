import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// Custom window class that accepts key events (required for borderless windows)
// Used by ScreenRecordingManager and other components
class KeyableWindow: NSWindow {
    var onEscapeKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // Keep helper overlays visible to the user while preventing them from being encoded in captures.
        sharingType = .none
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscapeKey {
            onEscapeKey()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
class ScreenshotManager: NSObject, ObservableObject {
    private enum ScreenshotTarget {
        case fullscreen
        case area(CGRect)
        case window(windowID: UInt32)
    }

    private struct ScreenshotContext {
        let filter: SCContentFilter
        let streamConfiguration: SCStreamConfiguration
    }

    private let storageManager: StorageManager
    private var pendingAction: PendingAction = .save
    private var captureTask: Task<Void, Never>?
    private var captureTaskID = UUID()
    private var currentCaptureTask: Process?
    private var currentTempFile: URL?
    private var selectionWindow: NSWindow?
    private var windowSelectionWindow: NSWindow?
    private var scrollingCapture: ScrollingCapture?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    enum PendingAction {
        case save, ocr, pin
    }

    override init() {
        fatalError("Use init(storageManager:)")
    }

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
        debugLog("ScreenshotManager initialized")
    }

    // MARK: - Public Capture Methods

    func captureArea() {
        debugLog("captureArea() called")
        pendingAction = .save
        showAreaSelection()
    }

    func captureWindow() {
        debugLog("captureWindow() called")
        pendingAction = .save
        captureWithNativeScreencapture(windowMode: true)
    }

    func captureFullscreen() {
        debugLog("captureFullscreen() called")
        pendingAction = .save
        capture(target: .fullscreen)
    }

    func captureScrolling() {
        debugLog("captureScrolling() called")
        pendingAction = .save
        scrollingCapture = ScrollingCapture(storageManager: storageManager) { [weak self] in
            self?.scrollingCapture = nil
        }
        scrollingCapture?.start()
    }

    func captureForOCR() {
        debugLog("captureForOCR() called")
        pendingAction = .ocr
        showAreaSelection()
    }

    func captureForPinning() {
        debugLog("captureForPinning() called")
        pendingAction = .pin
        showAreaSelection()
    }

    func cancelPendingCapture(reason: String) {
        debugLog("Cancelling pending capture (\(reason))")
        captureTask?.cancel()
        captureTask = nil
        removeEscapeCancellationMonitors()

        if let task = currentCaptureTask {
            if task.isRunning {
                task.interrupt()
                task.terminate()
            }
            currentCaptureTask = nil
        }

        if let tempFile = currentTempFile {
            try? FileManager.default.removeItem(at: tempFile)
            currentTempFile = nil
        }
        closeSelectionWindow()
        closeWindowSelectionWindow()
    }

    // MARK: - Selection UI

    private func showAreaSelection() {
        closeSelectionWindow()

        guard let screen = currentInteractionScreen() else {
            errorLog("ScreenshotManager: No active screen available for area selection")
            return
        }

        let selectionView = SelectionOverlay(
            onSelection: { [weak self] rect in
                self?.closeSelectionWindow()
                self?.capture(target: .area(rect))
            },
            onCancel: { [weak self] in
                self?.closeSelectionWindow()
            },
            screenFrame: screen.frame
        )

        let hostingView = NSHostingView(rootView: selectionView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeSelectionWindow() {
        guard let windowToClose = selectionWindow else { return }
        selectionWindow = nil

        windowToClose.orderOut(nil)
        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func showWindowSelection() {
        closeWindowSelectionWindow()

        guard let screen = currentInteractionScreen() else {
            errorLog("ScreenshotManager: No active screen available for window selection")
            return
        }

        let windowView = WindowSelectionView(
            title: "Select Window to Capture",
            onWindowSelected: { [weak self] window in
                self?.closeWindowSelectionWindow()
                self?.capture(target: .window(windowID: window.windowID))
            },
            onCancel: { [weak self] in
                self?.closeWindowSelectionWindow()
            }
        )

        let hostingView = NSHostingView(rootView: windowView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        windowSelectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeWindowSelectionWindow() {
        guard let windowToClose = windowSelectionWindow else { return }
        windowSelectionWindow = nil

        windowToClose.orderOut(nil)
        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    // MARK: - ScreenCaptureKit Capture

    private func captureWithNativeScreencapture(interactive: Bool = true, windowMode: Bool = false) {
        debugLog("captureWithNativeScreencapture(interactive: \(interactive), windowMode: \(windowMode))")

        captureTask?.cancel()
        captureTask = nil

        if let runningTask = currentCaptureTask, runningTask.isRunning {
            debugLog("Previous screencapture task still running, terminating before starting a new one")
            cancelPendingCapture(reason: "new capture started")
        }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("capture_\(UUID().uuidString).png")
        currentTempFile = tempFile

        var arguments = ["-o", tempFile.path] // -o: no shadow

        if interactive {
            arguments.insert("-i", at: 0) // -i: interactive mode
        }

        if windowMode {
            arguments.insert("-w", at: 0) // -w: window mode
            arguments.insert("-i", at: 0) // -i: interactive (window picker)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments
        currentCaptureTask = task

        if interactive || windowMode {
            installEscapeCancellationMonitors()
        } else {
            removeEscapeCancellationMonitors()
        }

        debugLog("Running: screencapture \(arguments.joined(separator: " "))")

        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                let isCurrentTask = self.currentCaptureTask === task
                if isCurrentTask {
                    self.currentCaptureTask = nil
                    self.currentTempFile = nil
                    self.removeEscapeCancellationMonitors()
                }

                guard isCurrentTask else {
                    try? FileManager.default.removeItem(at: tempFile)
                    return
                }
                guard process.terminationStatus == 0 else {
                    let reason = process.terminationReason == .uncaughtSignal ? "signal" : "status"
                    debugLog("screencapture cancelled or failed (\(reason): \(process.terminationStatus))")
                    try? FileManager.default.removeItem(at: tempFile)
                    return
                }

                guard FileManager.default.fileExists(atPath: tempFile.path),
                      let image = NSImage(contentsOf: tempFile) else {
                    errorLog("Failed to load captured image from \(tempFile.path)")
                    return
                }

                debugLog("Screenshot captured: \(image.size)")

                try? FileManager.default.removeItem(at: tempFile)
                self.handleCapturedImage(image)
            }
        }

        do {
            try task.run()
        } catch {
            errorLog("Failed to run screencapture", error: error)
            removeEscapeCancellationMonitors()
            currentCaptureTask = nil
            currentTempFile = nil
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    private func installEscapeCancellationMonitors() {
        removeEscapeCancellationMonitors()

        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }

            DispatchQueue.main.async {
                self?.cancelPendingCapture(reason: "escape key pressed")
            }

            return nil
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }

            DispatchQueue.main.async {
                self?.cancelPendingCapture(reason: "escape key pressed")
            }
        }
    }

    private func removeEscapeCancellationMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }

        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    private func capture(target: ScreenshotTarget) {
        captureTask?.cancel()
        let taskID = UUID()
        captureTaskID = taskID

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let context = try await self.makeCaptureContext(for: target)
                try Task.checkCancellation()

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: context.filter,
                    configuration: context.streamConfiguration
                )
                try Task.checkCancellation()

                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                self.handleCapturedImage(image)
            } catch is CancellationError {
                debugLog("Screenshot capture cancelled")
            } catch {
                errorLog("Screenshot capture failed", error: error)
                self.presentCaptureError(error)
            }

            if self.captureTaskID == taskID {
                self.captureTask = nil
            }
        }
    }

    private func makeCaptureContext(for target: ScreenshotTarget) async throws -> ScreenshotContext {
        let showsCursor = includeCursorInCapture

        switch target {
        case .fullscreen:
            let display = try await displayForCurrentInteraction()
            let scaleFactor = displayScaleFactor(for: display.displayID)
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = max(2, Int((CGFloat(display.width) * scaleFactor).rounded()))
            config.height = max(2, Int((CGFloat(display.height) * scaleFactor).rounded()))
            config.captureResolution = .best
            config.showsCursor = showsCursor
            return ScreenshotContext(filter: filter, streamConfiguration: config)

        case let .area(rect):
            let display = try await ScreenCaptureContentProvider.shared.getDisplay(containing: rect)
            let sourceRect = localizedSourceRect(for: rect, displayID: display.displayID)
            let scaleFactor = displayScaleFactor(for: display.displayID)
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            config.width = max(2, Int((sourceRect.width * scaleFactor).rounded()))
            config.height = max(2, Int((sourceRect.height * scaleFactor).rounded()))
            config.captureResolution = .best
            config.showsCursor = showsCursor
            return ScreenshotContext(filter: filter, streamConfiguration: config)

        case let .window(windowID):
            let content = try await ScreenCaptureContentProvider.shared.getContent()
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureEngineError.invalidWindowTarget(windowID)
            }

            let display = try await ScreenCaptureContentProvider.shared.getDisplay(containing: window.frame)
            let scaleFactor = displayScaleFactor(for: display.displayID)
            let filter = SCContentFilter(desktopIndependentWindow: window)

            let config = SCStreamConfiguration()
            config.width = max(2, Int((window.frame.width * scaleFactor).rounded()))
            config.height = max(2, Int((window.frame.height * scaleFactor).rounded()))
            config.captureResolution = .best
            config.showsCursor = showsCursor
            return ScreenshotContext(filter: filter, streamConfiguration: config)
        }
    }

    private var includeCursorInCapture: Bool {
        guard UserDefaults.standard.object(forKey: "showCursor") != nil else { return false }
        return UserDefaults.standard.bool(forKey: "showCursor")
    }

    private func displayForCurrentInteraction() async throws -> SCDisplay {
        let content = try await ScreenCaptureContentProvider.shared.getContent()
        guard let fallbackDisplay = content.displays.first else {
            throw NSError(
                domain: "ScreenshotManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display found"]
            )
        }

        guard let screen = currentInteractionScreen(),
              let screenDisplayID = displayID(for: screen),
              let matchedDisplay = content.displays.first(where: { $0.displayID == screenDisplayID }) else {
            return fallbackDisplay
        }

        return matchedDisplay
    }

    private func currentInteractionScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func displayScaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            if CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.backingScaleFactor
            }
        }

        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private func displayFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            if CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.frame
            }
        }

        return nil
    }

    private func localizedSourceRect(for globalRect: CGRect, displayID: CGDirectDisplayID) -> CGRect {
        guard let displayFrame = displayFrame(for: displayID) else {
            return globalRect.standardized
        }

        // ScreenCaptureKit sourceRect uses top-left coordinates per-display.
        let localX = globalRect.minX - displayFrame.minX
        let localYBottom = globalRect.minY - displayFrame.minY
        let localYTop = displayFrame.height - localYBottom - globalRect.height

        let localizedRect = CGRect(
            x: localX,
            y: localYTop,
            width: globalRect.width,
            height: globalRect.height
        ).standardized

        let displayBounds = CGRect(x: 0, y: 0, width: displayFrame.width, height: displayFrame.height)
        let clippedRect = localizedRect.intersection(displayBounds)
        guard !clippedRect.isNull, clippedRect.width >= 2, clippedRect.height >= 2 else {
            return localizedRect
        }

        return clippedRect
    }

    // MARK: - Image Handling

    private func handleCapturedImage(_ image: NSImage) {
        debugLog("handleCapturedImage() called - action: \(pendingAction)")

        switch pendingAction {
        case .save:
            saveAndNotify(image: image)
        case .ocr:
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                performOCR(on: cgImage)
            }
        case .pin:
            pinImage(image)
        }
    }

    private func saveAndNotify(image: NSImage) {
        debugLog("saveAndNotify() - saving image...")
        let capture = storageManager.saveCapture(image: image, type: .screenshot)
        debugLog("Image saved, posting notification")
        NotificationCenter.default.post(name: .captureCompleted, object: capture)
        playScreenshotSound()
    }

    private var shouldPlayCaptureSound: Bool {
        guard UserDefaults.standard.object(forKey: "playSound") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "playSound")
    }

    private func performOCR(on cgImage: CGImage) {
        debugLog("performOCR() starting")
        let ocrService = OCRService()
        ocrService.recognizeText(in: cgImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    debugLog("OCR successful, text length: \(text.count)")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self?.showOCRNotification(text: text)
                case .failure(let error):
                    errorLog("OCR failed", error: error)
                    self?.showOCRError(error)
                }
            }
        }
    }

    private func pinImage(_ image: NSImage) {
        debugLog("pinImage() - creating pinned window")
        let pinnedWindow = PinnedScreenshotWindow(image: image)
        pinnedWindow.show()
        debugLog("Pinned window displayed")
    }

    private func playScreenshotSound() {
        guard shouldPlayCaptureSound else { return }
        NSSound(named: "Grab")?.play()
    }

    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showOCRNotification(text: String) {
        let truncated = text.prefix(100) + (text.count > 100 ? "..." : "")
        let alert = NSAlert()
        alert.messageText = "Text Copied to Clipboard"
        alert.informativeText = String(truncated)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showOCRError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "OCR Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
