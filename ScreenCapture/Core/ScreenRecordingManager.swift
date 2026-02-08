import AppKit
import SwiftUI
import ScreenCaptureKit
import Combine
import AVFoundation

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
class ScreenRecordingManager: NSObject, ObservableObject {
    private struct PendingOutput {
        let temporaryURL: URL
        let finalURL: URL
    }

    private let storageManager: StorageManager
    private let gifExportService = GIFExportService()

    private var captureEngine: CaptureEngine?
    private var currentConfig: RecordingConfig?
    private var activeMode: RecordingMode?
    private var activeCaptureOutput: PendingOutput?
    private var gifExportTask: Task<Void, Never>?

    @Published var isRecording = false
    @Published var isGIFRecording = false
    @Published private(set) var isExportingGIF = false
    @Published var recordingDuration: TimeInterval = 0
    @Published private(set) var sessionState: RecordingSessionState = .idle

    let sessionModel = RecordingSessionModel()

    private var cancellables = Set<AnyCancellable>()

    private var controlWindow: NSWindow?
    private var selectionWindow: NSWindow?
    private var windowSelectionWindow: NSWindow?
    private var recordingOverlayWindow: NSWindow?
    private var pendingRecordingMode: RecordingMode = .video

    private enum RecordingMode {
        case video
        case gif

        var sessionKind: RecordingSessionKind {
            switch self {
            case .video:
                return .video
            case .gif:
                return .gif
            }
        }

        var outputMode: RecordingOutputMode {
            switch self {
            case .video:
                return .video
            case .gif:
                return .gif
            }
        }
    }

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
        bindSessionModel()
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
            return
        }

        if isRecording {
            debugLog("Stopping screen recording due to \(reason)")
            stopRecording(completion: completion)
            return
        }

        if isExportingGIF {
            debugLog("Cancelling GIF export due to \(reason)")
            gifExportTask?.cancel()
            isExportingGIF = false
            transitionSession { try sessionModel.markCancelled() }
            transitionSession { try sessionModel.markIdle() }
            hideRecordingControls()
            completion?()
            return
        }

        completion?()
    }

    private func bindSessionModel() {
        sessionModel.$elapsedDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                self?.recordingDuration = duration
            }
            .store(in: &cancellables)

        sessionModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.sessionState = state
            }
            .store(in: &cancellables)
    }

    private func transitionSession(_ transition: () throws -> Void) {
        do {
            try transition()
        } catch {
            errorLog("Invalid recording session transition", error: error)
        }
    }

    private func failSession(_ message: String, error: Error? = nil) {
        if let error {
            errorLog(message, error: error)
        } else {
            errorLog(message)
        }

        guard sessionModel.state != .idle else { return }
        transitionSession { try sessionModel.markFailed(message) }
        transitionSession { try sessionModel.markIdle() }
    }

    private func resetActiveSessionRuntime() {
        captureEngine = nil
        currentConfig = nil
        activeMode = nil
        activeCaptureOutput = nil
        gifExportTask = nil
        isRecording = false
        isGIFRecording = false
        isExportingGIF = false
    }

    private func presentRecordingAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Selection Flow

    private func startRecordingWithSelection() {
        sessionModel.forceIdle()
        transitionSession { try sessionModel.beginSelection(for: .video) }
        pendingRecordingMode = .video
        showAreaSelection(onSelection: { [weak self] rect in
            self?.startRecording(in: rect)
        }, onCancel: { [weak self] in
            guard let self else { return }
            self.transitionSession { try self.sessionModel.markCancelled() }
            self.transitionSession { try self.sessionModel.markIdle() }
        })
    }

    private func startGIFRecordingWithSelection() {
        sessionModel.forceIdle()
        transitionSession { try sessionModel.beginSelection(for: .gif) }
        pendingRecordingMode = .gif
        showAreaSelection(onSelection: { [weak self] rect in
            self?.startGIFRecording(in: rect)
        }, onCancel: { [weak self] in
            guard let self else { return }
            self.transitionSession { try self.sessionModel.markCancelled() }
            self.transitionSession { try self.sessionModel.markIdle() }
        })
    }

    private func showAreaSelection(onSelection: @escaping (CGRect?) -> Void, onCancel: @escaping () -> Void) {
        closeSelectionWindow()

        guard let screen = currentInteractionScreen() else {
            onCancel()
            return
        }

        let selectionView = RecordingSelectionView(
            onSelection: { [weak self] rect in
                self?.closeSelectionWindow()
                onSelection(rect)
            },
            onFullscreen: { [weak self] in
                self?.closeSelectionWindow()
                onSelection(nil)
            },
            onWindowSelect: { [weak self] in
                self?.closeSelectionWindow()
                self?.showWindowSelection()
            },
            onCancel: { [weak self] in
                self?.closeSelectionWindow()
                onCancel()
            }
        )

        let hostingView = FirstMouseHostingView(rootView: selectionView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
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
        guard let screen = currentInteractionScreen() else { return }

        let windowView = WindowSelectionView(
            onWindowSelected: { [weak self] window in
                self?.closeWindowSelectionWindow()
                self?.startRecordingForWindow(window)
            },
            onCancel: { [weak self] in
                self?.closeWindowSelectionWindow()
                guard let self else { return }
                self.transitionSession { try self.sessionModel.markCancelled() }
                self.transitionSession { try self.sessionModel.markIdle() }
            }
        )

        let hostingView = FirstMouseHostingView(rootView: windowView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver

        windowSelectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
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

    // MARK: - Session Start

    private func startRecording(in rect: CGRect?) {
        let target: RecordingTarget = rect.map { .area($0) } ?? .fullscreen
        startCaptureSession(mode: .video, target: target)
    }

    private func startRecording(window scWindow: SCWindow) {
        startCaptureSession(mode: .video, target: .window(windowID: scWindow.windowID))
    }

    private func startGIFRecording(in rect: CGRect?) {
        let target: RecordingTarget = rect.map { .area($0) } ?? .fullscreen
        startCaptureSession(mode: .gif, target: target)
    }

    private func startGIFRecording(window scWindow: SCWindow) {
        startCaptureSession(mode: .gif, target: .window(windowID: scWindow.windowID))
    }

    private func startCaptureSession(mode: RecordingMode, target: RecordingTarget) {
        Task {
            transitionSession { try sessionModel.beginStarting(for: mode.sessionKind) }

            do {
                let config = RecordingConfig.resolve(mode: mode.outputMode, target: target)
                let pendingOutput = try prepareCaptureOutput(for: mode)
                let engine = makeCaptureEngine()

                try await engine.start(config: config, outputURL: pendingOutput.temporaryURL)

                captureEngine = engine
                currentConfig = config
                activeMode = mode
                activeCaptureOutput = pendingOutput

                isRecording = mode == .video
                isGIFRecording = mode == .gif
                isExportingGIF = false

                transitionSession { try sessionModel.beginRecording(for: mode.sessionKind) }
                showRecordingControls()
                NotificationCenter.default.post(name: .recordingStarted, object: nil)

                debugLog("Recording session started: mode=\(mode.outputMode.rawValue), output=\(pendingOutput.temporaryURL.lastPathComponent)")
            } catch {
                hideRecordingControls()
                resetActiveSessionRuntime()
                failSession("Failed to start \(mode.outputMode.rawValue) recording", error: error)
                presentRecordingAlert(title: "Recording Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Session Stop

    private func stopRecording(completion: (() -> Void)? = nil) {
        stopCaptureSession(mode: .video, completion: completion)
    }

    private func stopGIFRecording(completion: (() -> Void)? = nil) {
        stopCaptureSession(mode: .gif, completion: completion)
    }

    private func stopCaptureSession(mode: RecordingMode, completion: (() -> Void)? = nil) {
        Task {
            defer { completion?() }

            transitionSession { try sessionModel.beginStopping(for: mode.sessionKind) }

            guard let captureEngine, let pendingCaptureOutput = activeCaptureOutput else {
                failSession("No active recording session to stop")
                hideRecordingControls()
                resetActiveSessionRuntime()
                return
            }

            do {
                _ = try await captureEngine.stop()
                NotificationCenter.default.post(name: .recordingStopped, object: nil)

                switch mode {
                case .video:
                    let finalURL = try finalizeAtomicOutput(pendingCaptureOutput)
                    try await validateVideoOutputFile(finalURL)

                    transitionSession { try sessionModel.markCompleted() }
                    transitionSession { try sessionModel.markIdle() }

                    hideRecordingControls()
                    resetActiveSessionRuntime()

                    let capture = storageManager.saveRecording(url: finalURL)
                    NotificationCenter.default.post(name: .recordingCompleted, object: capture)

                case .gif:
                    isGIFRecording = false
                    isExportingGIF = true
                    transitionSession { try sessionModel.beginGIFExport() }

                    let sourceVideoURL = try finalizeAtomicOutput(pendingCaptureOutput)
                    try await validateVideoOutputFile(sourceVideoURL)
                    let gifOutput = try prepareAtomicOutput(finalURL: storageManager.generateGIFURL())
                    let gifFPS = currentConfig?.fps ?? 15
                    let gifQuality = currentConfig?.gifExportQuality ?? .medium

                    gifExportTask = Task { @MainActor [weak self] in
                        guard let self else { return }

                        do {
                            try await self.gifExportService.exportGIF(
                                from: sourceVideoURL,
                                to: gifOutput.temporaryURL,
                                fps: gifFPS,
                                quality: gifQuality,
                                onProgress: { snapshot in
                                    self.sessionModel.updateGIFExportProgress(snapshot.progress)
                                }
                            )

                            let finalizedGIFURL = try self.finalizeAtomicOutput(gifOutput)
                            try? FileManager.default.removeItem(at: sourceVideoURL)

                            self.transitionSession { try self.sessionModel.markCompleted() }
                            self.transitionSession { try self.sessionModel.markIdle() }

                            self.hideRecordingControls()
                            self.resetActiveSessionRuntime()

                            let capture = self.storageManager.saveGIF(url: finalizedGIFURL)
                            NotificationCenter.default.post(name: .recordingCompleted, object: capture)

                            debugLog("GIF export finished: \(finalizedGIFURL.lastPathComponent)")
                        } catch {
                            self.isExportingGIF = false
                            self.hideRecordingControls()
                            self.resetActiveSessionRuntime()

                            self.failSession("GIF export failed", error: error)

                            let message = "GIF export failed. \(error.localizedDescription)\n\nThe source video was preserved at:\n\(sourceVideoURL.path)"
                            self.presentRecordingAlert(title: "GIF Export Failed", message: message)
                        }
                    }

                    await gifExportTask?.value
                    gifExportTask = nil
                }
            } catch {
                await captureEngine.cancel()
                discardPendingOutputArtifacts(activeCaptureOutput)
                hideRecordingControls()
                resetActiveSessionRuntime()
                failSession("Failed to stop recording", error: error)
                presentRecordingAlert(title: "Stop Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - File Output

    private func prepareCaptureOutput(for mode: RecordingMode) throws -> PendingOutput {
        switch mode {
        case .video:
            return try prepareAtomicOutput(finalURL: storageManager.generateRecordingURL())
        case .gif:
            return try prepareAtomicOutput(finalURL: temporaryGIFSourceVideoURL())
        }
    }

    private func prepareAtomicOutput(finalURL: URL) throws -> PendingOutput {
        let directory = finalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryFilename = ".partial-\(UUID().uuidString)-\(finalURL.lastPathComponent)"
        let temporaryURL = directory.appendingPathComponent(temporaryFilename)

        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }

        return PendingOutput(temporaryURL: temporaryURL, finalURL: finalURL)
    }

    private func finalizeAtomicOutput(_ pendingOutput: PendingOutput) throws -> URL {
        guard FileManager.default.fileExists(atPath: pendingOutput.temporaryURL.path) else {
            throw CaptureEngineError.outputFileMissing(pendingOutput.temporaryURL)
        }

        if FileManager.default.fileExists(atPath: pendingOutput.finalURL.path) {
            try FileManager.default.removeItem(at: pendingOutput.finalURL)
        }

        try FileManager.default.moveItem(at: pendingOutput.temporaryURL, to: pendingOutput.finalURL)
        return pendingOutput.finalURL
    }

    private func discardPendingOutputArtifacts(_ pendingOutput: PendingOutput?) {
        guard let pendingOutput else { return }

        if FileManager.default.fileExists(atPath: pendingOutput.temporaryURL.path) {
            try? FileManager.default.removeItem(at: pendingOutput.temporaryURL)
        }
    }

    private func validateVideoOutputFile(_ url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CaptureEngineError.outputFileMissing(url)
        }

        let fileSize: Int64
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let sizeNumber = attributes[.size] as? NSNumber {
            fileSize = sizeNumber.int64Value
        } else {
            fileSize = 0
        }

        guard fileSize > 0 else {
            throw CaptureEngineError.outputFileInvalid(url, reason: "File is empty")
        }

        let asset = AVURLAsset(url: url)

        let duration: CMTime
        let isPlayable: Bool
        let hasVideoTrack: Bool

        do {
            if #available(macOS 13.0, *) {
                duration = try await asset.load(.duration)
                isPlayable = try await asset.load(.isPlayable)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                hasVideoTrack = !videoTracks.isEmpty
            } else {
                duration = asset.duration
                isPlayable = asset.isPlayable
                hasVideoTrack = !asset.tracks(withMediaType: .video).isEmpty
            }
        } catch {
            throw CaptureEngineError.outputFileInvalid(url, reason: "Unable to parse video metadata (\(describe(error: error)))")
        }

        guard hasVideoTrack else {
            throw CaptureEngineError.outputFileInvalid(url, reason: "No video track")
        }

        guard duration.isValid, duration.seconds.isFinite, duration.seconds > 0 else {
            throw CaptureEngineError.outputFileInvalid(url, reason: "Missing or invalid duration")
        }

        guard isPlayable else {
            throw CaptureEngineError.outputFileInvalid(url, reason: "Asset is not playable")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let probeTime = CMTime(seconds: min(duration.seconds * 0.05, max(duration.seconds - 0.001, 0)), preferredTimescale: 600)

        do {
            _ = try generator.copyCGImage(at: probeTime, actualTime: nil)
        } catch {
            throw CaptureEngineError.outputFileInvalid(url, reason: "First-frame decode failed (\(describe(error: error)))")
        }
    }

    private func describe(error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    private func temporaryGIFSourceVideoURL() -> URL {
        storageManager.screenshotsDirectory
            .appendingPathComponent(".gif-source-\(UUID().uuidString).mp4")
    }

    private func makeCaptureEngine() -> CaptureEngine {
        // Prefer native ScreenCaptureKit recording output on macOS 15+.
        // AVAssetWriter has shown intermittent output routing and stability issues.
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            return SCRecordingOutputEngine()
        }
        #endif

        return AVAssetWriterCaptureEngine()
    }

    // MARK: - Recording Controls

    private func showRecordingControls() {
        guard let screen = recordingScreen() ?? currentInteractionScreen() else { return }

        hideRecordingControls()

        let controlView = RecordingControlsView(
            session: sessionModel,
            onStop: { [weak self] in
                guard let self else { return }
                if self.isGIFRecording {
                    self.stopGIFRecording()
                } else if self.isRecording {
                    self.stopRecording()
                }
            }
        )

        let hostingView = NSHostingView(rootView: controlView)
        let controlSize = NSSize(width: 300, height: 70)
        hostingView.frame = NSRect(origin: .zero, size: controlSize)

        let centerX = screen.frame.midX - controlSize.width / 2
        let bottomY = screen.visibleFrame.minY + 20

        let window = KeyableWindow(
            contentRect: NSRect(x: centerX, y: bottomY, width: controlSize.width, height: controlSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        controlWindow = window
        window.makeKeyAndOrderFront(nil)

        showRecordingOverlay()
    }

    private func showRecordingOverlay() {
        guard case .area(let rect) = currentConfig?.target else { return }
        guard let screen = screenContaining(rect) ?? recordingScreen() ?? currentInteractionScreen() else { return }

        hideRecordingOverlay()

        let overlayView = RecordingOverlayView(recordingRect: rect, screenFrame: screen.frame)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        recordingOverlayWindow = window
        window.orderBack(nil)
    }

    private func hideRecordingOverlay() {
        guard let windowToClose = recordingOverlayWindow else { return }
        recordingOverlayWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func hideRecordingControls() {
        hideRecordingOverlay()

        guard let windowToClose = controlWindow else { return }
        controlWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func currentInteractionScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func recordingScreen() -> NSScreen? {
        guard let target = currentConfig?.target else {
            return nil
        }

        switch target {
        case .fullscreen:
            return currentInteractionScreen()

        case .window:
            return NSScreen.main ?? NSScreen.screens.first

        case let .area(rect):
            return screenContaining(rect)
        }
    }

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let directMatch = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return directMatch
        }

        var bestScreen: NSScreen?
        var bestIntersectionArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            guard !intersection.isNull else { continue }

            let area = max(0, intersection.width) * max(0, intersection.height)
            if area > bestIntersectionArea {
                bestIntersectionArea = area
                bestScreen = screen
            }
        }

        return bestScreen
    }
}
