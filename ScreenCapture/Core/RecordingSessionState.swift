import Foundation

enum RecordingSessionState: Equatable, Sendable {
    case idle
    case selecting
    case starting
    case recording
    case stopping
    case completed
    case failed(String)
    case cancelled
}

enum RecordingSessionTransitionError: Error, Equatable {
    case illegalTransition(from: RecordingSessionState, to: RecordingSessionState)
}

extension RecordingSessionState {
    func canTransition(to next: RecordingSessionState) -> Bool {
        switch (self, next) {
        case (.idle, .selecting),
             (.idle, .starting),
             (.idle, .idle):
            return true

        case (.selecting, .starting),
             (.selecting, .cancelled),
             (.selecting, .failed),
             (.selecting, .idle):
            return true

        case (.starting, .recording),
             (.starting, .cancelled),
             (.starting, .failed),
             (.starting, .idle):
            return true

        case (.recording, .stopping),
             (.recording, .failed),
             (.recording, .cancelled),
             (.recording, .idle):
            return true

        case (.stopping, .completed),
             (.stopping, .failed),
             (.stopping, .cancelled),
             (.stopping, .idle):
            return true

        case (.completed, .idle),
             (.failed, .idle),
             (.cancelled, .idle):
            return true

        default:
            return false
        }
    }
}
