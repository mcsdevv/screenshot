import Foundation
import Combine

enum CaptureEngineStatus: Equatable, Sendable {
    case idle
    case running
    case stopping
    case failed(String)
}

@MainActor
protocol CaptureEngine {
    var statusPublisher: AnyPublisher<CaptureEngineStatus, Never> { get }

    func start(config: RecordingConfig, outputURL: URL) async throws
    func stop() async throws -> URL
    func cancel() async
}
