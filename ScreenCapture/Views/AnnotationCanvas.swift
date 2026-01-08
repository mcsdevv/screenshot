import SwiftUI
import AppKit

struct AnnotationCanvas: View {
    let image: NSImage
    @Binding var state: AnnotationState
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    @State private var currentDrawing: Annotation?
    @State private var currentPoints: [CGPoint] = []
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: image.size.width * zoom,
                            height: image.size.height * zoom
                        )

                    Canvas { context, size in
                        for annotation in state.annotations {
                            drawAnnotation(annotation, in: context, size: size)
                        }

                        if let current = currentDrawing {
                            drawAnnotation(current, in: context, size: size)
                        }
                    }
                    .frame(
                        width: image.size.width * zoom,
                        height: image.size.height * zoom
                    )

                    ForEach(state.annotations) { annotation in
                        if annotation.id == state.selectedAnnotationId {
                            SelectionHandles(
                                rect: scaleRect(annotation.rect),
                                onResize: { newRect in
                                    var updated = annotation
                                    updated.rect = unscaleRect(newRect)
                                    state.updateAnnotation(updated)
                                }
                            )
                        }
                    }

                    if showTextInput {
                        TextInputOverlay(
                            text: $textInput,
                            position: textPosition,
                            color: state.currentColor,
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

        if state.currentTool == .select {
            state.selectedAnnotationId = nil
            for annotation in state.annotations.reversed() {
                if annotation.rect.contains(unscaledLocation) {
                    state.selectedAnnotationId = annotation.id
                    break
                }
            }
        } else if state.currentTool == .text {
            textPosition = location
            textInput = ""
            showTextInput = true
        } else if state.currentTool == .numberedStep {
            let annotation = Annotation(
                type: .numberedStep,
                rect: CGRect(origin: unscaledLocation, size: CGSize(width: 30, height: 30)),
                color: state.currentColor,
                stepNumber: state.stepCounter
            )
            state.addAnnotation(annotation)
            state.stepCounter += 1
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard state.currentTool != .select && state.currentTool != .text else { return }

        let startLocation = CGPoint(x: value.startLocation.x / zoom, y: value.startLocation.y / zoom)
        let currentLocation = CGPoint(x: value.location.x / zoom, y: value.location.y / zoom)

        switch state.currentTool {
        case .pencil, .highlighter:
            let scaledPoint = currentLocation
            currentPoints.append(scaledPoint)

            let type: AnnotationType = state.currentTool == .pencil ? .pencil : .highlighter
            currentDrawing = Annotation(
                type: type,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth,
                points: currentPoints
            )

        case .arrow:
            currentDrawing = Annotation(
                type: .arrow(state.arrowStyle),
                rect: CGRect(origin: startLocation, size: CGSize(width: currentLocation.x - startLocation.x, height: currentLocation.y - startLocation.y)),
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .rectangle:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .rectangle,
                rect: rect,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth,
                isFilled: state.isFilled
            )

        case .ellipse:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: .ellipse,
                rect: rect,
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth,
                isFilled: state.isFilled
            )

        case .line:
            currentDrawing = Annotation(
                type: .line,
                rect: CGRect(origin: startLocation, size: CGSize(width: currentLocation.x - startLocation.x, height: currentLocation.y - startLocation.y)),
                color: state.currentColor,
                strokeWidth: state.currentStrokeWidth
            )

        case .blur, .pixelate:
            let rect = makeRect(from: startLocation, to: currentLocation)
            currentDrawing = Annotation(
                type: state.currentTool == .blur ? .blur : .pixelate,
                rect: rect,
                color: .clear
            )

        default:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if let drawing = currentDrawing {
            state.addAnnotation(drawing)
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
            strokeWidth: state.currentStrokeWidth,
            text: textInput
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

    private func scaleRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * zoom,
            y: rect.origin.y * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    private func unscaleRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x / zoom,
            y: rect.origin.y / zoom,
            width: rect.width / zoom,
            height: rect.height / zoom
        )
    }

    private func drawAnnotation(_ annotation: Annotation, in context: GraphicsContext, size: CGSize) {
        let scaledRect = scaleRect(annotation.rect)
        let color = annotation.color

        switch annotation.type {
        case .arrow(let style):
            drawArrow(context: context, annotation: annotation, style: style)

        case .rectangle:
            let path = Path(roundedRect: scaledRect, cornerRadius: 4)
            if annotation.isFilled {
                context.fill(path, with: .color(color.opacity(0.3)))
            }
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)

        case .ellipse:
            let path = Path(ellipseIn: scaledRect)
            if annotation.isFilled {
                context.fill(path, with: .color(color.opacity(0.3)))
            }
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)

        case .line:
            var path = Path()
            path.move(to: CGPoint(x: scaledRect.minX, y: scaledRect.minY))
            path.addLine(to: CGPoint(x: scaledRect.maxX, y: scaledRect.maxY))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))

        case .pencil:
            drawPencilPath(context: context, annotation: annotation)

        case .highlighter:
            drawHighlighterPath(context: context, annotation: annotation)

        case .text:
            if let text = annotation.text {
                let scaledOrigin = CGPoint(x: annotation.rect.origin.x * zoom, y: annotation.rect.origin.y * zoom)
                context.draw(
                    Text(text)
                        .font(.system(size: annotation.strokeWidth * 6 * zoom, weight: .medium))
                        .foregroundColor(color),
                    at: scaledOrigin,
                    anchor: .topLeading
                )
            }

        case .blur:
            context.fill(Path(scaledRect), with: .color(.gray.opacity(0.5)))

        case .pixelate:
            context.fill(Path(scaledRect), with: .color(.gray.opacity(0.5)))

        case .numberedStep:
            if let number = annotation.stepNumber {
                let size: CGFloat = 30 * zoom
                let center = CGPoint(x: annotation.rect.midX * zoom, y: annotation.rect.midY * zoom)
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)

                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.draw(
                    Text("\(number)")
                        .font(.system(size: 16 * zoom, weight: .bold))
                        .foregroundColor(.white),
                    at: center
                )
            }
        }
    }

    private func drawArrow(context: GraphicsContext, annotation: Annotation, style: ArrowStyle) {
        let scaledRect = scaleRect(annotation.rect)
        let start = CGPoint(x: scaledRect.minX, y: scaledRect.minY)
        let end = CGPoint(x: scaledRect.maxX, y: scaledRect.maxY)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15 * zoom

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)

        context.stroke(path, with: .color(annotation.color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawPencilPath(context: GraphicsContext, annotation: Annotation) {
        guard annotation.points.count > 1 else { return }

        var path = Path()
        let scaledPoints = annotation.points.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }

        path.move(to: scaledPoints[0])
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(path, with: .color(annotation.color), style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawHighlighterPath(context: GraphicsContext, annotation: Annotation) {
        guard annotation.points.count > 1 else { return }

        var path = Path()
        let scaledPoints = annotation.points.map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }

        path.move(to: scaledPoints[0])
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(path, with: .color(annotation.color.opacity(0.4)), style: StrokeStyle(lineWidth: annotation.strokeWidth * 3, lineCap: .round, lineJoin: .round))
    }
}

struct SelectionHandles: View {
    let rect: CGRect
    let onResize: (CGRect) -> Void

    private let handleSize: CGFloat = 10

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

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

    private func handleResize(position: HandlePosition, translation: CGSize) {
        var newRect = rect

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

        onResize(newRect)
    }

    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }
}

struct TextInputOverlay: View {
    @Binding var text: String
    let position: CGPoint
    let color: Color
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Enter text...", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(color)
            .padding(8)
            .background(Color.white.opacity(0.9))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.2), radius: 4)
            .frame(minWidth: 150)
            .position(position)
            .focused($isFocused)
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
            .onAppear { isFocused = true }
    }
}
