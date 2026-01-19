import Foundation
@testable import ScreenCapture

// MARK: - Notification Observer Helper

/// Helper class for observing and capturing notifications in tests
class NotificationObserver {
    private(set) var receivedNotifications: [Notification] = []
    private var observers: [NSObjectProtocol] = []

    /// Start observing a notification name
    func observe(_ name: Notification.Name, object: Any? = nil) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] notification in
            self?.receivedNotifications.append(notification)
        }
        observers.append(observer)
    }

    /// Check if a specific notification was received
    func didReceive(_ name: Notification.Name) -> Bool {
        return receivedNotifications.contains { $0.name == name }
    }

    /// Get count of notifications with the given name
    func count(of name: Notification.Name) -> Int {
        return receivedNotifications.filter { $0.name == name }.count
    }

    /// Clear all received notifications
    func clear() {
        receivedNotifications.removeAll()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - Test UserDefaults

/// A scoped UserDefaults wrapper for isolated testing
class TestUserDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "com.screencapture.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func reset() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        reset()
    }
}

// MARK: - Test Error Types

/// Generic test error for testing error handling
struct TestError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        return message
    }

    init(_ message: String = "Test error") {
        self.message = message
    }
}

// MARK: - Async Test Helpers

/// Wait for a condition to become true
func waitFor(
    timeout: TimeInterval = 5.0,
    condition: @escaping () -> Bool,
    completion: @escaping (Bool) -> Void
) {
    let deadline = Date().addingTimeInterval(timeout)
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
        if condition() {
            timer.invalidate()
            completion(true)
        } else if Date() > deadline {
            timer.invalidate()
            completion(false)
        }
    }
    RunLoop.current.add(timer, forMode: .common)
}

// MARK: - File System Test Helpers

/// Helper for creating temporary test directories
class TestDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenCaptureTests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(named name: String) -> URL {
        return url.appendingPathComponent(name)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        cleanup()
    }
}
