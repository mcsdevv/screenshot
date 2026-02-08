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

    func testResolveVideoConfigUsesUserSettings() {
        defaults.set("medium", forKey: "recordingQuality")
        defaults.set(30, forKey: "recordingFPS")
        defaults.set(true, forKey: "recordShowCursor")
        defaults.set(true, forKey: "showMouseClicks")
        defaults.set(true, forKey: "recordMicrophone")
        defaults.set(false, forKey: "recordSystemAudio")

        let config = RecordingConfig.resolve(
            mode: .video,
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

    func testResolveGIFConfigUsesGIFSettings() {
        defaults.set(20, forKey: "gifFPS")
        defaults.set("high", forKey: "gifQuality")

        let config = RecordingConfig.resolve(
            mode: .gif,
            target: .fullscreen,
            userDefaults: defaults
        )

        XCTAssertEqual(config.mode, .gif)
        XCTAssertEqual(config.fps, 20)
        XCTAssertEqual(config.gifExportQuality, .high)
    }

    func testInvalidFPSFallsBackToDefaults() {
        defaults.set(144, forKey: "recordingFPS")
        defaults.set(7, forKey: "gifFPS")

        let videoConfig = RecordingConfig.resolve(
            mode: .video,
            target: .fullscreen,
            userDefaults: defaults
        )

        let gifConfig = RecordingConfig.resolve(
            mode: .gif,
            target: .fullscreen,
            userDefaults: defaults
        )

        XCTAssertEqual(videoConfig.fps, 60)
        XCTAssertEqual(gifConfig.fps, 15)
    }

    func testScaledDimensionsRespectQualityCaps() {
        let low = RecordingConfig(
            mode: .video,
            quality: .low,
            fps: 30,
            includeCursor: true,
            showMouseClicks: false,
            includeMicrophone: false,
            includeSystemAudio: true,
            excludesCurrentProcessAudio: false,
            gifExportQuality: .medium,
            target: .fullscreen
        )

        let high = RecordingConfig(
            mode: .video,
            quality: .high,
            fps: 60,
            includeCursor: true,
            showMouseClicks: true,
            includeMicrophone: false,
            includeSystemAudio: true,
            excludesCurrentProcessAudio: false,
            gifExportQuality: .medium,
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
