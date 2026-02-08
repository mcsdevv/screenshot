import XCTest
@testable import ScreenCapture

final class RecordingConfigTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RecordingConfigTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testResolveConfigUsesUserSettings() {
        defaults.set("medium", forKey: "recordingQuality")
        defaults.set(30, forKey: "recordingFPS")
        defaults.set(true, forKey: "recordShowCursor")
        defaults.set(true, forKey: "showMouseClicks")
        defaults.set(true, forKey: "recordMicrophone")
        defaults.set(false, forKey: "recordSystemAudio")

        let config = RecordingConfig.resolve(
            target: .fullscreen,
            userDefaults: defaults
        )

        XCTAssertEqual(config.quality, .medium)
        XCTAssertEqual(config.fps, 30)
        XCTAssertTrue(config.includeCursor)
        XCTAssertTrue(config.showMouseClicks)
        XCTAssertTrue(config.includeMicrophone)
        XCTAssertFalse(config.includeSystemAudio)
    }

    func testInvalidFPSFallsBackToDefault() {
        defaults.set(144, forKey: "recordingFPS")

        let config = RecordingConfig.resolve(
            target: .fullscreen,
            userDefaults: defaults
        )

        XCTAssertEqual(config.fps, 60)
    }

    func testScaledDimensionsRespectQualityCaps() {
        let low = RecordingConfig(
            quality: .low,
            fps: 30,
            includeCursor: true,
            showMouseClicks: false,
            includeMicrophone: false,
            includeSystemAudio: true,
            excludesCurrentProcessAudio: false,
            target: .fullscreen
        )

        let high = RecordingConfig(
            quality: .high,
            fps: 60,
            includeCursor: true,
            showMouseClicks: true,
            includeMicrophone: false,
            includeSystemAudio: true,
            excludesCurrentProcessAudio: false,
            target: .fullscreen
        )

        let lowScaled = low.scaledDimensions(width: 2560, height: 1440)
        let highScaled = high.scaledDimensions(width: 2560, height: 1440)

        XCTAssertEqual(lowScaled.height, 720)
        XCTAssertLessThan(lowScaled.width, 2560)
        XCTAssertEqual(highScaled.width, 2560)
        XCTAssertEqual(highScaled.height, 1440)
    }
}
