import ScreenCaptureKit
import AppKit

/// Centralized provider for SCShareableContent.
/// Caches the content to avoid repeated ScreenCaptureKit calls that trigger
/// the macOS 15 "bypass system private window picker" privacy dialog.
@MainActor
class ScreenCaptureContentProvider {
    static let shared = ScreenCaptureContentProvider()

    private var cachedContent: SCShareableContent?
    private var lastFetchTime: Date?
    private let cacheTTL: TimeInterval = 60

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invalidateCache()
            }
        }
    }

    /// Warm the cache and trigger the permission dialog early (call at app launch).
    func preflight() async {
        _ = try? await fetchContent()
    }

    /// Returns cached content or fetches fresh if expired.
    func getContent() async throws -> SCShareableContent {
        if let cached = cachedContent,
           let fetchTime = lastFetchTime,
           Date().timeIntervalSince(fetchTime) < cacheTTL {
            return cached
        }
        return try await fetchContent()
    }

    /// Returns the primary display from cached content.
    func getPrimaryDisplay() async throws -> SCDisplay {
        let content = try await getContent()
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenCaptureContentProvider", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        return display
    }

    private func fetchContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        lastFetchTime = Date()
        return content
    }

    func invalidateCache() {
        cachedContent = nil
        lastFetchTime = nil
    }
}
