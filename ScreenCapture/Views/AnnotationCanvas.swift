import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct AnnotationCanvas: View {
    let image: NSImage
    @Binding var state: AnnotationState
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    @ObservedObject var viewModel: AnnotationEditorViewModel

    @State private var currentDrawing: Annotation?
    @State private var currentPoints: [CGPoint] = []
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero
    @State private var dragStartLocation: CGPoint = .zero

    // For blur preview
    @State private var blurPreviewImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    // Background image (with blur regions applied)
                    imageLayer

                    // Annotation canvas
                    Canvas { context, size in
                        // Draw all annotations
                        for annotation in state.annotations {
                            drawAnnotation(annotation, in: context, size: size)
                        }

                        // Draw current drawing preview
                        if let current = currentDrawing {
                            drawAnnotation(current, in: context, size: size)
                        }
                    }
                    .frame(
                        width: image.size.width * zoom,
                        height: image.size.height * zoom
                    )

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
                            color: state.currentColor,
                            fontSize: state.currentFontSize,
                            fontName: state.currentFontName,
                            onCommit: { commitTextAnnotation() },
                            onCancel: { showTextInput = false }
                        )
                    }
                }
                .frame(
                    width: max(geometry.size.width, image.size.width * zoom),
                    height: max(geometry.size.height, image.size.height * zoom)
                )
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
    }

    // MARK: - Image Layer

    @ViewBuilder
    private var imageLayer: some View {
        // If there are blur annotations, render image with blurs applied
        if let blurredImage = renderImageWithBlurs() {
            Image(nsImage: blurredImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: image.size.width * zoom,
                    height: image.size.height * zoom
                )
        } else {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: image.size.width * zoom,
                    height: image.size.height * zoom
                )
        }
    }

    // MARK: - Blur Rendering

    private func renderImageWithBlurs() -> NSImage? {
        let blurAnnotations = state.annotations.filter { $0.type == .blur }
        guard !blurAnnotations.isEmpty else { return nil }

        // Include current drawing if it's a blur
        var allBlurs = blurAnnotations
        if let current = currentDrawing, current.type == .blur {
            allBlurs.append(current)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        for blur in allBlurs {
            let rect = blur.cgRect

            // Create mask for this blur region
            let maskImage = createMaskCIImage(for: rect, in: image.size)

            // Apply masked blur
            let blurFilter = CIFilter.maskedVariableBlur()
            blurFilter.inputImage = ciImage.clampedToExtent()
            blurFilter.mask = maskImage
            blurFilter.radius = Float(blur.blurRadius)

            if let output = blurFilter.outputImage?.cropped(to: ciImage.extent) {
                ciImage = output
            }
        }

        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    private func createMaskCIImage(for rect: CGRect, in size: NSSize) -> CIImage {
        let maskImage = NSImage(size: size)
        maskImage.lockFocus()

        // Black background (no blur)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        // White rectangle (blur region) - note: flip Y coordinate for Core Image
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: size.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        NSColor.white.setFill()
        flippedRect.fill()

        maskImage.unlockFocus()

        guard let cgImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
        let unscaledLocation = CGPoint(x: location.x / zoom, y: location.y / zoom)

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

        let startLocation = CGPoint(x: value.startLocation.x / zoom, y: value.startLocation.y / zoom)
        let currentLocation = CGPoint(x: value.location.x / zoom, y: value.location.y / zoom)

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

        let unscaledPosition = CGPoint(x: textPosition.x / zoom, y: textPosition.y / zoom)
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
        CGRect(
            x: rect.origin.x * zoom,
            y: rect.origin.y * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
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
            var path = Path()
            path.move(to: CGPoint(x: scaledRect.minX, y: scaledRect.minY))
            path.addLine(to: CGPoint(x: scaledRect.maxX, y: scaledRect.maxY))
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
            // Blur is rendered in imageLayer, just show selection indicator
            let path = Path(roundedRect: scaledRect, cornerRadius: 4)
            context.stroke(path, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))

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
        let start = CGPoint(x: scaledRect.minX, y: scaledRect.minY)
        let end = CGPoint(x: scaledRect.maxX, y: scaledRect.maxY)
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

    @State private var dragStart: CGPoint = .zero
    @State private var isDragging = false

    private var scaledImageSize: CGSize {
        CGSize(width: imageSize.width * zoom, height: imageSize.height * zoom)
    }

    private var displayRect: CGRect {
        if let rect = cropRect {
            return CGRect(
                x: rect.origin.x * zoom,
                y: rect.origin.y * zoom,
                width: rect.width * zoom,
                height: rect.height * zoom
            )
        }
        return CGRect(origin: .zero, size: scaledImageSize)
    }

    var body: some View {
        ZStack {
            // Dimmed overlay outside crop area
            Path { path in
                path.addRect(CGRect(origin: .zero, size: scaledImageSize))
                path.addRect(displayRect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            // Crop border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

            // Corner handles
            ForEach(CropHandle.allCases, id: \.self) { handle in
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .position(handlePosition(for: handle))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleCropResize(handle: handle, translation: value.translation)
                            }
                    )
            }
        }
        .frame(width: scaledImageSize.width, height: scaledImageSize.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        dragStart = value.startLocation
                        isDragging = true
                    }
                    let rect = makeRect(from: dragStart, to: value.location)
                    cropRect = CGRect(
                        x: rect.origin.x / zoom,
                        y: rect.origin.y / zoom,
                        width: rect.width / zoom,
                        height: rect.height / zoom
                    )
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onAppear {
            // Initialize with full image
            if cropRect == nil {
                cropRect = CGRect(origin: .zero, size: imageSize)
            }
        }
    }

    private func handlePosition(for handle: CropHandle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: displayRect.minX, y: displayRect.minY)
        case .topRight: return CGPoint(x: displayRect.maxX, y: displayRect.minY)
        case .bottomLeft: return CGPoint(x: displayRect.minX, y: displayRect.maxY)
        case .bottomRight: return CGPoint(x: displayRect.maxX, y: displayRect.maxY)
        }
    }

    private func handleCropResize(handle: CropHandle, translation: CGSize) {
        guard var rect = cropRect else { return }
        let dx = translation.width / zoom
        let dy = translation.height / zoom

        switch handle {
        case .topLeft:
            rect.origin.x += dx
            rect.origin.y += dy
            rect.size.width -= dx
            rect.size.height -= dy
        case .topRight:
            rect.origin.y += dy
            rect.size.width += dx
            rect.size.height -= dy
        case .bottomLeft:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.size.height += dy
        case .bottomRight:
            rect.size.width += dx
            rect.size.height += dy
        }

        // Clamp to image bounds
        rect = rect.intersection(CGRect(origin: .zero, size: imageSize))

        if rect.width > 10 && rect.height > 10 {
            cropRect = rect
        }
    }

    private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    enum CropHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

// MARK: - Text Input Overlay

struct TextInputOverlay: View {
    @Binding var text: String
    let position: CGPoint
    let color: Color
    let fontSize: CGFloat
    let fontName: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Enter text...", text: $text)
                .textFieldStyle(.plain)
                .font(fontName == ".AppleSystemUIFont" ? .system(size: fontSize) : .custom(fontName, size: fontSize))
                .foregroundColor(color)
                .focused($isFocused)
                .onSubmit { onCommit() }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button("Add") { onCommit() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 11))
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 8)
        .frame(minWidth: 200)
        .position(position)
        .onAppear { isFocused = true }
        .onExitCommand { onCancel() }
    }
}
