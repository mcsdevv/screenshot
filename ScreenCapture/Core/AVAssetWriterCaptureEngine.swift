import Foundation
import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit
import AppKit

@MainActor
final class AVAssetWriterCaptureEngine: NSObject, CaptureEngine {
    private struct FilterContext {
        let filter: SCContentFilter
        let baseWidthPoints: CGFloat
        let baseHeightPoints: CGFloat
        let scaleFactor: CGFloat
        let sourceRect: CGRect?
    }

    private let statusSubject = CurrentValueSubject<CaptureEngineStatus, Never>(.idle)

    private var stream: SCStream?
    private var streamOutput: AVAssetWriterStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    private var currentOutputURL: URL?

    var statusPublisher: AnyPublisher<CaptureEngineStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    func start(config: RecordingConfig, outputURL: URL) async throws {
        guard stream == nil else {
            throw CaptureEngineError.alreadyRunning
        }

        let filterContext = try await resolveFilterContext(for: config.target)
        let streamConfig = makeStreamConfiguration(config: config, context: filterContext)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings = makeVideoSettings(config: config, width: streamConfig.width, height: streamConfig.height)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]

        var systemAudioInput: AVAssetWriterInput?
        var microphoneAudioInput: AVAssetWriterInput?

        if config.includeSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }

        if config.includeMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                microphoneAudioInput = input
            }
        }

        let output = AVAssetWriterStreamOutput(
            videoInput: videoInput,
            systemAudioInput: systemAudioInput,
            microphoneAudioInput: microphoneAudioInput,
            assetWriter: writer
        )

        let stream = SCStream(filter: filterContext.filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

        if config.includeSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        }

        if config.includeMicrophone {
            #if compiler(>=6.0)
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: .global(qos: .userInteractive))
            }
            #endif
        }

        writer.startWriting()

        guard writer.status == .writing else {
            throw writer.error ?? NSError(
                domain: "AVAssetWriterCaptureEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Asset writer failed to start"]
            )
        }

        try await stream.startCapture()

        self.stream = stream
        self.streamOutput = output
        self.assetWriter = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
        self.currentOutputURL = outputURL
        self.statusSubject.send(.running)

        debugLog("AVAssetWriterCaptureEngine: Started capture to \(outputURL.lastPathComponent)")
    }

    func stop() async throws -> URL {
        guard let stream, let writer = assetWriter, let outputURL = currentOutputURL else {
            throw CaptureEngineError.notRunning
        }

        statusSubject.send(.stopping)

        do {
            try await stream.stopCapture()
        } catch {
            // SCStream can already be stopped when upstream tears down capture first.
            // Continue writer finalization so we can salvage the recording when possible.
            if isStreamAlreadyStoppedError(error) {
                debugLog("AVAssetWriterCaptureEngine: Stream already stopped before stop() completed")
            } else {
                throw error
            }
        }

        let outputSummary = await streamOutput?.finish()

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        if writer.status == .writing {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            let reason = writer.error.map { "Asset writer failed and produced no file (\(describe(error: $0)))" }
                ?? "Asset writer did not produce an output file"
            throw CaptureEngineError.outputFileInvalid(outputURL, reason: reason)
        }

        let fileSize: Int64
        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let sizeNumber = attributes[.size] as? NSNumber {
            fileSize = sizeNumber.int64Value
        } else {
            fileSize = 0
        }

        guard fileSize > 0 else {
            let writerReason = writer.error.map { " (\(describe(error: $0)))" } ?? ""
            throw CaptureEngineError.outputFileInvalid(outputURL, reason: "Recorded file is empty\(writerReason)")
        }

        switch writer.status {
        case .failed, .cancelled:
            // Some macOS builds report writer failure even though a playable file was written.
            // Let higher-level AVAsset validation determine whether this output is usable.
            let errorDetail = writer.error.map(describe(error:)) ?? "no error details"
            debugLog("AVAssetWriterCaptureEngine: Writer ended with status=\(writer.status.rawValue), attempting salvage (\(errorDetail))")
        case .completed:
            break
        default:
            debugLog("AVAssetWriterCaptureEngine: Writer ended with status=\(writer.status.rawValue), file size=\(fileSize)")
        }

        if (outputSummary?.videoFrameCount ?? 0) == 0 {
            debugLog("AVAssetWriterCaptureEngine: No appended frames recorded before finalize; deferring final validity decision to AVAsset validation")
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
            if isStreamAlreadyStoppedError(error) {
                debugLog("AVAssetWriterCaptureEngine: Cancel ignored because stream is already stopped")
            } else {
                errorLog("AVAssetWriterCaptureEngine: Cancel stopCapture failed", error: error)
            }
        }

        if let writer = assetWriter, writer.status == .writing {
            writer.cancelWriting()
        }

        cleanup()
        statusSubject.send(.idle)
    }

    private func cleanup() {
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneAudioInput = nil
        currentOutputURL = nil
    }

    private func isStreamAlreadyStoppedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3808
    }

    private func describe(error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
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

        if let sourceRect = context.sourceRect {
            streamConfig.sourceRect = sourceRect
        }

        streamConfig.capturesAudio = config.includeSystemAudio
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2
        streamConfig.excludesCurrentProcessAudio = config.excludesCurrentProcessAudio

        if #available(macOS 15.0, *) {
            streamConfig.captureMicrophone = config.includeMicrophone
            streamConfig.showMouseClicks = config.includeCursor && config.showMouseClicks
        }

        return streamConfig
    }

    private func makeVideoSettings(config: RecordingConfig, width: Int, height: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.quality.videoBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
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
}

@MainActor
extension AVAssetWriterCaptureEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.statusSubject.send(.failed(error.localizedDescription))
        }
    }
}

final class AVAssetWriterStreamOutput: NSObject, SCStreamOutput {
    struct OutputSummary: Sendable {
        let videoFrameCount: Int
        let systemAudioBufferCount: Int
        let microphoneAudioBufferCount: Int
    }

    private let videoInput: AVAssetWriterInput?
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneAudioInput: AVAssetWriterInput?
    private let assetWriter: AVAssetWriter?
    private var sessionStarted = false
    private var sessionStartTime: CMTime?
    private let queue = DispatchQueue(label: "capture.output.assetwriter")
    private var isFinishing = false
    private var videoFrameCount = 0
    private var systemAudioBufferCount = 0
    private var microphoneAudioBufferCount = 0

    init(
        videoInput: AVAssetWriterInput?,
        systemAudioInput: AVAssetWriterInput?,
        microphoneAudioInput: AVAssetWriterInput?,
        assetWriter: AVAssetWriter?
    ) {
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
        self.assetWriter = assetWriter
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            if self.isFinishing { return }
            guard self.assetWriter?.status == .writing || !self.sessionStarted else { return }

            if !self.sessionStarted {
                // Anchor the writer timeline to the first screen frame.
                // Starting from audio can produce invalid timestamps for subsequent video frames.
                guard type == .screen else { return }
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter?.startSession(atSourceTime: timestamp)
                self.sessionStarted = true
                self.sessionStartTime = timestamp
            }

            if let sessionStartTime = self.sessionStartTime {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if timestamp < sessionStartTime {
                    return
                }
            }

            switch type {
            case .screen:
                if self.videoInput?.isReadyForMoreMediaData == true {
                    if self.videoInput?.append(sampleBuffer) == true {
                        self.videoFrameCount += 1
                    }
                }

            case .audio:
                if self.systemAudioInput?.isReadyForMoreMediaData == true {
                    if self.systemAudioInput?.append(sampleBuffer) == true {
                        self.systemAudioBufferCount += 1
                    }
                }

            #if compiler(>=6.0)
            case .microphone:
                if self.microphoneAudioInput?.isReadyForMoreMediaData == true {
                    if self.microphoneAudioInput?.append(sampleBuffer) == true {
                        self.microphoneAudioBufferCount += 1
                    }
                } else if self.systemAudioInput?.isReadyForMoreMediaData == true {
                    if self.systemAudioInput?.append(sampleBuffer) == true {
                        self.systemAudioBufferCount += 1
                    }
                }
            #endif

            @unknown default:
                if self.systemAudioInput?.isReadyForMoreMediaData == true {
                    if self.systemAudioInput?.append(sampleBuffer) == true {
                        self.systemAudioBufferCount += 1
                    }
                }
            }
        }
    }

    func finish() async -> OutputSummary {
        await withCheckedContinuation { (continuation: CheckedContinuation<OutputSummary, Never>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: OutputSummary(videoFrameCount: 0, systemAudioBufferCount: 0, microphoneAudioBufferCount: 0))
                    return
                }

                self.isFinishing = true
                continuation.resume(
                    returning: OutputSummary(
                        videoFrameCount: self.videoFrameCount,
                        systemAudioBufferCount: self.systemAudioBufferCount,
                        microphoneAudioBufferCount: self.microphoneAudioBufferCount
                    )
                )
            }
        }
    }
}
