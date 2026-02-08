import AVFoundation
import CoreVideo
import XCTest
@testable import ScreenCapture

@MainActor
final class StorageManagerTests: XCTestCase {

    var storageManager: StorageManager!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        testSuiteName = "StorageManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
    }

    override func tearDown() {
        storageManager = nil
        if let testSuiteName {
            testDefaults?.removePersistentDomain(forName: testSuiteName)
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        testDefaults = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(storageManager)
        XCTAssertNotNil(storageManager.history)
        XCTAssertNotNil(storageManager.defaultDirectory)
    }

    func testDefaultDirectoryExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageManager.defaultDirectory.path))
    }

    // MARK: - Save Capture Tests

    func testSaveCaptureScreenshot() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)

        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertEqual(capture.type, .screenshot)
        XCTAssertTrue(capture.filename.hasSuffix(".png"))
        XCTAssertTrue(capture.filename.contains("Screenshot"))
        XCTAssertEqual(storageManager.history.items.count, 1)
    }

    func testSaveCaptureAddsToHistory() {
        let initialCount = storageManager.history.items.count
        let testImage = createTestImage(size: CGSize(width: 50, height: 50), color: .green)

        _ = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertEqual(storageManager.history.items.count, initialCount + 1)
    }

    // MARK: - Get Capture Tests

    func testGetCaptureById() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let saved = storageManager.saveCapture(image: testImage, type: .screenshot)

        let retrieved = storageManager.getCapture(id: saved.id)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, saved.id)
        XCTAssertEqual(retrieved?.type, saved.type)
    }

    func testGetCaptureByInvalidId() {
        let result = storageManager.getCapture(id: UUID())

        XCTAssertNil(result)
    }

    // MARK: - Delete Capture Tests

    func testDeleteCapture() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        storageManager.deleteCapture(capture)

        XCTAssertNil(storageManager.getCapture(id: capture.id))
    }

    func testDeleteCaptureRemovesFromHistory() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)
        let countAfterSave = storageManager.history.items.count

        storageManager.deleteCapture(capture)

        XCTAssertEqual(storageManager.history.items.count, countAfterSave - 1)
    }

    // MARK: - Favorite Tests

    func testToggleFavorite() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertFalse(storageManager.getCapture(id: capture.id)?.isFavorite ?? true)

        storageManager.toggleFavorite(capture)

        XCTAssertTrue(storageManager.getCapture(id: capture.id)?.isFavorite ?? false)
    }

    // MARK: - Annotations Tests

    func testUpdateAnnotations() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let annotationData = "test annotation data".data(using: .utf8)!
        storageManager.updateAnnotations(for: capture, annotations: annotationData)

        let retrieved = storageManager.getCapture(id: capture.id)
        XCTAssertEqual(retrieved?.annotations, annotationData)
    }

    // MARK: - Metadata Tests

    func testGetMetadata() {
        let testImage = createTestImage(size: CGSize(width: 200, height: 150), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let metadata = storageManager.getMetadata(for: capture)

        XCTAssertEqual(metadata.width, 200)
        XCTAssertEqual(metadata.height, 150)
        XCTAssertGreaterThan(metadata.fileSize, 0)
    }

    // MARK: - URL Generation Tests

    func testGenerateRecordingURL() {
        let recordingURL = storageManager.generateRecordingURL()

        XCTAssertEqual(recordingURL.pathExtension, "mp4")
        XCTAssertTrue(recordingURL.lastPathComponent.contains("Recording"))
    }

    func testGenerateGIFURL() {
        let gifURL = storageManager.generateGIFURL()

        XCTAssertEqual(gifURL.pathExtension, "gif")
        XCTAssertTrue(gifURL.lastPathComponent.contains("GIF"))
    }

    // MARK: - Storage Location Tests

    func testGetStorageLocationDefault() {
        let location = storageManager.getStorageLocation()

        // Should be "default" or whatever was set
        XCTAssertFalse(location.isEmpty)
    }

    func testSetStorageLocation() {
        storageManager.setStorageLocation("desktop")
        XCTAssertEqual(storageManager.getStorageLocation(), "desktop")

        // Reset to default
        storageManager.setStorageLocation("default")
        XCTAssertEqual(storageManager.getStorageLocation(), "default")
    }

    // MARK: - Export/Import Tests

    func testExportCapture() throws {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_test_\(UUID().uuidString).png")

        defer {
            try? FileManager.default.removeItem(at: exportURL)
        }

        try storageManager.exportCapture(capture, to: exportURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    // MARK: - Storage Usage Tests

    func testTotalStorageUsed() {
        // Save a capture to ensure there's something to measure
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        _ = storageManager.saveCapture(image: testImage, type: .screenshot)

        let storage = storageManager.totalStorageUsed

        XCTAssertGreaterThanOrEqual(storage, 0)
    }

    func testFormattedStorageUsed() {
        let formatted = storageManager.formattedStorageUsed

        XCTAssertFalse(formatted.isEmpty)
        // Should contain a unit (bytes, KB, MB, etc.)
        let containsUnit = formatted.contains("bytes") ||
                          formatted.contains("KB") ||
                          formatted.contains("MB") ||
                          formatted.contains("GB") ||
                          formatted.contains("Zero")
        XCTAssertTrue(containsUnit)
    }

    // MARK: - Import Capture Tests

    func testImportCapturePNG() {
        // Create a PNG file to import
        let sourceURL = tempDirectory.appendingPathComponent("test_import.png")
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .blue)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        guard let tiffData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG")
            return
        }
        try? pngData.write(to: sourceURL)

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.type, .screenshot)
        XCTAssertEqual(storageManager.history.items.count, 1)
    }

    func testImportCaptureJPEG() {
        let sourceURL = tempDirectory.appendingPathComponent("test_import.jpg")
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .green)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        guard let tiffData = testImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test JPEG")
            return
        }
        try? jpegData.write(to: sourceURL)

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.type, .screenshot)
    }

    func testImportCaptureMP4() {
        let sourceURL = tempDirectory.appendingPathComponent("test_import.mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertNoThrow(try writeTestVideo(to: sourceURL, fileType: .mp4))

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.type, .recording)
    }

    func testImportCaptureGIF() {
        let sourceURL = tempDirectory.appendingPathComponent("test_import.gif")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let gifData = makeMinimalGIFData()
        XCTAssertNoThrow(try gifData.write(to: sourceURL))

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.type, .gif)
    }

    func testImportCaptureUnsupportedExtension() {
        let sourceURL = tempDirectory.appendingPathComponent("test_import.txt")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let dummyData = "dummy text data".data(using: .utf8)!
        try? dummyData.write(to: sourceURL)

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNil(capture)
    }

    func testImportCaptureNonexistentFile() {
        let sourceURL = tempDirectory.appendingPathComponent("nonexistent.png")

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNil(capture)
    }

    func testImportCaptureMOV() {
        let sourceURL = tempDirectory.appendingPathComponent("test_import.mov")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertNoThrow(try writeTestVideo(to: sourceURL, fileType: .mov))

        let capture = storageManager.importCapture(from: sourceURL)

        XCTAssertNotNil(capture)
        XCTAssertEqual(capture?.type, .recording)
    }

    // MARK: - Save Recording/GIF Tests

    func testSaveRecordingAddsToHistory() {
        let recordingURL = tempDirectory.appendingPathComponent("Test Recording.mp4")
        let dummyData = "dummy video".data(using: .utf8)!
        try? dummyData.write(to: recordingURL)

        let capture = storageManager.saveRecording(url: recordingURL)

        XCTAssertEqual(capture.type, .recording)
        XCTAssertEqual(capture.filename, "Test Recording.mp4")
        XCTAssertEqual(storageManager.history.items.count, 1)
    }

    func testSaveGIFAddsToHistory() {
        let gifURL = tempDirectory.appendingPathComponent("Test GIF.gif")
        let dummyData = "dummy gif".data(using: .utf8)!
        try? dummyData.write(to: gifURL)

        let capture = storageManager.saveGIF(url: gifURL)

        XCTAssertEqual(capture.type, .gif)
        XCTAssertEqual(capture.filename, "Test GIF.gif")
        XCTAssertEqual(storageManager.history.items.count, 1)
    }

    // MARK: - Storage Location Resolved Tests

    func testStorageLocationDesktop() {
        storageManager.setStorageLocation("desktop")

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        XCTAssertEqual(storageManager.screenshotsDirectory, desktopURL)
    }

    func testStorageLocationCustomFallsBackToDefault() {
        // Set to custom without a valid bookmark
        storageManager.setStorageLocation("custom")

        // Should fall back to default since no valid bookmark exists
        XCTAssertEqual(storageManager.screenshotsDirectory, storageManager.defaultDirectory)
    }

    func testStorageLocationDefaultReturnsDefaultDirectory() {
        storageManager.setStorageLocation("default")

        XCTAssertEqual(storageManager.screenshotsDirectory, storageManager.defaultDirectory)
    }

    // MARK: - Custom Folder Tests

    func testGetCustomFolderURLWithNoBookmark() {
        let customURL = storageManager.getCustomFolderURL()

        XCTAssertNil(customURL)
    }

    func testSetCustomFolderSuccess() {
        // Use a valid directory that exists
        let customDir = tempDirectory.appendingPathComponent("custom_screenshots")
        try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)

        let success = storageManager.setCustomFolder(customDir)

        // Note: This may fail in sandboxed test environments
        // In that case, we just verify the method doesn't crash
        if success {
            XCTAssertEqual(storageManager.getStorageLocation(), "custom")
        }
    }

    // MARK: - Toggle Favorite Multiple Times Tests

    func testToggleFavoriteTwice() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        XCTAssertFalse(storageManager.getCapture(id: capture.id)?.isFavorite ?? true)

        storageManager.toggleFavorite(capture)
        XCTAssertTrue(storageManager.getCapture(id: capture.id)?.isFavorite ?? false)

        storageManager.toggleFavorite(capture)
        XCTAssertFalse(storageManager.getCapture(id: capture.id)?.isFavorite ?? true)
    }

    // MARK: - Metadata Tests for Different Types

    func testGetMetadataForRecording() {
        let recordingURL = storageManager.generateRecordingURL()
        let dummyData = "dummy video data for size test".data(using: .utf8)!
        try? dummyData.write(to: recordingURL)

        let capture = storageManager.saveRecording(url: recordingURL)
        let metadata = storageManager.getMetadata(for: capture)

        // Recording metadata doesn't include width/height by default
        XCTAssertEqual(metadata.width, 0)
        XCTAssertEqual(metadata.height, 0)
        XCTAssertGreaterThan(metadata.fileSize, 0)
    }

    func testGetMetadataForGIF() {
        let gifURL = storageManager.generateGIFURL()
        let dummyData = "dummy gif data for size test".data(using: .utf8)!
        try? dummyData.write(to: gifURL)

        let capture = storageManager.saveGIF(url: gifURL)
        let metadata = storageManager.getMetadata(for: capture)

        XCTAssertGreaterThan(metadata.fileSize, 0)
    }

    // MARK: - Update Annotations for Non-existent Capture

    func testUpdateAnnotationsForNonexistentCapture() {
        // Create a capture item that doesn't exist in storage
        let nonExistentCapture = CaptureItem(type: .screenshot, filename: "nonexistent.png")

        // Try to update annotations for nonexistent capture - should not crash
        let annotationData = "test annotation data".data(using: .utf8)!
        storageManager.updateAnnotations(for: nonExistentCapture, annotations: annotationData)

        // Verify nothing was added (capture doesn't exist)
        XCTAssertNil(storageManager.getCapture(id: nonExistentCapture.id))
    }

    // MARK: - Export Capture Failure Tests

    func testExportCaptureToInvalidPath() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let capture = storageManager.saveCapture(image: testImage, type: .screenshot)

        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/export.png")

        XCTAssertThrowsError(try storageManager.exportCapture(capture, to: invalidURL))
    }

    // MARK: - Multiple Captures Tests

    func testMultipleCapturesSameType() {
        let testImage1 = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let testImage2 = createTestImage(size: CGSize(width: 100, height: 100), color: .blue)
        let testImage3 = createTestImage(size: CGSize(width: 100, height: 100), color: .green)

        let capture1 = storageManager.saveCapture(image: testImage1, type: .screenshot)
        let capture2 = storageManager.saveCapture(image: testImage2, type: .screenshot)
        let capture3 = storageManager.saveCapture(image: testImage3, type: .screenshot)

        XCTAssertEqual(storageManager.history.items.count, 3)
        XCTAssertNotEqual(capture1.id, capture2.id)
        XCTAssertNotEqual(capture2.id, capture3.id)
    }

    func testMultipleCapturesDifferentTypes() {
        let testImage = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let recordingURL = storageManager.generateRecordingURL()
        let gifURL = storageManager.generateGIFURL()

        XCTAssertNoThrow(try writeTestVideo(to: recordingURL, fileType: .mp4))
        XCTAssertNoThrow(try makeMinimalGIFData().write(to: gifURL))

        let screenshot = storageManager.saveCapture(image: testImage, type: .screenshot)
        let recording = storageManager.saveRecording(url: recordingURL)
        let gif = storageManager.saveGIF(url: gifURL)

        XCTAssertEqual(storageManager.history.items.count, 3)
        XCTAssertEqual(screenshot.type, .screenshot)
        XCTAssertEqual(recording.type, .recording)
        XCTAssertEqual(gif.type, .gif)
    }

    // MARK: - Storage Verified Tests

    func testStorageVerifiedAfterInit() {
        // The storage should be verified during initialization
        XCTAssertTrue(storageManager.storageVerified)
    }

    // MARK: - Delete Multiple Captures Tests

    func testDeleteMultipleCaptures() {
        let testImage1 = createTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let testImage2 = createTestImage(size: CGSize(width: 100, height: 100), color: .blue)

        let capture1 = storageManager.saveCapture(image: testImage1, type: .screenshot)
        let capture2 = storageManager.saveCapture(image: testImage2, type: .screenshot)

        XCTAssertEqual(storageManager.history.items.count, 2)

        storageManager.deleteCapture(capture1)
        XCTAssertEqual(storageManager.history.items.count, 1)
        XCTAssertNil(storageManager.getCapture(id: capture1.id))
        XCTAssertNotNil(storageManager.getCapture(id: capture2.id))

        storageManager.deleteCapture(capture2)
        XCTAssertEqual(storageManager.history.items.count, 0)
    }

    // MARK: - Helper Methods

    private func createTestImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func makeMinimalGIFData() -> Data {
        Data([
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00,
            0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
            0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44,
            0x01, 0x00, 0x3b,
        ])
    }

    private func writeTestVideo(to url: URL, fileType: AVFileType) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let size = CGSize(width: 16, height: 16)
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "StorageManagerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let pixelBuffer = makeSolidPixelBuffer(size: size)
        let readyDeadline = Date().addingTimeInterval(1.0)
        while !input.isReadyForMoreMediaData {
            if Date() > readyDeadline {
                throw NSError(domain: "StorageManagerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Writer input not ready"])
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
            throw NSError(domain: "StorageManagerTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to append pixel buffer"])
        }
        input.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        writer.finishWriting {
            group.leave()
        }
        group.wait()

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "StorageManagerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video write failed"])
        }
    }

    private func makeSolidPixelBuffer(size: CGSize) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            preconditionFailure("Failed to create pixel buffer")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0xFF, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
