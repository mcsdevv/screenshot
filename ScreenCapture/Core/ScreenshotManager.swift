import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
class ScreenshotManager: NSObject, ObservableObject {
    private let storageManager: StorageManager
    private var pendingAction: PendingAction = .save
    private let picker = SCContentSharingPicker.shared

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

        // Configure picker for single selection
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay]
        picker.setConfiguration(config, for: nil)

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
        picker.setConfiguration(config, for: nil)

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

                // Set high resolution
                config.width = 3840
                config.height = 2160

                debugLog("Capturing image with filter...")
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                debugLog("Image captured: \(image.width)x\(image.height)")

                await MainActor.run {
                    handleCapturedImage(image)
                }
            } catch {
                errorLog("Screenshot capture failed", error: error)
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
