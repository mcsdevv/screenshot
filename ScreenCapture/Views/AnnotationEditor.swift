import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit

struct AnnotationEditor: View {
    let capture: CaptureItem
    @EnvironmentObject var storageManager: StorageManager
    @StateObject private var viewModel = AnnotationEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background with subtle gradient
            Color.dsBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Modern toolbar - inline with traffic lights
                AnnotationToolbar(
                    viewModel: viewModel,
                    onDone: finishEditing,
                    onCancel: { dismiss() }
                )

                // Main canvas area with optional layer panel
                HStack(spacing: 0) {
                    // Canvas
                    ZStack {
                        if let image = viewModel.image {
                            AnnotationCanvas(
                                image: image,
                                state: viewModel.state,  // @Observable - no binding needed
                                zoom: $viewModel.zoom,
                                offset: $viewModel.offset,
                                viewModel: viewModel
                            )
                        } else {
                            // Loading state
                            VStack(spacing: DSSpacing.md) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .dsAccent))
                                Text("Loading image...")
                                    .font(DSTypography.bodyMedium)
                                    .foregroundColor(.dsTextSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dsBackground)

                    // Layer panel (right sidebar)
                    if viewModel.state.isLayerPanelVisible {
                        LayerPanelView(
                            state: viewModel.state,
                            onClose: {
                                viewModel.state.isLayerPanelVisible = false
                                viewModel.state.isLayerPanelManuallyHidden = true
                            }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(DSAnimation.standard, value: viewModel.state.isLayerPanelVisible)

                // Bottom status bar
                AnnotationStatusBar(viewModel: viewModel)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            loadImage()
        }
        .focusedSceneValue(\.annotationViewModel, viewModel)
    }

    private func loadImage() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let nsImage = NSImage(contentsOf: url) {
            viewModel.image = nsImage
            viewModel.imageURL = url
            viewModel.state.originalImageSize = nsImage.size

            // Try to load existing annotations from sidecar file
            viewModel.loadAnnotations()
        }
    }

    private func finishEditing() {
        viewModel.saveAnnotatedImage(storageManager: storageManager, capture: capture)
        dismiss()
    }
}

// MARK: - View Model

@MainActor
class AnnotationEditorViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var imageURL: URL?
    var state = AnnotationState()  // @Observable handles change tracking
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    // For blur rendering - shared context for performance (CIContext is expensive to create)
    let ciContext = CIContext(options: [
        .cacheIntermediates: false,  // Better for dynamic content
        .useSoftwareRenderer: false  // Force Metal/GPU rendering
    ])

    func loadAnnotations() {
        guard let imageURL = imageURL else { return }
        let sidecarURL = AnnotationDocument.sidecarURL(for: imageURL)

        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            debugLog("AnnotationEditor: No sidecar file found")
            return
        }

        do {
            let document = try AnnotationDocument.load(from: sidecarURL)
            state.annotations = document.annotations
            debugLog("AnnotationEditor: Loaded \(document.annotations.count) annotations")
        } catch {
            errorLog("AnnotationEditor: Failed to load annotations: \(error)")
        }
    }

    func saveAnnotatedImage(storageManager: StorageManager, capture: CaptureItem) {
        guard let image = renderAnnotatedImage() else {
            errorLog("AnnotationEditor: Failed to render annotated image")
            return
        }

        // Save to file
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: url)
                debugLog("AnnotationEditor: Saved image to \(url.path)")
            } catch {
                errorLog("AnnotationEditor: Failed to save image: \(error)")
            }
        }

        // Save annotations to sidecar file for future editing
        saveAnnotations()

        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        debugLog("AnnotationEditor: Copied to clipboard")

        // Play sound
        NSSound(named: "Pop")?.play()
    }

    func saveAnnotations() {
        guard let imageURL = imageURL,
              let image = image,
              !state.annotations.isEmpty else { return }

        // Calculate image hash for verification
        let hash = computeImageHash(image)
        let document = AnnotationDocument(annotations: state.annotations, imageHash: hash)
        let sidecarURL = AnnotationDocument.sidecarURL(for: imageURL)

        do {
            try document.save(to: sidecarURL)
        } catch {
            errorLog("AnnotationEditor: Failed to save annotations: \(error)")
        }
    }

    private func computeImageHash(_ image: NSImage) -> String {
        guard let tiffData = image.tiffRepresentation else { return "" }
        let hash = SHA256.hash(data: tiffData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func renderAnnotatedImage() -> NSImage? {
        guard let originalImage = image else { return nil }

        // Apply crop if active
        var workingImage = originalImage
        if let cropRect = state.cropRect {
            workingImage = cropImage(originalImage, to: cropRect)
        }

        // Apply blur annotations to the working image
        if let blurredImage = applyBlurAnnotations(to: workingImage, cropOffset: state.cropRect?.origin) {
            workingImage = blurredImage
        }

        let size = workingImage.size
        let newImage = NSImage(size: size)

        newImage.lockFocus()

        // Draw blurred image (blur already applied)
        workingImage.draw(in: NSRect(origin: .zero, size: size))

        // Draw non-blur annotations
        for annotation in state.annotations {
            drawAnnotation(annotation, in: size)
        }

        newImage.unlockFocus()

        return newImage
    }

    /// Applies all visible blur annotations to an image
    /// - Parameters:
    ///   - image: The source image to apply blur to
    ///   - cropOffset: Optional offset if image was cropped (blur rects need adjustment)
    /// - Returns: The blurred image, or nil if no blur annotations or processing failed
    private func applyBlurAnnotations(to image: NSImage, cropOffset: CGPoint?) -> NSImage? {
        // Filter visible blur annotations
        let blurAnnotations = state.annotations.filter {
            $0.type == .blur && state.isAnnotationVisible($0.id)
        }
        guard !blurAnnotations.isEmpty else { return nil }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // CRITICAL: Use pixel dimensions for the mask, not point dimensions
        // NSImage.size returns points, but CGImage has actual pixels (2x for Retina)
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let pointSize = image.size
        guard pointSize.width > 0, pointSize.height > 0 else {
            return nil
        }

        // Scale factor from points to pixels
        let scaleX = CGFloat(pixelWidth) / pointSize.width
        let scaleY = CGFloat(pixelHeight) / pointSize.height

        let ciImage = CIImage(cgImage: cgImage)

        // Create combined mask for all blur regions at PIXEL dimensions
        guard let combinedMask = createBlurMask(
            for: blurAnnotations,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scaleX: scaleX,
            scaleY: scaleY,
            cropOffset: cropOffset
        ) else {
            return nil
        }

        // Calculate average blur radius, scaled for pixel density
        let avgRadius = blurAnnotations.reduce(0.0) { $0 + $1.blurRadius } / CGFloat(blurAnnotations.count)
        let scaledRadius = avgRadius * max(scaleX, scaleY)

        // Apply masked variable blur
        let blurFilter = CIFilter.maskedVariableBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.mask = combinedMask
        blurFilter.radius = Float(scaledRadius)

        guard let blurredOutput = blurFilter.outputImage?.cropped(to: ciImage.extent),
              let outputCGImage = ciContext.createCGImage(blurredOutput, from: blurredOutput.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: pointSize)
    }

    /// Creates a grayscale mask image for blur regions at PIXEL dimensions
    /// White = blur, Black = no blur
    private func createBlurMask(
        for blurAnnotations: [Annotation],
        pixelWidth: Int,
        pixelHeight: Int,
        scaleX: CGFloat,
        scaleY: CGFloat,
        cropOffset: CGPoint?
    ) -> CIImage? {
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        // Black background (no blur)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // White rectangles for blur regions
        context.setFillColor(gray: 1, alpha: 1)
        for blur in blurAnnotations {
            var rect = blur.cgRect

            // Adjust for crop offset if image was cropped
            if let offset = cropOffset {
                rect.origin.x -= offset.x
                rect.origin.y -= offset.y
            }

            // Scale from points to pixels
            let scaledRect = CGRect(
                x: rect.origin.x * scaleX,
                y: rect.origin.y * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )

            // Flip Y coordinate for Core Image (bottom-left origin)
            let flippedRect = CGRect(
                x: scaledRect.origin.x,
                y: CGFloat(pixelHeight) - scaledRect.origin.y - scaledRect.height,
                width: scaledRect.width,
                height: scaledRect.height
            )
            context.fill(flippedRect)
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage {
        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: rect.size),
            from: NSRect(origin: rect.origin, size: rect.size),
            operation: .copy,
            fraction: 1.0
        )
        croppedImage.unlockFocus()
        return croppedImage
    }

    private func drawAnnotation(_ annotation: Annotation, in size: NSSize) {
        let nsColor = annotation.color.nsColor
        nsColor.setStroke()
        nsColor.setFill()

        switch annotation.type {
        case .rectangleOutline:
            drawRectangleOutline(annotation)
        case .rectangleSolid:
            drawRectangleSolid(annotation)
        case .circleOutline:
            drawCircleOutline(annotation)
        case .line:
            drawLine(annotation)
        case .arrow:
            drawArrow(annotation)
        case .text:
            drawText(annotation)
        case .blur:
            // Blur is applied during rendering, not drawn
            break
        case .pencil:
            drawPencil(annotation)
        case .highlighter:
            drawHighlighter(annotation)
        case .numberedStep:
            drawNumberedStep(annotation)
        }
    }

    private func drawRectangleOutline(_ annotation: Annotation) {
        let path = NSBezierPath(roundedRect: annotation.cgRect, xRadius: 2, yRadius: 2)
        path.lineWidth = annotation.strokeWidth
        path.stroke()
    }

    private func drawRectangleSolid(_ annotation: Annotation) {
        let path = NSBezierPath(roundedRect: annotation.cgRect, xRadius: 2, yRadius: 2)
        path.fill()
    }

    private func drawCircleOutline(_ annotation: Annotation) {
        let path = NSBezierPath(ovalIn: annotation.cgRect)
        path.lineWidth = annotation.strokeWidth
        path.stroke()
    }

    private func drawLine(_ annotation: Annotation) {
        let rect = annotation.cgRect
        // Use origin and origin+size to preserve direction (not minX/maxX which normalizes)
        let start = CGPoint(x: rect.origin.x, y: rect.origin.y)
        let end = CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()
    }

    private func drawArrow(_ annotation: Annotation) {
        let rect = annotation.cgRect
        // Use origin and origin+size to preserve direction (not minX/maxX which normalizes)
        let start = CGPoint(x: rect.origin.x, y: rect.origin.y)
        let end = CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)

        // Calculate arrow geometry
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15 + annotation.strokeWidth
        let arrowheadHeight = arrowLength * cos(.pi / 6)  // Height from tip to base
        let totalLength = hypot(end.x - start.x, end.y - start.y)

        // Draw shaft only if arrow is longer than arrowhead, ending at arrowhead base
        if totalLength > arrowheadHeight {
            let shaftEnd = CGPoint(
                x: end.x - arrowheadHeight * cos(angle),
                y: end.y - arrowheadHeight * sin(angle)
            )
            let path = NSBezierPath()
            path.lineWidth = annotation.strokeWidth
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: shaftEnd)
            path.stroke()
        }

        // Draw arrowhead
        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        arrowPath.fill()
    }

    private func drawText(_ annotation: Annotation) {
        guard let text = annotation.text else { return }

        let font: NSFont
        if annotation.fontName == ".AppleSystemUIFont" {
            font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .medium)
        } else {
            font = NSFont(name: annotation.fontName, size: annotation.fontSize) ?? NSFont.systemFont(ofSize: annotation.fontSize)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color.nsColor
        ]

        let string = NSAttributedString(string: text, attributes: attributes)
        string.draw(at: annotation.cgRect.origin)
    }

    private func drawPencil(_ annotation: Annotation) {
        guard annotation.cgPoints.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: annotation.cgPoints[0])
        for point in annotation.cgPoints.dropFirst() {
            path.line(to: point)
        }
        path.stroke()
    }

    private func drawHighlighter(_ annotation: Annotation) {
        guard annotation.cgPoints.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth * 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        annotation.color.nsColor.withAlphaComponent(0.4).setStroke()

        path.move(to: annotation.cgPoints[0])
        for point in annotation.cgPoints.dropFirst() {
            path.line(to: point)
        }
        path.stroke()
    }

    private func drawNumberedStep(_ annotation: Annotation) {
        guard let number = annotation.stepNumber else { return }

        let size: CGFloat = 30
        let rect = CGRect(
            x: annotation.cgRect.midX - size / 2,
            y: annotation.cgRect.midY - size / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: rect)
        annotation.color.nsColor.setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        let string = NSAttributedString(string: "\(number)", attributes: attributes)
        let stringSize = string.size()
        let stringPoint = CGPoint(
            x: rect.midX - stringSize.width / 2,
            y: rect.midY - stringSize.height / 2
        )
        string.draw(at: stringPoint)
    }

    // MARK: - Blur Rendering

    func renderBlurredRegion(in image: NSImage, rect: CGRect, radius: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Create a mask image (white in blur region, black elsewhere)
        let maskImage = createMaskImage(for: rect, in: image.size)

        guard let maskCGImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let maskCIImage = CIImage(cgImage: maskCGImage)

        // Use masked variable blur
        let blurFilter = CIFilter.maskedVariableBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.mask = maskCIImage
        blurFilter.radius = Float(radius)

        guard let outputImage = blurFilter.outputImage?.cropped(to: ciImage.extent),
              let outputCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    private func createMaskImage(for rect: CGRect, in size: NSSize) -> NSImage {
        let maskImage = NSImage(size: size)
        maskImage.lockFocus()

        // Black background (no blur)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        // White rectangle (blur region)
        NSColor.white.setFill()
        rect.fill()

        maskImage.unlockFocus()
        return maskImage
    }
}

// MARK: - Modern Annotation Toolbar

struct AnnotationToolbar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel
    let onDone: () -> Void
    let onCancel: () -> Void

    // Primary tools - Select tool first, then creation tools
    private var primaryTools: [AnnotationTool] {
        [.select, .crop, .rectangleOutline, .rectangleSolid, .circleOutline, .line, .arrow, .text, .blur]
    }

    // Color binding - reflects selected annotation's color or current color
    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                if let annotation = viewModel.state.selectedAnnotation {
                    return annotation.swiftUIColor
                }
                return viewModel.state.currentColor
            },
            set: { newColor in
                viewModel.state.currentColor = newColor
            }
        )
    }

    // Stroke width binding - reflects selected annotation's stroke or current stroke
    private var strokeWidthBinding: Binding<CGFloat> {
        Binding(
            get: {
                if let annotation = viewModel.state.selectedAnnotation {
                    return annotation.strokeWidth
                }
                return viewModel.state.currentStrokeWidth
            },
            set: { newWidth in
                viewModel.state.currentStrokeWidth = newWidth
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            // Custom traffic light buttons (close/minimize/fullscreen)
            DSTrafficLightButtons()

            // Tool buttons
            HStack(spacing: 2) {
                ForEach(primaryTools, id: \.self) { tool in
                    AnnotationToolbarButton(
                        tool: tool,
                        isSelected: viewModel.state.currentTool == tool,
                        action: { viewModel.state.currentTool = tool }
                    )
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(Color.dsBackgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .strokeBorder(Color.dsBorder, lineWidth: 1)
                    )
            )

            // Vertical divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 24)

            // Text options (shown when text tool is selected OR text annotation is selected)
            if viewModel.state.currentTool == .text ||
               (viewModel.state.selectedAnnotation?.type == .text) {
                TextOptionsBar(viewModel: viewModel)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 24)
            }

            // Color and stroke - sync with selected annotation
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                ColorPickerButton(
                    selectedColor: colorBinding,
                    onColorChange: { newColor in
                        if viewModel.state.selectedAnnotationId != nil {
                            viewModel.state.updateSelectedAnnotationColor(newColor)
                        }
                    }
                )
                StrokeWidthButton(
                    strokeWidth: strokeWidthBinding,
                    onStrokeChange: { newWidth in
                        if viewModel.state.selectedAnnotationId != nil {
                            viewModel.state.updateSelectedAnnotationStrokeWidth(newWidth)
                        }
                    }
                )
            }

            Spacer()

            // Undo/Redo
            HStack(alignment: .center, spacing: DSSpacing.xs) {
                DSIconButton(icon: "arrow.uturn.backward", size: 28) {
                    viewModel.state.undo()
                }
                .disabled(!viewModel.state.canUndo)
                .opacity(viewModel.state.canUndo ? 1 : 0.4)
                .help("Undo (⌘Z)")

                DSIconButton(icon: "arrow.uturn.forward", size: 28) {
                    viewModel.state.redo()
                }
                .disabled(!viewModel.state.canRedo)
                .opacity(viewModel.state.canRedo ? 1 : 0.4)
                .help("Redo (⌘⇧Z)")
            }

            // Delete selected
            if viewModel.state.selectedAnnotationId != nil {
                DSIconButton(icon: "trash", size: 28) {
                    viewModel.state.deleteSelectedAnnotation()
                }
                .help("Delete selected (⌫)")
            }

            // Layer panel toggle
            DSIconButton(icon: viewModel.state.isLayerPanelVisible ? "sidebar.right" : "sidebar.right", size: 28) {
                viewModel.state.toggleLayerPanelVisibility()
            }
            .opacity(viewModel.state.isLayerPanelVisible ? 1 : 0.6)
            .help("Toggle layer panel")

            // Vertical divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 24)

            // Done button - accent colored
            DSPrimaryButton("Done", icon: "checkmark") {
                onDone()
            }
            .help("Save and copy to clipboard (⌘↵)")
        }
        .frame(height: 52) // Taller for better vertical centering like Raycast
        .padding(.horizontal, DSSpacing.lg)
        .background(
            ZStack {
                Color.dsBackgroundElevated
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Annotation Toolbar Button

struct AnnotationToolbarButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected ? .dsAccent :
                    (isHovered ? .dsTextPrimary : .dsTextSecondary)
                )
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(
                            isSelected ? Color.dsAccent.opacity(0.15) :
                            (isHovered ? Color.white.opacity(0.06) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .strokeBorder(
                            isSelected ? Color.dsAccent.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help(tool.tooltip)
    }
}

// MARK: - Text Options Bar

struct TextOptionsBar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel
    @State private var showFontPicker = false
    @State private var showSizePicker = false

    // Get current font name from selected annotation or current state
    private var currentFontName: String {
        if let annotation = viewModel.state.selectedAnnotation, annotation.type == .text {
            return annotation.fontName
        }
        return viewModel.state.currentFontName
    }

    // Get current font size from selected annotation or current state
    private var currentFontSize: CGFloat {
        if let annotation = viewModel.state.selectedAnnotation, annotation.type == .text {
            return annotation.fontSize
        }
        return viewModel.state.currentFontSize
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            // Font picker
            Button(action: { showFontPicker.toggle() }) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(currentFontDisplayName)
                        .font(DSTypography.labelSmall)
                        .foregroundColor(.dsTextSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.dsTextTertiary)
                }
                .frame(width: 80)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(Color.dsBackgroundSecondary)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFontPicker) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(FontOption.systemFonts) { font in
                        PickerOptionButton(
                            label: font.displayName,
                            isSelected: currentFontName == font.name,
                            font: DSTypography.bodySmall
                        ) {
                            viewModel.state.currentFontName = font.name
                            // Update selected text annotation if any
                            if viewModel.state.selectedAnnotation?.type == .text {
                                viewModel.state.updateSelectedAnnotationFontName(font.name)
                            }
                            showFontPicker = false
                        }
                    }
                }
                .padding(DSSpacing.sm)
                .frame(width: 140)
                .background(Color.dsBackgroundElevated)
            }

            // Font size
            Button(action: { showSizePicker.toggle() }) {
                HStack(spacing: DSSpacing.xxs) {
                    Text("\(Int(currentFontSize))pt")
                        .font(DSTypography.monoSmall)
                        .foregroundColor(.dsTextSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.dsTextTertiary)
                }
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(Color.dsBackgroundSecondary)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSizePicker) {
                VStack(spacing: DSSpacing.xxs) {
                    ForEach([12, 14, 16, 18, 24, 32, 48, 64], id: \.self) { size in
                        PickerOptionButton(
                            label: "\(size)pt",
                            isSelected: Int(currentFontSize) == size,
                            font: DSTypography.monoSmall
                        ) {
                            viewModel.state.currentFontSize = CGFloat(size)
                            // Update selected text annotation if any
                            if viewModel.state.selectedAnnotation?.type == .text {
                                viewModel.state.updateSelectedAnnotationFontSize(CGFloat(size))
                            }
                            showSizePicker = false
                        }
                    }
                }
                .padding(DSSpacing.sm)
                .frame(width: 100)
                .background(Color.dsBackgroundElevated)
            }
        }
    }

    private var currentFontDisplayName: String {
        FontOption.systemFonts.first { $0.name == currentFontName }?.displayName ?? "System"
    }
}

// MARK: - Picker Option Button with Hover State

struct PickerOptionButton: View {
    let label: String
    let isSelected: Bool
    let font: Font
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(font)
                    .foregroundColor(isHovered ? .dsTextPrimary : (isSelected ? .dsTextPrimary : .dsTextSecondary))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.dsAccent)
                }
            }
            .padding(.vertical, DSSpacing.xs)
            .padding(.horizontal, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.xs)
                    .fill(
                        isSelected ? Color.dsAccent.opacity(0.15) :
                        (isHovered ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Color Picker Button

struct ColorPickerButton: View {
    @Binding var selectedColor: Color
    var onColorChange: ((Color) -> Void)? = nil
    @State private var showPicker = false
    @State private var isHovered = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            ZStack {
                // Hover ring (always present but opacity changes)
                Circle()
                    .strokeBorder(Color.white.opacity(isHovered ? 0.4 : 0), lineWidth: 2)
                    .frame(width: 28, height: 28)

                // Color fill
                Circle()
                    .fill(selectedColor)
                    .frame(width: 22, height: 22)

                // Border
                Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 28, height: 28) // Fixed size to prevent layout shift
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help("Color")
        .popover(isPresented: $showPicker) {
            ColorPickerGrid(selectedColor: $selectedColor, showPicker: $showPicker, onColorChange: onColorChange)
        }
    }
}

struct ColorPickerGrid: View {
    @Binding var selectedColor: Color
    @Binding var showPicker: Bool
    var onColorChange: ((Color) -> Void)? = nil

    // Local state to buffer ColorPicker updates and prevent crash from rapid binding updates
    @State private var pickerColor: Color = .red

    private let colors = Color.annotationColors

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 5), spacing: DSSpacing.sm) {
                ForEach(colors, id: \.self) { color in
                    DSColorSwatch(
                        color: color,
                        isSelected: selectedColor == color,
                        size: 28
                    ) {
                        selectedColor = color
                        onColorChange?(color)
                        showPicker = false
                    }
                }
            }

            DSDivider()

            ColorPicker("Custom", selection: $pickerColor)
                .labelsHidden()
                .onChange(of: pickerColor) { _, newColor in
                    selectedColor = newColor
                    onColorChange?(newColor)
                }
        }
        .padding(DSSpacing.md)
        .background(Color.dsBackgroundElevated)
        .onAppear {
            pickerColor = selectedColor
        }
    }
}

// MARK: - Stroke Width Button

struct StrokeWidthButton: View {
    @Binding var strokeWidth: CGFloat
    var onStrokeChange: ((CGFloat) -> Void)? = nil
    @State private var showPicker = false
    @State private var isHovered = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            Image(systemName: "pencil.tip")
                .font(.system(size: 13))
                .foregroundColor(isHovered ? .dsTextPrimary : .dsTextSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help("Stroke width")
        .popover(isPresented: $showPicker) {
            VStack(spacing: DSSpacing.xs) {
                ForEach([1, 2, 3, 5, 8, 12], id: \.self) { width in
                    Button(action: {
                        strokeWidth = CGFloat(width)
                        onStrokeChange?(CGFloat(width))
                        showPicker = false
                    }) {
                        HStack {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.dsTextPrimary)
                                .frame(width: 40, height: CGFloat(width))
                            Spacer()
                            if Int(strokeWidth) == width {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.dsAccent)
                            }
                        }
                        .padding(.vertical, DSSpacing.xs)
                        .padding(.horizontal, DSSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.xs)
                                .fill(Int(strokeWidth) == width ? Color.dsAccent.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DSSpacing.sm)
            .frame(width: 100)
            .background(Color.dsBackgroundElevated)
        }
    }
}

// MARK: - Status Bar

struct AnnotationStatusBar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel
    @State private var isHoveredZoomOut = false
    @State private var isHoveredZoomIn = false
    @State private var isHoveredReset = false

    var body: some View {
        HStack {
            // Image dimensions
            if let image = viewModel.image {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 10))
                        .foregroundColor(.dsTextTertiary)
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(DSTypography.monoSmall)
                        .foregroundColor(.dsTextSecondary)
                }
            }

            Spacer()

            // Zoom controls
            HStack(spacing: DSSpacing.xs) {
                Button(action: { viewModel.zoom = max(0.1, viewModel.zoom - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(isHoveredZoomOut ? .dsTextPrimary : .dsTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.xs)
                                .fill(isHoveredZoomOut ? Color.white.opacity(0.06) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveredZoomOut = $0 }

                Text("\(Int(viewModel.zoom * 100))%")
                    .font(DSTypography.monoSmall)
                    .foregroundColor(.dsTextSecondary)
                    .frame(width: 44)

                Button(action: { viewModel.zoom = min(4.0, viewModel.zoom + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(isHoveredZoomIn ? .dsTextPrimary : .dsTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.xs)
                                .fill(isHoveredZoomIn ? Color.white.opacity(0.06) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveredZoomIn = $0 }

                Button(action: { viewModel.zoom = 1.0; viewModel.offset = .zero }) {
                    Image(systemName: "1.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(isHoveredReset ? .dsTextPrimary : .dsTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.xs)
                                .fill(isHoveredReset ? Color.white.opacity(0.06) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveredReset = $0 }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.dsBackgroundElevated)
        .overlay(
            DSDivider(), alignment: .top
        )
    }
}

// MARK: - Focus Value Key

struct AnnotationViewModelKey: FocusedValueKey {
    typealias Value = AnnotationEditorViewModel
}

extension FocusedValues {
    var annotationViewModel: AnnotationEditorViewModel? {
        get { self[AnnotationViewModelKey.self] }
        set { self[AnnotationViewModelKey.self] = newValue }
    }
}
