import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import Vision

// Custom window class that accepts key events (required for borderless windows)
// Used by ScreenRecordingManager and other components
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Helper class to capture a single frame from SCStream
class SingleFrameCaptureOutput: NSObject, SCStreamOutput {
    private let onCapture: (CGImage) -> Void
    private var hasCaptured = false

    init(onCapture: @escaping (CGImage) -> Void) {
        self.onCapture = onCapture
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !hasCaptured else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            debugLog("SingleFrameCaptureOutput: No image buffer in sample")
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            debugLog("SingleFrameCaptureOutput: Failed to create CGImage")
            return
        }

        hasCaptured = true
        debugLog("SingleFrameCaptureOutput: Captured frame")
        onCapture(cgImage)
    }
}

@MainActor
class ScreenshotManager: NSObject, ObservableObject {
    private let storageManager: StorageManager
    private var pendingAction: PendingAction = .save
    private let picker = SCContentSharingPicker.shared
    private var activeStream: SCStream?
    private var activeStreamOutput: SingleFrameCaptureOutput?

    enum PendingAction {
        case save, ocr, pin
    }

    override init() {
        fatalError("Use init(storageManager:)")
    }

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
        setupPicker()
    }

    private func setupPicker() {
        debugLog("Setting up SCContentSharingPicker")
        picker.add(self)
        picker.defaultConfiguration = SCContentSharingPickerConfiguration()
        debugLog("Picker configured")
    }

    deinit {
        picker.remove(self)
    }

    // MARK: - Public Capture Methods

    func captureArea() {
        debugLog("captureArea() called - presenting system picker")
        pendingAction = .save
        presentPicker(mode: .singleDisplay)
    }

    func captureWindow() {
        debugLog("captureWindow() called - presenting system picker")
        pendingAction = .save
        presentPicker(mode: .singleWindow)
    }

    func captureFullscreen() {
        debugLog("captureFullscreen() called - presenting system picker")
        pendingAction = .save
        presentPicker(mode: .singleDisplay)
    }

    func captureScrolling() {
        debugLog("captureScrolling() called")
        pendingAction = .save
        let scrollingCapture = ScrollingCapture(storageManager: storageManager)
        scrollingCapture.start()
    }

    func captureForOCR() {
        debugLog("captureForOCR() called - presenting system picker")
        pendingAction = .ocr
        presentPicker(mode: .singleDisplay)
    }

    func captureForPinning() {
        debugLog("captureForPinning() called - presenting system picker")
        pendingAction = .pin
        presentPicker(mode: .singleDisplay)
    }

    // MARK: - Picker Presentation

    private func presentPicker(mode: SCContentSharingPickerMode) {
        debugLog("Presenting picker with mode: \(mode)")

        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [mode]
        picker.defaultConfiguration = config

        picker.isActive = true
        picker.present()

        debugLog("Picker presented")
    }

    // MARK: - Capture with Filter

    private func captureWithFilter(_ filter: SCContentFilter) {
        debugLog("captureWithFilter() called")

        Task {
            do {
                let config = SCStreamConfiguration()
                config.scalesToFit = false
                config.showsCursor = false
                config.captureResolution = .best
                config.width = 3840
                config.height = 2160
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.queueDepth = 1

                debugLog("Creating stream for single frame capture...")

                // Use SCStream to capture a single frame (works with picker without extra permissions)
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                self.activeStream = stream  // Keep strong reference

                // Use continuation to wait for capture
                let capturedImage: CGImage = try await withCheckedThrowingContinuation { continuation in
                    let streamOutput = SingleFrameCaptureOutput { image in
                        debugLog("Frame captured: \(image.width)x\(image.height)")
                        continuation.resume(returning: image)
                    }
                    self.activeStreamOutput = streamOutput  // Keep strong reference

                    do {
                        try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global())
                        Task {
                            do {
                                try await stream.startCapture()
                                debugLog("Stream started")
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }

                // Stop the stream
                try await activeStream?.stopCapture()
                debugLog("Stream stopped")

                // Clear references
                self.activeStream = nil
                self.activeStreamOutput = nil

                // Handle the captured image on main thread
                handleCapturedImage(capturedImage)

            } catch {
                errorLog("Screenshot capture failed", error: error)
                self.activeStream = nil
                self.activeStreamOutput = nil
            }
        }
    }

    // MARK: - Image Handling

    private func handleCapturedImage(_ cgImage: CGImage) {
        debugLog("handleCapturedImage() called - image: \(cgImage.width)x\(cgImage.height), action: \(pendingAction)")
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        switch pendingAction {
        case .save:
            saveAndNotify(image: nsImage)
        case .ocr:
            performOCR(on: cgImage)
        case .pin:
            pinImage(nsImage)
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

// MARK: - SCContentSharingPickerObserver

extension ScreenshotManager: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        debugLog("Picker cancelled")
        Task { @MainActor in
            picker.isActive = false
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        debugLog("Picker updated with filter")
        Task { @MainActor in
            picker.isActive = false
            self.captureWithFilter(filter)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        errorLog("Picker failed to start", error: error)
        Task { @MainActor in
            picker.isActive = false
        }
    }
}
