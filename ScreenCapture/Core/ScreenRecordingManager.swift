import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Combine

/// Thread-safe actor for collecting GIF frames from the capture stream
actor GIFFrameCollector {
    private var frames: [CGImage] = []
    private var frameCount: Int = 0

    func addFrame(_ frame: CGImage) {
        frames.append(frame)
        frameCount += 1
    }

    func getFramesAndReset() -> [CGImage] {
        let collectedFrames = frames
        frames = []
        frameCount = 0
        return collectedFrames
    }

    func reset() {
        frames = []
        frameCount = 0
    }

    var count: Int {
        frameCount
    }
}

@MainActor
class ScreenRecordingManager: NSObject, ObservableObject {
    private let storageManager: StorageManager
    private var stream: SCStream?
    private var streamOutput: SCStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var audioAppInput: AVAssetWriterInput?

    // Shared CIContext for frame processing (expensive to create, reuse across frames)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    @Published var isRecording = false
    @Published var isGIFRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isPaused = false

    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var recordingRect: CGRect?
    private let gifFrameCollector = GIFFrameCollector()

    private var controlWindow: NSWindow?
    private var selectionWindow: NSWindow?
    private var windowSelectionWindow: NSWindow?
    private var pendingRecordingMode: RecordingMode = .video

    private enum RecordingMode {
        case video
        case gif
    }

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecordingWithSelection()
        }
    }

    func toggleGIFRecording() {
        if isGIFRecording {
            stopGIFRecording()
        } else {
            startGIFRecordingWithSelection()
        }
    }

    func stopActiveRecordingIfNeeded(reason: String = "termination", completion: (() -> Void)? = nil) {
        if isGIFRecording {
            debugLog("Stopping GIF recording due to \(reason)")
            stopGIFRecording(completion: completion)
        } else if isRecording {
            debugLog("Stopping screen recording due to \(reason)")
            stopRecording(completion: completion)
        } else {
            completion?()
        }
    }

    // MARK: - Selection Flow

    private func startRecordingWithSelection() {
        pendingRecordingMode = .video
        showAreaSelection { [weak self] rect in
            self?.startRecording(in: rect)
        }
    }

    private func startGIFRecordingWithSelection() {
        pendingRecordingMode = .gif
        showAreaSelection { [weak self] rect in
            self?.startGIFRecording(in: rect)
        }
    }

    private func showAreaSelection(completion: @escaping (CGRect?) -> Void) {
        closeSelectionWindow()

        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        let selectionView = RecordingSelectionView(
            onSelection: { [weak self] rect in
                self?.closeSelectionWindow()
                completion(rect)
            },
            onFullscreen: { [weak self] in
                self?.closeSelectionWindow()
                completion(nil)
            },
            onWindowSelect: { [weak self] in
                self?.closeSelectionWindow()
                self?.showWindowSelection()
            },
            onCancel: { [weak self] in
                self?.closeSelectionWindow()
                completion(nil)
            }
        )

        let hostingView = NSHostingView(rootView: selectionView)
        hostingView.frame = screen.frame

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        selectionWindow = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingView)
    }

    private func closeSelectionWindow() {
        guard let windowToClose = selectionWindow else { return }
        selectionWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    // MARK: - Window Selection

    private func showWindowSelection() {
        guard let screen = NSScreen.main else { return }

        let windowView = WindowSelectionView(
            onWindowSelected: { [weak self] window in
                self?.closeWindowSelectionWindow()
                self?.startRecordingForWindow(window)
            },
            onCancel: { [weak self] in
                self?.closeWindowSelectionWindow()
            }
        )

        let hostingView = NSHostingView(rootView: windowView)
        hostingView.frame = screen.frame

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        windowSelectionWindow = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingView)
    }

    private func closeWindowSelectionWindow() {
        guard let windowToClose = windowSelectionWindow else { return }
        windowSelectionWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func startRecordingForWindow(_ window: SCWindow) {
        switch pendingRecordingMode {
        case .video:
            startRecording(window: window)
        case .gif:
            startGIFRecording(window: window)
        }
    }

    // MARK: - Video Recording (Area/Fullscreen)

    private func startRecording(in rect: CGRect?) {
        Task {
            do {
                let display = try await ScreenCaptureContentProvider.shared.getPrimaryDisplay()

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = rect != nil ? Int(rect!.width * 2) : display.width * 2
                config.height = rect != nil ? Int(rect!.height * 2) : display.height * 2
                if let rect = rect {
                    config.sourceRect = rect
                }
                config.showsCursor = true
                config.captureResolution = .best
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.capturesAudio = true
                config.sampleRate = 48000
                config.channelCount = 2

                try await beginVideoRecording(filter: filter, config: config)
            } catch {
                errorLog("Failed to start recording", error: error)
            }
        }
    }

    // MARK: - Video Recording (Window)

    private func startRecording(window scWindow: SCWindow) {
        Task {
            do {
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)

                let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
                let config = SCStreamConfiguration()
                config.width = Int(scWindow.frame.width * scaleFactor)
                config.height = Int(scWindow.frame.height * scaleFactor)
                config.showsCursor = true
                config.captureResolution = .best
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.capturesAudio = true
                config.sampleRate = 48000
                config.channelCount = 2

                debugLog("Starting window recording: \(scWindow.owningApplication?.applicationName ?? "unknown") - \(config.width)x\(config.height)")
                try await beginVideoRecording(filter: filter, config: config)
            } catch {
                errorLog("Failed to start window recording", error: error)
            }
        }
    }

    /// Shared video recording setup used by both area and window recording
    private func beginVideoRecording(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        let outputURL = storageManager.generateRecordingURL()
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        if let videoInput = videoInput {
            assetWriter?.add(videoInput)
        }
        if let audioInput = audioInput {
            assetWriter?.add(audioInput)
        }

        streamOutput = CaptureOutput(
            videoInput: videoInput,
            audioInput: audioInput,
            assetWriter: assetWriter
        )

        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        assetWriter?.startWriting()

        guard assetWriter?.status == .writing else {
            errorLog("AssetWriter failed to start: \(assetWriter?.error?.localizedDescription ?? "unknown")")
            return
        }

        try await stream?.startCapture()

        debugLog("Recording started - \(config.width)x\(config.height)")

        await MainActor.run {
            self.isRecording = true
            self.recordingStartTime = Date()
            self.startRecordingTimer()
            self.showRecordingControls()
            NotificationCenter.default.post(name: .recordingStarted, object: nil)
        }
    }

    private func stopRecording(completion: (() -> Void)? = nil) {
        Task {
            do {
                try await stream?.stopCapture()
                stream = nil

                if let captureOutput = streamOutput as? CaptureOutput {
                    await captureOutput.finish()
                }

                videoInput?.markAsFinished()
                audioInput?.markAsFinished()

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    assetWriter?.finishWriting {
                        continuation.resume()
                    }
                }

                let outputURL = assetWriter?.outputURL

                if assetWriter?.status == .failed {
                    errorLog("AssetWriter failed: \(assetWriter?.error?.localizedDescription ?? "unknown")")
                }

                debugLog("Recording stopped - output: \(outputURL?.lastPathComponent ?? "none")")

                await MainActor.run {
                    self.isRecording = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    self.recordingDuration = 0
                    self.hideRecordingControls()
                    NotificationCenter.default.post(name: .recordingStopped, object: nil)

                    if let url = outputURL {
                        let capture = self.storageManager.saveRecording(url: url)
                        NotificationCenter.default.post(name: .recordingCompleted, object: capture)
                    }
                }
            } catch {
                errorLog("Failed to stop recording", error: error)
            }

            if let completion = completion {
                await MainActor.run {
                    completion()
                }
            }
        }
    }

    // MARK: - GIF Recording (Area/Fullscreen)

    private func startGIFRecording(in rect: CGRect?) {
        Task {
            await gifFrameCollector.reset()

            do {
                let display = try await ScreenCaptureContentProvider.shared.getPrimaryDisplay()

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = rect != nil ? Int(rect!.width) : display.width
                config.height = rect != nil ? Int(rect!.height) : display.height
                if let rect = rect {
                    config.sourceRect = rect
                }
                config.showsCursor = true
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)

                try await beginGIFRecording(filter: filter, config: config)
            } catch {
                errorLog("Failed to start GIF recording", error: error)
            }
        }
    }

    // MARK: - GIF Recording (Window)

    private func startGIFRecording(window scWindow: SCWindow) {
        Task {
            await gifFrameCollector.reset()

            do {
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)

                let config = SCStreamConfiguration()
                config.width = Int(scWindow.frame.width)
                config.height = Int(scWindow.frame.height)
                config.showsCursor = true
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)

                debugLog("Starting window GIF recording: \(scWindow.owningApplication?.applicationName ?? "unknown") - \(config.width)x\(config.height)")
                try await beginGIFRecording(filter: filter, config: config)
            } catch {
                errorLog("Failed to start window GIF recording", error: error)
            }
        }
    }

    /// Shared GIF recording setup used by both area and window recording
    private func beginGIFRecording(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        let collector = self.gifFrameCollector
        streamOutput = GIFCaptureOutput { frame in
            Task {
                await collector.addFrame(frame)
            }
        }

        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream?.startCapture()

        debugLog("GIF recording started - \(config.width)x\(config.height), fps: 15")

        await MainActor.run {
            self.isGIFRecording = true
            self.recordingStartTime = Date()
            self.startRecordingTimer()
            self.showRecordingControls()
            NotificationCenter.default.post(name: .recordingStarted, object: nil)
        }
    }

    private func stopGIFRecording(completion: (() -> Void)? = nil) {
        Task {
            do {
                try await stream?.stopCapture()
                stream = nil

                let gifFrames = await gifFrameCollector.getFramesAndReset()
                debugLog("GIF recording stopped - \(gifFrames.count) frames collected")

                let encoder = GIFEncoder()
                let outputURL = storageManager.generateGIFURL()

                await MainActor.run {
                    self.isGIFRecording = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    self.recordingDuration = 0
                    self.hideRecordingControls()
                    NotificationCenter.default.post(name: .recordingStopped, object: nil)
                }

                let success = await encoder.createGIF(from: gifFrames, outputURL: outputURL, frameDelay: 1.0/15.0)

                if success {
                    debugLog("GIF created at \(outputURL.lastPathComponent)")
                    await MainActor.run {
                        let capture = self.storageManager.saveGIF(url: outputURL)
                        NotificationCenter.default.post(name: .recordingCompleted, object: capture)
                    }
                } else {
                    errorLog("GIF creation failed - \(gifFrames.count) frames, output: \(outputURL.lastPathComponent)")
                }
            } catch {
                errorLog("Failed to stop GIF recording", error: error)
            }

            if let completion = completion {
                await MainActor.run {
                    completion()
                }
            }
        }
    }

    // MARK: - Recording Controls

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                guard let startTime = strongSelf.recordingStartTime else { return }
                strongSelf.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func showRecordingControls() {
        guard let screen = NSScreen.main else { return }

        hideRecordingControls()

        let controlView = RecordingControlsView(
            duration: Binding(get: { self.recordingDuration }, set: { _ in }),
            isPaused: Binding(get: { self.isPaused }, set: { _ in }),
            onStop: { [weak self] in
                if self?.isGIFRecording == true {
                    self?.stopGIFRecording()
                } else {
                    self?.stopRecording()
                }
            },
            onPause: { [weak self] in
                self?.togglePause()
            }
        )

        let hostingView = NSHostingView(rootView: controlView)
        let controlSize = NSSize(width: 200, height: 60)
        hostingView.frame = NSRect(origin: .zero, size: controlSize)

        let centerX = screen.frame.midX - controlSize.width / 2
        let bottomY = screen.visibleFrame.minY + 20

        let window = KeyableWindow(
            contentRect: NSRect(x: centerX, y: bottomY, width: controlSize.width, height: controlSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        controlWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func hideRecordingControls() {
        guard let windowToClose = controlWindow else { return }
        controlWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func togglePause() {
        isPaused.toggle()
    }
}

// MARK: - Video Capture Output

class CaptureOutput: NSObject, SCStreamOutput {
    private let videoInput: AVAssetWriterInput?
    private let audioInput: AVAssetWriterInput?
    private let assetWriter: AVAssetWriter?
    private var sessionStarted = false
    private let queue = DispatchQueue(label: "capture.output")

    init(videoInput: AVAssetWriterInput?, audioInput: AVAssetWriterInput?, assetWriter: AVAssetWriter?) {
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.assetWriter = assetWriter
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.assetWriter?.status == .writing || !self.sessionStarted else { return }

            if !self.sessionStarted {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.assetWriter?.startSession(atSourceTime: timestamp)
                self.sessionStarted = true
            }

            switch type {
            case .screen:
                if self.videoInput?.isReadyForMoreMediaData == true {
                    self.videoInput?.append(sampleBuffer)
                }
            case .audio:
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }
            #if compiler(>=6.0)
            case .microphone:
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }
            #endif
            @unknown default:
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }
            }
        }
    }

    func finish() async {
        // Cleanup if needed
    }
}

// MARK: - GIF Capture Output

class GIFCaptureOutput: NSObject, SCStreamOutput {
    private let onFrame: (CGImage) -> Void
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var frameCount = 0

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            frameCount += 1
            onFrame(cgImage)
        }
    }
}
