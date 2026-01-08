import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

// Custom window class that accepts key events (required for borderless windows)
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
        captureMode = .area
        pendingAction = .save
        showSelectionOverlay()
    }

    func captureWindow() {
        captureMode = .window
        pendingAction = .save
        captureWindowUnderCursor()
    }

    func captureFullscreen() {
        captureMode = .fullscreen
        pendingAction = .save
        performFullscreenCapture()
    }

    func captureScrolling() {
        captureMode = .scrolling
        pendingAction = .save
        showScrollingCaptureUI()
    }

    func captureForOCR() {
        captureMode = .ocr
        pendingAction = .ocr
        showSelectionOverlay()
    }

    func captureForPinning() {
        captureMode = .pin
        pendingAction = .pin
        showSelectionOverlay()
    }

    private func showSelectionOverlay() {
        // Prevent multiple overlays from stacking
        if selectionWindow != nil {
            dismissSelectionOverlay()
        }

        guard let screen = NSScreen.main else { return }

        let selectionView = SelectionOverlayView(
            onSelection: { [weak self] rect in
                self?.handleAreaSelection(rect)
            },
            onCancel: { [weak self] in
                self?.dismissSelectionOverlay()
            }
        )

        let hostingView = NSHostingView(rootView: selectionView)
        hostingView.frame = screen.frame

        selectionWindow = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        selectionWindow?.contentView = hostingView
        selectionWindow?.isOpaque = false
        selectionWindow?.backgroundColor = .clear
        selectionWindow?.level = .screenSaver
        selectionWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        selectionWindow?.ignoresMouseEvents = false
        selectionWindow?.makeKeyAndOrderFront(nil)
        selectionWindow?.makeFirstResponder(hostingView)

        NSCursor.crosshair.push()
    }

    private func dismissSelectionOverlay() {
        NSCursor.pop()
        selectionWindow?.close()
        selectionWindow = nil
    }

    private func handleAreaSelection(_ rect: CGRect) {
        dismissSelectionOverlay()

        guard rect.width > 10 && rect.height > 10 else { return }

        Task {
            await captureRect(rect)
        }
    }

    private func captureRect(_ rect: CGRect) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(rect.width * 2)
            config.height = Int(rect.height * 2)
            config.sourceRect = rect
            config.scalesToFit = false
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            await MainActor.run {
                handleCapturedImage(image)
            }
        } catch {
            print("Screenshot error: \(error)")
        }
    }

    private func captureWindowUnderCursor() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                let mouseLocation = NSEvent.mouseLocation
                var targetWindow: SCWindow?

                for window in content.windows {
                    guard window.isOnScreen,
                          let app = window.owningApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                        continue
                    }

                    let windowFrame = window.frame
                    if windowFrame.contains(CGPoint(x: mouseLocation.x, y: mouseLocation.y)) {
                        targetWindow = window
                        break
                    }
                }

                if let window = targetWindow {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    config.width = Int(window.frame.width * 2)
                    config.height = Int(window.frame.height * 2)
                    config.showsCursor = false
                    config.captureResolution = .best

                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                    await MainActor.run {
                        handleCapturedImage(image)
                    }
                } else {
                    showWindowPicker(content: content)
                }
            } catch {
                print("Window capture error: \(error)")
            }
        }
    }

    private func showWindowPicker(content: SCShareableContent) {
        // Prevent multiple overlays from stacking
        if overlayWindow != nil {
            overlayWindow?.close()
            overlayWindow = nil
        }

        let windows = content.windows.filter { window in
            window.isOnScreen &&
            window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
            window.frame.width > 100 && window.frame.height > 100
        }

        let pickerView = WindowPickerView(windows: windows) { [weak self] window in
            self?.captureSpecificWindow(window)
        }

        guard let screen = NSScreen.main else { return }

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
    }

    private func captureSpecificWindow(_ window: SCWindow) {
        overlayWindow?.close()
        overlayWindow = nil

        Task {
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * 2)
                config.height = Int(window.frame.height * 2)
                config.showsCursor = false
                config.captureResolution = .best

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                await MainActor.run {
                    handleCapturedImage(image)
                }
            } catch {
                print("Window capture error: \(error)")
            }
        }
    }

    private func performFullscreenCapture() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = Int(display.width * 2)
                config.height = Int(display.height * 2)
                config.showsCursor = false
                config.captureResolution = .best

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                await MainActor.run {
                    handleCapturedImage(image)
                }
            } catch {
                print("Fullscreen capture error: \(error)")
            }
        }
    }

    private func showScrollingCaptureUI() {
        let scrollingCapture = ScrollingCapture(storageManager: storageManager)
        scrollingCapture.start()
    }

    private func handleCapturedImage(_ cgImage: CGImage) {
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
        let capture = storageManager.saveCapture(image: image, type: .screenshot)
        NotificationCenter.default.post(name: .captureCompleted, object: capture)
        playScreenshotSound()
    }

    private func performOCR(on cgImage: CGImage) {
        let ocrService = OCRService()
        ocrService.recognizeText(in: cgImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self?.showOCRNotification(text: text)
                case .failure(let error):
                    self?.showOCRError(error)
                }
            }
        }
    }

    private func pinImage(_ image: NSImage) {
        let pinnedWindow = PinnedScreenshotWindow(image: image)
        pinnedWindow.show()
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

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .background(
                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                        )
                        .overlay(
                            DimensionsLabel(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.minY - 20)
                        )

                    CutoutMask(rect: rect, size: geometry.size)
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

    var body: some View {
        Canvas { context, canvasSize in
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.black.opacity(0.4))
            )

            context.blendMode = .destinationOut
            context.fill(
                Path(rect),
                with: .color(.white)
            )
        }
        .allowsHitTesting(false)
    }
}

struct CrosshairOverlay: View {
    @State private var mousePosition: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: mousePosition.x, y: 0))
                    path.addLine(to: CGPoint(x: mousePosition.x, y: geometry.size.height))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: mousePosition.y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: mousePosition.y))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1)

                MagnifierView(position: mousePosition)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mousePosition = location
                case .ended:
                    break
                }
            }
        }
        .allowsHitTesting(false)
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
