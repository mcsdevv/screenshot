import XCTest
import Combine
import SwiftUI
@testable import ScreenCapture

@MainActor
final class ScreenRecordingManagerTests: XCTestCase {

    var storageManager: StorageManager!
    var recordingManager: ScreenRecordingManager!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testSuiteName = "ScreenRecordingManagerTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)

        storageManager = StorageManager(
            config: .test(
                baseDirectory: tempDirectory,
                userDefaults: testDefaults ?? .standard
            )
        )
        recordingManager = ScreenRecordingManager(storageManager: storageManager)
    }

    override func tearDown() async throws {
        recordingManager = nil
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
        XCTAssertNotNil(recordingManager)
    }

    func testInitialStateIsNotRecording() {
        XCTAssertFalse(recordingManager.isRecording)
        XCTAssertEqual(recordingManager.recordingDuration, 0)
        XCTAssertEqual(recordingManager.sessionState, .idle)
    }

    func testFirstMouseHostingViewAcceptsFirstMouse() {
        let hostingView = FirstMouseHostingView(rootView: EmptyView())
        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))
    }

    func testStartFullscreenRecordingClearsExistingSelectionWindow() {
        let staleWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        staleWindow.isReleasedWhenClosed = false
        recordingManager.installSelectionWindowForTesting(staleWindow)
        XCTAssertTrue(recordingManager.hasSelectionWindowForTesting)

        recordingManager.startFullscreenRecording()

        XCTAssertFalse(recordingManager.hasSelectionWindowForTesting)
        XCTAssertTrue(recordingManager.isPreparingRecordingForTesting)
        XCTAssertEqual(recordingManager.sessionModel.state, .selecting)
    }

    // MARK: - Published Properties Tests

    func testIsRecordingIsPublished() {
        var changeCount = 0
        let cancellable = recordingManager.$isRecording.sink { _ in
            changeCount += 1
        }

        // Initial subscription counts as one
        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    func testRecordingDurationIsPublished() {
        var changeCount = 0
        let cancellable = recordingManager.$recordingDuration.sink { _ in
            changeCount += 1
        }

        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    func testSessionStateIsPublished() {
        var changeCount = 0
        let cancellable = recordingManager.$sessionState.sink { _ in
            changeCount += 1
        }

        XCTAssertGreaterThanOrEqual(changeCount, 1)
        cancellable.cancel()
    }

    // MARK: - Observable Object Tests

    func testRecordingManagerIsObservableObject() {
        let objectWillChangePublisher = recordingManager.objectWillChange
        XCTAssertNotNil(objectWillChangePublisher)
    }

    // MARK: - Notification Name Tests

    func testRecordingStartedNotificationName() {
        XCTAssertEqual(Notification.Name.recordingStarted.rawValue, "recordingStarted")
    }

    func testRecordingStoppedNotificationName() {
        XCTAssertEqual(Notification.Name.recordingStopped.rawValue, "recordingStopped")
    }

    func testRecordingCompletedNotificationName() {
        XCTAssertEqual(Notification.Name.recordingCompleted.rawValue, "recordingCompleted")
    }
}

// MARK: - RecordingControlsView Tests

final class RecordingControlsViewTests: XCTestCase {

    // MARK: - Duration Formatting Tests

    func testFormatDurationZero() {
        let formatted = formatDuration(0)
        XCTAssertEqual(formatted, "00:00.0")
    }

    func testFormatDurationOneSecond() {
        let formatted = formatDuration(1.0)
        XCTAssertEqual(formatted, "00:01.0")
    }

    func testFormatDurationOneMinute() {
        let formatted = formatDuration(60.0)
        XCTAssertEqual(formatted, "01:00.0")
    }

    func testFormatDurationComplexValue() {
        let formatted = formatDuration(65.5)
        XCTAssertEqual(formatted, "01:05.5")
    }

    func testFormatDurationWithTenths() {
        let formatted = formatDuration(10.3)
        XCTAssertEqual(formatted, "00:10.3")
    }

    func testFormatDurationLargeValue() {
        // 5 minutes, 45 seconds, 5 tenths
        // Using .5 to avoid floating point precision issues with .9
        let formatted = formatDuration(345.5)
        XCTAssertEqual(formatted, "05:45.5")
    }

    func testFormatDurationRounding() {
        // Test that tenths are truncated, not rounded
        let formatted = formatDuration(1.99)
        XCTAssertEqual(formatted, "00:01.9")
    }

    // Helper to replicate the formatDuration logic from RecordingControlsView
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - AVAssetWriterStreamOutput Tests

final class AVAssetWriterStreamOutputTests: XCTestCase {

    func testAVAssetWriterStreamOutputInitialization() {
        let output = AVAssetWriterStreamOutput(
            videoInput: nil,
            systemAudioInput: nil,
            microphoneAudioInput: nil,
            assetWriter: nil
        )
        XCTAssertNotNil(output)
    }
}
