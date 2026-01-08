import SwiftUI
import AppKit

struct AnnotationEditor: View {
    let capture: CaptureItem
    @EnvironmentObject var storageManager: StorageManager
    @StateObject private var viewModel = AnnotationEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditorToolbar(viewModel: viewModel, onSave: saveImage, onDismiss: { dismiss() })

                ZStack {
                    if let image = viewModel.image {
                        AnnotationCanvas(
                            image: image,
                            state: $viewModel.state,
                            zoom: $viewModel.zoom,
                            offset: $viewModel.offset
                        )
                    } else {
                        ProgressView("Loading...")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                EditorBottomBar(viewModel: viewModel)
            }
        }
        .onAppear {
            loadImage()
        }
        .focusedSceneValue(\.annotationViewModel, viewModel)
    }

    private func loadImage() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let nsImage = NSImage(contentsOf: url) {
            viewModel.image = nsImage
        }
    }

    private func saveImage() {
        guard let image = viewModel.renderAnnotatedImage() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = capture.filename

        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}

@MainActor
class AnnotationEditorViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var state = AnnotationState()
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var showExportOptions = false

    func renderAnnotatedImage() -> NSImage? {
        guard let originalImage = image else { return nil }

        let size = originalImage.size
        let newImage = NSImage(size: size)

        newImage.lockFocus()

        originalImage.draw(in: NSRect(origin: .zero, size: size))

        for annotation in state.annotations {
            drawAnnotation(annotation, in: size)
        }

        newImage.unlockFocus()

        return newImage
    }

    private func drawAnnotation(_ annotation: Annotation, in size: NSSize) {
        let nsColor = NSColor(annotation.color)
        nsColor.setStroke()
        nsColor.setFill()

        switch annotation.type {
        case .arrow(let style):
            drawArrow(annotation, style: style)
        case .rectangle:
            drawRectangle(annotation)
        case .ellipse:
            drawEllipse(annotation)
        case .line:
            drawLine(annotation)
        case .pencil:
            drawPencil(annotation)
        case .highlighter:
            drawHighlighter(annotation)
        case .text:
            drawText(annotation)
        case .blur:
            break
        case .pixelate:
            break
        case .numberedStep:
            drawNumberedStep(annotation)
        }
    }

    private func drawArrow(_ annotation: Annotation, style: ArrowStyle) {
        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round

        let start = CGPoint(x: annotation.rect.minX, y: annotation.rect.minY)
        let end = CGPoint(x: annotation.rect.maxX, y: annotation.rect.maxY)

        path.move(to: start)
        path.line(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 15

        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        path.move(to: end)
        path.line(to: arrowPoint1)
        path.move(to: end)
        path.line(to: arrowPoint2)

        path.stroke()
    }

    private func drawRectangle(_ annotation: Annotation) {
        let path = NSBezierPath(roundedRect: annotation.rect, xRadius: 4, yRadius: 4)
        path.lineWidth = annotation.strokeWidth

        if annotation.isFilled {
            NSColor(annotation.color).withAlphaComponent(0.3).setFill()
            path.fill()
        }

        path.stroke()
    }

    private func drawEllipse(_ annotation: Annotation) {
        let path = NSBezierPath(ovalIn: annotation.rect)
        path.lineWidth = annotation.strokeWidth

        if annotation.isFilled {
            NSColor(annotation.color).withAlphaComponent(0.3).setFill()
            path.fill()
        }

        path.stroke()
    }

    private func drawLine(_ annotation: Annotation) {
        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round

        path.move(to: CGPoint(x: annotation.rect.minX, y: annotation.rect.minY))
        path.line(to: CGPoint(x: annotation.rect.maxX, y: annotation.rect.maxY))

        path.stroke()
    }

    private func drawPencil(_ annotation: Annotation) {
        guard annotation.points.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: annotation.points[0])
        for point in annotation.points.dropFirst() {
            path.line(to: point)
        }

        path.stroke()
    }

    private func drawHighlighter(_ annotation: Annotation) {
        guard annotation.points.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = annotation.strokeWidth * 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSColor(annotation.color).withAlphaComponent(0.4).setStroke()

        path.move(to: annotation.points[0])
        for point in annotation.points.dropFirst() {
            path.line(to: point)
        }

        path.stroke()
    }

    private func drawText(_ annotation: Annotation) {
        guard let text = annotation.text else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.strokeWidth * 6, weight: .medium),
            .foregroundColor: NSColor(annotation.color)
        ]

        let string = NSAttributedString(string: text, attributes: attributes)
        string.draw(at: annotation.rect.origin)
    }

    private func drawNumberedStep(_ annotation: Annotation) {
        guard let number = annotation.stepNumber else { return }

        let size: CGFloat = 30
        let rect = CGRect(
            x: annotation.rect.midX - size / 2,
            y: annotation.rect.midY - size / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: rect)
        NSColor(annotation.color).setFill()
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
}

struct EditorToolbar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Divider()
                .frame(height: 20)

            ForEach(mainTools, id: \.self) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: viewModel.state.currentTool == tool,
                    action: { viewModel.state.currentTool = tool }
                )
            }

            Divider()
                .frame(height: 20)

            ColorPickerButton(
                selectedColor: $viewModel.state.currentColor,
                colors: Color.annotationColors
            )

            StrokeWidthPicker(strokeWidth: $viewModel.state.currentStrokeWidth)

            if viewModel.state.currentTool == .rectangle || viewModel.state.currentTool == .ellipse {
                Toggle(isOn: $viewModel.state.isFilled) {
                    Image(systemName: viewModel.state.isFilled ? "rectangle.fill" : "rectangle")
                }
                .toggleStyle(.button)
            }

            Spacer()

            Button(action: { viewModel.state.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(viewModel.state.undoStack.isEmpty)
            .keyboardShortcut("z", modifiers: .command)

            Button(action: { viewModel.state.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(viewModel.state.redoStack.isEmpty)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()
                .frame(height: 20)

            Button("Copy") {
                copyToClipboard()
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var mainTools: [AnnotationTool] {
        [.select, .arrow, .rectangle, .ellipse, .line, .pencil, .highlighter, .text, .blur, .numberedStep]
    }

    private func copyToClipboard() {
        guard let image = viewModel.renderAnnotatedImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .primary)
        .help(tool.rawValue)
    }
}

struct ColorPickerButton: View {
    @Binding var selectedColor: Color
    let colors: [Color]
    @State private var showPicker = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            Circle()
                .fill(selectedColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            ColorPickerView(selectedColor: $selectedColor, colors: colors)
        }
    }
}

struct StrokeWidthPicker: View {
    @Binding var strokeWidth: CGFloat
    @State private var showPicker = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 20, height: strokeWidth)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            VStack(spacing: 8) {
                ForEach([1, 2, 3, 5, 8, 12], id: \.self) { width in
                    Button(action: {
                        strokeWidth = CGFloat(width)
                        showPicker = false
                    }) {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 40, height: CGFloat(width))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

struct EditorBottomBar: View {
    @ObservedObject var viewModel: AnnotationEditorViewModel

    var body: some View {
        HStack {
            if let image = viewModel.image {
                Text("\(Int(image.size.width)) x \(Int(image.size.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: { viewModel.zoom = max(0.1, viewModel.zoom - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Text("\(Int(viewModel.zoom * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 40)

                Button(action: { viewModel.zoom = min(4.0, viewModel.zoom + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.zoom = 1.0; viewModel.offset = .zero }) {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AnnotationViewModelKey: FocusedValueKey {
    typealias Value = AnnotationEditorViewModel
}

extension FocusedValues {
    var annotationViewModel: AnnotationEditorViewModel? {
        get { self[AnnotationViewModelKey.self] }
        set { self[AnnotationViewModelKey.self] = newValue }
    }
}
