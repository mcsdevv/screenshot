import XCTest
@testable import ScreenCapture

@MainActor
final class RecordingSessionModelTests: XCTestCase {
    var model: RecordingSessionModel!

    override func setUp() {
        super.setUp()
        model = RecordingSessionModel()
    }

    override func tearDown() {
        model = nil
        super.tearDown()
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.elapsedDuration, 0)
    }

    func testVideoTransitionPathIsValid() throws {
        try model.beginSelection(for: .video)
        try model.beginStarting(for: .video)
        try model.beginRecording(for: .video)
        try model.beginStopping(for: .video)
        try model.markCompleted()
        try model.markIdle()

        XCTAssertEqual(model.state, .idle)
    }

    func testGIFTransitionPathIsValid() throws {
        try model.beginSelection(for: .gif)
        try model.beginStarting(for: .gif)
        try model.beginRecording(for: .gif)
        try model.beginStopping(for: .gif)
        try model.beginGIFExport()
        try model.markCompleted()
        try model.markIdle()

        XCTAssertEqual(model.state, .idle)
    }

    func testInvalidTransitionThrows() {
        XCTAssertThrowsError(try model.beginRecording(for: .video)) { error in
            XCTAssertEqual(
                error as? RecordingSessionTransitionError,
                .illegalTransition(from: .idle, to: .recording(.video))
            )
        }
    }

    func testElapsedDurationAdvancesDuringRecording() async throws {
        try model.beginStarting(for: .video)
        try model.beginRecording(for: .video)

        let initialDuration = model.elapsedDuration
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertGreaterThan(model.elapsedDuration, initialDuration)
    }

    func testElapsedDurationResetsWhenReturningToIdle() throws {
        try model.beginStarting(for: .video)
        try model.beginRecording(for: .video)
        try model.beginStopping(for: .video)
        try model.markCompleted()
        try model.markIdle()

        XCTAssertEqual(model.elapsedDuration, 0)
    }
}
