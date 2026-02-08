import Foundation
import AppKit
import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit

enum CaptureEngineError: LocalizedError {
    case alreadyRunning
    case notRunning
    case invalidWindowTarget(UInt32)
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case outputFileMissing(URL)
    case outputFileInvalid(URL, reason: String)
    case noVideoFramesCaptured
    case recordingFinishTimedOut
    case engineDeallocated

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A recording session is already running."
        case .notRunning:
            return "No active recording session to stop."
        case let .invalidWindowTarget(windowID):
            return "Could not find a shareable window for ID \(windowID)."
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable access in System Settings > Privacy & Security > Microphone."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted on this Mac."
        case let .outputFileMissing(url):
            return "Recording finished but output file is missing at \(url.path)."
        case let .outputFileInvalid(url, reason):
            return "Recording finished but output file is invalid (\(reason)) at \(url.path)."
        case .noVideoFramesCaptured:
            return "Recording stopped before any frames were captured."
        case .recordingFinishTimedOut:
            return "Timed out while waiting for recording finalization."
        case .engineDeallocated:
            return "Recording engine was released before completion."
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class SCRecordingOutputEngine: NSObject, CaptureEngine {
    private struct FilterContext {
        let filter: SCContentFilter
        let baseWidthPoints: CGFloat
        let baseHeightPoints: CGFloat
        let scaleFactor: CGFloat
        let sourceRect: CGRect?
    }

    private let statusSubject = CurrentValueSubject<CaptureEngineStatus, Never>(.idle)
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var currentOutputURL: URL?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    var statusPublisher: AnyPublisher<CaptureEngineStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    func start(config: RecordingConfig, outputURL: URL) async throws {
        guard stream == nil else {
            throw CaptureEngineError.alreadyRunning
        }

        if config.includeMicrophone {
            try await ensureMicrophoneAuthorization()
        }

        let filterContext = try await resolveFilterContext(for: config.target)
        let streamConfig = makeStreamConfiguration(config: config, context: filterContext)

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.videoCodecType = .h264
        recordingConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filterContext.filter, configuration: streamConfig, delegate: self)
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.currentOutputURL = outputURL
        statusSubject.send(.running)

        debugLog("SCRecordingOutputEngine: Started capture to \(outputURL.lastPathComponent)")
    }

    func stop() async throws -> URL {
        guard let stream, let outputURL = currentOutputURL else {
            throw CaptureEngineError.notRunning
        }

        statusSubject.send(.stopping)
        let finishWaitTask = Task { @MainActor in
            try await self.waitForRecordingFinish(timeout: 12)
        }

        do {
            try await stream.stopCapture()
        } catch {
            if isStreamAlreadyStoppedError(error) {
                debugLog("SCRecordingOutputEngine: Stream already stopped before stop() completed")
            } else {
                throw error
            }
        }

        // Intentionally do not remove recording output manually.
        // Stopping capture finalizes the recording output and keeps
        // ScreenCaptureKit's internal output routing consistent.

        do {
            try await finishWaitTask.value
        } catch {
            errorLog("SCRecordingOutputEngine: Recording finish wait failed", error: error)
        }

        cleanup()

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CaptureEngineError.outputFileMissing(outputURL)
        }

        statusSubject.send(.idle)
        return outputURL
    }

    func cancel() async {
        do {
            if let stream {
                try await stream.stopCapture()
            }
        } catch {
            errorLog("SCRecordingOutputEngine: Cancel stopCapture failed", error: error)
        }

        if let continuation = finishContinuation {
            finishContinuation = nil
            continuation.resume(throwing: CancellationError())
        }

        cleanup()
        statusSubject.send(.idle)
    }

    private func cleanup() {
        stream = nil
        recordingOutput = nil
        currentOutputURL = nil
        finishContinuation = nil
    }

    private func waitForRecordingFinish(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            finishContinuation = continuation

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let continuation = self.finishContinuation else { return }
                self.finishContinuation = nil
                continuation.resume(throwing: CaptureEngineError.recordingFinishTimedOut)
            }
        }
    }

    private func resolveFilterContext(for target: RecordingTarget) async throws -> FilterContext {
        switch target {
        case .fullscreen:
            let display = try await ScreenCaptureContentProvider.shared.getPrimaryDisplay()
            let filter = SCContentFilter(display: display, excludingWindows: [])
            return FilterContext(
                filter: filter,
                baseWidthPoints: CGFloat(display.width),
                baseHeightPoints: CGFloat(display.height),
                scaleFactor: displayScaleFactor(for: display.displayID),
                sourceRect: nil
            )

        case let .area(rect):
            let display = try await ScreenCaptureContentProvider.shared.getDisplay(containing: rect)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let sourceRect = localizedSourceRect(for: rect, displayID: display.displayID)
            return FilterContext(
                filter: filter,
                baseWidthPoints: sourceRect.width,
                baseHeightPoints: sourceRect.height,
                scaleFactor: displayScaleFactor(for: display.displayID),
                sourceRect: sourceRect
            )

        case let .window(windowID):
            let content = try await ScreenCaptureContentProvider.shared.getContent()
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureEngineError.invalidWindowTarget(windowID)
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return FilterContext(
                filter: filter,
                baseWidthPoints: window.frame.width,
                baseHeightPoints: window.frame.height,
                scaleFactor: NSScreen.main?.backingScaleFactor ?? 2.0,
                sourceRect: nil
            )
        }
    }

    private func makeStreamConfiguration(config: RecordingConfig, context: FilterContext) -> SCStreamConfiguration {
        let streamConfig = SCStreamConfiguration()

        let baseWidth = Int((context.baseWidthPoints * context.scaleFactor).rounded())
        let baseHeight = Int((context.baseHeightPoints * context.scaleFactor).rounded())
        let scaledDimensions = config.scaledDimensions(width: baseWidth, height: baseHeight)

        streamConfig.width = max(2, scaledDimensions.width)
        streamConfig.height = max(2, scaledDimensions.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, config.fps)))
        streamConfig.captureResolution = .best
        streamConfig.queueDepth = 6
        streamConfig.showsCursor = config.includeCursor
        streamConfig.showMouseClicks = config.includeCursor && config.showMouseClicks

        if let sourceRect = context.sourceRect {
            streamConfig.sourceRect = sourceRect
        }

        streamConfig.capturesAudio = config.includeSystemAudio
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2
        streamConfig.excludesCurrentProcessAudio = config.excludesCurrentProcessAudio
        streamConfig.captureMicrophone = config.includeMicrophone

        return streamConfig
    }

    private func displayScaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            if CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.backingScaleFactor
            }
        }

        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private func displayFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            if CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.frame
            }
        }

        return nil
    }

    private func localizedSourceRect(for globalRect: CGRect, displayID: CGDirectDisplayID) -> CGRect {
        guard let displayFrame = displayFrame(for: displayID) else {
            return globalRect.standardized
        }

        // ScreenCaptureKit sourceRect uses the display logical coordinate system
        // (origin at top-left). NSEvent/NSScreen global coordinates are bottom-left.
        let localX = globalRect.minX - displayFrame.minX
        let localYBottom = globalRect.minY - displayFrame.minY
        let localYTop = displayFrame.height - localYBottom - globalRect.height

        let localizedRect = CGRect(
            x: localX,
            y: localYTop,
            width: globalRect.width,
            height: globalRect.height
        ).standardized

        let displayBounds = CGRect(x: 0, y: 0, width: displayFrame.width, height: displayFrame.height)
        let clippedRect = localizedRect.intersection(displayBounds)
        guard !clippedRect.isNull, clippedRect.width >= 2, clippedRect.height >= 2 else {
            return localizedRect
        }

        return clippedRect
    }

    private func isStreamAlreadyStoppedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3808
    }

    private func ensureMicrophoneAuthorization() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw CaptureEngineError.microphonePermissionDenied
            }

        case .denied:
            throw CaptureEngineError.microphonePermissionDenied

        case .restricted:
            throw CaptureEngineError.microphonePermissionRestricted

        @unknown default:
            throw CaptureEngineError.microphonePermissionDenied
        }
    }
}

@available(macOS 15.0, *)
extension SCRecordingOutputEngine: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.statusSubject.send(.running)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusSubject.send(.failed(error.localizedDescription))
            if let continuation = self.finishContinuation {
                self.finishContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            if let continuation = self.finishContinuation {
                self.finishContinuation = nil
                continuation.resume()
            }
        }
    }
}

@available(macOS 15.0, *)
extension SCRecordingOutputEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.statusSubject.send(.failed(error.localizedDescription))
            if let continuation = self.finishContinuation {
                self.finishContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
