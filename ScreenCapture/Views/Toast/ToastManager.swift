import SwiftUI
import Combine

// MARK: - Toast Manager

/// Singleton manager for displaying toast notifications
/// Thread-safe and handles stacking of multiple toasts
@MainActor
final class ToastManager: ObservableObject {
    /// Shared singleton instance
    static let shared = ToastManager()

    /// Currently active toasts (displayed on screen)
    @Published private(set) var activeToasts: [Toast] = []

    /// Maximum number of toasts to show at once
    private let maxVisibleToasts = 3

    private init() {}

    // MARK: - Public API

    /// Show a toast notification
    /// - Parameter type: The type of toast to display
    func show(_ type: ToastType) {
        let toast = Toast(type: type)

        // Add to active toasts
        activeToasts.append(toast)

        // Limit visible toasts (remove oldest if exceeds max)
        if activeToasts.count > maxVisibleToasts {
            activeToasts.removeFirst()
        }
    }

    /// Remove a specific toast
    /// - Parameter toast: The toast to remove
    func remove(_ toast: Toast) {
        activeToasts.removeAll { $0.id == toast.id }
    }

    /// Remove all active toasts
    func removeAll() {
        activeToasts.removeAll()
    }
}
