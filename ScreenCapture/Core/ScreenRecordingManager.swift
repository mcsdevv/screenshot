import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Combine

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
    private var gifFrames: [CGImage] = []
    private var gifFrameCount = 0

    private var controlWindow: NSWindow?
    private var selectionWindow: NSWindow?

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

    private func startRecordingWithSelection() {
        showAreaSelection { [weak self] rect in
            self?.startRecording(in: rect)
        }
    }

    private func startGIFRecordingWithSelection() {
        showAreaSelection { [weak self] rect in
            self?.startGIFRecording(in: rect)
        }
    }

    private func showAreaSelection(completion: @escaping (CGRect?) -> Void) {
        // Dismiss any existing selection window first
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
                completion(screen.frame)
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

        // Hide window immediately but defer all cleanup to next run loop
        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func startRecording(in rect: CGRect?) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

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
                try await stream?.startCapture()

                await MainActor.run {
                    self.isRecording = true
                    self.recordingStartTime = Date()
                    self.recordingRect = rect
                    self.startRecordingTimer()
                    self.showRecordingControls()
                    NotificationCenter.default.post(name: .recordingStarted, object: nil)
                }
            } catch {
                print("Recording error: \(error)")
                // Check if this is a permission issue and show alert if so
                _ = PermissionManager.shared.ensureScreenCapturePermission()
            }
        }
    }

    private func stopRecording() {
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
                print("Stop recording error: \(error)")
            }
        }
    }

    private func startGIFRecording(in rect: CGRect?) {
        gifFrames = []
        gifFrameCount = 0

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.width = rect != nil ? Int(rect!.width) : display.width
                config.height = rect != nil ? Int(rect!.height) : display.height
                if let rect = rect {
                    config.sourceRect = rect
                }
                config.showsCursor = true
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)

                streamOutput = GIFCaptureOutput { [weak self] frame in
                    self?.gifFrames.append(frame)
                    self?.gifFrameCount += 1
                }

                stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

                try await stream?.startCapture()

                await MainActor.run {
                    self.isGIFRecording = true
                    self.recordingStartTime = Date()
                    self.recordingRect = rect
                    self.startRecordingTimer()
                    self.showRecordingControls()
                    NotificationCenter.default.post(name: .recordingStarted, object: nil)
                }
            } catch {
                print("GIF recording error: \(error)")
                // Check if this is a permission issue and show alert if so
                _ = PermissionManager.shared.ensureScreenCapturePermission()
            }
        }
    }

    private func stopGIFRecording() {
        Task {
            do {
                try await stream?.stopCapture()
                stream = nil

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

                encoder.createGIF(from: gifFrames, outputURL: outputURL, frameDelay: 1.0/15.0) { [weak self] success in
                    guard let self = self else { return }

                    DispatchQueue.main.async {
                        if success {
                            let capture = self.storageManager.saveGIF(url: outputURL)
                            NotificationCenter.default.post(name: .recordingCompleted, object: capture)
                        }
                        self.gifFrames = []
                    }
                }
            } catch {
                print("Stop GIF recording error: \(error)")
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func showRecordingControls() {
        guard let screen = NSScreen.main else { return }

        // Close any existing control window first
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

        // Use KeyableWindow for proper event handling
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
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        controlWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func hideRecordingControls() {
        guard let windowToClose = controlWindow else { return }
        controlWindow = nil

        // Hide window immediately but defer all cleanup to next run loop
        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func togglePause() {
        isPaused.toggle()
    }
}

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
            case .audio, .microphone:
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }
            @unknown default:
                break
            }
        }
    }

    func finish() async {
        // Cleanup if needed
    }
}

class GIFCaptureOutput: NSObject, SCStreamOutput {
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            onFrame(cgImage)
        }
    }
}

struct RecordingSelectionView: View {
    let onSelection: (CGRect) -> Void
    let onFullscreen: () -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint? = nil
    @State private var currentPoint: CGPoint? = nil

    init(onSelection: @escaping (CGRect) -> Void, onFullscreen: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onSelection = onSelection
        self.onFullscreen = onFullscreen
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)

            VStack(spacing: 20) {
                Text("Select Recording Area")
                    .font(.title)
                    .foregroundColor(.white)

                HStack(spacing: 16) {
                    Button("Record Fullscreen") {
                        onFullscreen()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct RecordingControlsView: View {
    @Binding var duration: TimeInterval
    @Binding var isPaused: Bool
    let onStop: () -> Void
    let onPause: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(isPaused ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: !isPaused)

            Text(formatDuration(duration))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            Button(action: onPause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
