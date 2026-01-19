import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
class ScrollingCapture: NSObject {
    private let storageManager: StorageManager
    private var capturedImages: [NSImage] = []
    private var controlWindow: NSWindow?
    private var isCapturing = false
    private var scrollTimer: Timer?
    private var lastCaptureY: CGFloat = 0

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
    }

    func start() {
        showInstructions()
    }

    private func showInstructions() {
        guard let screen = NSScreen.main else { return }

        // Close any existing window first
        closeControlWindow()

        let instructionView = ScrollingCaptureInstructionsView(
            onStart: { [weak self] in
                self?.startCapturing()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let hostingView = NSHostingView(rootView: instructionView)
        let size = NSSize(width: 400, height: 200)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let centerX = screen.frame.midX - size.width / 2
        let centerY = screen.frame.midY - size.height / 2

        // Use KeyableWindow for proper event handling
        let window = KeyableWindow(
            contentRect: NSRect(x: centerX, y: centerY, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true

        controlWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func startCapturing() {
        closeControlWindow()
        isCapturing = true
        capturedImages = []

        showCaptureControls()
        captureCurrentView()
    }

    private func showCaptureControls() {
        guard let screen = NSScreen.main else { return }

        let controlView = ScrollingCaptureControlsView(
            captureCount: Binding(get: { self.capturedImages.count }, set: { _ in }),
            onCapture: { [weak self] in
                self?.captureCurrentView()
            },
            onFinish: { [weak self] in
                self?.finishCapture()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let hostingView = NSHostingView(rootView: controlView)
        let size = NSSize(width: 300, height: 80)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let centerX = screen.frame.midX - size.width / 2
        let bottomY = screen.visibleFrame.minY + 20

        // Use KeyableWindow for proper event handling
        let window = KeyableWindow(
            contentRect: NSRect(x: centerX, y: bottomY, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true

        controlWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func closeControlWindow() {
        guard let windowToClose = controlWindow else { return }
        controlWindow = nil

        // Hide window immediately but defer all cleanup to next run loop
        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func captureCurrentView() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                config.showsCursor = false
                config.captureResolution = .best

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                await MainActor.run {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    self.capturedImages.append(nsImage)
                    NSSound(named: "Pop")?.play()
                }
            } catch {
                print("Scrolling capture error: \(error)")
            }
        }
    }

    private func finishCapture() {
        isCapturing = false
        closeControlWindow()

        guard !capturedImages.isEmpty else { return }

        if capturedImages.count == 1 {
            let capture = storageManager.saveCapture(image: capturedImages[0], type: .screenshot)
            NotificationCenter.default.post(name: .captureCompleted, object: capture)
        } else {
            stitchImages()
        }
    }

    private func stitchImages() {
        guard capturedImages.count > 1 else { return }

        let stitcher = ImageStitcher()
        if let stitchedImage = stitcher.stitch(images: capturedImages) {
            let capture = storageManager.saveCapture(image: stitchedImage, type: .scrollingCapture)
            NotificationCenter.default.post(name: .captureCompleted, object: capture)
        }
    }

    private func cancel() {
        isCapturing = false
        closeControlWindow()
        capturedImages = []
    }
}

class ImageStitcher {
    func stitch(images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }

        if images.count == 1 {
            return images[0]
        }

        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for image in images {
            totalHeight += image.size.height
            maxWidth = max(maxWidth, image.size.width)
        }

        let overlapEstimate = images[0].size.height * 0.1
        let adjustedHeight = totalHeight - (overlapEstimate * CGFloat(images.count - 1))

        let stitchedSize = NSSize(width: maxWidth, height: adjustedHeight)
        let stitchedImage = NSImage(size: stitchedSize)

        stitchedImage.lockFocus()

        var currentY = adjustedHeight

        for (index, image) in images.enumerated() {
            let drawHeight = index == 0 ? image.size.height : image.size.height - overlapEstimate
            currentY -= (index == 0 ? image.size.height : drawHeight)

            let sourceRect: NSRect
            if index == 0 {
                sourceRect = NSRect(origin: .zero, size: image.size)
            } else {
                sourceRect = NSRect(x: 0, y: overlapEstimate, width: image.size.width, height: drawHeight)
            }

            let destRect = NSRect(x: 0, y: currentY, width: image.size.width, height: index == 0 ? image.size.height : drawHeight)

            image.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
        }

        stitchedImage.unlockFocus()

        return stitchedImage
    }
}

struct ScrollingCaptureInstructionsView: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scroll")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Scrolling Capture")
                .font(.title2.bold())

            Text("Scroll through the content you want to capture. Click 'Capture' after each scroll, then click 'Done' when finished.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Start Capture") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

struct ScrollingCaptureControlsView: View {
    @Binding var captureCount: Int
    let onCapture: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(captureCount) captured")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onCapture) {
                Label("Capture", systemImage: "camera")
            }
            .buttonStyle(.bordered)

            Button(action: onFinish) {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)

            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}
