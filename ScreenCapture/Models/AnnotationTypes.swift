import SwiftUI
import AppKit
import Observation

// MARK: - Annotation Tools

enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    case select = "Select"
    case crop = "Crop"
    case rectangleOutline = "Rectangle"
    case rectangleSolid = "Rectangle Solid"
    case circleOutline = "Circle"
    case line = "Line"
    case arrow = "Arrow"
    case text = "Text"
    case blur = "Blur"
    case pencil = "Pencil"
    case highlighter = "Highlighter"
    case numberedStep = "Number"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .crop: return "crop"
        case .rectangleOutline: return "rectangle"
        case .rectangleSolid: return "rectangle.fill"
        case .circleOutline: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "character"
        case .blur: return "aqi.medium"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .numberedStep: return "number"
        }
    }

    var tooltip: String {
        switch self {
        case .select: return "Select and move annotations"
        case .crop: return "Crop the image"
        case .rectangleOutline: return "Draw rectangle outline"
        case .rectangleSolid: return "Draw filled rectangle"
        case .circleOutline: return "Draw circle outline"
        case .line: return "Draw a line"
        case .arrow: return "Draw an arrow"
        case .text: return "Add text"
        case .blur: return "Blur an area"
        case .pencil: return "Freehand drawing"
        case .highlighter: return "Highlight an area"
        case .numberedStep: return "Add numbered step"
        }
    }
}

// MARK: - Annotation Type

enum AnnotationType: Equatable, Codable {
    case rectangleOutline
    case rectangleSolid
    case circleOutline
    case line
    case arrow
    case text
    case blur
    case pencil
    case highlighter
    case numberedStep

    var canBeFilled: Bool {
        switch self {
        case .rectangleSolid:
            return true
        default:
            return false
        }
    }
}

// MARK: - Annotation Model

struct Annotation: Identifiable, Equatable, Codable {
    let id: UUID
    var type: AnnotationType
    var rect: CodableRect
    var color: CodableColor
    var strokeWidth: CGFloat
    var text: String?
    var fontSize: CGFloat
    var fontName: String
    var points: [CodablePoint]
    var stepNumber: Int?
    var blurRadius: CGFloat

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        rect: CGRect = .zero,
        color: Color = .red,
        strokeWidth: CGFloat = 3,
        text: String? = nil,
        fontSize: CGFloat = 16,
        fontName: String = ".AppleSystemUIFont",
        points: [CGPoint] = [],
        stepNumber: Int? = nil,
        blurRadius: CGFloat = 10
    ) {
        self.id = id
        self.type = type
        self.rect = CodableRect(rect)
        self.color = CodableColor(color)
        self.strokeWidth = strokeWidth
        self.text = text
        self.fontSize = fontSize
        self.fontName = fontName
        self.points = points.map { CodablePoint($0) }
        self.stepNumber = stepNumber
        self.blurRadius = blurRadius
    }

    // Convenience accessors for CGRect/Color
    var cgRect: CGRect {
        get { rect.cgRect }
        set { rect = CodableRect(newValue) }
    }

    var swiftUIColor: Color {
        get { color.color }
        set { color = CodableColor(newValue) }
    }

    var cgPoints: [CGPoint] {
        get { points.map { $0.cgPoint } }
        set { points = newValue.map { CodablePoint($0) } }
    }

    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Codable Wrappers for Core Graphics Types

struct CodableRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CodablePoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ color: Color) {
        // Convert SwiftUI Color to NSColor to extract components
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.red
        self.red = nsColor.redComponent
        self.green = nsColor.greenComponent
        self.blue = nsColor.blueComponent
        self.alpha = nsColor.alphaComponent
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Annotation State

struct AnnotationState: Equatable {
    var annotations: [Annotation] = []
    var selectedAnnotationId: UUID?
    var currentTool: AnnotationTool = .select
    var currentColor: Color = .red
    var currentStrokeWidth: CGFloat = 3
    var currentFontSize: CGFloat = 16
    var currentFontName: String = ".AppleSystemUIFont"
    var stepCounter: Int = 1
    var undoStack: [[Annotation]] = []
    var redoStack: [[Annotation]] = []
    var blurRadius: CGFloat = 10

    // Crop state
    var cropRect: CGRect?
    var isCropping: Bool = false
    var originalImageSize: CGSize = .zero

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

    mutating func selectAnnotationAt(_ point: CGPoint) {
        selectedAnnotationId = nil
        for annotation in annotations.reversed() {
            if annotation.cgRect.contains(point) {
                selectedAnnotationId = annotation.id
                break
            }
        }
    }
}

// MARK: - Annotation Document (for sidecar file persistence)

struct AnnotationDocument: Codable {
    static let fileExtension = "screencapture-annotations"
    static let currentVersion = 1

    var version: Int
    var annotations: [Annotation]
    var imageHash: String // SHA256 hash of original image for verification

    init(annotations: [Annotation], imageHash: String) {
        self.version = Self.currentVersion
        self.annotations = annotations
        self.imageHash = imageHash
    }

    static func sidecarURL(for imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
        debugLog("AnnotationDocument: Saved \(annotations.count) annotations to \(url.path)")
    }

    static func load(from url: URL) throws -> AnnotationDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document = try decoder.decode(AnnotationDocument.self, from: data)
        debugLog("AnnotationDocument: Loaded \(document.annotations.count) annotations from \(url.path)")
        return document
    }
}

// MARK: - Color Presets

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

// MARK: - Font Options

struct FontOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String

    static let systemFonts: [FontOption] = [
        FontOption(name: ".AppleSystemUIFont", displayName: "System"),
        FontOption(name: "Helvetica Neue", displayName: "Helvetica"),
        FontOption(name: "Arial", displayName: "Arial"),
        FontOption(name: "Georgia", displayName: "Georgia"),
        FontOption(name: "Courier New", displayName: "Courier"),
        FontOption(name: "Menlo", displayName: "Menlo"),
        FontOption(name: "Monaco", displayName: "Monaco")
    ]
}
