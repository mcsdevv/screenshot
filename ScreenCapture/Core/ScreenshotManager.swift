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
    private let storageManager: StorageManager
    private var pendingAction: PendingAction = .save
    private var currentCaptureTask: Process?
    private var currentTempFile: URL?
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
        captureWithNativeScreencapture(interactive: true)
    }

    func captureWindow() {
        debugLog("captureWindow() called")
        pendingAction = .save
        captureWithNativeScreencapture(windowMode: true)
    }

    func captureFullscreen() {
        debugLog("captureFullscreen() called")
        pendingAction = .save
        captureWithNativeScreencapture(interactive: false)
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
        captureWithNativeScreencapture(interactive: true)
    }

    func captureForPinning() {
        debugLog("captureForPinning() called")
        pendingAction = .pin
        captureWithNativeScreencapture(interactive: true)
    }

    func cancelPendingCapture(reason: String) {
        removeEscapeCancellationMonitors()

        guard let task = currentCaptureTask else { return }
        debugLog("Cancelling screencapture task (\(reason))")
        if task.isRunning {
            task.interrupt()
            task.terminate()
        }
        currentCaptureTask = nil
        if let tempFile = currentTempFile {
            try? FileManager.default.removeItem(at: tempFile)
        }
        currentTempFile = nil
    }

    // MARK: - Native Screencapture

    private func captureWithNativeScreencapture(interactive: Bool = true, windowMode: Bool = false) {
        debugLog("captureWithNativeScreencapture(interactive: \(interactive), windowMode: \(windowMode))")

        if let runningTask = currentCaptureTask, runningTask.isRunning {
            debugLog("Previous screencapture task still running, terminating before starting a new one")
            cancelPendingCapture(reason: "new capture started")
        }

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("capture_\(UUID().uuidString).png")
        currentTempFile = tempFile

        var arguments = ["-o", tempFile.path]  // -o: no shadow

        if interactive {
            arguments.insert("-i", at: 0)  // -i: interactive mode (area selection)
        }

        if windowMode {
            arguments.insert("-w", at: 0)  // -w: window mode
            arguments.insert("-i", at: 0)  // -i: interactive (lets you click on a window)
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
                guard let self = self else { return }
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

                // Clean up temp file
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
        NSSound(named: "Grab")?.play()
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
