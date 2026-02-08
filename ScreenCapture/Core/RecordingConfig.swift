import Foundation
import CoreGraphics

enum RecordingQualityPreset: String, Sendable {
    case low
    case medium
    case high

    init(settingsValue: String) {
        switch settingsValue.lowercased() {
        case "low":
            self = .low
        case "medium":
            self = .medium
        default:
            self = .high
        }
    }

    var targetMaxHeight: Int? {
        switch self {
        case .low:
            return 720
        case .medium:
            return 1080
        case .high:
            return nil
        }
    }

    var videoBitrate: Int {
        switch self {
        case .low:
            return 5_000_000
        case .medium:
            return 8_000_000
        case .high:
            return 12_000_000
        }
    }
}

enum RecordingTarget: Sendable, Equatable {
    case fullscreen
    case area(CGRect)
    case window(windowID: UInt32)
}

struct RecordingConfig: Sendable, Equatable {
    let quality: RecordingQualityPreset
    let fps: Int
    let includeCursor: Bool
    let showMouseClicks: Bool
    let includeMicrophone: Bool
    let includeSystemAudio: Bool
    let excludesCurrentProcessAudio: Bool
    let target: RecordingTarget

    static func defaults(target: RecordingTarget) -> RecordingConfig {
        RecordingConfig(
            quality: .high,
            fps: 60,
            includeCursor: true,
            showMouseClicks: true,
            includeMicrophone: false,
            includeSystemAudio: true,
            excludesCurrentProcessAudio: false,
            target: target
        )
    }

    static func resolve(
        target: RecordingTarget,
        userDefaults: UserDefaults = .standard
    ) -> RecordingConfig {
        let quality = RecordingQualityPreset(settingsValue: userDefaults.string(forKey: "recordingQuality") ?? "high")
        let fps = sanitizeVideoFPS(userDefaults.integer(forKey: "recordingFPS"))
        let includeCursor = readBool(userDefaults, key: "recordShowCursor", fallback: true)
        let showMouseClicks = readBool(userDefaults, key: "showMouseClicks", fallback: true)
        let includeMicrophone = readBool(userDefaults, key: "recordMicrophone", fallback: false)
        let includeSystemAudio = readBool(userDefaults, key: "recordSystemAudio", fallback: true)
        let excludesCurrentProcessAudio = readBool(userDefaults, key: "excludeAppAudio", fallback: false)

        return RecordingConfig(
            quality: quality,
            fps: fps,
            includeCursor: includeCursor,
            showMouseClicks: showMouseClicks,
            includeMicrophone: includeMicrophone,
            includeSystemAudio: includeSystemAudio,
            excludesCurrentProcessAudio: excludesCurrentProcessAudio,
            target: target
        )
    }

    func scaledDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return (max(2, width), max(2, height))
        }

        guard let maxHeight = quality.targetMaxHeight, height > maxHeight else {
            return (makeEven(width), makeEven(height))
        }

        let scale = Double(maxHeight) / Double(height)
        let scaledWidth = Int(Double(width) * scale)
        return (makeEven(scaledWidth), makeEven(maxHeight))
    }

    private static func sanitizeVideoFPS(_ value: Int) -> Int {
        if value == 30 { return 30 }
        return 60
    }

    private static func readBool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private func makeEven(_ value: Int) -> Int {
        if value <= 2 { return 2 }
        return value % 2 == 0 ? value : value - 1
    }
}
