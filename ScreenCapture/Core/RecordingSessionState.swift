import Foundation

enum RecordingSessionKind: String, Sendable {
    case video
    case gif
}

enum RecordingSessionState: Equatable, Sendable {
    case idle
    case selecting(RecordingSessionKind)
    case starting(RecordingSessionKind)
    case recording(RecordingSessionKind)
    case stopping(RecordingSessionKind)
    case exportingGIF
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

        case let (.selecting(current), .starting(nextKind)):
            return current == nextKind
        case (.selecting, .cancelled),
             (.selecting, .failed),
             (.selecting, .idle):
            return true

        case let (.starting(current), .recording(nextKind)):
            return current == nextKind
        case (.starting, .cancelled),
             (.starting, .failed),
             (.starting, .idle):
            return true

        case let (.recording(current), .stopping(nextKind)):
            return current == nextKind
        case (.recording, .failed),
             (.recording, .cancelled),
             (.recording, .idle):
            return true

        case (.stopping(.video), .completed):
            return true
        case (.stopping(.gif), .exportingGIF):
            return true
        case (.stopping, .failed),
             (.stopping, .cancelled),
             (.stopping, .idle):
            return true

        case (.exportingGIF, .completed),
             (.exportingGIF, .failed),
             (.exportingGIF, .cancelled),
             (.exportingGIF, .idle):
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
