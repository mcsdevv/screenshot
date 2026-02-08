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

    // MARK: - New Annotation Properties Tests

    func testAnnotationCreationOrder() {
        let annotation = Annotation(type: .line, rect: .zero, creationOrder: 5)
        XCTAssertEqual(annotation.creationOrder, 5)
    }

    func testAnnotationCreationOrderDefault() {
        let annotation = Annotation(type: .line, rect: .zero)
        XCTAssertEqual(annotation.creationOrder, 0)
    }

    func testAnnotationIsNumberLocked() {
        let annotation = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1, isNumberLocked: true)
        XCTAssertTrue(annotation.isNumberLocked)
    }

    func testAnnotationIsNumberLockedDefault() {
        let annotation = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1)
        XCTAssertFalse(annotation.isNumberLocked)
    }

    // MARK: - Layer Panel State Tests

    func testLayerPanelInitiallyHidden() {
        let state = AnnotationState()
        XCTAssertFalse(state.isLayerPanelVisible)
        XCTAssertFalse(state.isLayerPanelManuallyHidden)
    }

    func testToggleLayerPanelVisibility() {
        let state = AnnotationState()

        state.toggleLayerPanelVisibility()
        XCTAssertTrue(state.isLayerPanelVisible)
        XCTAssertFalse(state.isLayerPanelManuallyHidden)

        state.toggleLayerPanelVisibility()
        XCTAssertFalse(state.isLayerPanelVisible)
        XCTAssertTrue(state.isLayerPanelManuallyHidden)
    }

    func testHiddenAnnotationIds() {
        let state = AnnotationState()
        XCTAssertTrue(state.hiddenAnnotationIds.isEmpty)
    }

    func testClipboardInitiallyNil() {
        let state = AnnotationState()
        XCTAssertNil(state.clipboard)
    }

    // MARK: - Annotation Visibility Tests

    func testToggleAnnotationVisibility() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        XCTAssertTrue(state.isAnnotationVisible(annotation.id))

        state.toggleAnnotationVisibility(id: annotation.id)
        XCTAssertFalse(state.isAnnotationVisible(annotation.id))

        state.toggleAnnotationVisibility(id: annotation.id)
        XCTAssertTrue(state.isAnnotationVisible(annotation.id))
    }

    func testMultipleAnnotationsVisibility() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        state.toggleAnnotationVisibility(id: annotation1.id)

        XCTAssertFalse(state.isAnnotationVisible(annotation1.id))
        XCTAssertTrue(state.isAnnotationVisible(annotation2.id))
    }

    // MARK: - Layer Ordering Tests

    func testMoveAnnotation() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        let annotation3 = Annotation(type: .text, rect: .zero, text: "Test")
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)
        state.addAnnotation(annotation3)

        // Move annotation1 to the end
        state.moveAnnotation(id: annotation1.id, toIndex: 2)

        XCTAssertEqual(state.annotations[0].id, annotation2.id)
        XCTAssertEqual(state.annotations[1].id, annotation3.id)
        XCTAssertEqual(state.annotations[2].id, annotation1.id)
    }

    func testMoveAnnotationInvalidIndex() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        // Attempt to move to invalid index
        state.moveAnnotation(id: annotation.id, toIndex: 10)

        // Should remain unchanged
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations[0].id, annotation.id)
    }

    func testBringForward() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        state.bringForward(id: annotation1.id)

        XCTAssertEqual(state.annotations[0].id, annotation2.id)
        XCTAssertEqual(state.annotations[1].id, annotation1.id)
    }

    func testBringForwardAtFront() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        // annotation2 is already at front
        state.bringForward(id: annotation2.id)

        // Should remain unchanged
        XCTAssertEqual(state.annotations[0].id, annotation1.id)
        XCTAssertEqual(state.annotations[1].id, annotation2.id)
    }

    func testSendBackward() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        state.sendBackward(id: annotation2.id)

        XCTAssertEqual(state.annotations[0].id, annotation2.id)
        XCTAssertEqual(state.annotations[1].id, annotation1.id)
    }

    func testSendBackwardAtBack() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        // annotation1 is already at back
        state.sendBackward(id: annotation1.id)

        // Should remain unchanged
        XCTAssertEqual(state.annotations[0].id, annotation1.id)
        XCTAssertEqual(state.annotations[1].id, annotation2.id)
    }

    func testBringToFront() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        let annotation3 = Annotation(type: .text, rect: .zero, text: "Test")
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)
        state.addAnnotation(annotation3)

        state.bringToFront(id: annotation1.id)

        XCTAssertEqual(state.annotations[0].id, annotation2.id)
        XCTAssertEqual(state.annotations[1].id, annotation3.id)
        XCTAssertEqual(state.annotations[2].id, annotation1.id)
    }

    func testSendToBack() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        let annotation3 = Annotation(type: .text, rect: .zero, text: "Test")
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)
        state.addAnnotation(annotation3)

        state.sendToBack(id: annotation3.id)

        XCTAssertEqual(state.annotations[0].id, annotation3.id)
        XCTAssertEqual(state.annotations[1].id, annotation1.id)
        XCTAssertEqual(state.annotations[2].id, annotation2.id)
    }

    // MARK: - Copy/Paste/Duplicate Tests

    func testCopySelectedAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .arrow, rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: .blue)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.copySelectedAnnotation()

        XCTAssertNotNil(state.clipboard)
        XCTAssertEqual(state.clipboard?.type, .arrow)
    }

    func testCopyWithNoSelection() {
        let state = AnnotationState()
        let annotation = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation)

        state.copySelectedAnnotation()

        XCTAssertNil(state.clipboard)
    }

    func testPasteAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .arrow, rect: CGRect(x: 10, y: 10, width: 50, height: 50))
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id
        state.copySelectedAnnotation()

        let pastedId = state.pasteAnnotation()

        XCTAssertNotNil(pastedId)
        XCTAssertEqual(state.annotations.count, 2)
        XCTAssertEqual(state.selectedAnnotationId, pastedId) // Paste selects new annotation

        let pasted = state.annotations.last!
        XCTAssertEqual(pasted.cgRect.origin.x, 20) // Offset by 10
        XCTAssertEqual(pasted.cgRect.origin.y, 20)
    }

    func testPasteWithCustomOffset() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id
        state.copySelectedAnnotation()

        _ = state.pasteAnnotation(offset: CGPoint(x: 20, y: 30))

        let pasted = state.annotations.last!
        XCTAssertEqual(pasted.cgRect.origin.x, 20)
        XCTAssertEqual(pasted.cgRect.origin.y, 30)
    }

    func testPasteWithEmptyClipboard() {
        let state = AnnotationState()

        let pastedId = state.pasteAnnotation()

        XCTAssertNil(pastedId)
        XCTAssertTrue(state.annotations.isEmpty)
    }

    func testDuplicateAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .rectangleOutline, rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: .green)
        state.addAnnotation(annotation)

        let duplicateId = state.duplicateAnnotation(id: annotation.id)

        XCTAssertNotNil(duplicateId)
        XCTAssertEqual(state.annotations.count, 2)

        let duplicate = state.annotations.last!
        XCTAssertEqual(duplicate.type, .rectangleOutline)
        XCTAssertEqual(duplicate.cgRect.origin.x, 20)
        XCTAssertEqual(duplicate.cgRect.origin.y, 20)
        XCTAssertNotEqual(duplicate.id, annotation.id)
    }

    func testDuplicateAnnotationWithCustomOffset() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.addAnnotation(annotation)

        _ = state.duplicateAnnotation(id: annotation.id, offset: CGPoint(x: 25, y: 25))

        let duplicate = state.annotations.last!
        XCTAssertEqual(duplicate.cgRect.origin.x, 25)
        XCTAssertEqual(duplicate.cgRect.origin.y, 25)
    }

    func testDuplicateInvalidId() {
        let state = AnnotationState()

        let duplicateId = state.duplicateAnnotation(id: UUID())

        XCTAssertNil(duplicateId)
        XCTAssertTrue(state.annotations.isEmpty)
    }

    func testDuplicateNumberedStep() {
        let state = AnnotationState()
        state.stepCounter = 5
        let annotation = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1)
        state.addAnnotation(annotation)

        _ = state.duplicateAnnotation(id: annotation.id)

        XCTAssertEqual(state.annotations.count, 2)
        XCTAssertEqual(state.annotations.last?.stepNumber, 5) // Uses current stepCounter
        XCTAssertEqual(state.stepCounter, 6) // Incremented
    }

    // MARK: - Nudge Tests

    func testNudgeSelectedAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.nudgeSelectedAnnotation(dx: 5, dy: 10)

        XCTAssertEqual(state.annotations.first?.cgRect.origin.x, 55)
        XCTAssertEqual(state.annotations.first?.cgRect.origin.y, 60)
    }

    func testNudgeSelectedAnnotationNegative() {
        let state = AnnotationState()
        let annotation = Annotation(type: .arrow, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.nudgeSelectedAnnotation(dx: -10, dy: -5)

        XCTAssertEqual(state.annotations.first?.cgRect.origin.x, 40)
        XCTAssertEqual(state.annotations.first?.cgRect.origin.y, 45)
    }

    func testNudgeWithNoSelection() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        state.addAnnotation(annotation)

        state.nudgeSelectedAnnotation(dx: 5, dy: 10)

        // Should remain unchanged
        XCTAssertEqual(state.annotations.first?.cgRect.origin.x, 50)
        XCTAssertEqual(state.annotations.first?.cgRect.origin.y, 50)
    }

    func testNudgePencilAnnotationWithPoints() {
        let state = AnnotationState()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)]
        let annotation = Annotation(type: .pencil, rect: CGRect(x: 0, y: 0, width: 50, height: 50), points: points)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.nudgeSelectedAnnotation(dx: 10, dy: 20)

        let updatedAnnotation = state.annotations.first!
        XCTAssertEqual(updatedAnnotation.cgPoints[0].x, 10)
        XCTAssertEqual(updatedAnnotation.cgPoints[0].y, 20)
        XCTAssertEqual(updatedAnnotation.cgPoints[1].x, 60)
        XCTAssertEqual(updatedAnnotation.cgPoints[1].y, 70)
    }

    // MARK: - Property Update Tests

    func testUpdateSelectedAnnotationColor() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, color: .red)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationColor(.blue)

        let nsColor = NSColor(state.annotations.first!.swiftUIColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(nsColor.blueComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(nsColor.redComponent, 0.0, accuracy: 0.01)
    }

    func testUpdateColorWithNoSelection() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, color: .red)
        state.addAnnotation(annotation)

        state.updateSelectedAnnotationColor(.blue)

        // Should remain unchanged (red)
        let nsColor = NSColor(state.annotations.first!.swiftUIColor).usingColorSpace(.sRGB)!
        XCTAssertEqual(nsColor.redComponent, 1.0, accuracy: 0.01)
    }

    func testUpdateSelectedAnnotationStrokeWidth() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, strokeWidth: 3)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationStrokeWidth(8)

        XCTAssertEqual(state.annotations.first?.strokeWidth, 8)
    }

    func testUpdateSelectedAnnotationFontSize() {
        let state = AnnotationState()
        let annotation = Annotation(type: .text, rect: .zero, text: "Hello", fontSize: 16)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationFontSize(24)

        XCTAssertEqual(state.annotations.first?.fontSize, 24)
    }

    func testUpdateFontSizeOnNonTextAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, fontSize: 16)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationFontSize(24)

        // Should remain unchanged for non-text annotations
        XCTAssertEqual(state.annotations.first?.fontSize, 16)
    }

    func testUpdateSelectedAnnotationFontName() {
        let state = AnnotationState()
        let annotation = Annotation(type: .text, rect: .zero, text: "Hello", fontName: ".AppleSystemUIFont")
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationFontName("Helvetica Neue")

        XCTAssertEqual(state.annotations.first?.fontName, "Helvetica Neue")
    }

    // MARK: - Numbered Step Renumbering Tests

    func testRenumberSteps() {
        let state = AnnotationState()
        let step1 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 5)
        let step2 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 10)
        let step3 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 15)
        state.addAnnotation(step1)
        state.addAnnotation(step2)
        state.addAnnotation(step3)

        state.renumberSteps(force: false)

        XCTAssertEqual(state.annotations[0].stepNumber, 1)
        XCTAssertEqual(state.annotations[1].stepNumber, 2)
        XCTAssertEqual(state.annotations[2].stepNumber, 3)
        XCTAssertEqual(state.stepCounter, 4)
    }

    func testRenumberStepsPreservesLocked() {
        let state = AnnotationState()
        let step1 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 99, isNumberLocked: true)
        let step2 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 10)
        state.addAnnotation(step1)
        state.addAnnotation(step2)

        state.renumberSteps(force: false)

        XCTAssertEqual(state.annotations[0].stepNumber, 99) // Preserved
        XCTAssertEqual(state.annotations[1].stepNumber, 2) // Renumbered
    }

    func testRenumberStepsForceIgnoresLocks() {
        let state = AnnotationState()
        let step1 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 99, isNumberLocked: true)
        let step2 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 10, isNumberLocked: true)
        state.addAnnotation(step1)
        state.addAnnotation(step2)

        state.renumberSteps(force: true)

        XCTAssertEqual(state.annotations[0].stepNumber, 1)
        XCTAssertEqual(state.annotations[1].stepNumber, 2)
    }

    func testRenumberSkipsNonSteps() {
        let state = AnnotationState()
        let line = Annotation(type: .line, rect: .zero)
        let step = Annotation(type: .numberedStep, rect: .zero, stepNumber: 5)
        let arrow = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(line)
        state.addAnnotation(step)
        state.addAnnotation(arrow)

        state.renumberSteps(force: false)

        XCTAssertEqual(state.annotations[1].stepNumber, 1)
        XCTAssertNil(state.annotations[0].stepNumber) // Line unchanged
        XCTAssertNil(state.annotations[2].stepNumber) // Arrow unchanged
    }

    func testToggleStepNumberLock() {
        let state = AnnotationState()
        let step = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1, isNumberLocked: false)
        state.addAnnotation(step)

        state.toggleStepNumberLock(id: step.id)
        XCTAssertTrue(state.annotations.first!.isNumberLocked)

        state.toggleStepNumberLock(id: step.id)
        XCTAssertFalse(state.annotations.first!.isNumberLocked)
    }

    func testToggleLockOnNonStep() {
        let state = AnnotationState()
        let line = Annotation(type: .line, rect: .zero)
        state.addAnnotation(line)

        state.toggleStepNumberLock(id: line.id)

        // Should have no effect
        XCTAssertFalse(state.annotations.first!.isNumberLocked)
    }

    func testSetStepNumber() {
        let state = AnnotationState()
        let step = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1)
        state.addAnnotation(step)

        state.setStepNumber(id: step.id, number: 42)

        XCTAssertEqual(state.annotations.first?.stepNumber, 42)
        XCTAssertTrue(state.annotations.first!.isNumberLocked) // Auto-locks on manual set
    }

    // MARK: - Deselection Tests

    func testDeselectAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.deselectAnnotation()

        XCTAssertNil(state.selectedAnnotationId)
    }

    // MARK: - Add Annotation With Order Tests

    func testAddAnnotationWithOrder() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)

        state.addAnnotationWithOrder(annotation1)
        state.addAnnotationWithOrder(annotation2)

        XCTAssertEqual(state.annotations[0].creationOrder, 1)
        XCTAssertEqual(state.annotations[1].creationOrder, 2)
    }

    // MARK: - Undo/Redo for New Operations Tests

    func testMoveAnnotationUndo() {
        let state = AnnotationState()
        let annotation1 = Annotation(type: .line, rect: .zero)
        let annotation2 = Annotation(type: .arrow, rect: .zero)
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2)

        state.moveAnnotation(id: annotation1.id, toIndex: 1)
        XCTAssertEqual(state.annotations[1].id, annotation1.id)

        state.undo()
        XCTAssertEqual(state.annotations[0].id, annotation1.id)
    }

    func testNudgeUndo() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.nudgeSelectedAnnotation(dx: 10, dy: 10)
        XCTAssertEqual(state.annotations.first?.cgRect.origin.x, 60)

        state.undo()
        XCTAssertEqual(state.annotations.first?.cgRect.origin.x, 50)
    }

    func testPropertyUpdateUndo() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, strokeWidth: 3)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationStrokeWidth(10)
        XCTAssertEqual(state.annotations.first?.strokeWidth, 10)

        state.undo()
        XCTAssertEqual(state.annotations.first?.strokeWidth, 3)
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

    // MARK: - Additional AnnotationState Tests

    func testUpdateAnnotationColorById() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, color: .red)
        state.addAnnotation(annotation)

        state.updateAnnotationColor(id: annotation.id, color: .green)

        XCTAssertEqual(state.annotations.first?.color, CodableColor(.green))
    }

    func testUpdateAnnotationColorByInvalidId() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, color: .red)
        state.addAnnotation(annotation)

        state.updateAnnotationColor(id: UUID(), color: .green)

        // Should remain unchanged
        XCTAssertEqual(state.annotations.first?.color, CodableColor(.red))
    }

    func testUpdateAnnotationName() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        state.updateAnnotationName(id: annotation.id, name: "My Line")

        XCTAssertEqual(state.annotations.first?.name, "My Line")
    }

    func testUpdateAnnotationNameWithEmptyString() {
        let state = AnnotationState()
        var annotation = Annotation(type: .line, rect: .zero)
        annotation.name = "Initial Name"
        state.addAnnotation(annotation)

        state.updateAnnotationName(id: annotation.id, name: "")

        XCTAssertNil(state.annotations.first?.name) // Empty string should become nil
    }

    func testUpdateAnnotationNameToNil() {
        let state = AnnotationState()
        var annotation = Annotation(type: .line, rect: .zero)
        annotation.name = "Initial Name"
        state.addAnnotation(annotation)

        state.updateAnnotationName(id: annotation.id, name: nil)

        XCTAssertNil(state.annotations.first?.name)
    }

    func testDeleteAnnotationWithRenumberSteps() {
        let state = AnnotationState()
        let step1 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1)
        let step2 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 2)
        let step3 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 3)
        state.addAnnotation(step1)
        state.addAnnotation(step2)
        state.addAnnotation(step3)

        state.deleteAnnotation(id: step2.id, renumberSteps: true)

        XCTAssertEqual(state.annotations.count, 2)
        XCTAssertEqual(state.annotations[0].stepNumber, 1)
        XCTAssertEqual(state.annotations[1].stepNumber, 2) // Renumbered from 3
    }

    func testDeleteAnnotationWithoutRenumberSteps() {
        let state = AnnotationState()
        let step1 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 1)
        let step2 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 2)
        let step3 = Annotation(type: .numberedStep, rect: .zero, stepNumber: 3)
        state.addAnnotation(step1)
        state.addAnnotation(step2)
        state.addAnnotation(step3)

        state.deleteAnnotation(id: step2.id, renumberSteps: false)

        XCTAssertEqual(state.annotations.count, 2)
        XCTAssertEqual(state.annotations[0].stepNumber, 1)
        XCTAssertEqual(state.annotations[1].stepNumber, 3) // Unchanged
    }

    func testDeleteAnnotationClearsHiddenId() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)
        state.toggleAnnotationVisibility(id: annotation.id)

        XCTAssertTrue(state.hiddenAnnotationIds.contains(annotation.id))

        state.deleteAnnotation(id: annotation.id)

        XCTAssertFalse(state.hiddenAnnotationIds.contains(annotation.id))
    }

    func testDeleteNonExistentAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        state.deleteAnnotation(id: UUID())

        XCTAssertEqual(state.annotations.count, 1)
    }

    func testSelectAnnotationAtReversesOrder() {
        let state = AnnotationState()
        // Both annotations overlap at (75, 75)
        let annotation1 = Annotation(type: .rectangleOutline, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        let annotation2 = Annotation(type: .rectangleOutline, rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        state.addAnnotation(annotation1)
        state.addAnnotation(annotation2) // Added second, so it's "on top"

        state.selectAnnotationAt(CGPoint(x: 75, y: 75))

        // Should select the one on top (added last = annotation2)
        XCTAssertEqual(state.selectedAnnotationId, annotation2.id)
    }

    func testUpdateAnnotationNonExistentId() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        var nonExistent = Annotation(type: .arrow, rect: CGRect(x: 100, y: 100, width: 50, height: 50))
        nonExistent.cgRect = CGRect(x: 200, y: 200, width: 100, height: 100)
        state.updateAnnotation(nonExistent)

        // Original should be unchanged
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations.first?.type, .line)
    }

    func testSelectedAnnotationWithStaleIndex() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        // Access should work via fallback
        XCTAssertNotNil(state.selectedAnnotation)
        XCTAssertEqual(state.selectedAnnotation?.id, annotation.id)
    }

    func testAnnotationDocumentVersion() {
        XCTAssertEqual(AnnotationDocument.currentVersion, 1)
    }

    func testAnnotationDocumentFileExtension() {
        XCTAssertEqual(AnnotationDocument.fileExtension, "screencapture-annotations")
    }

    func testCropStateDefaults() {
        let state = AnnotationState()
        XCTAssertNil(state.cropRect)
        XCTAssertFalse(state.isCropping)
        XCTAssertEqual(state.originalImageSize, .zero)
    }

    func testAnnotationWithName() {
        let annotation = Annotation(type: .line, rect: .zero, name: "My Annotation")
        XCTAssertEqual(annotation.name, "My Annotation")
    }

    func testAnnotationNameDefault() {
        let annotation = Annotation(type: .line, rect: .zero)
        XCTAssertNil(annotation.name)
    }

    func testCanBeFilleddCircleSolid() {
        // Test that only rectangleSolid has canBeFilled true
        XCTAssertFalse(AnnotationType.circleOutline.canBeFilled)
    }

    func testDuplicatePencilAnnotationWithPoints() {
        let state = AnnotationState()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        let annotation = Annotation(type: .pencil, rect: CGRect(x: 0, y: 0, width: 100, height: 50), points: points)
        state.addAnnotation(annotation)

        let duplicateId = state.duplicateAnnotation(id: annotation.id)

        XCTAssertNotNil(duplicateId)
        let duplicate = state.annotations.last!
        XCTAssertEqual(duplicate.cgPoints.count, 3)
        XCTAssertEqual(duplicate.cgPoints[0].x, 10) // Offset
        XCTAssertEqual(duplicate.cgPoints[0].y, 10)
    }

    func testPasteNumberedStep() {
        let state = AnnotationState()
        state.stepCounter = 3
        let annotation = Annotation(type: .numberedStep, rect: CGRect(x: 0, y: 0, width: 50, height: 50), stepNumber: 1)
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id
        state.copySelectedAnnotation()

        let pastedId = state.pasteAnnotation()

        XCTAssertNotNil(pastedId)
        let pasted = state.annotations.last!
        XCTAssertEqual(pasted.stepNumber, 3) // Uses current stepCounter
        XCTAssertEqual(state.stepCounter, 4) // Incremented
    }

    func testAddAnnotationSetsCreationOrder() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)

        state.addAnnotation(annotation)

        XCTAssertEqual(state.annotations.first?.creationOrder, 1)
    }

    func testAddAnnotationPreservesExistingCreationOrder() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, creationOrder: 10)

        state.addAnnotation(annotation)

        XCTAssertEqual(state.annotations.first?.creationOrder, 10)
    }

    func testUpdateStrokeWidthWithNoSelection() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, strokeWidth: 3)
        state.addAnnotation(annotation)
        // No selection

        state.updateSelectedAnnotationStrokeWidth(10)

        // Should remain unchanged
        XCTAssertEqual(state.annotations.first?.strokeWidth, 3)
    }

    func testUpdateFontNameOnNonTextAnnotation() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero, fontName: ".AppleSystemUIFont")
        state.addAnnotation(annotation)
        state.selectedAnnotationId = annotation.id

        state.updateSelectedAnnotationFontName("Helvetica")

        // Should remain unchanged for non-text annotations
        XCTAssertEqual(state.annotations.first?.fontName, ".AppleSystemUIFont")
    }

    func testSetStepNumberOnNonStep() {
        let state = AnnotationState()
        let annotation = Annotation(type: .line, rect: .zero)
        state.addAnnotation(annotation)

        state.setStepNumber(id: annotation.id, number: 42)

        // Should have no effect
        XCTAssertNil(state.annotations.first?.stepNumber)
    }

    // MARK: - Hit Testing and Cursor Policy Tests

    func testLineHitTestUsesDirectionalEndpointsForNegativeDimensions() {
        let line = Annotation(
            type: .line,
            rect: CGRect(x: 100, y: 100, width: -80, height: 60),
            strokeWidth: 3
        )

        XCTAssertTrue(
            line.hitTest(
                at: CGPoint(x: 80, y: 115),
                zoom: 1.0,
                intent: .hover
            )
        )
        XCTAssertFalse(
            line.hitTest(
                at: CGPoint(x: 80, y: 145),
                zoom: 1.0,
                intent: .hover
            )
        )
    }

    func testLineHoverHitToleranceScalesWithZoom() {
        let line = Annotation(
            type: .line,
            rect: CGRect(x: 10, y: 10, width: 100, height: 0),
            strokeWidth: 2
        )
        let testPoint = CGPoint(x: 60, y: 15)

        XCTAssertTrue(line.hitTest(at: testPoint, zoom: 1.0, intent: .hover))
        XCTAssertFalse(line.hitTest(at: testPoint, zoom: 4.0, intent: .hover))
    }

    func testArrowHitTestIncludesArrowheadEdges() {
        let arrow = Annotation(
            type: .arrow,
            rect: CGRect(x: 0, y: 0, width: 100, height: 0),
            strokeWidth: 3
        )

        XCTAssertTrue(
            arrow.hitTest(
                at: CGPoint(x: 92, y: 4.5),
                zoom: 1.0,
                intent: .hover
            )
        )
    }

    func testCursorPolicyLineAndArrowRequireSelection() {
        let line = Annotation(type: .line, rect: CGRect(x: 0, y: 0, width: 100, height: 0))
        let arrow = Annotation(type: .arrow, rect: CGRect(x: 0, y: 0, width: 100, height: 0))

        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(for: line, selectedAnnotationId: nil, selectedAnnotationType: nil),
            .none
        )
        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(for: line, selectedAnnotationId: line.id, selectedAnnotationType: .line),
            .pointingHand
        )
        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(for: arrow, selectedAnnotationId: line.id, selectedAnnotationType: .line),
            .none
        )
        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(for: arrow, selectedAnnotationId: arrow.id, selectedAnnotationType: .arrow),
            .pointingHand
        )
    }

    func testCursorPolicyUsesOpenHandForText() {
        let text = Annotation(type: .text, rect: CGRect(x: 0, y: 0, width: 80, height: 30), text: "Test")
        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(for: text, selectedAnnotationId: nil, selectedAnnotationType: nil),
            .openHand
        )
    }

    func testCursorPolicySuppressesOtherLayersWhenLineIsSelected() {
        let line = Annotation(type: .line, rect: CGRect(x: 0, y: 0, width: 100, height: 0))
        let rectangle = Annotation(type: .rectangleOutline, rect: CGRect(x: 0, y: 0, width: 60, height: 40))

        XCTAssertEqual(
            AnnotationCursorPolicy.cursorKind(
                for: rectangle,
                selectedAnnotationId: line.id,
                selectedAnnotationType: .line
            ),
            .none
        )
    }
}
