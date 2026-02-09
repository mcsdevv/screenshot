import SwiftUI

// MARK: - Toast Type

/// Defines the different toast notification types with their visual properties
enum ToastType: Identifiable, Equatable {
    case copy
    case save
    case pin
    case ocr
    case open
    case delete
    case shortcutStandardEnabled
    case shortcutSafeEnabled
    case shortcutModeUpdateFailed

    var id: String {
        switch self {
        case .copy: return "copy"
        case .save: return "save"
        case .pin: return "pin"
        case .ocr: return "ocr"
        case .open: return "open"
        case .delete: return "delete"
        case .shortcutStandardEnabled: return "shortcutStandardEnabled"
        case .shortcutSafeEnabled: return "shortcutSafeEnabled"
        case .shortcutModeUpdateFailed: return "shortcutModeUpdateFailed"
        }
    }

    var icon: String {
        switch self {
        case .copy: return "doc.on.clipboard"
        case .save: return "checkmark.circle.fill"
        case .pin: return "pin.fill"
        case .ocr: return "text.viewfinder"
        case .open: return "folder.fill"
        case .delete: return "trash.fill"
        case .shortcutStandardEnabled: return "command"
        case .shortcutSafeEnabled: return "shield"
        case .shortcutModeUpdateFailed: return "exclamationmark.triangle.fill"
        }
    }

    var message: String {
        switch self {
        case .copy: return "Copied"
        case .save: return "Saved"
        case .pin: return "Pinned"
        case .ocr: return "Text copied"
        case .open: return "Opened in Finder"
        case .delete: return "Deleted"
        case .shortcutStandardEnabled: return "Standard shortcuts enabled"
        case .shortcutSafeEnabled: return "Safe mode enabled"
        case .shortcutModeUpdateFailed: return "Could not update shortcut mode"
        }
    }

    var iconColor: Color {
        switch self {
        case .copy: return .dsAccent
        case .save: return .dsSuccess
        case .pin: return .dsWarmAccent
        case .ocr: return .dsAccent
        case .open: return .dsAccent
        case .delete: return .dsDanger
        case .shortcutStandardEnabled: return .dsSuccess
        case .shortcutSafeEnabled: return .dsSuccess
        case .shortcutModeUpdateFailed: return .dsDanger
        }
    }
}

// MARK: - Toast Model

/// Represents a single toast notification instance
struct Toast: Identifiable, Equatable {
    let id: UUID
    let type: ToastType
    let createdAt: Date

    init(type: ToastType) {
        self.id = UUID()
        self.type = type
        self.createdAt = Date()
    }
}

// MARK: - Toast View

/// A single toast pill notification
struct ToastView: View {
    let toast: Toast
    let onRemove: () -> Void

    @State private var isVisible = false
    @State private var isExiting = false

    private let holdDuration: Double = 1.8

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(toast.type.iconColor)

            Text(toast.type.message)
                .font(DSTypography.labelMedium)
                .foregroundColor(.dsTextPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(
            ZStack {
                // Glass base
                Capsule()
                    .fill(.ultraThinMaterial)

                // Gradient overlay for depth
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Top edge highlight
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .scaleEffect(isVisible && !isExiting ? 1.0 : 0.85)
        .opacity(isVisible && !isExiting ? 1.0 : 0.0)
        .offset(y: isVisible && !isExiting ? 0 : -12)
        .onAppear {
            // Enter animation
            withAnimation(DSAnimation.springQuick) {
                isVisible = true
            }

            // Schedule exit
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                withAnimation(DSAnimation.quick) {
                    isExiting = true
                }

                // Remove after exit animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onRemove()
                }
            }
        }
    }
}

// MARK: - Toast Container View

/// Container view that displays and manages multiple toasts
struct ToastContainerView: View {
    @ObservedObject var manager: ToastManager

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            ForEach(manager.activeToasts) { toast in
                ToastView(toast: toast) {
                    manager.remove(toast)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
        }
        .animation(DSAnimation.springQuick, value: manager.activeToasts)
    }
}

// MARK: - Preview

#if DEBUG
struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                ToastView(toast: Toast(type: .copy)) {}
                ToastView(toast: Toast(type: .save)) {}
                ToastView(toast: Toast(type: .pin)) {}
                ToastView(toast: Toast(type: .ocr)) {}
                ToastView(toast: Toast(type: .open)) {}
                ToastView(toast: Toast(type: .delete)) {}
                ToastView(toast: Toast(type: .shortcutStandardEnabled)) {}
                ToastView(toast: Toast(type: .shortcutSafeEnabled)) {}
                ToastView(toast: Toast(type: .shortcutModeUpdateFailed)) {}
            }
            .padding()
        }
        .frame(width: 300, height: 400)
    }
}
#endif
