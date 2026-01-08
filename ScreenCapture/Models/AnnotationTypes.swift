import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case pencil = "Pencil"
    case highlighter = "Highlighter"
    case text = "Text"
    case blur = "Blur"
    case pixelate = "Pixelate"
    case numberedStep = "Number"
    case crop = "Crop"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .arrow: return "arrow.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3"
        case .numberedStep: return "number"
        case .crop: return "crop"
        }
    }
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var type: AnnotationType
    var rect: CGRect
    var color: Color
    var strokeWidth: CGFloat
    var isFilled: Bool
    var text: String?
    var points: [CGPoint]
    var stepNumber: Int?
    var rotation: Angle

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        rect: CGRect = .zero,
        color: Color = .red,
        strokeWidth: CGFloat = 3,
        isFilled: Bool = false,
        text: String? = nil,
        points: [CGPoint] = [],
        stepNumber: Int? = nil,
        rotation: Angle = .zero
    ) {
        self.id = id
        self.type = type
        self.rect = rect
        self.color = color
        self.strokeWidth = strokeWidth
        self.isFilled = isFilled
        self.text = text
        self.points = points
        self.stepNumber = stepNumber
        self.rotation = rotation
    }

    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }
}

enum AnnotationType: Equatable {
    case arrow(ArrowStyle)
    case rectangle
    case ellipse
    case line
    case pencil
    case highlighter
    case text
    case blur
    case pixelate
    case numberedStep

    var canBeFilled: Bool {
        switch self {
        case .rectangle, .ellipse:
            return true
        default:
            return false
        }
    }
}

enum ArrowStyle: String, CaseIterable {
    case straight = "Straight"
    case curved = "Curved"
    case double = "Double"
    case thick = "Thick"

    var icon: String {
        switch self {
        case .straight: return "arrow.right"
        case .curved: return "arrow.turn.down.right"
        case .double: return "arrow.left.arrow.right"
        case .thick: return "arrow.right.circle.fill"
        }
    }
}

struct AnnotationState: Equatable {
    var annotations: [Annotation] = []
    var selectedAnnotationId: UUID?
    var currentTool: AnnotationTool = .arrow
    var currentColor: Color = .red
    var currentStrokeWidth: CGFloat = 3
    var isFilled: Bool = false
    var arrowStyle: ArrowStyle = .straight
    var stepCounter: Int = 1
    var undoStack: [[Annotation]] = []
    var redoStack: [[Annotation]] = []

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationId else { return nil }
        return annotations.first { $0.id == id }
    }

    mutating func addAnnotation(_ annotation: Annotation) {
        saveToUndoStack()
        annotations.append(annotation)
        redoStack.removeAll()
    }

    mutating func updateAnnotation(_ annotation: Annotation) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        }
    }

    mutating func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationId else { return }
        saveToUndoStack()
        annotations.removeAll { $0.id == id }
        selectedAnnotationId = nil
        redoStack.removeAll()
    }

    mutating func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
        selectedAnnotationId = nil
    }

    mutating func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
        selectedAnnotationId = nil
    }

    private mutating func saveToUndoStack() {
        undoStack.append(annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
}

struct ToolbarState {
    var isExpanded: Bool = true
    var showColorPicker: Bool = false
    var showStrokeOptions: Bool = false
}

extension Color {
    static let annotationColors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .pink,
        .white,
        .black,
        .gray
    ]
}
