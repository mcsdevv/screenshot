import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// Custom window class that accepts key events (required for borderless windows)
class KeyableWindow: NSWindow {
    var onEscapePressed: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            debugLog("KeyableWindow: Escape key pressed")
            onEscapePressed?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
class ScreenshotManager: NSObject, ObservableObject {
    private let storageManager: StorageManager
    private var selectionWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var captureMode: CaptureMode = .area
    private var pendingAction: PendingAction = .save

    enum CaptureMode {
        case area, window, fullscreen, scrolling, ocr, pin
    }

    enum PendingAction {
        case save, ocr, pin
    }

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
    }

    func captureArea() {
        debugLog("captureArea() called")
        captureMode = .area
        pendingAction = .save
        showSelectionOverlay()
    }

    func captureWindow() {
        debugLog("captureWindow() called")
        captureMode = .window
        pendingAction = .save
        captureWindowUnderCursor()
    }

    func captureFullscreen() {
        debugLog("captureFullscreen() called")
        captureMode = .fullscreen
        pendingAction = .save
        performFullscreenCapture()
    }

    func captureScrolling() {
        debugLog("captureScrolling() called")
        captureMode = .scrolling
        pendingAction = .save
        showScrollingCaptureUI()
    }

    func captureForOCR() {
        debugLog("captureForOCR() called")
        captureMode = .ocr
        pendingAction = .ocr
        showSelectionOverlay()
    }

    func captureForPinning() {
        debugLog("captureForPinning() called")
        captureMode = .pin
        pendingAction = .pin
        showSelectionOverlay()
    }

    private func showSelectionOverlay() {
        debugLog("showSelectionOverlay() called")

        // Prevent multiple overlays from stacking
        if selectionWindow != nil {
            debugLog("Existing selection window found, dismissing first")
            dismissSelectionOverlay()
        }

        guard let screen = NSScreen.main else {
            debugLog("ERROR: No main screen available")
            return
        }

        debugLog("Creating SelectionOverlayView for screen: \(screen.frame)")

        let selectionView = SelectionOverlayView(
            onSelection: { [weak self] rect in
                debugLog("onSelection callback triggered with rect: \(rect)")
                self?.handleAreaSelection(rect)
            },
            onCancel: { [weak self] in
                debugLog("onCancel callback triggered (Escape pressed)")
                self?.dismissSelectionOverlay()
            }
        )

        let hostingView = NSHostingView(rootView: selectionView)
        hostingView.frame = screen.frame

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Handle Escape key at window level
        window.onEscapePressed = { [weak self] in
            debugLog("Escape pressed - dismissing overlay")
            self?.dismissSelectionOverlay()
        }

        selectionWindow = window
        selectionWindow?.contentView = hostingView
        selectionWindow?.isOpaque = false
        selectionWindow?.backgroundColor = .clear
        selectionWindow?.level = .screenSaver
        selectionWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        selectionWindow?.ignoresMouseEvents = false
        selectionWindow?.makeKeyAndOrderFront(nil)
        selectionWindow?.makeFirstResponder(hostingView)

        NSCursor.crosshair.push()
        debugLog("Selection overlay window displayed and made key")
    }

    private func dismissSelectionOverlay() {
        guard let window = selectionWindow as? KeyableWindow else {
            debugLog("dismissSelectionOverlay() called but no window exists")
            return
        }
        debugLog("Dismissing selection overlay")

        // Clear references first
        window.onEscapePressed = nil
        selectionWindow = nil
        NSCursor.pop()

        // Hide window immediately, then close after a delay to let SwiftUI cleanup
        window.orderOut(nil)
        debugLog("Window hidden")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            debugLog("Closing selection window (delayed)")
            window.close()
            debugLog("Selection window closed successfully")
        }
    }

    private func handleAreaSelection(_ rect: CGRect) {
        debugLog("handleAreaSelection() called with rect: \(rect)")
        dismissSelectionOverlay()

        guard rect.width > 10 && rect.height > 10 else {
            debugLog("Selection too small (< 10x10), ignoring")
            return
        }

        debugLog("Starting capture task for rect: \(rect)")
        Task {
            await captureRect(rect)
        }
    }

    private func captureRect(_ rect: CGRect) async {
        debugLog("captureRect() starting for rect: \(rect)")
        do {
            debugLog("Requesting shareable content...")
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                errorLog("No display found in shareable content")
                return
            }

            debugLog("Found display: \(display.width)x\(display.height)")
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(rect.width * 2)
            config.height = Int(rect.height * 2)
            config.sourceRect = rect
            config.scalesToFit = false
            config.showsCursor = false

            debugLog("Capturing image...")
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            debugLog("Image captured: \(image.width)x\(image.height)")

            await MainActor.run {
                handleCapturedImage(image)
            }
        } catch {
            errorLog("Screenshot capture failed", error: error)
        }
    }

    private func captureWindowUnderCursor() {
        debugLog("captureWindowUnderCursor() starting")
        Task {
            do {
                debugLog("Requesting shareable content for window capture...")
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // NSEvent.mouseLocation uses Quartz coordinates (origin: bottom-left, Y increases upward)
                // SCWindow.frame uses Core Graphics coordinates (origin: top-left, Y increases downward)
                // Convert mouse location to Core Graphics coordinate system
                let mouseLocation = NSEvent.mouseLocation
                let screenHeight = NSScreen.main?.frame.height ?? 0
                let convertedMouseLocation = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

                var targetWindow: SCWindow?

                for window in content.windows {
                    guard window.isOnScreen,
                          let app = window.owningApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                        continue
                    }

                    let windowFrame = window.frame
                    if windowFrame.contains(convertedMouseLocation) {
                        targetWindow = window
                        break
                    }
                }

                if let window = targetWindow {
                    debugLog("Found target window: \(window.title ?? "untitled") at \(window.frame)")
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    config.width = Int(window.frame.width * 2)
                    config.height = Int(window.frame.height * 2)
                    config.showsCursor = false
                    config.captureResolution = .best

                    debugLog("Capturing window...")
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    debugLog("Window captured: \(image.width)x\(image.height)")

                    await MainActor.run {
                        handleCapturedImage(image)
                    }
                } else {
                    debugLog("No window under cursor, showing window picker")
                    showWindowPicker(content: content)
                }
            } catch {
                errorLog("Window capture failed", error: error)
            }
        }
    }

    private func showWindowPicker(content: SCShareableContent) {
        debugLog("showWindowPicker() called")
        // Prevent multiple overlays from stacking
        if let existingWindow = overlayWindow as? KeyableWindow {
            debugLog("Closing existing overlay window")
            existingWindow.onEscapePressed = nil
            overlayWindow = nil
            existingWindow.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                existingWindow.close()
            }
        }

        let windows = content.windows.filter { window in
            window.isOnScreen &&
            window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
            window.frame.width > 100 && window.frame.height > 100
        }

        debugLog("Found \(windows.count) windows to display in picker")

        let pickerView = WindowPickerView(windows: windows) { [weak self] window in
            debugLog("Window selected from picker: \(window.title ?? "untitled")")
            self?.captureSpecificWindow(window)
        }

        guard let screen = NSScreen.main else {
            errorLog("No main screen for window picker")
            return
        }

        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.frame = screen.frame

        overlayWindow = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow?.contentView = hostingView
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        overlayWindow?.level = .screenSaver
        overlayWindow?.makeKeyAndOrderFront(nil)
        overlayWindow?.makeFirstResponder(hostingView)
        debugLog("Window picker displayed")
    }

    private func captureSpecificWindow(_ window: SCWindow) {
        debugLog("captureSpecificWindow() called for: \(window.title ?? "untitled")")
        if let windowToClose = overlayWindow as? KeyableWindow {
            windowToClose.onEscapePressed = nil
            overlayWindow = nil
            windowToClose.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                windowToClose.close()
            }
        }

        Task {
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * 2)
                config.height = Int(window.frame.height * 2)
                config.showsCursor = false
                config.captureResolution = .best

                debugLog("Capturing specific window...")
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                debugLog("Window captured: \(image.width)x\(image.height)")

                await MainActor.run {
                    handleCapturedImage(image)
                }
            } catch {
                errorLog("Window capture failed", error: error)
            }
        }
    }

    private func performFullscreenCapture() {
        debugLog("performFullscreenCapture() starting")
        Task {
            do {
                debugLog("Requesting shareable content for fullscreen...")
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let display = content.displays.first else {
                    errorLog("No display found for fullscreen capture")
                    return
                }

                debugLog("Capturing fullscreen display: \(display.width)x\(display.height)")
                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = Int(display.width * 2)
                config.height = Int(display.height * 2)
                config.showsCursor = false
                config.captureResolution = .best

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                debugLog("Fullscreen captured: \(image.width)x\(image.height)")

                await MainActor.run {
                    handleCapturedImage(image)
                }
            } catch {
                errorLog("Fullscreen capture failed", error: error)
            }
        }
    }

    private func showScrollingCaptureUI() {
        debugLog("showScrollingCaptureUI() called")
        let scrollingCapture = ScrollingCapture(storageManager: storageManager)
        scrollingCapture.start()
    }

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

struct SelectionOverlayView: View {
    let onSelection: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isSelecting = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                if let start = startPoint, let current = currentPoint {
                    let rect = selectionRect(from: start, to: current)
                    // Round corners that touch screen edges to match Mac display corners
                    let cornerRadius = cornerRadius(for: rect, in: geometry.size)

                    // Calculate per-corner radii
                    let topLeading = rect.minY <= 1 && rect.minX <= 1 ? cornerRadius : 0
                    let topTrailing = rect.minY <= 1 && rect.maxX >= geometry.size.width - 1 ? cornerRadius : 0
                    let bottomLeading = rect.maxY >= geometry.size.height - 1 && rect.minX <= 1 ? cornerRadius : 0
                    let bottomTrailing = rect.maxY >= geometry.size.height - 1 && rect.maxX >= geometry.size.width - 1 ? cornerRadius : 0

                    UnevenRoundedRectangle(
                        topLeadingRadius: topLeading,
                        bottomLeadingRadius: bottomLeading,
                        bottomTrailingRadius: bottomTrailing,
                        topTrailingRadius: topTrailing
                    )
                    .stroke(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                    DimensionsLabel(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.minY - 20)

                    CutoutMask(rect: rect, size: geometry.size, cornerRadius: cornerRadius)
                }

                CrosshairOverlay()
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isSelecting {
                            startPoint = value.startLocation
                            isSelecting = true
                        }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        if let start = startPoint {
                            let rect = selectionRect(from: start, to: value.location)
                            onSelection(convertToScreenCoordinates(rect, in: geometry))
                        }
                        isSelecting = false
                        startPoint = nil
                        currentPoint = nil
                    }
            )
            .onExitCommand {
                onCancel()
            }
        }
    }

    private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func cornerRadius(for rect: CGRect, in size: CGSize) -> CGFloat {
        // Mac display corner radius (approximately 10pt for most modern Macs)
        let screenCornerRadius: CGFloat = 10
        let touchesTop = rect.minY <= 1
        let touchesBottom = rect.maxY >= size.height - 1
        let touchesLeft = rect.minX <= 1
        let touchesRight = rect.maxX >= size.width - 1

        // Only apply corner radius if selection touches a screen edge
        if touchesTop || touchesBottom || touchesLeft || touchesRight {
            return screenCornerRadius
        }
        return 0
    }

    private func convertToScreenCoordinates(_ rect: CGRect, in geometry: GeometryProxy) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let screenHeight = screen.frame.height
        return CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

struct CutoutMask: View {
    let rect: CGRect
    let size: CGSize
    var cornerRadius: CGFloat = 0

    var body: some View {
        Canvas { context, canvasSize in
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.black.opacity(0.4))
            )

            context.blendMode = .destinationOut

            // Create path with rounded corners for edges that touch screen bounds
            let path = Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                topLeading: rect.minY <= 1 && rect.minX <= 1 ? cornerRadius : 0,
                bottomLeading: rect.maxY >= canvasSize.height - 1 && rect.minX <= 1 ? cornerRadius : 0,
                bottomTrailing: rect.maxY >= canvasSize.height - 1 && rect.maxX >= canvasSize.width - 1 ? cornerRadius : 0,
                topTrailing: rect.minY <= 1 && rect.maxX >= canvasSize.width - 1 ? cornerRadius : 0
            ))
            context.fill(path, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

struct CrosshairOverlay: View {
    var body: some View {
        // Simplified - removed onContinuousHover which may cause crashes during cleanup
        EmptyView()
    }
}

struct MagnifierView: View {
    let position: CGPoint
    @State private var pixelColor: Color = .clear

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(width: 100, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                )

            Text("\(Int(position.x)), \(Int(position.y))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.7)))
        }
        .position(x: position.x + 70, y: position.y + 70)
    }
}

struct DimensionsLabel: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text("\(Int(width)) x \(Int(height))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.8)))
    }
}

struct WindowPickerView: View {
    let windows: [SCWindow]
    let onSelect: (SCWindow) -> Void

    var body: some View {
        VStack {
            Text("Click on a window to capture")
                .font(.title2)
                .foregroundColor(.white)
                .padding()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(windows, id: \.windowID) { window in
                        WindowPreview(window: window)
                            .onTapGesture {
                                onSelect(window)
                            }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WindowPreview: View {
    let window: SCWindow

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(width: 200, height: 150)
                .overlay(
                    VStack {
                        Image(systemName: "macwindow")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        if let title = window.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                        }
                    }
                )

            if let app = window.owningApplication {
                Text(app.applicationName)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
}
