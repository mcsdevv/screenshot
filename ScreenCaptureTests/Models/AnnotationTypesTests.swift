import XCTest
import SwiftUI
@testable import ScreenCapture

final class AnnotationTypesTests: XCTestCase {

    // MARK: - AnnotationTool Tests

    func testAnnotationToolCases() {
        XCTAssertEqual(AnnotationTool.allCases.count, 12)
    }

    func testAnnotationToolIds() {
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(tool.id, tool.rawValue)
        }
    }

    func testAnnotationToolIcons() {
        for tool in AnnotationTool.allCases {
            XCTAssertFalse(tool.icon.isEmpty, "Tool \(tool) should have an icon")
        }
    }

    func testAnnotationToolTooltips() {
        for tool in AnnotationTool.allCases {
            XCTAssertFalse(tool.tooltip.isEmpty, "Tool \(tool) should have a tooltip")
        }
    }

    func testSpecificToolIcons() {
        XCTAssertEqual(AnnotationTool.select.icon, "arrow.up.left.and.arrow.down.right")
        XCTAssertEqual(AnnotationTool.crop.icon, "crop")
        XCTAssertEqual(AnnotationTool.arrow.icon, "arrow.up.right")
        XCTAssertEqual(AnnotationTool.text.icon, "character")
    }

    // MARK: - AnnotationType Tests

    func testCanBeFilled() {
        XCTAssertTrue(AnnotationType.rectangleSolid.canBeFilled)
        XCTAssertFalse(AnnotationType.rectangleOutline.canBeFilled)
        XCTAssertFalse(AnnotationType.circleOutline.canBeFilled)
        XCTAssertFalse(AnnotationType.line.canBeFilled)
        XCTAssertFalse(AnnotationType.arrow.canBeFilled)
        XCTAssertFalse(AnnotationType.text.canBeFilled)
        XCTAssertFalse(AnnotationType.blur.canBeFilled)
        XCTAssertFalse(AnnotationType.pencil.canBeFilled)
        XCTAssertFalse(AnnotationType.highlighter.canBeFilled)
        XCTAssertFalse(AnnotationType.numberedStep.canBeFilled)
    }

    // MARK: - Annotation Tests

    func testAnnotationInitialization() {
        let annotation = Annotation(
            type: .rectangleOutline,
            rect: CGRect(x: 10, y: 20, width: 100, height: 50),
            color: .red,
            strokeWidth: 5
        )

        XCTAssertEqual(annotation.type, .rectangleOutline)
        XCTAssertEqual(annotation.cgRect, CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(annotation.strokeWidth, 5)
    }

    func testAnnotationDefaultValues() {
        let annotation = Annotation(type: .line, rect: .zero)

        XCTAssertEqual(annotation.strokeWidth, 3)
        XCTAssertEqual(annotation.fontSize, 16)
        XCTAssertEqual(annotation.fontName, ".AppleSystemUIFont")
        XCTAssertNil(annotation.text)
        XCTAssertNil(annotation.stepNumber)
        XCTAssertEqual(annotation.blurRadius, 10)
    }

    func testAnnotationWithText() {
        let annotation = Annotation(
            type: .text,
            rect: CGRect(x: 0, y: 0, width: 100, height: 30),
            text: "Hello World",
            fontSize: 24
        )

        XCTAssertEqual(annotation.text, "Hello World")
        XCTAssertEqual(annotation.fontSize, 24)
    }

    func testAnnotationWithPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        let annotation = Annotation(type: .pencil, rect: .zero, points: points)

        XCTAssertEqual(annotation.cgPoints.count, 3)
        XCTAssertEqual(annotation.cgPoints[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(annotation.cgPoints[1], CGPoint(x: 50, y: 50))
        XCTAssertEqual(annotation.cgPoints[2], CGPoint(x: 100, y: 0))
    }

    func testAnnotationEquatable() {
        let id = UUID()
        let annotation1 = Annotation(id: id, type: .arrow, rect: .zero)
        let annotation2 = Annotation(id: id, type: .line, rect: CGRect(x: 10, y: 10, width: 20, height: 20))

        XCTAssertEqual(annotation1, annotation2) // Same ID
    }

    func testAnnotationCodable() throws {
        let original = Annotation(
            type: .arrow,
            rect: CGRect(x: 10, y: 20, width: 50, height: 50),
            color: .blue,
            text: "Test text",
            fontSize: 20
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Annotation.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.text, decoded.text)
        XCTAssertEqual(original.fontSize, decoded.fontSize)
        XCTAssertEqual(original.cgRect, decoded.cgRect)
    }

    // MARK: - CodableRect Tests

    func testCodableRectConversion() {
        let cgRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let codableRect = CodableRect(cgRect)

        XCTAssertEqual(codableRect.x, 10)
        XCTAssertEqual(codableRect.y, 20)
        XCTAssertEqual(codableRect.width, 100)
        XCTAssertEqual(codableRect.height, 50)
        XCTAssertEqual(codableRect.cgRect, cgRect)
    }

    func testCodableRectCodable() throws {
        let original = CodableRect(CGRect(x: 5, y: 10, width: 200, height: 100))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableRect.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - CodablePoint Tests

    func testCodablePointConversion() {
        let cgPoint = CGPoint(x: 42, y: 84)
        let codablePoint = CodablePoint(cgPoint)

        XCTAssertEqual(codablePoint.x, 42)
        XCTAssertEqual(codablePoint.y, 84)
        XCTAssertEqual(codablePoint.cgPoint, cgPoint)
    }

    func testCodablePointCodable() throws {
        let original = CodablePoint(CGPoint(x: 100, y: 200))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodablePoint.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - CodableColor Tests

    func testCodableColorFromSwiftUIColor() {
        // Use an explicitly defined sRGB color to avoid color space conversion issues
        let swiftUIColor = Color(red: 1.0, green: 0.0, blue: 0.0)
        let codableColor = CodableColor(swiftUIColor)

        // Red component should be close to 1
        XCTAssertEqual(codableColor.red, 1.0, accuracy: 0.01)
        // Green and blue should be close to 0
        XCTAssertEqual(codableColor.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(codableColor.blue, 0.0, accuracy: 0.01)
    }

    func testCodableColorComponentInit() {
        let codableColor = CodableColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8)

        XCTAssertEqual(codableColor.red, 0.5)
        XCTAssertEqual(codableColor.green, 0.6)
        XCTAssertEqual(codableColor.blue, 0.7)
        XCTAssertEqual(codableColor.alpha, 0.8)
    }

    func testCodableColorToNSColor() {
        let codableColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let nsColor = codableColor.nsColor

        XCTAssertEqual(nsColor.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(nsColor.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(nsColor.blueComponent, 0, accuracy: 0.01)
    }

    func testCodableColorCodable() throws {
        let original = CodableColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)

        XCTAssertEqual(original.red, decoded.red, accuracy: 0.01)
        XCTAssertEqual(original.green, decoded.green, accuracy: 0.01)
        XCTAssertEqual(original.blue, decoded.blue, accuracy: 0.01)
        XCTAssertEqual(original.alpha, decoded.alpha, accuracy: 0.01)
    }

    // MARK: - AnnotationState Tests

    func testAnnotationStateInitialization() {
        let state = AnnotationState()

        XCTAssertTrue(state.annotations.isEmpty)
        XCTAssertNil(state.selectedAnnotationId)
        XCTAssertEqual(state.currentTool, .select)
        XCTAssertEqual(state.currentStrokeWidth, 3)
        XCTAssertEqual(state.currentFontSize, 16)
        XCTAssertEqual(state.stepCounter, 1)
        XCTAssertEqual(state.blurRadius, 10)
    }

    func testAnnotationStateAddAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)

        state.addAnnotation(annotation)

        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations.first?.id, annotation.id)
    }

    func testAnnotationStateUndo() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)

        state.addAnnotation(annotation)
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertTrue(state.canUndo)

        state.undo()
        XCTAssertEqual(state.annotations.count, 0)
        XCTAssertFalse(state.canUndo)
        XCTAssertTrue(state.canRedo)
    }

    func testAnnotationStateRedo() {
        let state = AnnotationState()
        let annotation = Annotation(type: .text, rect: .zero, text: "Hello")

        state.addAnnotation(annotation)
        state.undo()
        state.redo()

        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations.first?.text, "Hello")
    }

    func testAnnotationStateUpdateAnnotation() {
        let state = AnnotationState()
        var annotation = Annotation(type: .rectangleOutline, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.addAnnotation(annotation)

        annotation.cgRect = CGRect(x: 10, y: 10, width: 100, height: 100)
        state.updateAnnotation(annotation)

        XCTAssertEqual(state.annotations.first?.cgRect, CGRect(x: 10, y: 10, width: 100, height: 100))
    }

    func testAnnotationStateDeleteSelected() {
        let state = AnnotationState()
        let annotation = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.deleteSelectedAnnotation()

        XCTAssertTrue(state.annotations.isEmpty)
        XCTAssertNil(state.selectedAnnotationId)
    }

    func testAnnotationStateSelectAt() {
        let state = AnnotationState()
        let annotation = Annotation(
            type: .rectangleOutline,
            rect: CGRect(x: 50, y: 50, width: 100, height: 100)
        )
        state.addAnnotation(annotation)

        state.selectAnnotationAt(CGPoint(x: 75, y: 75))
        XCTAssertEqual(state.selectedAnnotationId, annotation.id)

        state.selectAnnotationAt(CGPoint(x: 0, y: 0))
        XCTAssertNil(state.selectedAnnotationId)
    }

    func testAnnotationStateSelectedAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .text, rect: .zero, text: "Test")
        state.addAnnotation(annotation)

        XCTAssertNil(state.selectedAnnotation)

        state.selectedAnnotationId = annotation.id
        XCTAssertEqual(state.selectedAnnotation?.id, annotation.id)
    }

    func testAnnotationStateUndoStackLimit() {
        let state = AnnotationState()

        // Add more than 50 annotations to test stack limit
        for i in 1...60 {
            state.addAnnotation(Annotation(type: .line, rect: CGRect(x: CGFloat(i), y: 0, width: 10, height: 10)))
        }

        // Should still be able to undo (stack limited to 50)
        XCTAssertTrue(state.canUndo)
    }

    // MARK: - AnnotationDocument Tests

    func testAnnotationDocumentInitialization() {
        let annotations = [Annotation(type: .arrow, rect: .zero)]
        let doc = AnnotationDocument(annotations: annotations, imageHash: "abc123")

        XCTAssertEqual(doc.version, AnnotationDocument.currentVersion)
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.imageHash, "abc123")
    }

    func testAnnotationDocumentSidecarURL() {
        let imageURL = URL(fileURLWithPath: "/path/to/image.png")
        let sidecarURL = AnnotationDocument.sidecarURL(for: imageURL)

        XCTAssertEqual(sidecarURL.pathExtension, AnnotationDocument.fileExtension)
        XCTAssertTrue(sidecarURL.path.contains("image"))
    }

    func testAnnotationDocumentSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_doc.\(AnnotationDocument.fileExtension)")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        let originalDoc = AnnotationDocument(
            annotations: [Annotation(type: .text, rect: .zero, text: "Test")],
            imageHash: "testhash"
        )

        try originalDoc.save(to: testURL)
        let loadedDoc = try AnnotationDocument.load(from: testURL)

        XCTAssertEqual(loadedDoc.version, originalDoc.version)
        XCTAssertEqual(loadedDoc.imageHash, originalDoc.imageHash)
        XCTAssertEqual(loadedDoc.annotations.count, 1)
    }

    // MARK: - FontOption Tests

    func testFontOptionSystemFonts() {
        XCTAssertGreaterThan(FontOption.systemFonts.count, 0)

        let systemFont = FontOption.systemFonts.first { $0.displayName == "System" }
        XCTAssertNotNil(systemFont)
        XCTAssertEqual(systemFont?.name, ".AppleSystemUIFont")
    }

    // MARK: - Color Extension Tests

    func testAnnotationColorsCount() {
        XCTAssertEqual(Color.annotationColors.count, 10)
    }
}
