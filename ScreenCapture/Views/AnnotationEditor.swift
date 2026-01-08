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
                .padding(.top, DSSpacing.xxs)

                // Main canvas area
                ZStack {
                    if let image = viewModel.image {
                        AnnotationCanvas(
                            image: image,
                            state: $viewModel.state,
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
    @Published var state = AnnotationState()
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    // For blur rendering
    private let ciContext = CIContext()

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

        let size = workingImage.size
        let newImage = NSImage(size: size)

        newImage.lockFocus()

        // Draw original/cropped image
        workingImage.draw(in: NSRect(origin: .zero, size: size))

        // Draw annotations
        for annotation in state.annotations {
            drawAnnotation(annotation, in: size)
        }

        newImage.unlockFocus()

        return newImage
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

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round

        // Draw line
        path.move(to: start)
        path.line(to: end)

        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15 + annotation.strokeWidth

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        // Filled arrowhead
        let arrowPath = NSBezierPath()
        arrowPath.move(to: end)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()
        arrowPath.fill()

        path.stroke()
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

    // Primary tools matching CleanShot X order
    private var primaryTools: [AnnotationTool] {
        [.crop, .rectangleOutline, .rectangleSolid, .circleOutline, .line, .arrow, .text, .blur]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left padding for traffic light buttons (close/minimize/fullscreen)
            Spacer()
                .frame(width: 78)

            // Tool buttons
            HStack(spacing: DSSpacing.xxxs) {
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

            DSDivider(.vertical)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.md)

            // Text options (shown when text tool is selected)
            if viewModel.state.currentTool == .text {
                TextOptionsBar(viewModel: viewModel)

                DSDivider(.vertical)
                    .frame(height: 28)
                    .padding(.horizontal, DSSpacing.md)
            }

            // Color and stroke
            HStack(spacing: DSSpacing.sm) {
                ColorPickerButton(selectedColor: $viewModel.state.currentColor)
                StrokeWidthButton(strokeWidth: $viewModel.state.currentStrokeWidth)
            }

            Spacer()

            // Undo/Redo
            HStack(spacing: DSSpacing.xxs) {
                DSIconButton(icon: "arrow.uturn.backward", size: 28) {
                    viewModel.state.undo()
                }
                .disabled(viewModel.state.undoStack.isEmpty)
                .opacity(viewModel.state.undoStack.isEmpty ? 0.4 : 1)
                .help("Undo (⌘Z)")

                DSIconButton(icon: "arrow.uturn.forward", size: 28) {
                    viewModel.state.redo()
                }
                .disabled(viewModel.state.redoStack.isEmpty)
                .opacity(viewModel.state.redoStack.isEmpty ? 0.4 : 1)
                .help("Redo (⌘⇧Z)")
            }
            .padding(.horizontal, DSSpacing.sm)

            // Delete selected
            if viewModel.state.selectedAnnotationId != nil {
                DSIconButton(icon: "trash", size: 28) {
                    viewModel.state.deleteSelectedAnnotation()
                }
                .help("Delete selected (⌫)")
                .padding(.trailing, DSSpacing.sm)
            }

            DSDivider(.vertical)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.sm)

            // Done button - accent colored
            DSPrimaryButton("Done", icon: "checkmark") {
                onDone()
            }
            .help("Save and copy to clipboard (⌘↵)")
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
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
            DSDivider(), alignment: .bottom
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
                        Button(action: {
                            viewModel.state.currentFontName = font.name
                            showFontPicker = false
                        }) {
                            HStack {
                                Text(font.displayName)
                                    .font(DSTypography.bodySmall)
                                    .foregroundColor(.dsTextPrimary)
                                Spacer()
                                if viewModel.state.currentFontName == font.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.dsAccent)
                                }
                            }
                            .padding(.vertical, DSSpacing.xs)
                            .padding(.horizontal, DSSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DSRadius.xs)
                                    .fill(viewModel.state.currentFontName == font.name ? Color.dsAccent.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DSSpacing.sm)
                .frame(width: 140)
                .background(Color.dsBackgroundElevated)
            }

            // Font size
            Button(action: { showSizePicker.toggle() }) {
                HStack(spacing: DSSpacing.xxs) {
                    Text("\(Int(viewModel.state.currentFontSize))pt")
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
                        Button(action: {
                            viewModel.state.currentFontSize = CGFloat(size)
                            showSizePicker = false
                        }) {
                            HStack {
                                Text("\(size)pt")
                                    .font(DSTypography.monoSmall)
                                    .foregroundColor(.dsTextPrimary)
                                Spacer()
                                if Int(viewModel.state.currentFontSize) == size {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.dsAccent)
                                }
                            }
                            .padding(.vertical, DSSpacing.xs)
                            .padding(.horizontal, DSSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DSRadius.xs)
                                    .fill(Int(viewModel.state.currentFontSize) == size ? Color.dsAccent.opacity(0.1) : Color.clear)
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

    private var currentFontDisplayName: String {
        FontOption.systemFonts.first { $0.name == viewModel.state.currentFontName }?.displayName ?? "System"
    }
}

// MARK: - Color Picker Button

struct ColorPickerButton: View {
    @Binding var selectedColor: Color
    @State private var showPicker = false
    @State private var isHovered = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            ZStack {
                Circle()
                    .fill(selectedColor)
                    .frame(width: 24, height: 24)

                Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 24, height: 24)

                if isHovered {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help("Color")
        .popover(isPresented: $showPicker) {
            ColorPickerGrid(selectedColor: $selectedColor, showPicker: $showPicker)
        }
    }
}

struct ColorPickerGrid: View {
    @Binding var selectedColor: Color
    @Binding var showPicker: Bool

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
                        showPicker = false
                    }
                }
            }

            DSDivider()

            ColorPicker("Custom", selection: $selectedColor)
                .labelsHidden()
        }
        .padding(DSSpacing.md)
        .background(Color.dsBackgroundElevated)
    }
}

// MARK: - Stroke Width Button

struct StrokeWidthButton: View {
    @Binding var strokeWidth: CGFloat
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
