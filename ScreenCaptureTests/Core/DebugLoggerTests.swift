import XCTest
@testable import ScreenCapture

final class DebugLoggerTests: XCTestCase {

    // Note: DebugLogger is a singleton, so we test against the shared instance
    // Tests should not assume clean state between runs

    // MARK: - Log File Path Tests

    func testLogFilePathIsNotEmpty() {
        let path = DebugLogger.shared.logFilePath
        XCTAssertFalse(path.isEmpty)
    }

    func testLogFilePathContainsScreenCapture() {
        let path = DebugLogger.shared.logFilePath
        XCTAssertTrue(path.contains("ScreenCapture"))
    }

    func testLogFilePathEndsWithDebugLog() {
        let path = DebugLogger.shared.logFilePath
        XCTAssertTrue(path.hasSuffix("debug.log"))
    }

    func testLogFilePathIsInLibraryLogs() {
        let path = DebugLogger.shared.logFilePath
        XCTAssertTrue(path.contains("Library/Logs"))
    }

    // MARK: - Log File Creation Tests

    func testLogFileDirectoryExists() {
        let path = DebugLogger.shared.logFilePath
        let url = URL(fileURLWithPath: path)
        let directoryURL = url.deletingLastPathComponent()

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

        XCTAssertTrue(exists, "Log directory should exist")
        XCTAssertTrue(isDirectory.boolValue, "Should be a directory")
    }

    // MARK: - Logging Tests

    func testLogWritesToFile() {
        let uniqueMarker = "TEST_LOG_\(UUID().uuidString)"

        // Log the unique message
        DebugLogger.shared.log(uniqueMarker)

        // Flush to ensure write completes
        DebugLogger.shared.flush()

        // Read the log file
        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        XCTAssertNotNil(content, "Should be able to read log file")
        XCTAssertTrue(content?.contains(uniqueMarker) ?? false, "Log file should contain our marker")
    }

    func testLogIncludesTimestamp() {
        let uniqueMarker = "TIMESTAMP_TEST_\(UUID().uuidString)"

        DebugLogger.shared.log(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        // Find the line containing our marker
        let lines = content?.components(separatedBy: "\n") ?? []
        let markerLine = lines.first { $0.contains(uniqueMarker) }

        XCTAssertNotNil(markerLine, "Should find our log entry")
        // Timestamp format: [2024-01-15 12:34:56.789]
        XCTAssertTrue(markerLine?.contains("[20") ?? false, "Should contain timestamp")
    }

    func testLogIncludesFileAndLineInfo() {
        let uniqueMarker = "FILEINFO_TEST_\(UUID().uuidString)"

        DebugLogger.shared.log(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        let lines = content?.components(separatedBy: "\n") ?? []
        let markerLine = lines.first { $0.contains(uniqueMarker) }

        XCTAssertNotNil(markerLine, "Should find our log entry")
        // Should contain the test file name
        XCTAssertTrue(markerLine?.contains("DebugLoggerTests.swift") ?? false, "Should contain file name")
    }

    // MARK: - Error Logging Tests

    func testErrorLogsWithPrefix() {
        let uniqueMarker = "ERROR_TEST_\(UUID().uuidString)"

        DebugLogger.shared.error(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        let lines = content?.components(separatedBy: "\n") ?? []
        let markerLine = lines.first { $0.contains(uniqueMarker) }

        XCTAssertNotNil(markerLine, "Should find our log entry")
        XCTAssertTrue(markerLine?.contains("ERROR:") ?? false, "Should contain ERROR prefix")
    }

    func testErrorLogsWithErrorObject() {
        let uniqueMarker = "ERROR_OBJ_TEST_\(UUID().uuidString)"
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error description"])

        DebugLogger.shared.error(uniqueMarker, error: testError)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        let lines = content?.components(separatedBy: "\n") ?? []
        let markerLine = lines.first { $0.contains(uniqueMarker) }

        XCTAssertNotNil(markerLine, "Should find our log entry")
        XCTAssertTrue(markerLine?.contains("Test error description") ?? false, "Should contain error description")
    }

    // MARK: - Warning Logging Tests

    func testWarningLogsWithPrefix() {
        let uniqueMarker = "WARNING_TEST_\(UUID().uuidString)"

        DebugLogger.shared.warning(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        let lines = content?.components(separatedBy: "\n") ?? []
        let markerLine = lines.first { $0.contains(uniqueMarker) }

        XCTAssertNotNil(markerLine, "Should find our log entry")
        XCTAssertTrue(markerLine?.contains("WARNING:") ?? false, "Should contain WARNING prefix")
    }

    // MARK: - Flush Tests

    func testFlushDoesNotCrash() {
        // Just ensure flush completes without crashing
        DebugLogger.shared.flush()
        XCTAssertTrue(true, "Flush completed without crash")
    }

    func testFlushIsIdempotent() {
        // Multiple flushes should be safe
        DebugLogger.shared.flush()
        DebugLogger.shared.flush()
        DebugLogger.shared.flush()
        XCTAssertTrue(true, "Multiple flushes completed without crash")
    }

    func testFlushEnsuresWriteCompletes() {
        let uniqueMarker = "FLUSH_TEST_\(UUID().uuidString)"

        DebugLogger.shared.log(uniqueMarker)
        DebugLogger.shared.flush()

        // Immediately after flush, the write should be complete
        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content?.contains(uniqueMarker) ?? false, "Content should be written immediately after flush")
    }

    // MARK: - Concurrent Logging Tests

    func testConcurrentLoggingDoesNotCrash() {
        let expectation = XCTestExpectation(description: "Concurrent logging completes")
        expectation.expectedFulfillmentCount = 10

        let dispatchGroup = DispatchGroup()

        for i in 0..<10 {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for j in 0..<10 {
                    DebugLogger.shared.log("Concurrent test \(i)-\(j)")
                }
                dispatchGroup.leave()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        DebugLogger.shared.flush()

        // Just ensure no crash
        XCTAssertTrue(true, "Concurrent logging completed without crash")
    }

    // MARK: - Global Function Tests

    func testErrorLogGlobalFunction() {
        let uniqueMarker = "GLOBAL_ERROR_\(UUID().uuidString)"

        errorLog(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content?.contains(uniqueMarker) ?? false, "Global errorLog should write to file")
    }

    #if DEBUG
    func testDebugLogGlobalFunction() {
        let uniqueMarker = "GLOBAL_DEBUG_\(UUID().uuidString)"

        debugLog(uniqueMarker)
        DebugLogger.shared.flush()

        let path = DebugLogger.shared.logFilePath
        let content = try? String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content?.contains(uniqueMarker) ?? false, "Global debugLog should write to file in DEBUG mode")
    }
    #endif
}
