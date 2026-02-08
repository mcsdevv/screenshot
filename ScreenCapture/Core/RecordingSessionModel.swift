import Foundation

@MainActor
final class RecordingSessionModel: ObservableObject {
    @Published private(set) var state: RecordingSessionState = .idle
    @Published private(set) var elapsedDuration: TimeInterval = 0
    @Published private(set) var gifExportProgress: Double = 0

    private var timer: Timer?
    private var recordingStartUptime: TimeInterval?

    deinit {
        timer?.invalidate()
    }

    func transition(to next: RecordingSessionState) throws {
        guard state.canTransition(to: next) else {
            throw RecordingSessionTransitionError.illegalTransition(from: state, to: next)
        }

        state = next
        handleTransition(to: next)
    }

    func beginSelection(for kind: RecordingSessionKind) throws {
        try transition(to: .selecting(kind))
    }

    func beginStarting(for kind: RecordingSessionKind) throws {
        try transition(to: .starting(kind))
    }

    func beginRecording(for kind: RecordingSessionKind) throws {
        try transition(to: .recording(kind))
    }

    func beginStopping(for kind: RecordingSessionKind) throws {
        try transition(to: .stopping(kind))
    }

    func beginGIFExport() throws {
        try transition(to: .exportingGIF)
    }

    func markCompleted() throws {
        try transition(to: .completed)
    }

    func markFailed(_ message: String) throws {
        try transition(to: .failed(message))
    }

    func markCancelled() throws {
        try transition(to: .cancelled)
    }

    func markIdle() throws {
        try transition(to: .idle)
    }

    func updateGIFExportProgress(_ progress: Double) {
        gifExportProgress = min(max(progress, 0), 1)
    }

    func forceIdle() {
        stopTimer(resetDuration: true)
        gifExportProgress = 0
        state = .idle
    }

    private func handleTransition(to next: RecordingSessionState) {
        switch next {
        case .recording:
            startTimerIfNeeded()

        case .stopping, .completed, .failed, .cancelled:
            stopTimer(resetDuration: false)

        case .exportingGIF:
            stopTimer(resetDuration: false)
            gifExportProgress = 0

        case .idle:
            stopTimer(resetDuration: true)
            gifExportProgress = 0

        case .selecting, .starting:
            stopTimer(resetDuration: true)
            gifExportProgress = 0
        }
    }

    private func startTimerIfNeeded() {
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        elapsedDuration = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshElapsedDuration()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshElapsedDuration() {
        guard let recordingStartUptime else {
            elapsedDuration = 0
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        elapsedDuration = max(0, now - recordingStartUptime)
    }

    private func stopTimer(resetDuration: Bool) {
        timer?.invalidate()
        timer = nil
        recordingStartUptime = nil

        if resetDuration {
            elapsedDuration = 0
        }
    }
}
