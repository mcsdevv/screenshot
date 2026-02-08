import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
class ScrollingCapture: NSObject {
    private let storageManager: StorageManager
    private let onComplete: () -> Void
    private var capturedImages: [NSImage] = []
    private var controlWindow: NSWindow?
    private var isCapturing = false
    private var scrollTimer: Timer?
    private var lastCaptureY: CGFloat = 0

    init(storageManager: StorageManager, onComplete: @escaping () -> Void) {
        self.storageManager = storageManager
        self.onComplete = onComplete
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
                let display = try await ScreenCaptureContentProvider.shared.getPrimaryDisplay()

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

        guard !capturedImages.isEmpty else {
            onComplete()
            return
        }

        if capturedImages.count == 1 {
            let capture = storageManager.saveCapture(image: capturedImages[0], type: .screenshot)
            NotificationCenter.default.post(name: .captureCompleted, object: capture)
        } else {
            stitchImages()
        }
        onComplete()
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
        onComplete()
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

        var overlaps: [CGFloat] = []
        overlaps.reserveCapacity(max(0, images.count - 1))

        for index in 1..<images.count {
            let overlap = estimateOverlap(previous: images[index - 1], next: images[index])
                ?? (images[index].size.height * 0.1)
            overlaps.append(max(0, min(overlap, images[index].size.height * 0.5)))
        }

        let totalOverlap = overlaps.reduce(0, +)
        let adjustedHeight = max(1, totalHeight - totalOverlap)

        let stitchedSize = NSSize(width: maxWidth, height: adjustedHeight)
        let stitchedImage = NSImage(size: stitchedSize)

        stitchedImage.lockFocus()

        var currentY = adjustedHeight

        for (index, image) in images.enumerated() {
            let overlap = index == 0 ? 0 : overlaps[index - 1]
            let drawHeight = index == 0 ? image.size.height : image.size.height - overlap
            currentY -= (index == 0 ? image.size.height : drawHeight)

            let sourceRect: NSRect
            if index == 0 {
                sourceRect = NSRect(origin: .zero, size: image.size)
            } else {
                sourceRect = NSRect(x: 0, y: overlap, width: image.size.width, height: drawHeight)
            }

            let destRect = NSRect(x: 0, y: currentY, width: image.size.width, height: index == 0 ? image.size.height : drawHeight)

            image.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
        }

        stitchedImage.unlockFocus()

        return stitchedImage
    }

    private func estimateOverlap(previous: NSImage, next: NSImage) -> CGFloat? {
        guard let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let nextCG = next.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previousCG)
        let handler = VNImageRequestHandler(cgImage: nextCG, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation,
                  observation.confidence > 0.3 else {
                return nil
            }

            let translationY = abs(observation.alignmentTransform.ty)
            let overlap = previous.size.height - translationY
            let maxAllowedOverlap = min(previous.size.height, next.size.height) * 0.6
            guard overlap.isFinite, overlap > 0, overlap <= maxAllowedOverlap else {
                return nil
            }

            // Vision can return unstable alignment for low-texture inputs.
            // Verify that the predicted overlap bands are visually similar.
            guard hasSufficientOverlapSimilarity(previous: previous, next: next, overlap: overlap) else {
                return nil
            }

            return overlap
        } catch {
            return nil
        }
    }

    private func hasSufficientOverlapSimilarity(previous: NSImage, next: NSImage, overlap: CGFloat) -> Bool {
        guard let previousRep = bitmapRepresentation(for: previous),
              let nextRep = bitmapRepresentation(for: next) else {
            return false
        }

        let minWidth = min(previousRep.pixelsWide, nextRep.pixelsWide)
        let maxOverlapPixels = min(previousRep.pixelsHigh, nextRep.pixelsHigh)
        let overlapPixels = max(1, min(Int(overlap.rounded()), maxOverlapPixels))

        guard minWidth >= 8, overlapPixels >= 8 else { return false }

        let sampleColumns = min(24, max(4, minWidth / 8))
        let sampleRows = min(16, max(4, overlapPixels / 8))

        guard sampleColumns > 0, sampleRows > 0 else { return false }

        let xStep = max(1, minWidth / sampleColumns)
        let yStep = max(1, overlapPixels / sampleRows)
        let previousStartY = previousRep.pixelsHigh - overlapPixels

        var totalDifference: CGFloat = 0
        var channelSampleCount: CGFloat = 0
        var pixelSampleCount: CGFloat = 0
        var previousLuminanceSum: CGFloat = 0
        var previousLuminanceSquaredSum: CGFloat = 0
        var nextLuminanceSum: CGFloat = 0
        var nextLuminanceSquaredSum: CGFloat = 0

        for row in 0..<sampleRows {
            let prevY = min(previousRep.pixelsHigh - 1, previousStartY + (row * yStep))
            let nextY = min(nextRep.pixelsHigh - 1, row * yStep)

            for column in 0..<sampleColumns {
                let x = min(minWidth - 1, column * xStep)
                guard let previousColor = previousRep.colorAt(x: x, y: prevY)?.usingColorSpace(.sRGB),
                      let nextColor = nextRep.colorAt(x: x, y: nextY)?.usingColorSpace(.sRGB) else {
                    continue
                }

                totalDifference += abs(previousColor.redComponent - nextColor.redComponent)
                totalDifference += abs(previousColor.greenComponent - nextColor.greenComponent)
                totalDifference += abs(previousColor.blueComponent - nextColor.blueComponent)
                channelSampleCount += 3

                let previousLuminance = (0.2126 * previousColor.redComponent)
                    + (0.7152 * previousColor.greenComponent)
                    + (0.0722 * previousColor.blueComponent)
                let nextLuminance = (0.2126 * nextColor.redComponent)
                    + (0.7152 * nextColor.greenComponent)
                    + (0.0722 * nextColor.blueComponent)

                previousLuminanceSum += previousLuminance
                previousLuminanceSquaredSum += previousLuminance * previousLuminance
                nextLuminanceSum += nextLuminance
                nextLuminanceSquaredSum += nextLuminance * nextLuminance
                pixelSampleCount += 1
            }
        }

        guard channelSampleCount > 0, pixelSampleCount > 0 else { return false }
        let averageDifference = totalDifference / channelSampleCount

        let previousMean = previousLuminanceSum / pixelSampleCount
        let previousVariance = max(0, (previousLuminanceSquaredSum / pixelSampleCount) - (previousMean * previousMean))
        let nextMean = nextLuminanceSum / pixelSampleCount
        let nextVariance = max(0, (nextLuminanceSquaredSum / pixelSampleCount) - (nextMean * nextMean))

        // Flat-color regions are ambiguous for registration and often produce unstable shifts.
        guard previousVariance > 0.0008, nextVariance > 0.0008 else {
            return false
        }

        // 0 = identical colors, 1 = completely different.
        return averageDifference < 0.20
    }

    private func bitmapRepresentation(for image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return bitmap
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage)
    }
}

struct ScrollingCaptureInstructionsView: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "scroll")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.dsAccent)

            Text("Scrolling Capture")
                .font(DSTypography.displaySmall)
                .foregroundColor(.dsTextPrimary)

            Text("Scroll through the content you want to capture. Click 'Capture' after each scroll, then click 'Done' when finished.")
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DSSpacing.sm)

            HStack(spacing: DSSpacing.md) {
                DSSecondaryButton("Cancel", action: onCancel)
                DSPrimaryButton("Start Capture", action: onStart)
            }
        }
        .padding(DSSpacing.xl)
        .frame(width: 400)
        .background(scrollingCaptureBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }

    private var scrollingCaptureBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                Spacer()
            }
        }
    }
}

struct ScrollingCaptureControlsView: View {
    @Binding var captureCount: Int
    let onCapture: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Text("\(captureCount) captured")
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)

            Spacer()

            DSSecondaryButton("Capture", icon: "camera", action: onCapture)
            DSPrimaryButton("Done", icon: "checkmark", action: onFinish)
            DSIconButton(icon: "xmark", action: onCancel)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(controlsBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private var controlsBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
