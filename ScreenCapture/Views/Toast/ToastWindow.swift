import AppKit
import SwiftUI

// MARK: - Toast Window Controller

/// Manages the floating window that displays toast notifications
@MainActor
final class ToastWindowController {
    private var window: NSWindow?
    private let manager = ToastManager.shared

    /// Creates and shows the toast window
    func setup() {
        guard window == nil else { return }

        // Create the content view
        let contentView = ToastContainerView(manager: manager)
            .frame(maxWidth: 300)

        // Create the hosting view
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        // Position at top center of main screen
        positionWindow(window)

        // Show the window
        window.orderFront(nil)

        self.window = window

        // Observe screen changes to reposition
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Hide and cleanup the toast window
    func teardown() {
        window?.close()
        window = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let topOffset: CGFloat = 60

        // Center horizontally, position from top
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + screenFrame.height - topOffset

        window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    @objc private func screenDidChange() {
        if let window = window {
            positionWindow(window)
        }
    }
}
