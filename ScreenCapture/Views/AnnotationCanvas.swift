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

    // For blur caching - only cache committed blur annotations, not during drag
    @State private var cachedBlurImage: NSImage?
    @State private var blurCacheKey: String = ""

    // Cache key for COMMITTED blur annotations only (not current drawing)
    // This prevents re-rendering during drag which was causing performance issues
    private var committedBlurCacheKey: String {
        let blurAnnotations = state.annotations.filter { $0.type == .blur }
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

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                // Use topLeading alignment so image is at (0,0) and gestures map directly
                ZStack(alignment: .topLeading) {
                    // Background image (with blur regions applied)
                    imageLayer

                    // Static annotation canvas - committed annotations only
                    // Uses drawingGroup() for Metal-backed off-screen rendering
                    Canvas { context, size in
                        for annotation in state.annotations {
                            drawAnnotation(annotation, in: context, size: size)
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
                        if annotation.id == state.selectedAnnotationId {
                            AnnotationSelectionOverlay(
                                annotation: annotation,
                                zoom: zoom,
                                onMove: { delta in
                                    moveSelectedAnnotation(by: delta)
                                },
                                onResize: { newRect in
                                    resizeSelectedAnnotation(to: newRect)
                                }
                            )
                        }
                    }

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
                            onCancel: { showTextInput = false }
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
        }
        .onChange(of: state.currentTool) { _, newTool in
            // Dismiss text input when switching to a different tool
            if newTool != .text && showTextInput {
                showTextInput = false
                textInput = ""
            }
        }
    }

    // MARK: - Image Layer

    @ViewBuilder
    private var imageLayer: some View {
        let cacheKey = committedBlurCacheKey

        ZStack(alignment: .topLeading) {
            // Base image layer - either original or with committed blurs applied
            if cacheKey.isEmpty {
                // No committed blur annotations - show original image
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
            } else if let cached = cachedBlurImage, blurCacheKey == cacheKey {
                // Use cached blur result for committed blurs
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
            } else {
                // Render committed blurs and cache (this only runs when annotations change, not during drag)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                    .task(id: cacheKey) {
                        // Render blurs asynchronously to avoid blocking UI
                        if let blurredImage = renderCommittedBlurs() {
                            cachedBlurImage = blurredImage
                            blurCacheKey = cacheKey
                        }
                    }
            }

            // Blur preview overlay - shown during drag instead of real-time blur rendering
            // This is MUCH faster than rendering actual blur on every mouse move
            if isDrawingBlur, let current = currentDrawing {
                blurPreviewOverlay(for: current)
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

        Rectangle()
            .fill(Color.white.opacity(0.3))
            .background(.ultraThinMaterial)
            .frame(width: abs(scaledRect.width), height: abs(scaledRect.height))
            .position(
                x: scaledRect.origin.x + scaledRect.width / 2,
                y: scaledRect.origin.y + scaledRect.height / 2
            )
    }

    // MARK: - Blur Rendering

    /// Renders only COMMITTED blur annotations (not current drawing during drag)
    /// This function is only called when blur annotations are added/removed, not during drag
    private func renderCommittedBlurs() -> NSImage? {
        let blurAnnotations = state.annotations.filter { $0.type == .blur }
        guard !blurAnnotations.isEmpty else { return nil }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Combine all blur regions into a single mask for efficiency
        // This avoids creating N separate filters for N blur regions
        let combinedMask = createCombinedMaskCIImage(for: blurAnnotations, in: image.size)

        // Use average blur radius for combined blur (could be refined per-region with more complex approach)
        let avgRadius = blurAnnotations.reduce(0.0) { $0 + $1.blurRadius } / CGFloat(blurAnnotations.count)

        let ciImage = CIImage(cgImage: cgImage)

        // Single blur filter pass with combined mask
        let blurFilter = CIFilter.maskedVariableBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.mask = combinedMask
        blurFilter.radius = Float(avgRadius)

            if let output = blurFilter.outputImage?.cropped(to: ciImage.extent) {
                ciImage = output
            }
        }

        guard let outputCGImage = viewModel.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    private func createMaskCIImage(for rect: CGRect, in size: NSSize) -> CIImage {
        // Use CGContext directly for better performance (avoids NSGraphicsContext overhead)
        let width = Int(size.width)
        let height = Int(size.height)

        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return CIImage()
        }

        // Black background (no blur) - gray value 0
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // White rectangle (blur region) - note: flip Y coordinate for Core Image
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: size.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(flippedRect)

        guard let cgImage = context.makeImage() else {
            return CIImage()
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

        switch state.currentTool {
        case .select:
            // Try to select an annotation at this point
            state.selectedAnnotationId = nil
            for annotation in state.annotations.reversed() {
                if hitTest(annotation: annotation, at: unscaledLocation) {
                    state.selectedAnnotationId = annotation.id
                    break
                }
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
            // Deselect on tap for other tools
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
        annotation.cgRect = annotation.cgRect.offsetBy(dx: delta.width / zoom, dy: delta.height / zoom)
        state.annotations[index] = annotation
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
        state.annotations[index] = annotation
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

        // Draw line
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))

        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = (15 + annotation.strokeWidth) * zoom

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

    private let handleSize: CGFloat = 10

    private var scaledRect: CGRect {
        CGRect(
            x: annotation.cgRect.origin.x * zoom,
            y: annotation.cgRect.origin.y * zoom,
            width: annotation.cgRect.width * zoom,
            height: annotation.cgRect.height * zoom
        )
    }

    var body: some View {
        ZStack {
            // Selection border
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onMove(value.translation)
                        }
                )

            // Resize handles
            ForEach(HandlePosition.allCases, id: \.self) { position in
                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1))
                    .position(handlePoint(for: position))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleResize(position: position, translation: value.translation)
                            }
                    )
            }
        }
    }

    private func handlePoint(for position: HandlePosition) -> CGPoint {
        switch position {
        case .topLeft: return CGPoint(x: scaledRect.minX, y: scaledRect.minY)
        case .topRight: return CGPoint(x: scaledRect.maxX, y: scaledRect.minY)
        case .bottomLeft: return CGPoint(x: scaledRect.minX, y: scaledRect.maxY)
        case .bottomRight: return CGPoint(x: scaledRect.maxX, y: scaledRect.maxY)
        case .top: return CGPoint(x: scaledRect.midX, y: scaledRect.minY)
        case .bottom: return CGPoint(x: scaledRect.midX, y: scaledRect.maxY)
        case .left: return CGPoint(x: scaledRect.minX, y: scaledRect.midY)
        case .right: return CGPoint(x: scaledRect.maxX, y: scaledRect.midY)
        }
    }

    private func handleResize(position: HandlePosition, translation: CGSize) {
        var newRect = scaledRect

        switch position {
        case .topLeft:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
            newRect.size.width -= translation.width
            newRect.size.height -= translation.height
        case .topRight:
            newRect.origin.y += translation.height
            newRect.size.width += translation.width
            newRect.size.height -= translation.height
        case .bottomLeft:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            newRect.size.height += translation.height
        case .bottomRight:
            newRect.size.width += translation.width
            newRect.size.height += translation.height
        case .top:
            newRect.origin.y += translation.height
            newRect.size.height -= translation.height
        case .bottom:
            newRect.size.height += translation.height
        case .left:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
        case .right:
            newRect.size.width += translation.width
        }

        // Ensure minimum size
        if newRect.width > 10 && newRect.height > 10 {
            onResize(newRect)
        }
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
