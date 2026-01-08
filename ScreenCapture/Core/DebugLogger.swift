import Foundation
import os.log

/// A debug logger that writes to both console and a persistent file
/// Useful for debugging crashes and freezes where Xcode's console is lost
final class DebugLogger {
    static let shared = DebugLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.screencapture.debuglogger")
    private let dateFormatter: DateFormatter
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "ScreenCapture", category: "Debug")

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Store logs in ~/Library/Logs/ScreenCapture/
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
            .appendingPathComponent("ScreenCapture")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        fileURL = logsDir.appendingPathComponent("debug.log")

        // Rotate log if it's too large (> 5MB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size > 5_000_000 {
            let backupURL = logsDir.appendingPathComponent("debug.log.old")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        }

        log("=== ScreenCapture Debug Session Started ===")
        log("Log file: \(fileURL.path)")
    }

    /// Log file location for easy access
    var logFilePath: String {
        fileURL.path
    }

    /// Log a message with optional file/line context
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(filename):\(line)] \(function): \(message)\n"

        // Write to os_log for Console.app
        os_log("%{public}@", log: osLog, type: .debug, message)

        // Also write to file
        queue.async { [weak self] in
            guard let self = self else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? entry.write(to: self.fileURL, atomically: false, encoding: .utf8)
            }
        }
    }

    /// Log an error
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = "ERROR: \(message)"
        if let error = error {
            fullMessage += " | \(error.localizedDescription)"
        }
        log(fullMessage, file: file, function: function, line: line)
        os_log("%{public}@", log: osLog, type: .error, fullMessage)
    }

    /// Log a warning
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log("WARNING: \(message)", file: file, function: function, line: line)
        os_log("%{public}@", log: osLog, type: .info, "WARNING: \(message)")
    }

    /// Flush any pending writes (call before expected crash)
    func flush() {
        queue.sync {}
    }
}

// MARK: - Global convenience functions

/// Quick debug log
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    DebugLogger.shared.log(message, file: file, function: function, line: line)
    #endif
}

/// Quick error log (always logs, even in release)
func errorLog(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    DebugLogger.shared.error(message, error: error, file: file, function: function, line: line)
}
