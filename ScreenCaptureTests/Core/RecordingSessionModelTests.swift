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

    func testTransitionPathIsValid() throws {
        try model.beginSelection()
        try model.beginStarting()
        try model.beginRecording()
        try model.beginStopping()
        try model.markCompleted()
        try model.markIdle()

        XCTAssertEqual(model.state, .idle)
    }

    func testInvalidTransitionThrows() {
        XCTAssertThrowsError(try model.beginRecording()) { error in
            XCTAssertEqual(
                error as? RecordingSessionTransitionError,
                .illegalTransition(from: .idle, to: .recording)
            )
        }
    }

    func testElapsedDurationAdvancesDuringRecording() async throws {
        try model.beginStarting()
        try model.beginRecording()

        let initialDuration = model.elapsedDuration
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertGreaterThan(model.elapsedDuration, initialDuration)
    }

    func testElapsedDurationResetsWhenReturningToIdle() throws {
        try model.beginStarting()
        try model.beginRecording()
        try model.beginStopping()
        try model.markCompleted()
        try model.markIdle()

        XCTAssertEqual(model.elapsedDuration, 0)
    }
}
