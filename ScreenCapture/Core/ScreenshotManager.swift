import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// Custom window class that accepts key events (required for borderless windows)
// Used by ScreenRecordingManager and other components
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class ScreenshotManager: NSObject, ObservableObject {
    private let storageManager: StorageManager
    private var pendingAction: PendingAction = .save

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
        let scrollingCapture = ScrollingCapture(storageManager: storageManager)
        scrollingCapture.start()
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

    // MARK: - Native Screencapture

    private func captureWithNativeScreencapture(interactive: Bool = true, windowMode: Bool = false) {
        debugLog("captureWithNativeScreencapture(interactive: \(interactive), windowMode: \(windowMode))")

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("capture_\(UUID().uuidString).png")

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

        debugLog("Running: screencapture \(arguments.joined(separator: " "))")

        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard process.terminationStatus == 0 else {
                    debugLog("screencapture cancelled or failed with status: \(process.terminationStatus)")
                    // Check if this is a permission issue and show alert if so
                    PermissionManager.shared.handleCaptureFailure(status: process.terminationStatus)
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

                self?.handleCapturedImage(image)
            }
        }

        do {
            try task.run()
        } catch {
            errorLog("Failed to run screencapture", error: error)
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
