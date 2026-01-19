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
    var creationOrder: Int
    var isNumberLocked: Bool
    var name: String?

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
        blurRadius: CGFloat = 10,
        creationOrder: Int = 0,
        isNumberLocked: Bool = false,
        name: String? = nil
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
        self.creationOrder = creationOrder
        self.isNumberLocked = isNumberLocked
        self.name = name
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

/// @Observable class for fine-grained SwiftUI updates - only views that read changed properties will re-render
@Observable
class AnnotationState {
    var annotations: [Annotation] = []
    var selectedAnnotationId: UUID?
    var currentTool: AnnotationTool = .select
    var currentColor: Color = .red
    var currentStrokeWidth: CGFloat = 3
    var currentFontSize: CGFloat = 16
    var currentFontName: String = ".AppleSystemUIFont"
    var stepCounter: Int = 1
    var blurRadius: CGFloat = 10

    // Crop state
    var cropRect: CGRect?
    var isCropping: Bool = false
    var originalImageSize: CGSize = .zero

    // Layer panel state
    var isLayerPanelVisible: Bool = false
    var isLayerPanelManuallyHidden: Bool = false
    var hiddenAnnotationIds: Set<UUID> = []
    var clipboard: Annotation?

    // Creation order counter
    private var creationCounter: Int = 0

    // Undo/redo stacks - not observed to avoid unnecessary updates
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    // Index for O(1) annotation lookup
    private var annotationIndex: [UUID: Int] = [:]

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationId else { return nil }
        // Use index for O(1) lookup when available
        if let index = annotationIndex[id],
           index < annotations.count,
           annotations[index].id == id {
            return annotations[index]
        }
        // Fallback to linear search if index is stale
        return annotations.first { $0.id == id }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Rebuilds the annotation index for O(1) lookups
    private func rebuildIndex() {
        annotationIndex = Dictionary(
            uniqueKeysWithValues: annotations.enumerated().map { ($1.id, $0) }
        )
    }

    func addAnnotation(_ annotation: Annotation) {
        saveToUndoStack()
        var newAnnotation = annotation
        if newAnnotation.creationOrder == 0 {
            creationCounter += 1
            newAnnotation.creationOrder = creationCounter
        } else {
            creationCounter = max(creationCounter, newAnnotation.creationOrder)
        }
        annotations.append(newAnnotation)
        annotationIndex[newAnnotation.id] = annotations.count - 1
        redoStack.removeAll()
    }

    func updateAnnotation(_ annotation: Annotation) {
        if let index = annotationIndex[annotation.id] ?? annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        }
    }

    func deleteAnnotation(id: UUID, renumberSteps: Bool = false) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        saveToUndoStack()
        annotations.removeAll { $0.id == id }
        hiddenAnnotationIds.remove(id)
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
        rebuildIndex()
        redoStack.removeAll()
        if renumberSteps {
            self.renumberSteps(force: false)
        }
    }

    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationId else { return }
        deleteAnnotation(id: id)
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
        selectedAnnotationId = nil
        rebuildIndex()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
        selectedAnnotationId = nil
        rebuildIndex()
    }

    private func saveToUndoStack() {
        undoStack.append(annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    func selectAnnotationAt(_ point: CGPoint) {
        selectedAnnotationId = nil
        for annotation in annotations.reversed() {
            if annotation.cgRect.contains(point) {
                selectedAnnotationId = annotation.id
                break
            }
        }
    }

    // MARK: - Layer Panel Methods

    func toggleLayerPanelVisibility() {
        isLayerPanelVisible.toggle()
        isLayerPanelManuallyHidden = !isLayerPanelVisible
    }

    func toggleAnnotationVisibility(id: UUID) {
        if hiddenAnnotationIds.contains(id) {
            hiddenAnnotationIds.remove(id)
        } else {
            hiddenAnnotationIds.insert(id)
        }
    }

    func isAnnotationVisible(_ id: UUID) -> Bool {
        !hiddenAnnotationIds.contains(id)
    }

    // MARK: - Layer Ordering Methods

    func moveAnnotation(id: UUID, toIndex newIndex: Int) {
        guard let currentIndex = annotations.firstIndex(where: { $0.id == id }),
              newIndex >= 0 && newIndex < annotations.count else { return }
        saveToUndoStack()
        let annotation = annotations.remove(at: currentIndex)
        annotations.insert(annotation, at: newIndex)
        rebuildIndex()
        redoStack.removeAll()
        renumberSteps(force: false)
    }

    func bringForward(id: UUID) {
        guard let currentIndex = annotations.firstIndex(where: { $0.id == id }),
              currentIndex < annotations.count - 1 else { return }
        moveAnnotation(id: id, toIndex: currentIndex + 1)
    }

    func sendBackward(id: UUID) {
        guard let currentIndex = annotations.firstIndex(where: { $0.id == id }),
              currentIndex > 0 else { return }
        moveAnnotation(id: id, toIndex: currentIndex - 1)
    }

    func bringToFront(id: UUID) {
        moveAnnotation(id: id, toIndex: annotations.count - 1)
    }

    func sendToBack(id: UUID) {
        moveAnnotation(id: id, toIndex: 0)
    }

    // MARK: - Copy/Paste/Duplicate Methods

    func duplicateAnnotation(id: UUID, offset: CGPoint = CGPoint(x: 10, y: 10)) -> UUID? {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return nil }
        let original = annotations[index]

        creationCounter += 1
        let duplicate = Annotation(
            type: original.type,
            rect: original.cgRect.offsetBy(dx: offset.x, dy: offset.y),
            color: original.swiftUIColor,
            strokeWidth: original.strokeWidth,
            text: original.text,
            fontSize: original.fontSize,
            fontName: original.fontName,
            points: original.cgPoints.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) },
            stepNumber: original.type == .numberedStep ? stepCounter : nil,
            blurRadius: original.blurRadius,
            creationOrder: creationCounter,
            isNumberLocked: false
        )

        if original.type == .numberedStep {
            stepCounter += 1
        }

        saveToUndoStack()
        annotations.append(duplicate)
        annotationIndex[duplicate.id] = annotations.count - 1
        redoStack.removeAll()
        return duplicate.id
    }

    func copySelectedAnnotation() {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        clipboard = annotations[index]
    }

    func pasteAnnotation(offset: CGPoint = CGPoint(x: 10, y: 10)) -> UUID? {
        guard let original = clipboard else { return nil }

        creationCounter += 1
        let pasted = Annotation(
            type: original.type,
            rect: original.cgRect.offsetBy(dx: offset.x, dy: offset.y),
            color: original.swiftUIColor,
            strokeWidth: original.strokeWidth,
            text: original.text,
            fontSize: original.fontSize,
            fontName: original.fontName,
            points: original.cgPoints.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) },
            stepNumber: original.type == .numberedStep ? stepCounter : nil,
            blurRadius: original.blurRadius,
            creationOrder: creationCounter,
            isNumberLocked: false
        )

        if original.type == .numberedStep {
            stepCounter += 1
        }

        saveToUndoStack()
        annotations.append(pasted)
        annotationIndex[pasted.id] = annotations.count - 1
        redoStack.removeAll()
        selectedAnnotationId = pasted.id
        return pasted.id
    }

    // MARK: - Numbered Step Renumbering

    func renumberSteps(force: Bool) {
        var stepNumber = 1
        for i in 0..<annotations.count {
            guard annotations[i].type == .numberedStep else { continue }
            if force || !annotations[i].isNumberLocked {
                annotations[i].stepNumber = stepNumber
            }
            stepNumber += 1
        }
        // Update step counter to be one more than highest number
        stepCounter = stepNumber
    }

    func toggleStepNumberLock(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .numberedStep else { return }
        annotations[index].isNumberLocked.toggle()
    }

    func updateAnnotationName(id: UUID, name: String?) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveToUndoStack()
        annotations[index].name = name?.isEmpty == true ? nil : name
        redoStack.removeAll()
    }

    func setStepNumber(id: UUID, number: Int) {
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .numberedStep else { return }
        saveToUndoStack()
        annotations[index].stepNumber = number
        annotations[index].isNumberLocked = true
        redoStack.removeAll()
    }

    // MARK: - Nudge Methods

    func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = annotations[index]
        annotation.cgRect = annotation.cgRect.offsetBy(dx: dx, dy: dy)

        // Also offset points for pencil/highlighter
        if !annotation.cgPoints.isEmpty {
            annotation.cgPoints = annotation.cgPoints.map {
                CGPoint(x: $0.x + dx, y: $0.y + dy)
            }
        }

        saveToUndoStack()
        annotations[index] = annotation
        redoStack.removeAll()
    }

    // MARK: - Enhanced Add Annotation

    func addAnnotationWithOrder(_ annotation: Annotation) {
        creationCounter += 1
        var newAnnotation = annotation
        newAnnotation.creationOrder = creationCounter
        saveToUndoStack()
        annotations.append(newAnnotation)
        annotationIndex[newAnnotation.id] = annotations.count - 1
        redoStack.removeAll()
    }

    // MARK: - Update Selected Annotation Property

    func updateSelectedAnnotationColor(_ color: Color) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveToUndoStack()
        annotations[index].color = CodableColor(color)
        redoStack.removeAll()
    }

    func updateAnnotationColor(id: UUID, color: Color) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveToUndoStack()
        annotations[index].color = CodableColor(color)
        redoStack.removeAll()
    }

    func updateSelectedAnnotationStrokeWidth(_ width: CGFloat) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        saveToUndoStack()
        annotations[index].strokeWidth = width
        redoStack.removeAll()
    }

    func updateSelectedAnnotationFontSize(_ size: CGFloat) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard annotations[index].type == .text else { return }
        saveToUndoStack()
        annotations[index].fontSize = size
        redoStack.removeAll()
    }

    func updateSelectedAnnotationFontName(_ name: String) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard annotations[index].type == .text else { return }
        saveToUndoStack()
        annotations[index].fontName = name
        redoStack.removeAll()
    }

    // MARK: - Deselection

    func deselectAnnotation() {
        selectedAnnotationId = nil
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
    struct AnnotationColorPreset {
        let color: Color
        let name: String
        let rgb: (r: Double, g: Double, b: Double)
    }

    static let annotationColorPresets: [AnnotationColorPreset] = [
        annotationColorPreset(.red, "Red"),
        annotationColorPreset(.orange, "Orange"),
        annotationColorPreset(.yellow, "Yellow"),
        annotationColorPreset(.green, "Green"),
        annotationColorPreset(.blue, "Blue"),
        annotationColorPreset(.purple, "Purple"),
        annotationColorPreset(.pink, "Pink"),
        annotationColorPreset(.white, "White"),
        annotationColorPreset(.black, "Black"),
        annotationColorPreset(.gray, "Gray")
    ]

    static let annotationColors: [Color] = annotationColorPresets.map { $0.color }

    static func sRGBComponents(for color: Color) -> (r: Double, g: Double, b: Double)? {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        return (
            r: Double(nsColor.redComponent),
            g: Double(nsColor.greenComponent),
            b: Double(nsColor.blueComponent)
        )
    }

    private static func annotationColorPreset(_ color: Color, _ name: String) -> AnnotationColorPreset {
        let rgb = sRGBComponents(for: color) ?? (r: 0.5, g: 0.5, b: 0.5)
        return AnnotationColorPreset(color: color, name: name, rgb: rgb)
    }
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
