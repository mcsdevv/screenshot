import Foundation

@MainActor
final class RecordingSessionModel: ObservableObject {
    @Published private(set) var state: RecordingSessionState = .idle
    @Published private(set) var elapsedDuration: TimeInterval = 0

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

    func beginSelection() throws {
        try transition(to: .selecting)
    }

    func beginStarting() throws {
        try transition(to: .starting)
    }

    func beginRecording() throws {
        try transition(to: .recording)
    }

    func beginStopping() throws {
        try transition(to: .stopping)
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

    func forceIdle() {
        stopTimer(resetDuration: true)
        state = .idle
    }

    private func handleTransition(to next: RecordingSessionState) {
        switch next {
        case .recording:
            startTimerIfNeeded()

        case .stopping, .completed, .failed, .cancelled:
            stopTimer(resetDuration: false)

        case .idle:
            stopTimer(resetDuration: true)

        case .selecting, .starting:
            stopTimer(resetDuration: true)
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
