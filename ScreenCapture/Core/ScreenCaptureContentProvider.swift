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
            guard let self else { return }
            Task { @MainActor in
                self.invalidateCache()
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

    /// Returns the display that contains most of the given rect.
    func getDisplay(containing rect: CGRect) async throws -> SCDisplay {
        let content = try await getContent()
        guard let fallbackDisplay = content.displays.first else {
            throw NSError(
                domain: "ScreenCaptureContentProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display found"]
            )
        }

        guard
            let screen = screenContaining(rect),
            let screenDisplayID = displayID(for: screen),
            let matchedDisplay = content.displays.first(where: { $0.displayID == screenDisplayID })
        else {
            return fallbackDisplay
        }

        return matchedDisplay
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

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let directMatch = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return directMatch
        }

        var bestScreen: NSScreen?
        var bestIntersectionArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            guard !intersection.isNull else { continue }

            let area = max(0, intersection.width) * max(0, intersection.height)
            if area > bestIntersectionArea {
                bestIntersectionArea = area
                bestScreen = screen
            }
        }

        return bestScreen
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
