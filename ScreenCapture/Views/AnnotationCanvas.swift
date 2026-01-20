import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct AnnotationCanvas: View {
    let image: NSImage
    @Bindable var state: AnnotationState  // @Observable with @Bindable for binding access
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    @ObservedObject var viewModel: AnnotationEditorViewModel

    @State private var currentDrawing: Annotation?
    @State private var currentPoints: [CGPoint] = []
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var editingAnnotationId: UUID? = nil  // Track which annotation is being edited (for text)

    // For blur caching - only cache committed blur annotations, not during drag
    @State private var cachedBlurImage: NSImage?
    @State private var blurCacheKey: String = ""

    // Cache key for COMMITTED blur annotations only (not current drawing)
    // This prevents re-rendering during drag which was causing performance issues
    private var committedBlurCacheKey: String {
        let blurAnnotations = state.annotations.filter {
            $0.type == .blur && state.isAnnotationVisible($0.id)
        }
        guard !blurAnnotations.isEmpty else { return "" }
        return blurAnnotations.map { blur in
            "\(blur.id)|\(Int(blur.cgRect.origin.x)),\(Int(blur.cgRect.origin.y)),\(Int(blur.cgRect.width)),\(Int(blur.cgRect.height))|\(Int(blur.blurRadius))"
        }.joined(separator: ";")
    }

    // Check if we're currently drawing a blur (for showing preview indicator)
    private var isDrawingBlur: Bool {
        currentDrawing?.type == .blur
    }

    // Scaled image dimensions for convenience
    private var scaledImageSize: CGSize {
        CGSize(width: image.size.width * zoom, height: image.size.height * zoom)
    }

    // Convert gesture location to image coordinates (just divide by zoom since we use topLeading alignment)
    private func gestureLocationToImageCoords(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / zoom, y: location.y / zoom)
    }

    // Clamp a point to stay within image bounds
    private func clampToImageBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(point.x, image.size.width)),
            y: max(0, min(point.y, image.size.height))
        )
    }

    // Check if a point is over any visible annotation (for hover cursor)
    private func isPointOverAnnotation(_ point: CGPoint) -> Bool {
        for annotation in state.annotations.reversed() {
            if state.isAnnotationVisible(annotation.id) && hitTest(annotation: annotation, at: point) {
                return true
            }
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                // Use topLeading alignment so image is at (0,0) and gestures map directly
                ZStack(alignment: .topLeading) {
                    // Background image (with blur regions applied)
                    imageLayer

                    // Static annotation canvas - committed annotations only (respects visibility)
                    // Uses drawingGroup() for Metal-backed off-screen rendering
                    Canvas { context, size in
                        for annotation in state.annotations {
                            // Skip hidden annotations
                            if state.isAnnotationVisible(annotation.id) {
                                drawAnnotation(annotation, in: context, size: size)
                            }
                        }
                    }
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                    .drawingGroup() // Metal-backed rendering for better performance

                    // Dynamic canvas - current drawing preview only
                    // Separated to avoid redrawing all annotations during drag
                    if currentDrawing != nil {
                        Canvas { context, size in
                            if let current = currentDrawing {
                                drawAnnotation(current, in: context, size: size)
                            }
                        }
                        .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                        .allowsHitTesting(false)
                    }

                    // Selection handles for selected annotation
                    ForEach(state.annotations) { annotation in
                        if annotation.id == state.selectedAnnotationId,
                           state.isAnnotationVisible(annotation.id) {
                            AnnotationSelectionOverlay(
                                annotation: annotation,
                                zoom: zoom,
                                onMove: { delta in
                                    moveSelectedAnnotation(by: delta)
                                },
                                onResize: { newRect in
                                    resizeSelectedAnnotation(to: newRect)
                                },
                                onEndpointMove: (annotation.type == .line || annotation.type == .arrow) ? { index, position in
                                    moveLineEndpoint(index: index, to: position)
                                } : nil
                            )
                        }
                    }

                    // Hover tracking for cursor changes in select mode
                    AnnotationHoverTracker(
                        state: state,
                        zoom: zoom,
                        hitTest: { point in isPointOverAnnotation(point) }
                    )
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                    .allowsHitTesting(false)

                    // Crop overlay
                    if state.currentTool == .crop {
                        CropOverlay(
                            imageSize: image.size,
                            zoom: zoom,
                            cropRect: $state.cropRect,
                            onConfirm: { applyCrop() },
                            onCancel: { state.cropRect = nil }
                        )
                    }

                    // Text input overlay
                    if showTextInput {
                        TextInputOverlay(
                            text: $textInput,
                            position: textPosition,
                            imageSize: scaledImageSize,
                            color: state.currentColor,
                            fontSize: state.currentFontSize,
                            fontName: state.currentFontName,
                            onCommit: { commitTextAnnotation() },
                            onCancel: {
                                showTextInput = false
                                editingAnnotationId = nil
                                textInput = ""
                            }
                        )
                    }
                }
                .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                .contentShape(Rectangle())
                .gesture(drawingGesture)
                .onTapGesture { location in
                    handleTap(at: location)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onExitCommand {
            state.selectedAnnotationId = nil
            showTextInput = false
            editingAnnotationId = nil
        }
        .onChange(of: state.currentTool) { _, newTool in
            // Dismiss text input when switching to a different tool
            if newTool != .text && showTextInput {
                showTextInput = false
                textInput = ""
                editingAnnotationId = nil
            }
            // Deselect annotation when switching tools (unless switching to select)
            if newTool != .select {
                state.selectedAnnotationId = nil
            }
        }
        // Keyboard shortcuts for annotation manipulation
        .background(
            AnnotationKeyboardHandler(
                onDelete: {
                    guard state.selectedAnnotationId != nil, !showTextInput else { return }
                    state.deleteSelectedAnnotation()
                },
                onNudge: { dx, dy in
                    guard state.selectedAnnotationId != nil, !showTextInput else { return }
                    state.nudgeSelectedAnnotation(dx: dx, dy: dy)
                },
                onDuplicate: {
                    guard let id = state.selectedAnnotationId, !showTextInput else { return }
                    if let newId = state.duplicateAnnotation(id: id) {
                        state.selectedAnnotationId = newId
                    }
                },
                onCopy: {
                    guard state.selectedAnnotationId != nil, !showTextInput else { return }
                    state.copySelectedAnnotation()
                },
                onPaste: {
                    guard !showTextInput else { return }
                    if let newId = state.pasteAnnotation() {
                        state.selectedAnnotationId = newId
                    }
                },
                onBringForward: {
                    guard let id = state.selectedAnnotationId, !showTextInput else { return }
                    state.bringForward(id: id)
                },
                onSendBackward: {
                    guard let id = state.selectedAnnotationId, !showTextInput else { return }
                    state.sendBackward(id: id)
                },
                onBringToFront: {
                    guard let id = state.selectedAnnotationId, !showTextInput else { return }
                    state.bringToFront(id: id)
                },
                onSendToBack: {
                    guard let id = state.selectedAnnotationId, !showTextInput else { return }
                    state.sendToBack(id: id)
                }
            )
        )
    }

    // MARK: - Image Layer

    @ViewBuilder
    private var imageLayer: some View {
        let cacheKey = committedBlurCacheKey

        ZStack(alignment: .topLeading) {
            // Show cached blur image if valid, otherwise show original
            if !cacheKey.isEmpty, let cached = cachedBlurImage, blurCacheKey == cacheKey {
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
            }

            // Blur preview overlay during drag
            if isDrawingBlur, let current = currentDrawing {
                blurPreviewOverlay(for: current)
            }
        }
        // CRITICAL: Move .task OUTSIDE the ZStack and conditional branches
        .task(id: cacheKey) {
            guard !cacheKey.isEmpty else { return }
            guard blurCacheKey != cacheKey else { return } // Already rendered

            debugLog("AnnotationCanvas: Rendering blur for cache key: \(cacheKey)")

            if let blurredImage = renderCommittedBlurs() {
                cachedBlurImage = blurredImage
                blurCacheKey = cacheKey
                debugLog("AnnotationCanvas: Blur rendered successfully")
            } else {
                // Mark as processed even on failure to avoid infinite retries
                blurCacheKey = cacheKey
                cachedBlurImage = nil
                debugLog("AnnotationCanvas: Blur rendering failed")
            }
        }
    }

    // Visual preview for blur during drag - semi-transparent overlay instead of expensive blur filter
    @ViewBuilder
    private func blurPreviewOverlay(for annotation: Annotation) -> some View {
        let scaledRect = CGRect(
            x: annotation.cgRect.origin.x * zoom,
            y: annotation.cgRect.origin.y * zoom,
            width: annotation.cgRect.size.width * zoom,
            height: annotation.cgRect.size.height * zoom
        )

        ZStack {
            // Semi-transparent fill
            Rectangle()
                .fill(Color.black.opacity(0.25))

            // Dashed border for visibility
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundColor(.white)

            // "Blur" label
            Text("Blur")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
        }
        .frame(width: max(abs(scaledRect.width), 20), height: max(abs(scaledRect.height), 20))
        .position(
            x: scaledRect.origin.x + scaledRect.width / 2,
            y: scaledRect.origin.y + scaledRect.height / 2
        )
    }

    // MARK: - Blur Rendering

    /// Renders only COMMITTED blur annotations (not current drawing during drag)
    /// This function is only called when blur annotations are added/removed, not during drag
    private func renderCommittedBlurs() -> NSImage? {
        let blurAnnotations = state.annotations.filter {
            $0.type == .blur && state.isAnnotationVisible($0.id)
        }
        guard !blurAnnotations.isEmpty else {
            debugLog("AnnotationCanvas: No visible blur annotations")
            return nil
        }

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

        // Combine all blur regions into a single mask at PIXEL dimensions
        guard let combinedMask = createCombinedMaskCIImage(
            for: blurAnnotations,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scaleX: scaleX,
            scaleY: scaleY
        ) else {
            return nil
        }

        // Use average blur radius for combined blur, scaled for pixel density
        let avgRadius = blurAnnotations.reduce(0.0) { $0 + $1.blurRadius } / CGFloat(blurAnnotations.count)
        let scaledRadius = avgRadius * max(scaleX, scaleY)

        let ciImage = CIImage(cgImage: cgImage)

        // Single blur filter pass with combined mask
        let blurFilter = CIFilter.maskedVariableBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.mask = combinedMask
        blurFilter.radius = Float(scaledRadius)

        guard let blurredOutput = blurFilter.outputImage?.cropped(to: ciImage.extent),
              let outputCGImage = viewModel.ciContext.createCGImage(blurredOutput, from: blurredOutput.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    /// Creates a combined mask for all blur regions at PIXEL dimensions
    /// - Parameters:
    ///   - blurAnnotations: The blur annotations (coordinates in points)
    ///   - pixelWidth: The actual pixel width of the image
    ///   - pixelHeight: The actual pixel height of the image
    ///   - scaleX: Scale factor from points to pixels (X axis)
    ///   - scaleY: Scale factor from points to pixels (Y axis)
    private func createCombinedMaskCIImage(
        for blurAnnotations: [Annotation],
        pixelWidth: Int,
        pixelHeight: Int,
        scaleX: CGFloat,
        scaleY: CGFloat
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

        // White rectangles for all blur regions (combined into single mask)
        context.setFillColor(gray: 1, alpha: 1)
        for blur in blurAnnotations {
            let rect = blur.cgRect

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

    // MARK: - Gestures

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleTap(at location: CGPoint) {
        let unscaledLocation = clampToImageBounds(gestureLocationToImageCoords(location))

        // First, try to select an annotation at this point (regardless of tool)
        // Search in reverse to select topmost annotation
        var hitAnnotation: Annotation? = nil
        for annotation in state.annotations.reversed() {
            if state.isAnnotationVisible(annotation.id) && hitTest(annotation: annotation, at: unscaledLocation) {
                hitAnnotation = annotation
                break
            }
        }

        // If we hit an annotation, select it
        if let annotation = hitAnnotation {
            state.selectedAnnotationId = annotation.id
            // For text annotations in select mode, also enter edit mode
            if annotation.type == .text && state.currentTool == .select {
                state.currentColor = annotation.swiftUIColor
                state.currentFontSize = annotation.fontSize
                state.currentFontName = annotation.fontName
                editingAnnotationId = annotation.id
                textInput = annotation.text ?? ""
                // Position the text input at the annotation's location (scaled)
                textPosition = CGPoint(
                    x: annotation.cgRect.origin.x * zoom - 12, // Account for padding offset
                    y: annotation.cgRect.origin.y * zoom - 12
                )
                showTextInput = true
            }
            // Show layer panel when selection made (unless manually hidden)
            if !state.isLayerPanelManuallyHidden {
                state.isLayerPanelVisible = true
            }
            return
        }

        // No annotation hit - proceed with tool-specific behavior
        switch state.currentTool {
        case .select:
            // Deselect when clicking empty space
            state.selectedAnnotationId = nil
            // Hide layer panel if nothing selected
            if !state.isLayerPanelManuallyHidden {
                state.isLayerPanelVisible = false
            }

        case .text:
            // Store position in scaled coordinates (where user clicked)
            textPosition = location
            textInput = ""
            showTextInput = true

        case .numberedStep:
            let annotation = Annotation(
                type: .numberedStep,
                rect: CGRect(origin: unscaledLocation, size: CGSize(width: 30, height: 30)),
                color: state.currentColor,
                stepNumber: state.stepCounter
            )
            state.addAnnotation(annotation)
            state.stepCounter += 1

        default:
            // Deselect on tap for other tools when clicking empty space
            state.selectedAnnotationId = nil
        }
    }

    private func hitTest(annotation: Annotation, at point: CGPoint) -> Bool {
        switch annotation.type {
        case .line, .arrow:
            // For lines, check distance to line segment
            let start = CGPoint(x: annotation.cgRect.minX, y: annotation.cgRect.minY)
            let end = CGPoint(x: annotation.cgRect.maxX, y: annotation.cgRect.maxY)
            return distanceToLineSegment(point: point, start: start, end: end) < 10

        case .pencil, .highlighter:
            // Check distance to any segment
            let points = annotation.cgPoints
            for i in 0..<(points.count - 1) {
                if distanceToLineSegment(point: point, start: points[i], end: points[i + 1]) < 10 {
                    return true
                }
            }
            return false

        default:
            // For rectangles, circles, etc., use bounding rect
            return annotation.cgRect.insetBy(dx: -5, dy: -5).contains(point)
        }
    }

    private func distanceToLineSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projX = start.x + t * dx
        let projY = start.y + t * dy

        return hypot(point.x - projX, point.y - projY)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard state.currentTool != .select && state.currentTool != .text && state.currentTool != .crop else {
            return
        }

        // Convert gesture coordinates to image coordinates (accounting for centering offset)
        let startLocation = clampToImageBounds(gestureLocationToImageCoords(value.startLocation))
        let currentLocation = clampToImageBounds(gestureLocationToImageCoords(value.location))

        switch state.currentTool {
        case .pencil, .highlighter:
            currentPoints.append(currentLocation)
            let type: AnnotationType = state.currentTool == .pencil ? .pencil : .highlighter
            currentDrawing = Annotation(
                type: type,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth,
                points: currentPoints
            )

        case .rectangleOutline:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .rectangleOutline,
                rect: rect,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .rectangleSolid:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .rectangleSolid,
                rect: rect,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .circleOutline:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .circleOutline,
                rect: rect,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .line:
            currentDrawing = Annotation(
                type: .line,
                rect: CGRect(
                    origin: startLocation,
                    size: CGSize(width: currentLocation.x - startLocation.x, height: currentLocation.y - startLocation.y)
                ),
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .arrow:
            currentDrawing = Annotation(
                type: .arrow,
                rect: CGRect(
                    origin: startLocation,
                    size: CGSize(width: currentLocation.x - startLocation.x, height: currentLocation.y - startLocation.y)
                ),
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .blur:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .blur,
                rect: rect,
                color: .clear,
                blurRadius: state.blurRadius
            )

        default:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if let drawing = currentDrawing {
            // Only add if it has meaningful size
            let rect = drawing.cgRect
            if rect.width > 5 || rect.height > 5 || !drawing.cgPoints.isEmpty {
                state.addAnnotation(drawing)
            }
        }
        currentDrawing = nil
        currentPoints = []
    }

    private func commitTextAnnotation() {
        // If editing an existing annotation
        if let editingId = editingAnnotationId,
           let index = state.annotations.firstIndex(where: { $0.id == editingId }) {
            if textInput.isEmpty {
                // Delete the annotation if text is empty
                state.deleteAnnotation(id: editingId)
            } else {
                // Update the existing annotation
                var annotation = state.annotations[index]
                annotation.text = textInput
                annotation.fontSize = state.currentFontSize
                annotation.fontName = state.currentFontName
                annotation.color = CodableColor(state.currentColor)
                state.updateAnnotation(annotation)
            }
            editingAnnotationId = nil
            showTextInput = false
            textInput = ""
            return
        }

        // Creating a new annotation
        guard !textInput.isEmpty else {
            showTextInput = false
            return
        }

        // Account for text box padding (8pt) + text container inset (4pt) = 12pt offset
        // This ensures text renders at the same position as shown in the input overlay
        let paddingOffset: CGFloat = 12
        let adjustedPosition = CGPoint(
            x: textPosition.x + paddingOffset,
            y: textPosition.y + paddingOffset
        )

        // Convert from scaled position to image coordinates
        let unscaledPosition = clampToImageBounds(gestureLocationToImageCoords(adjustedPosition))
        let annotation = Annotation(
            type: .text,
            rect: CGRect(origin: unscaledPosition, size: .zero),
            color: state.currentColor,
            text: textInput,
            fontSize: state.currentFontSize,
            fontName: state.currentFontName
        )
        state.addAnnotation(annotation)
        showTextInput = false
        textInput = ""
    }

    private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // MARK: - Selection Handling

    private func moveSelectedAnnotation(by delta: CGSize) {
        guard let id = state.selectedAnnotationId,
              let index = state.annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = state.annotations[index]

        // Apply delta to annotation rect (delta is in screen coordinates, divide by zoom)
        annotation.cgRect = annotation.cgRect.offsetBy(dx: delta.width / zoom, dy: delta.height / zoom)

        // Also move points for pencil/highlighter
        if !annotation.cgPoints.isEmpty {
            annotation.cgPoints = annotation.cgPoints.map {
                CGPoint(x: $0.x + delta.width / zoom, y: $0.y + delta.height / zoom)
            }
        }

        state.updateAnnotation(annotation)
    }

    private func resizeSelectedAnnotation(to newRect: CGRect) {
        guard let id = state.selectedAnnotationId,
              let index = state.annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = state.annotations[index]
        annotation.cgRect = CGRect(
            x: newRect.origin.x / zoom,
            y: newRect.origin.y / zoom,
            width: newRect.width / zoom,
            height: newRect.height / zoom
        )
        state.updateAnnotation(annotation)
    }

    private func moveLineEndpoint(index: Int, to newPosition: CGPoint) {
        guard let id = state.selectedAnnotationId,
              let annotationIndex = state.annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = state.annotations[annotationIndex]

        // Line/arrow rect stores start point in origin and end offset in size
        let imageCoordPos = CGPoint(x: newPosition.x / zoom, y: newPosition.y / zoom)

        if index == 0 {
            // Moving start point - adjust origin and recalculate size to maintain end point
            let endX = annotation.cgRect.origin.x + annotation.cgRect.size.width
            let endY = annotation.cgRect.origin.y + annotation.cgRect.size.height
            annotation.cgRect = CGRect(
                origin: imageCoordPos,
                size: CGSize(width: endX - imageCoordPos.x, height: endY - imageCoordPos.y)
            )
        } else {
            // Moving end point - keep origin, adjust size
            annotation.cgRect = CGRect(
                origin: annotation.cgRect.origin,
                size: CGSize(
                    width: imageCoordPos.x - annotation.cgRect.origin.x,
                    height: imageCoordPos.y - annotation.cgRect.origin.y
                )
            )
        }

        state.updateAnnotation(annotation)
    }

    // MARK: - Crop

    private func applyCrop() {
        guard let cropRect = state.cropRect else { return }
        // Crop is applied when rendering the final image
        debugLog("AnnotationCanvas: Crop applied to rect \(cropRect)")
    }

    // MARK: - Drawing

    private func scaleRect(_ rect: CGRect) -> CGRect {
        // Use .size.width/.size.height to preserve negative values (direction for lines/arrows)
        // Note: CGRect.width/height return absolute values, but .size preserves sign
        CGRect(
            x: rect.origin.x * zoom,
            y: rect.origin.y * zoom,
            width: rect.size.width * zoom,
            height: rect.size.height * zoom
        )
    }

    private func drawAnnotation(_ annotation: Annotation, in context: GraphicsContext, size: CGSize) {
        let scaledRect = scaleRect(annotation.cgRect)
        let color = annotation.swiftUIColor

        switch annotation.type {
        case .rectangleOutline:
            let path = Path(roundedRect: scaledRect, cornerRadius: 2)
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)

        case .rectangleSolid:
            let path = Path(roundedRect: scaledRect, cornerRadius: 2)
            context.fill(path, with: .color(color))

        case .circleOutline:
            let path = Path(ellipseIn: scaledRect)
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)

        case .line:
            // Use .size.width/.size.height to preserve direction (negative values)
            // Note: CGRect.width/height return absolute values, but .size preserves sign
            let start = CGPoint(x: scaledRect.origin.x, y: scaledRect.origin.y)
            let end = CGPoint(x: scaledRect.origin.x + scaledRect.size.width, y: scaledRect.origin.y + scaledRect.size.height)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))

        case .arrow:
            drawArrow(context: context, annotation: annotation)

        case .text:
            if let text = annotation.text {
                let scaledOrigin = CGPoint(x: annotation.cgRect.origin.x * zoom, y: annotation.cgRect.origin.y * zoom)
                let font: Font
                if annotation.fontName == ".AppleSystemUIFont" {
                    font = .system(size: annotation.fontSize * zoom, weight: .medium)
                } else {
                    font = .custom(annotation.fontName, size: annotation.fontSize * zoom)
                }
                context.draw(
                    Text(text)
                        .font(font)
                        .foregroundColor(color),
                    at: scaledOrigin,
                    anchor: .topLeading
                )
            }

        case .blur:
            // Blur is rendered in imageLayer, no visual indicator needed
            break

        case .pencil:
            drawPencilPath(context: context, annotation: annotation)

        case .highlighter:
            drawHighlighterPath(context: context, annotation: annotation)

        case .numberedStep:
            drawNumberedStep(context: context, annotation: annotation)
        }
    }

    private func drawArrow(context: GraphicsContext, annotation: Annotation) {
        let scaledRect = scaleRect(annotation.cgRect)
        // Use .size.width/.size.height to preserve direction (negative values)
        // Note: CGRect.width/height return absolute values, but .size preserves sign
        let start = CGPoint(x: scaledRect.origin.x, y: scaledRect.origin.y)
        let end = CGPoint(x: scaledRect.origin.x + scaledRect.size.width, y: scaledRect.origin.y + scaledRect.size.height)
        let color = annotation.swiftUIColor

        // Calculate arrow geometry
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = (15 + annotation.strokeWidth) * zoom
        let arrowheadHeight = arrowLength * cos(.pi / 6)  // Height from tip to base
        let totalLength = hypot(end.x - start.x, end.y - start.y)

        // Draw shaft only if arrow is longer than arrowhead, ending at arrowhead base
        if totalLength > arrowheadHeight {
            let shaftEnd = CGPoint(
                x: end.x - arrowheadHeight * cos(angle),
                y: end.y - arrowheadHeight * sin(angle)
            )
            var path = Path()
            path.move(to: start)
            path.addLine(to: shaftEnd)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))
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

        var arrowPath = Path()
        arrowPath.move(to: end)
        arrowPath.addLine(to: arrowPoint1)
        arrowPath.addLine(to: arrowPoint2)
        arrowPath.closeSubpath()
        context.fill(arrowPath, with: .color(color))
    }

    private func drawPencilPath(context: GraphicsContext, annotation: Annotation) {
        guard annotation.cgPoints.count > 1 else { return }

        var path = Path()
        let scaledPoints = annotation.cgPoints.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }

        path.move(to: scaledPoints[0])
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(path, with: .color(annotation.swiftUIColor), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawHighlighterPath(context: GraphicsContext, annotation: Annotation) {
        guard annotation.cgPoints.count > 1 else { return }

        var path = Path()
        let scaledPoints = annotation.cgPoints.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }

        path.move(to: scaledPoints[0])
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(path, with: .color(annotation.swiftUIColor.opacity(0.4)), style: StrokeStyle(lineWidth: annotation.strokeWidth * 3, lineCap: .round, lineJoin: .round))
    }

    private func drawNumberedStep(context: GraphicsContext, annotation: Annotation) {
        guard let number = annotation.stepNumber else { return }

        let size: CGFloat = 30 * zoom
        let center = CGPoint(x: annotation.cgRect.midX * zoom, y: annotation.cgRect.midY * zoom)
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)

        context.fill(Path(ellipseIn: rect), with: .color(annotation.swiftUIColor))
        context.draw(
            Text("\(number)")
                .font(.system(size: 16 * zoom, weight: .bold))
                .foregroundColor(.white),
            at: center
        )
    }
}

// MARK: - Annotation Selection Overlay

struct AnnotationSelectionOverlay: View {
    let annotation: Annotation
    let zoom: CGFloat
    let onMove: (CGSize) -> Void
    let onResize: (CGRect) -> Void
    let onEndpointMove: ((Int, CGPoint) -> Void)?  // For line/arrow endpoints

    private let handleSize: CGFloat = 10

    // Track original rect at drag start for proper delta handling
    @State private var rectAtDragStart: CGRect = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeDelta: (position: HandlePosition, delta: CGSize)? = nil
    @GestureState private var endpointDrag: (index: Int, delta: CGSize)? = nil

    init(
        annotation: Annotation,
        zoom: CGFloat,
        onMove: @escaping (CGSize) -> Void,
        onResize: @escaping (CGRect) -> Void,
        onEndpointMove: ((Int, CGPoint) -> Void)? = nil
    ) {
        self.annotation = annotation
        self.zoom = zoom
        self.onMove = onMove
        self.onResize = onResize
        self.onEndpointMove = onEndpointMove
    }

    private var scaledRect: CGRect {
        CGRect(
            x: annotation.cgRect.origin.x * zoom,
            y: annotation.cgRect.origin.y * zoom,
            width: annotation.cgRect.width * zoom,
            height: annotation.cgRect.height * zoom
        )
    }

    // For lines/arrows, use size to preserve direction (can be negative)
    private var scaledLineStart: CGPoint {
        CGPoint(x: annotation.cgRect.origin.x * zoom, y: annotation.cgRect.origin.y * zoom)
    }

    private var scaledLineEnd: CGPoint {
        CGPoint(
            x: (annotation.cgRect.origin.x + annotation.cgRect.size.width) * zoom,
            y: (annotation.cgRect.origin.y + annotation.cgRect.size.height) * zoom
        )
    }

    // Compute display rect with active gesture applied
    private var displayRect: CGRect {
        var rect = rectAtDragStart == .zero ? scaledRect : rectAtDragStart

        // Apply move offset
        if dragOffset != .zero {
            rect.origin.x += dragOffset.width
            rect.origin.y += dragOffset.height
        }

        // Apply resize delta
        if let resize = resizeDelta {
            rect = applyResizeDelta(to: rect, position: resize.position, delta: resize.delta)
        }

        return rect
    }

    var body: some View {
        ZStack {
            switch annotation.type {
            case .line, .arrow:
                // Line/Arrow: show 2 endpoint handles
                lineArrowOverlay

            case .pencil, .highlighter:
                // Freeform: move only, no resize
                freeformOverlay

            default:
                // Standard: border + 8 handles
                standardOverlay
            }
        }
        .onAppear {
            rectAtDragStart = scaledRect
        }
        .onChange(of: annotation.cgRect) { _, _ in
            // Update tracked rect when annotation changes externally
            rectAtDragStart = scaledRect
        }
    }

    // MARK: - Standard Overlay (rectangles, circles, blur, text, numbered steps)

    @ViewBuilder
    private var standardOverlay: some View {
        // Selection border with move gesture
        Rectangle()
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .frame(width: max(displayRect.width, 10), height: max(displayRect.height, 10))
            .position(x: displayRect.midX, y: displayRect.midY)
            .contentShape(Rectangle())
            .gesture(moveGesture)

        // 8 resize handles
        ForEach(HandlePosition.allCases, id: \.self) { position in
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
                .position(handlePoint(for: position, in: displayRect))
                .gesture(resizeGesture(for: position))
        }
    }

    // MARK: - Line/Arrow Overlay (2 endpoint handles)

    @ViewBuilder
    private var lineArrowOverlay: some View {
        let start = endpointDrag?.index == 0
            ? CGPoint(x: scaledLineStart.x + (endpointDrag?.delta.width ?? 0),
                      y: scaledLineStart.y + (endpointDrag?.delta.height ?? 0))
            : (dragOffset != .zero
                ? CGPoint(x: scaledLineStart.x + dragOffset.width, y: scaledLineStart.y + dragOffset.height)
                : scaledLineStart)

        let end = endpointDrag?.index == 1
            ? CGPoint(x: scaledLineEnd.x + (endpointDrag?.delta.width ?? 0),
                      y: scaledLineEnd.y + (endpointDrag?.delta.height ?? 0))
            : (dragOffset != .zero
                ? CGPoint(x: scaledLineEnd.x + dragOffset.width, y: scaledLineEnd.y + dragOffset.height)
                : scaledLineEnd)

        // Dashed line showing selection
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        .contentShape(
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }.strokedPath(StrokeStyle(lineWidth: 20))
        )
        .gesture(lineMoveGesture)

        // Start endpoint handle
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
            .position(start)
            .gesture(endpointGesture(index: 0))

        // End endpoint handle
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
            .position(end)
            .gesture(endpointGesture(index: 1))
    }

    // MARK: - Freeform Overlay (pencil/highlighter - move only)

    @ViewBuilder
    private var freeformOverlay: some View {
        // Bounding rect with dashed border
        let bounds = computeFreeformBounds()

        Rectangle()
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .frame(width: bounds.width, height: bounds.height)
            .position(
                x: bounds.midX + dragOffset.width,
                y: bounds.midY + dragOffset.height
            )
            .contentShape(Rectangle())
            .gesture(moveGesture)

        // Single center move handle
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
            .position(
                x: bounds.midX + dragOffset.width,
                y: bounds.midY + dragOffset.height
            )
    }

    private func computeFreeformBounds() -> CGRect {
        let points = annotation.cgPoints
        guard !points.isEmpty else { return scaledRect }

        let xs = points.map { $0.x * zoom }
        let ys = points.map { $0.y * zoom }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -10, dy: -10)  // Add padding
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                onMove(value.translation)
            }
    }

    private var lineMoveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                onMove(value.translation)
            }
    }

    private func resizeGesture(for position: HandlePosition) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($resizeDelta) { value, state, _ in
                state = (position: position, delta: value.translation)
            }
            .onEnded { value in
                let newRect = applyResizeDelta(to: rectAtDragStart, position: position, delta: value.translation)
                onResize(newRect)
            }
    }

    private func endpointGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($endpointDrag) { value, state, _ in
                state = (index: index, delta: value.translation)
            }
            .onEnded { value in
                if let callback = onEndpointMove {
                    // Calculate new endpoint position in image coordinates
                    let originalPoint = index == 0 ? scaledLineStart : scaledLineEnd
                    let newPoint = CGPoint(
                        x: originalPoint.x + value.translation.width,
                        y: originalPoint.y + value.translation.height
                    )
                    callback(index, newPoint)
                }
            }
    }

    // MARK: - Helper Methods

    private func handlePoint(for position: HandlePosition, in rect: CGRect) -> CGPoint {
        switch position {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    private func applyResizeDelta(to rect: CGRect, position: HandlePosition, delta: CGSize) -> CGRect {
        var newRect = rect

        switch position {
        case .topLeft:
            newRect.origin.x += delta.width
            newRect.origin.y += delta.height
            newRect.size.width -= delta.width
            newRect.size.height -= delta.height
        case .topRight:
            newRect.origin.y += delta.height
            newRect.size.width += delta.width
            newRect.size.height -= delta.height
        case .bottomLeft:
            newRect.origin.x += delta.width
            newRect.size.width -= delta.width
            newRect.size.height += delta.height
        case .bottomRight:
            newRect.size.width += delta.width
            newRect.size.height += delta.height
        case .top:
            newRect.origin.y += delta.height
            newRect.size.height -= delta.height
        case .bottom:
            newRect.size.height += delta.height
        case .left:
            newRect.origin.x += delta.width
            newRect.size.width -= delta.width
        case .right:
            newRect.size.width += delta.width
        }

        // Ensure minimum size
        if newRect.width < 10 {
            newRect.size.width = 10
            if position == .topLeft || position == .bottomLeft || position == .left {
                newRect.origin.x = rect.maxX - 10
            }
        }
        if newRect.height < 10 {
            newRect.size.height = 10
            if position == .topLeft || position == .topRight || position == .top {
                newRect.origin.y = rect.maxY - 10
            }
        }

        return newRect
    }

    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }
}

// MARK: - Crop Overlay

struct CropOverlay: View {
    let imageSize: CGSize
    let zoom: CGFloat
    @Binding var cropRect: CGRect?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    // Use @GestureState for smooth, performant dragging (auto-resets on gesture end)
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var handleDragDelta: (handle: CropHandle, delta: CGSize)? = nil

    // Track the rect at start of gesture for delta-based updates
    @State private var rectAtDragStart: CGRect = .zero
    @State private var isDrawingNewRect = false
    @State private var newRectStart: CGPoint = .zero

    private var scaledImageSize: CGSize {
        CGSize(width: imageSize.width * zoom, height: imageSize.height * zoom)
    }

    // Compute display rect with any active gesture delta applied
    private var displayRect: CGRect {
        var rect = cropRect ?? CGRect(origin: .zero, size: imageSize)

        // Apply handle drag delta if active
        if let handleDrag = handleDragDelta {
            rect = applyHandleDelta(to: rectAtDragStart, handle: handleDrag.handle, delta: handleDrag.delta)
        }

        return CGRect(
            x: rect.origin.x * zoom,
            y: rect.origin.y * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    var body: some View {
        ZStack {
            // Dimmed overlay outside crop area
            Path { path in
                path.addRect(CGRect(origin: .zero, size: scaledImageSize))
                path.addRect(displayRect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            // Crop border with rule-of-thirds grid
            cropBorderView

            // All 8 handles: 4 corners + 4 edges
            ForEach(CropHandle.allCases, id: \.self) { handle in
                handleView(for: handle)
            }
        }
        .frame(width: scaledImageSize.width, height: scaledImageSize.height)
        .contentShape(Rectangle())
        .gesture(drawNewRectGesture)
        .onAppear {
            if cropRect == nil {
                cropRect = CGRect(origin: .zero, size: imageSize)
            }
        }
    }

    // MARK: - Subviews

    private var cropBorderView: some View {
        ZStack {
            // Main border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

            // Rule of thirds grid lines
            Path { path in
                let rect = displayRect
                // Vertical lines
                path.move(to: CGPoint(x: rect.minX + rect.width / 3, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + rect.width / 3, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX + 2 * rect.width / 3, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + 2 * rect.width / 3, y: rect.maxY))
                // Horizontal lines
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height / 3))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height / 3))
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + 2 * rect.height / 3))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2 * rect.height / 3))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func handleView(for handle: CropHandle) -> some View {
        let position = handlePosition(for: handle)
        let size = handleSize(for: handle)

        Rectangle()
            .fill(Color.white)
            .frame(width: size.width, height: size.height)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($handleDragDelta) { value, state, _ in
                        state = (handle: handle, delta: value.translation)
                    }
                    .onChanged { _ in
                        // Store rect at drag start (only on first change)
                        if rectAtDragStart == .zero || handleDragDelta == nil {
                            rectAtDragStart = cropRect ?? CGRect(origin: .zero, size: imageSize)
                        }
                    }
                    .onEnded { value in
                        // Commit the final rect
                        let newRect = applyHandleDelta(to: rectAtDragStart, handle: handle, delta: value.translation)
                        cropRect = clampRect(newRect)
                        rectAtDragStart = .zero
                    }
            )
    }

    // MARK: - Gesture for drawing new crop rect

    private var drawNewRectGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDrawingNewRect {
                    newRectStart = value.startLocation
                    isDrawingNewRect = true
                }
                let rect = makeRect(from: newRectStart, to: value.location)
                cropRect = CGRect(
                    x: rect.origin.x / zoom,
                    y: rect.origin.y / zoom,
                    width: rect.width / zoom,
                    height: rect.height / zoom
                )
            }
            .onEnded { _ in
                isDrawingNewRect = false
                if let rect = cropRect {
                    cropRect = clampRect(rect)
                }
            }
    }

    // MARK: - Handle positioning and sizing

    private func handlePosition(for handle: CropHandle) -> CGPoint {
        let rect = displayRect
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func handleSize(for handle: CropHandle) -> CGSize {
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return CGSize(width: 12, height: 12)
        case .top, .bottom:
            return CGSize(width: 24, height: 8)
        case .left, .right:
            return CGSize(width: 8, height: 24)
        }
    }

    // MARK: - Resize logic

    private func applyHandleDelta(to rect: CGRect, handle: CropHandle, delta: CGSize) -> CGRect {
        var r = rect
        let dx = delta.width / zoom
        let dy = delta.height / zoom

        switch handle {
        case .topLeft:
            r.origin.x += dx
            r.origin.y += dy
            r.size.width -= dx
            r.size.height -= dy
        case .top:
            r.origin.y += dy
            r.size.height -= dy
        case .topRight:
            r.origin.y += dy
            r.size.width += dx
            r.size.height -= dy
        case .left:
            r.origin.x += dx
            r.size.width -= dx
        case .right:
            r.size.width += dx
        case .bottomLeft:
            r.origin.x += dx
            r.size.width -= dx
            r.size.height += dy
        case .bottom:
            r.size.height += dy
        case .bottomRight:
            r.size.width += dx
            r.size.height += dy
        }

        return r
    }

    private func clampRect(_ rect: CGRect) -> CGRect {
        var r = rect

        // Ensure minimum size
        r.size.width = max(r.size.width, 20)
        r.size.height = max(r.size.height, 20)

        // Clamp to image bounds
        r.origin.x = max(0, min(r.origin.x, imageSize.width - r.width))
        r.origin.y = max(0, min(r.origin.y, imageSize.height - r.height))
        r.size.width = min(r.width, imageSize.width - r.origin.x)
        r.size.height = min(r.height, imageSize.height - r.origin.y)

        return r
    }

    private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // All 8 crop handles
    enum CropHandle: CaseIterable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }
}

// MARK: - Text Input Overlay

struct TextInputOverlay: View {
    @Binding var text: String
    let position: CGPoint
    let imageSize: CGSize
    let color: Color
    let fontSize: CGFloat
    let fontName: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    // Committed state - persists after gestures end
    @State private var committedOffset: CGSize = .zero
    @State private var committedWidth: CGFloat = 0
    @State private var committedHeight: CGFloat = 0

    // Gesture state - auto-resets when gesture ends
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var resizeState: ResizeState? = nil

    // UI state
    @State private var isHoveringBorder: Bool = false
    @State private var hoveredCorner: TextBoxCorner? = nil
    @State private var isDragging: Bool = false
    @State private var isResizing: Bool = false

    private let handleSize: CGFloat = 8
    private let minWidth: CGFloat = 80
    private let minHeight: CGFloat = 50
    private let defaultHeight: CGFloat = 80

    // Default to 25% of image width, min 120, max 300
    private var defaultWidth: CGFloat {
        min(max(imageSize.width * 0.25, 120), 300)
    }

    // Current dimensions including any active resize gesture
    private var currentWidth: CGFloat {
        let base = committedWidth > 0 ? committedWidth : defaultWidth
        if let resize = resizeState {
            return max(minWidth, base + resize.widthDelta)
        }
        return base
    }

    private var currentHeight: CGFloat {
        let base = committedHeight > 0 ? committedHeight : defaultHeight
        if let resize = resizeState {
            return max(minHeight, base + resize.heightDelta)
        }
        return base
    }

    // Current position including any active drag or resize gesture
    private var currentTopLeft: CGPoint {
        var x = position.x + committedOffset.width + dragTranslation.width
        var y = position.y + committedOffset.height + dragTranslation.height

        // Apply position offset from resize (for left/top edge drags)
        if let resize = resizeState {
            x += resize.xOffset
            y += resize.yOffset
        }

        // Constrain to image bounds
        x = min(max(x, 4), imageSize.width - currentWidth - 4)
        y = min(max(y, 4), imageSize.height - currentHeight - 4)

        return CGPoint(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main text box content
            VStack(alignment: .leading, spacing: 4) {
                // Text input area using NSTextView for proper keyboard shortcut support
                AnnotationTextView(
                    text: $text,
                    font: fontName == ".AppleSystemUIFont"
                        ? NSFont.systemFont(ofSize: fontSize, weight: .medium)
                        : NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
                    textColor: NSColor(color),
                    onCommit: onCommit
                )
                .frame(minHeight: 24, maxHeight: .infinity)

                // Minimal action buttons - positioned at bottom right
                HStack(spacing: 6) {
                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                    .clipShape(Circle())

                    Button(action: onCommit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                }
            }
            .padding(8)
            .frame(width: currentWidth, height: currentHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            )
            .overlay(
                // Border with drag gesture and hover cursor
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(lineWidth: 12) // Thicker hit area for dragging
                    )
                    .onHover { hovering in
                        if hoveredCorner == nil && !isResizing {
                            isHoveringBorder = hovering
                            if hovering && !isDragging {
                                NSCursor.openHand.push()
                            } else if !hovering && !isDragging {
                                NSCursor.pop()
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onChanged { _ in
                                if !isDragging {
                                    isDragging = true
                                    NSCursor.pop()
                                    NSCursor.closedHand.push()
                                }
                            }
                            .onEnded { value in
                                isDragging = false
                                NSCursor.pop()
                                // Commit the final drag offset
                                committedOffset.width += value.translation.width
                                committedOffset.height += value.translation.height
                                if isHoveringBorder {
                                    NSCursor.openHand.push()
                                }
                            }
                    )
            )
            .position(x: currentTopLeft.x + currentWidth / 2, y: currentTopLeft.y + currentHeight / 2)

            // Corner resize handles
            ForEach(TextBoxCorner.allCases, id: \.self) { corner in
                ResizeHandle(corner: corner, handleSize: handleSize)
                    .position(cornerPosition(for: corner))
                    .onHover { hovering in
                        hoveredCorner = hovering ? corner : nil
                        if hovering {
                            if isHoveringBorder {
                                NSCursor.pop()
                                isHoveringBorder = false
                            }
                            corner.nsCursor.push()
                        } else if !isResizing {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .updating($resizeState) { value, state, _ in
                                state = corner.calculateResize(
                                    translation: value.translation,
                                    currentWidth: committedWidth > 0 ? committedWidth : defaultWidth,
                                    currentHeight: committedHeight > 0 ? committedHeight : defaultHeight,
                                    minWidth: minWidth,
                                    minHeight: minHeight
                                )
                            }
                            .onChanged { _ in
                                if !isResizing {
                                    isResizing = true
                                }
                            }
                            .onEnded { value in
                                isResizing = false
                                // Commit the resize
                                let finalResize = corner.calculateResize(
                                    translation: value.translation,
                                    currentWidth: committedWidth > 0 ? committedWidth : defaultWidth,
                                    currentHeight: committedHeight > 0 ? committedHeight : defaultHeight,
                                    minWidth: minWidth,
                                    minHeight: minHeight
                                )
                                committedWidth = max(minWidth, (committedWidth > 0 ? committedWidth : defaultWidth) + finalResize.widthDelta)
                                committedHeight = max(minHeight, (committedHeight > 0 ? committedHeight : defaultHeight) + finalResize.heightDelta)
                                committedOffset.width += finalResize.xOffset
                                committedOffset.height += finalResize.yOffset

                                if hoveredCorner != nil {
                                    // Cursor already set from hover
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { onCancel() }
        .onAppear {
            if committedWidth == 0 {
                committedWidth = defaultWidth
            }
            if committedHeight == 0 {
                committedHeight = defaultHeight
            }
        }
    }

    private func cornerPosition(for corner: TextBoxCorner) -> CGPoint {
        let topLeft = currentTopLeft

        switch corner {
        case .topLeft:
            return CGPoint(x: topLeft.x, y: topLeft.y)
        case .topRight:
            return CGPoint(x: topLeft.x + currentWidth, y: topLeft.y)
        case .bottomLeft:
            return CGPoint(x: topLeft.x, y: topLeft.y + currentHeight)
        case .bottomRight:
            return CGPoint(x: topLeft.x + currentWidth, y: topLeft.y + currentHeight)
        }
    }
}

// MARK: - Resize State

struct ResizeState: Equatable {
    var widthDelta: CGFloat = 0
    var heightDelta: CGFloat = 0
    var xOffset: CGFloat = 0
    var yOffset: CGFloat = 0
}

// MARK: - Resize Handle View

struct ResizeHandle: View {
    let corner: TextBoxCorner
    let handleSize: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Text Box Corner

enum TextBoxCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var nsCursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            // NW-SE diagonal resize
            return NSCursor.crosshair // Fallback - macOS doesn't have diagonal cursors built-in
        case .topRight, .bottomLeft:
            // NE-SW diagonal resize
            return NSCursor.crosshair
        }
    }

    func calculateResize(
        translation: CGSize,
        currentWidth: CGFloat,
        currentHeight: CGFloat,
        minWidth: CGFloat,
        minHeight: CGFloat
    ) -> ResizeState {
        var state = ResizeState()

        switch self {
        case .topLeft:
            // Dragging top-left: decrease width/height, move origin
            let newWidth = currentWidth - translation.width
            let newHeight = currentHeight - translation.height

            if newWidth >= minWidth {
                state.widthDelta = -translation.width
                state.xOffset = translation.width
            }
            if newHeight >= minHeight {
                state.heightDelta = -translation.height
                state.yOffset = translation.height
            }

        case .topRight:
            // Dragging top-right: increase width, decrease height, move Y origin
            let newWidth = currentWidth + translation.width
            let newHeight = currentHeight - translation.height

            if newWidth >= minWidth {
                state.widthDelta = translation.width
            }
            if newHeight >= minHeight {
                state.heightDelta = -translation.height
                state.yOffset = translation.height
            }

        case .bottomLeft:
            // Dragging bottom-left: decrease width, increase height, move X origin
            let newWidth = currentWidth - translation.width
            let newHeight = currentHeight + translation.height

            if newWidth >= minWidth {
                state.widthDelta = -translation.width
                state.xOffset = translation.width
            }
            if newHeight >= minHeight {
                state.heightDelta = translation.height
            }

        case .bottomRight:
            // Dragging bottom-right: increase both width and height
            let newWidth = currentWidth + translation.width
            let newHeight = currentHeight + translation.height

            if newWidth >= minWidth {
                state.widthDelta = translation.width
            }
            if newHeight >= minHeight {
                state.heightDelta = translation.height
            }
        }

        return state
    }
}

// MARK: - NSTextView Wrapper for proper keyboard shortcut support

struct AnnotationTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = AnnotationNSTextView()

        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.onCommit = onCommit

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Make first responder after a brief delay to ensure view is in hierarchy
        // Use weak reference to prevent crash if view is deallocated before async block executes
        DispatchQueue.main.async { [weak textView] in
            guard let textView = textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnnotationTextView

        init(_ parent: AnnotationTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// Custom NSTextView that handles Enter key for commit
class AnnotationNSTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Enter key (without modifiers) commits the text
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Keyboard Shortcut Handler

/// Handles keyboard shortcuts for annotation manipulation using NSViewRepresentable
/// This is necessary because SwiftUI's keyboard handling doesn't capture all events reliably
struct AnnotationKeyboardHandler: NSViewRepresentable {
    var onDelete: () -> Void
    var onNudge: (CGFloat, CGFloat) -> Void
    var onDuplicate: () -> Void
    var onCopy: () -> Void
    var onPaste: () -> Void
    var onBringForward: () -> Void
    var onSendBackward: () -> Void
    var onBringToFront: () -> Void
    var onSendToBack: () -> Void

    func makeNSView(context: Context) -> AnnotationKeyboardHandlerView {
        let view = AnnotationKeyboardHandlerView()
        view.onDelete = onDelete
        view.onNudge = onNudge
        view.onDuplicate = onDuplicate
        view.onCopy = onCopy
        view.onPaste = onPaste
        view.onBringForward = onBringForward
        view.onSendBackward = onSendBackward
        view.onBringToFront = onBringToFront
        view.onSendToBack = onSendToBack
        return view
    }

    func updateNSView(_ nsView: AnnotationKeyboardHandlerView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onNudge = onNudge
        nsView.onDuplicate = onDuplicate
        nsView.onCopy = onCopy
        nsView.onPaste = onPaste
        nsView.onBringForward = onBringForward
        nsView.onSendBackward = onSendBackward
        nsView.onBringToFront = onBringToFront
        nsView.onSendToBack = onSendToBack
    }
}

class AnnotationKeyboardHandlerView: NSView {
    var onDelete: (() -> Void)?
    var onNudge: ((CGFloat, CGFloat) -> Void)?
    var onDuplicate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onBringForward: (() -> Void)?
    var onSendBackward: (() -> Void)?
    var onBringToFront: (() -> Void)?
    var onSendToBack: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Delete/Backspace (keyCode 51 = Delete, 117 = Forward Delete)
        if keyCode == 51 || keyCode == 117 {
            if modifiers.isEmpty {
                onDelete?()
                return
            }
        }

        // Arrow keys for nudging
        // Up: 126, Down: 125, Left: 123, Right: 124
        let nudgeAmount: CGFloat = modifiers.contains(.shift) ? 10 : 1

        switch keyCode {
        case 126: // Up
            if modifiers.isEmpty || modifiers == .shift {
                onNudge?(0, -nudgeAmount)
                return
            }
        case 125: // Down
            if modifiers.isEmpty || modifiers == .shift {
                onNudge?(0, nudgeAmount)
                return
            }
        case 123: // Left
            if modifiers.isEmpty || modifiers == .shift {
                onNudge?(-nudgeAmount, 0)
                return
            }
        case 124: // Right
            if modifiers.isEmpty || modifiers == .shift {
                onNudge?(nudgeAmount, 0)
                return
            }
        default:
            break
        }

        // Cmd+D - Duplicate
        if keyCode == 2 && modifiers == .command { // D key
            onDuplicate?()
            return
        }

        // Cmd+C - Copy
        if keyCode == 8 && modifiers == .command { // C key
            onCopy?()
            return
        }

        // Cmd+V - Paste
        if keyCode == 9 && modifiers == .command { // V key
            onPaste?()
            return
        }

        // Cmd+] - Bring forward (keyCode 30 = ])
        if keyCode == 30 && modifiers == .command {
            onBringForward?()
            return
        }

        // Cmd+[ - Send backward (keyCode 33 = [)
        if keyCode == 33 && modifiers == .command {
            onSendBackward?()
            return
        }

        // Cmd+Shift+] - Bring to front
        if keyCode == 30 && modifiers == [.command, .shift] {
            onBringToFront?()
            return
        }

        // Cmd+Shift+[ - Send to back
        if keyCode == 33 && modifiers == [.command, .shift] {
            onSendToBack?()
            return
        }

        super.keyDown(with: event)
    }
}

// MARK: - Hover Tracking for Cursor Changes

struct AnnotationHoverTracker: NSViewRepresentable {
    let state: AnnotationState
    let zoom: CGFloat
    let hitTest: (CGPoint) -> Bool

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.hitTest = hitTest
        view.state = state
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.hitTest = hitTest
        nsView.state = state
        nsView.zoom = zoom
        if state.currentTool != .select {
            nsView.resetCursor()
        }
    }
}

class HoverTrackingView: NSView {
    var hitTest: ((CGPoint) -> Bool)?
    var state: AnnotationState?
    var zoom: CGFloat = 1.0
    private var trackingArea: NSTrackingArea?
    private var isCursorOverAnnotation = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard state?.currentTool == .select else {
            resetCursor()
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        // Convert to image coordinates (divide by zoom)
        // Note: SwiftUI flips Y, but NSView also has flipped coordinates when inside SwiftUI
        let imageCoords = CGPoint(x: locationInView.x / zoom, y: locationInView.y / zoom)

        let isOverAnnotation = hitTest?(imageCoords) ?? false

        if isOverAnnotation && !isCursorOverAnnotation {
            NSCursor.pointingHand.push()
            isCursorOverAnnotation = true
        } else if !isOverAnnotation && isCursorOverAnnotation {
            NSCursor.pop()
            isCursorOverAnnotation = false
        }
    }

    override func mouseExited(with event: NSEvent) {
        resetCursor()
    }

    func resetCursor() {
        if isCursorOverAnnotation {
            NSCursor.pop()
            isCursorOverAnnotation = false
        }
    }
}
