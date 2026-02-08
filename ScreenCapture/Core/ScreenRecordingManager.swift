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
    static let recordWindowSelectionModeKey = "isSelectingRecordWindow"

    private struct PendingOutput {
        let temporaryURL: URL
        let finalURL: URL
    }

    private let storageManager: StorageManager

    private var captureEngine: CaptureEngine?
    private var currentConfig: RecordingConfig?
    private var activeCaptureOutput: PendingOutput?
    private var captureEngineStatusCancellable: AnyCancellable?
    private var isStoppingCapture = false

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published private(set) var sessionState: RecordingSessionState = .idle

    let sessionModel = RecordingSessionModel()

    private var cancellables = Set<AnyCancellable>()

    private var controlWindow: NSWindow?
    private var selectionWindow: NSWindow?
    private var recordingOverlayWindow: NSWindow?
    private var nativeWindowSelectionTask: Process?
    private var nativeWindowSelectionTempFile: URL?
    private var pendingRecordingTarget: RecordingTarget?
    private var pendingAreaRect: CGRect?
    private var isPreparingRecording = false
    private var pendingCountdownTask: Task<Void, Never>?
    private let controlsState = RecordingControlsStateModel()
    private var controlWindowOrigin: CGPoint?

    init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()
        setRecordWindowSelectionMode(false)
        bindSessionModel()
    }

    func toggleRecording() {
        if isPreparingRecording {
            cancelPendingRecordingPreparation()
            return
        }

        if isRecording {
            stopRecording()
        } else {
            startRecordingWithSelection()
        }
    }

    func startWindowRecordingSelection() {
        if isRecording {
            stopRecording()
            return
        }

        resetSelectionContextForModeSwitch(reason: "starting window recording selection")
        sessionModel.forceIdle()
        transitionSession { try sessionModel.beginSelection() }
        showWindowSelection()
    }

    func startFullscreenRecording() {
        if isRecording {
            stopRecording()
            return
        }

        resetSelectionContextForModeSwitch(reason: "starting fullscreen recording")
        sessionModel.forceIdle()
        transitionSession { try sessionModel.beginSelection() }
        prepareRecording(target: .fullscreen)
    }

    func stopActiveRecordingIfNeeded(reason: String = "termination", completion: (() -> Void)? = nil) {
        if isRecording {
            debugLog("Stopping screen recording due to \(reason)")
            stopRecording(completion: completion)
            return
        }

        if nativeWindowSelectionTask != nil {
            cancelNativeWindowSelection(reason: reason, updateSession: true)
            completion?()
            return
        }

        if isPreparingRecording {
            debugLog("Cancelling pending recording preparation due to \(reason)")
            cancelPendingRecordingPreparation()
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
        cancelNativeWindowSelection(reason: "reset active session", updateSession: false)
        captureEngineStatusCancellable = nil
        captureEngine = nil
        currentConfig = nil
        activeCaptureOutput = nil
        isStoppingCapture = false
        pendingCountdownTask?.cancel()
        pendingCountdownTask = nil
        pendingRecordingTarget = nil
        pendingAreaRect = nil
        isPreparingRecording = false
        controlsState.showRecordButton = false
        controlsState.countdownValue = nil
        controlWindowOrigin = nil
        isRecording = false
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
        resetSelectionContextForModeSwitch(reason: "starting area recording selection")
        sessionModel.forceIdle()
        transitionSession { try sessionModel.beginSelection() }
        showAreaSelection(onSelection: { [weak self] rect in
            self?.startRecording(in: rect)
        }, onCancel: { [weak self] in
            guard let self else { return }
            self.transitionSession { try self.sessionModel.markCancelled() }
            self.transitionSession { try self.sessionModel.markIdle() }
        })
    }

    private func resetSelectionContextForModeSwitch(reason: String) {
        closeSelectionWindow()
        cancelNativeWindowSelection(reason: reason, updateSession: false)

        guard isPreparingRecording else { return }

        pendingCountdownTask?.cancel()
        pendingCountdownTask = nil
        pendingRecordingTarget = nil
        pendingAreaRect = nil
        isPreparingRecording = false
        controlsState.showRecordButton = false
        controlsState.countdownValue = nil
        hideRecordingControls()
    }

    private func showAreaSelection(onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
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
        window.onEscapeKey = { [weak self] in
            self?.closeSelectionWindow()
            onCancel()
        }

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
        startNativeWindowSelection()
    }

    private func startNativeWindowSelection() {
        cancelNativeWindowSelection(reason: "starting new native window selection", updateSession: false)
        setRecordWindowSelectionMode(true)

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-window-selection-\(UUID().uuidString).png")
        nativeWindowSelectionTempFile = tempFile

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-w", "-o", "-x", tempFile.path]
        nativeWindowSelectionTask = task

        debugLog("Running native window picker for recording")

        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                let isCurrentTask = self.nativeWindowSelectionTask === task
                if isCurrentTask {
                    self.nativeWindowSelectionTask = nil
                    self.nativeWindowSelectionTempFile = nil
                    self.setRecordWindowSelectionMode(false)
                }

                guard isCurrentTask else {
                    try? FileManager.default.removeItem(at: tempFile)
                    return
                }

                defer { try? FileManager.default.removeItem(at: tempFile) }

                guard process.terminationStatus == 0 else {
                    self.handleNativeWindowSelectionCancelled()
                    return
                }

                let mouseLocation = NSEvent.mouseLocation
                guard let selectedWindowID = self.resolveSelectedWindowID(
                    mouseLocation: mouseLocation,
                    referenceImageURL: tempFile
                ) else {
                    self.presentRecordingAlert(
                        title: "Window Selection Failed",
                        message: "Unable to determine the selected window. Please try again."
                    )
                    self.handleNativeWindowSelectionCancelled()
                    return
                }

                self.startRecordingForWindowID(selectedWindowID)
            }
        }

        do {
            try task.run()
        } catch {
            errorLog("Failed to launch native window picker", error: error)
            try? FileManager.default.removeItem(at: tempFile)
            nativeWindowSelectionTask = nil
            nativeWindowSelectionTempFile = nil
            setRecordWindowSelectionMode(false)
            presentRecordingAlert(
                title: "Window Selection Failed",
                message: "Unable to open the native window selector."
            )
            handleNativeWindowSelectionCancelled()
        }
    }

    private func cancelNativeWindowSelection(reason: String, updateSession: Bool) {
        guard nativeWindowSelectionTask != nil || nativeWindowSelectionTempFile != nil else { return }

        debugLog("Cancelling native window selection (\(reason))")
        if let task = nativeWindowSelectionTask, task.isRunning {
            task.terminate()
        }
        nativeWindowSelectionTask = nil

        if let tempFile = nativeWindowSelectionTempFile {
            try? FileManager.default.removeItem(at: tempFile)
        }
        nativeWindowSelectionTempFile = nil
        setRecordWindowSelectionMode(false)

        if updateSession {
            handleNativeWindowSelectionCancelled()
        }
    }

    private func setRecordWindowSelectionMode(_ isSelecting: Bool) {
        UserDefaults.standard.set(isSelecting, forKey: Self.recordWindowSelectionModeKey)
    }

    private func handleNativeWindowSelectionCancelled() {
        transitionSession { try sessionModel.markCancelled() }
        transitionSession { try sessionModel.markIdle() }
    }

    private func resolveSelectedWindowID(mouseLocation: CGPoint, referenceImageURL: URL) -> UInt32? {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
        let flippedMouse = CGPoint(x: mouseLocation.x, y: desktopFrame.maxY - mouseLocation.y)
        let referenceSize = referenceImageSize(at: referenceImageURL)
        var sizeMatchedFallback: UInt32?

        for windowInfo in windowInfoList {
            guard
                let windowIDNumber = windowInfo[kCGWindowNumber as String] as? NSNumber,
                let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPIDNumber.int32Value != ownPID,
                let layerNumber = windowInfo[kCGWindowLayer as String] as? NSNumber,
                layerNumber.intValue == 0,
                let boundsDict = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 1,
                bounds.height > 1
            else {
                continue
            }

            if bounds.contains(mouseLocation) || bounds.contains(flippedMouse) {
                return windowIDNumber.uint32Value
            }

            if sizeMatchedFallback == nil, let referenceSize {
                let widthMatches = abs(bounds.width - referenceSize.width) <= 2
                let heightMatches = abs(bounds.height - referenceSize.height) <= 2
                if widthMatches && heightMatches {
                    sizeMatchedFallback = windowIDNumber.uint32Value
                }
            }
        }

        return sizeMatchedFallback
    }

    private func referenceImageSize(at url: URL) -> CGSize? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return image.size
    }

    private func startRecordingForWindowID(_ windowID: UInt32) {
        prepareRecording(target: .window(windowID: windowID))
    }

    // MARK: - Session Start

    private func startRecording(in rect: CGRect) {
        prepareRecording(target: .area(rect.standardized))
    }

    private func prepareRecording(target: RecordingTarget) {
        pendingRecordingTarget = target
        isPreparingRecording = true
        pendingCountdownTask?.cancel()
        pendingCountdownTask = nil
        controlsState.showRecordButton = true
        controlsState.countdownValue = nil
        controlWindowOrigin = nil

        switch target {
        case let .area(rect):
            pendingAreaRect = rect.standardized
            showAdjustableRecordingOverlay(for: rect.standardized)
        case .fullscreen, .window:
            pendingAreaRect = nil
            hideRecordingOverlay()
        }

        showRecordingControls(showRecordButton: true)
    }

    private func beginPendingRecordingCountdown() {
        guard isPreparingRecording, controlsState.showRecordButton else { return }
        guard pendingCountdownTask == nil else { return }

        pendingCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for countdownValue in stride(from: 3, through: 1, by: -1) {
                guard self.isPreparingRecording else {
                    self.pendingCountdownTask = nil
                    return
                }

                self.controlsState.countdownValue = countdownValue

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    self.pendingCountdownTask = nil
                    return
                }
            }

            self.pendingCountdownTask = nil
            self.controlsState.countdownValue = nil
            self.startPreparedRecording()
        }
    }

    private func startPreparedRecording() {
        guard isPreparingRecording, let pendingTarget = pendingRecordingTarget else { return }

        var resolvedTarget = pendingTarget
        if case .area = pendingTarget, let pendingAreaRect {
            resolvedTarget = .area(pendingAreaRect.standardized)
        }

        isPreparingRecording = false
        pendingRecordingTarget = nil
        controlsState.showRecordButton = false
        controlsState.countdownValue = nil
        startCaptureSession(target: resolvedTarget)
    }

    private func cancelPendingRecordingPreparation() {
        pendingCountdownTask?.cancel()
        pendingCountdownTask = nil
        pendingRecordingTarget = nil
        isPreparingRecording = false
        pendingAreaRect = nil
        controlsState.showRecordButton = false
        controlsState.countdownValue = nil
        hideRecordingControls()

        if sessionModel.state != .idle {
            transitionSession { try sessionModel.markCancelled() }
            transitionSession { try sessionModel.markIdle() }
        }
    }

    private func startCaptureSession(target: RecordingTarget) {
        Task {
            transitionSession { try sessionModel.beginStarting() }

            do {
                let config = RecordingConfig.resolve(target: target)
                let pendingOutput = try prepareCaptureOutput()
                let engine = makeCaptureEngine()

                try await engine.start(config: config, outputURL: pendingOutput.temporaryURL)
                bindCaptureEngineStatus(engine)

                captureEngine = engine
                currentConfig = config
                activeCaptureOutput = pendingOutput

                isRecording = true
                isPreparingRecording = false
                pendingRecordingTarget = nil
                pendingAreaRect = nil
                pendingCountdownTask?.cancel()
                pendingCountdownTask = nil
                controlsState.showRecordButton = false
                controlsState.countdownValue = nil

                transitionSession { try sessionModel.beginRecording() }
                showRecordingControls(showRecordButton: false)
                NotificationCenter.default.post(name: .recordingStarted, object: nil)

                debugLog("Recording session started: output=\(pendingOutput.temporaryURL.lastPathComponent)")
            } catch {
                hideRecordingControls()
                resetActiveSessionRuntime()
                failSession("Failed to start recording", error: error)
                presentRecordingAlert(title: "Recording Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Session Stop

    private func stopRecording(completion: (() -> Void)? = nil) {
        Task {
            isStoppingCapture = true
            defer {
                isStoppingCapture = false
                completion?()
            }

            transitionSession { try sessionModel.beginStopping() }

            guard let captureEngine, let pendingCaptureOutput = activeCaptureOutput else {
                failSession("No active recording session to stop")
                hideRecordingControls()
                resetActiveSessionRuntime()
                return
            }

            do {
                _ = try await captureEngine.stop()
                NotificationCenter.default.post(name: .recordingStopped, object: nil)

                let finalURL = try finalizeAtomicOutput(pendingCaptureOutput)
                try await validateVideoOutputFile(finalURL)

                transitionSession { try sessionModel.markCompleted() }
                transitionSession { try sessionModel.markIdle() }

                hideRecordingControls()
                resetActiveSessionRuntime()

                let capture = storageManager.saveRecording(url: finalURL)
                NotificationCenter.default.post(name: .recordingCompleted, object: capture)
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

    private func prepareCaptureOutput() throws -> PendingOutput {
        try prepareAtomicOutput(finalURL: storageManager.generateRecordingURL())
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
            _ = try await generator.generateCGImageAsync(at: probeTime)
        } catch {
            throw CaptureEngineError.outputFileInvalid(url, reason: "First-frame decode failed (\(describe(error: error)))")
        }
    }

    private func describe(error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    private func makeCaptureEngine() -> CaptureEngine {
        #if compiler(>=6.0)
        return SCRecordingOutputEngine()
        #else
        // Xcode 15/Swift 5 toolchains cannot compile SCRecordingOutputEngine.
        // Fall back to the AVAssetWriter engine so CI can still build.
        return AVAssetWriterCaptureEngine()
        #endif
    }

    private func bindCaptureEngineStatus(_ engine: CaptureEngine) {
        captureEngineStatusCancellable = engine.statusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleCaptureEngineStatus(status)
            }
    }

    private func handleCaptureEngineStatus(_ status: CaptureEngineStatus) {
        guard case .failed(let message) = status else { return }
        guard !isStoppingCapture else { return }
        guard sessionModel.state != .idle else { return }

        let reason = message.isEmpty ? "Unknown recording engine error." : message
        errorLog("Capture engine failed: \(reason)")

        discardPendingOutputArtifacts(activeCaptureOutput)
        hideRecordingControls()
        resetActiveSessionRuntime()
        failSession("Recording engine failed")
        presentRecordingAlert(title: "Recording Failed", message: reason)
    }

    // MARK: - Recording Controls

    private func showRecordingControls(showRecordButton: Bool) {
        guard let screen = controlsScreen() else { return }

        controlsState.showRecordButton = showRecordButton
        if !showRecordButton {
            controlsState.countdownValue = nil
        }

        hideControlWindow(resetPosition: false)

        let controlView = RecordingControlsView(
            session: sessionModel,
            controlsState: controlsState,
            onRecord: { [weak self] in
                self?.beginPendingRecordingCountdown()
            },
            onStop: { [weak self] in
                self?.handleControlStopTapped()
            }
        )

        let hostingView = NSHostingView(rootView: controlView)
        let controlSize = NSSize(width: 360, height: 74)
        hostingView.frame = NSRect(origin: .zero, size: controlSize)

        let defaultOrigin = CGPoint(
            x: screen.frame.midX - controlSize.width / 2,
            y: screen.visibleFrame.minY + 20
        )
        let origin = controlWindowOrigin ?? defaultOrigin

        let window = KeyableWindow(
            contentRect: NSRect(origin: origin, size: controlSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = showRecordButton
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : .floating
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if showRecordButton {
            window.onEscapeKey = { [weak self] in
                self?.cancelPendingRecordingPreparation()
            }
        }

        controlWindow = window
        controlWindowOrigin = origin

        window.makeKeyAndOrderFront(nil)

        if !showRecordButton {
            showRecordingOverlay()
        }
    }

    private func handleControlStopTapped() {
        if isPreparingRecording {
            cancelPendingRecordingPreparation()
            return
        }

        if isRecording {
            stopRecording()
        }
    }

    private func controlsScreen() -> NSScreen? {
        if let pendingRecordingTarget {
            switch pendingRecordingTarget {
            case .fullscreen:
                return currentInteractionScreen()
            case .window:
                return NSScreen.main ?? NSScreen.screens.first
            case .area:
                if let pendingAreaRect, let areaScreen = screenContaining(pendingAreaRect) {
                    return areaScreen
                }
            }
        }

        if let pendingAreaRect, let areaScreen = screenContaining(pendingAreaRect) {
            return areaScreen
        }

        return recordingScreen() ?? currentInteractionScreen()
    }

    private func showAdjustableRecordingOverlay(for rect: CGRect) {
        guard let screen = screenContaining(rect) ?? currentInteractionScreen() else { return }

        hideRecordingOverlay()

        let overlayView = AdjustableRecordingOverlayView(
            initialRect: rect,
            screenFrame: screen.frame
        ) { [weak self] updatedRect in
            self?.pendingAreaRect = updatedRect.standardized
        }
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
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        recordingOverlayWindow = window
        window.makeKeyAndOrderFront(nil)
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

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
        hideControlWindow(resetPosition: true)
    }

    private func hideControlWindow(resetPosition: Bool) {
        guard let windowToClose = controlWindow else { return }
        controlWindow = nil

        windowToClose.orderOut(nil)

        Task { @MainActor in
            windowToClose.contentView = nil
            windowToClose.close()
        }

        if resetPosition {
            controlWindowOrigin = nil
        } else {
            controlWindowOrigin = windowToClose.frame.origin
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

#if DEBUG
extension ScreenRecordingManager {
    var hasSelectionWindowForTesting: Bool {
        selectionWindow != nil
    }

    var isPreparingRecordingForTesting: Bool {
        isPreparingRecording
    }

    func installSelectionWindowForTesting(_ window: NSWindow) {
        selectionWindow = window
    }

    var pendingRecordingTargetForTesting: RecordingTarget? {
        pendingRecordingTarget
    }

    var isRecordButtonVisibleForTesting: Bool {
        controlsState.showRecordButton
    }

    var hasPendingCountdownTaskForTesting: Bool {
        pendingCountdownTask != nil
    }

    func prepareWindowRecordingForTesting(windowID: UInt32) {
        startRecordingForWindowID(windowID)
    }

    func beginPendingRecordingCountdownForTesting() {
        beginPendingRecordingCountdown()
    }

    func cancelPendingRecordingPreparationForTesting() {
        cancelPendingRecordingPreparation()
    }
}
#endif

private enum AVAssetImageGeneratorAsyncError: Error {
    case imageUnavailable
}

extension AVAssetImageGenerator {
    func generateCGImageAsync(at requestedTime: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generateCGImageAsynchronously(for: requestedTime) { image, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: AVAssetImageGeneratorAsyncError.imageUnavailable)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}
