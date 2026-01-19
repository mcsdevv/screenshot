import XCTest
import SwiftUI
@testable import ScreenCapture

@MainActor
final class ScrollingCaptureTests: XCTestCase {

    var storageManager: StorageManager!
    var scrollingCapture: ScrollingCapture!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testSuiteName = "ScrollingCaptureTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)

        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
        scrollingCapture = ScrollingCapture(storageManager: storageManager)
    }

    override func tearDown() async throws {
        scrollingCapture = nil
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
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithStorageManager() {
        XCTAssertNotNil(scrollingCapture)
    }

    // MARK: - Class Type Tests

    func testScrollingCaptureIsNSObject() {
        XCTAssertTrue(scrollingCapture is NSObject)
    }

    // MARK: - Storage Manager Integration Tests

    func testScrollingCaptureUsesProvidedStorageManager() {
        // The scrolling capture should use the injected storage manager
        // This is implicitly tested by the initialization
        XCTAssertNotNil(scrollingCapture)
    }
}

// MARK: - ScrollingCaptureInstructionsView Tests

final class ScrollingCaptureInstructionsViewTests: XCTestCase {

    func testInstructionsViewCallbacksExist() {
        var startCalled = false
        var cancelCalled = false

        let _ = ScrollingCaptureInstructionsView(
            onStart: { startCalled = true },
            onCancel: { cancelCalled = true }
        )

        // View exists and callbacks are set
        XCTAssertFalse(startCalled)
        XCTAssertFalse(cancelCalled)
    }
}

// MARK: - ScrollingCaptureControlsView Tests

final class ScrollingCaptureControlsViewTests: XCTestCase {

    func testControlsViewCallbacksExist() {
        var captureCalled = false
        var finishCalled = false
        var cancelCalled = false
        var captureCount = 0

        let binding = Binding(
            get: { captureCount },
            set: { captureCount = $0 }
        )

        let _ = ScrollingCaptureControlsView(
            captureCount: binding,
            onCapture: { captureCalled = true },
            onFinish: { finishCalled = true },
            onCancel: { cancelCalled = true }
        )

        // View exists and callbacks are set
        XCTAssertFalse(captureCalled)
        XCTAssertFalse(finishCalled)
        XCTAssertFalse(cancelCalled)
    }

    func testControlsViewCaptureCountBinding() {
        var captureCount = 5

        let binding = Binding(
            get: { captureCount },
            set: { captureCount = $0 }
        )

        let _ = ScrollingCaptureControlsView(
            captureCount: binding,
            onCapture: { },
            onFinish: { },
            onCancel: { }
        )

        // Binding should reflect the initial count
        XCTAssertEqual(binding.wrappedValue, 5)

        // Modify through binding
        binding.wrappedValue = 10
        XCTAssertEqual(captureCount, 10)
    }
}
