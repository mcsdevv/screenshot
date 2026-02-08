import Foundation
import AVFoundation

enum GIFExportError: LocalizedError {
    case ffmpegNotInstalled
    case sourceMissing(URL)
    case paletteGenerationFailed(String)
    case gifEncodingFailed(String)
    case outputMissing(URL)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotInstalled:
            return "ffmpeg was not found. Install it (for example with Homebrew: brew install ffmpeg) and retry GIF export."
        case let .sourceMissing(url):
            return "Source recording is missing: \(url.path)"
        case let .paletteGenerationFailed(message):
            return "Palette generation failed: \(message)"
        case let .gifEncodingFailed(message):
            return "GIF encoding failed: \(message)"
        case let .outputMissing(url):
            return "GIF export completed but no output file was found at \(url.path)."
        }
    }
}

@MainActor
final class GIFExportService {
    private final class FFmpegParseState {
        private let lock = NSLock()
        private var stderrBuffer = ""
        private var partialLineBuffer = ""

        func appendAndExtractLines(_ chunk: String) -> [String] {
            lock.lock()
            defer { lock.unlock() }

            stderrBuffer += chunk
            partialLineBuffer += chunk

            let lines = partialLineBuffer.components(separatedBy: "\n")
            partialLineBuffer = lines.last ?? ""
            return Array(lines.dropLast())
        }

        func fullStderr() -> String {
            lock.lock()
            defer { lock.unlock() }
            return stderrBuffer
        }
    }

    struct ProgressSnapshot: Sendable {
        let stage: String
        let progress: Double
    }

    private struct FFmpegResult {
        let exitCode: Int32
        let stderr: String
    }

    func exportGIF(
        from sourceVideoURL: URL,
        to outputGIFURL: URL,
        fps: Int,
        quality: GIFExportQualityPreset,
        onProgress: ((ProgressSnapshot) -> Void)? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: sourceVideoURL.path) else {
            throw GIFExportError.sourceMissing(sourceVideoURL)
        }

        let ffmpegURL = try resolveFFmpegURL()
        let totalDuration = max(0.1, await videoDurationSeconds(for: sourceVideoURL))
        let targetWidth = quality.targetWidth ?? 1_280

        let paletteURL = outputGIFURL.deletingLastPathComponent().appendingPathComponent("palette-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: paletteURL) }

        onProgress?(ProgressSnapshot(stage: "Preparing", progress: 0.0))

        let paletteFilter = "fps=\(fps),scale=\(targetWidth):-1:flags=lanczos,palettegen=stats_mode=diff"
        let paletteArgs = [
            "-y",
            "-i", sourceVideoURL.path,
            "-vf", paletteFilter,
            "-progress", "pipe:2",
            "-nostats",
            paletteURL.path
        ]

        let paletteResult = try await runFFmpeg(
            executableURL: ffmpegURL,
            arguments: paletteArgs,
            totalDuration: totalDuration,
            stageLabel: "Generating Palette"
        ) { stageProgress in
            onProgress?(ProgressSnapshot(stage: "Generating Palette", progress: stageProgress * 0.40))
        }

        guard paletteResult.exitCode == 0 else {
            throw GIFExportError.paletteGenerationFailed(paletteResult.stderr)
        }

        onProgress?(ProgressSnapshot(stage: "Encoding GIF", progress: 0.40))

        let encodeFilter = "fps=\(fps),scale=\(targetWidth):-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
        let encodeArgs = [
            "-y",
            "-i", sourceVideoURL.path,
            "-i", paletteURL.path,
            "-lavfi", encodeFilter,
            "-progress", "pipe:2",
            "-nostats",
            outputGIFURL.path
        ]

        let encodeResult = try await runFFmpeg(
            executableURL: ffmpegURL,
            arguments: encodeArgs,
            totalDuration: totalDuration,
            stageLabel: "Encoding GIF"
        ) { stageProgress in
            let overall = 0.40 + (stageProgress * 0.60)
            onProgress?(ProgressSnapshot(stage: "Encoding GIF", progress: overall))
        }

        guard encodeResult.exitCode == 0 else {
            throw GIFExportError.gifEncodingFailed(encodeResult.stderr)
        }

        guard FileManager.default.fileExists(atPath: outputGIFURL.path) else {
            throw GIFExportError.outputMissing(outputGIFURL)
        }

        onProgress?(ProgressSnapshot(stage: "Done", progress: 1.0))
    }

    private func resolveFFmpegURL() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "ffmpeg"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GIFExportError.ffmpegNotInstalled
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw GIFExportError.ffmpegNotInstalled
        }

        return URL(fileURLWithPath: path)
    }

    private func videoDurationSeconds(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)

        if #available(macOS 13.0, *) {
            if let duration = try? await asset.load(.duration),
               duration.isValid,
               duration.seconds.isFinite,
               duration.seconds > 0 {
                return duration.seconds
            }
        } else {
            let duration = asset.duration
            if duration.isValid, duration.seconds.isFinite, duration.seconds > 0 {
                return duration.seconds
            }
        }

        return 1.0
    }

    private func runFFmpeg(
        executableURL: URL,
        arguments: [String],
        totalDuration: Double,
        stageLabel: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> FFmpegResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        let parserState = FFmpegParseState()

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            let lines = parserState.appendAndExtractLines(chunk)

            for line in lines {
                guard let elapsed = GIFExportService.extractElapsedSeconds(from: line) else { continue }
                let progress = min(max(elapsed / totalDuration, 0), 1)
                Task { @MainActor in
                    onProgress(progress)
                }
            }
        }

        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = nil

        debugLog("GIFExportService: \(stageLabel) finished with code \(process.terminationStatus)")

        return FFmpegResult(exitCode: process.terminationStatus, stderr: parserState.fullStderr())
    }

    private nonisolated static func extractElapsedSeconds(from line: String) -> Double? {
        if line.hasPrefix("out_time_ms=") {
            let value = line.replacingOccurrences(of: "out_time_ms=", with: "")
            guard let raw = Double(value) else { return nil }
            return raw / 1_000_000.0
        }

        if line.hasPrefix("out_time_us=") {
            let value = line.replacingOccurrences(of: "out_time_us=", with: "")
            guard let raw = Double(value) else { return nil }
            return raw / 1_000_000.0
        }

        if line.hasPrefix("out_time=") {
            let value = line.replacingOccurrences(of: "out_time=", with: "")
            return parseTimestampToSeconds(value)
        }

        if let range = line.range(of: "time=") {
            let value = String(line[range.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
            return parseTimestampToSeconds(value)
        }

        return nil
    }

    private nonisolated static func parseTimestampToSeconds(_ timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }

        return (hours * 3600) + (minutes * 60) + seconds
    }
}
