import SwiftUI
import AppKit

// MARK: - Shortcut Mode Picker View

/// First-launch dialog for choosing keyboard shortcut mode.
/// Replaces the generic NSAlert with a branded, scannable two-card picker.
struct ShortcutModePickerView: View {
    let onChooseStandard: () -> Void
    let onChooseSafe: () -> Void
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    @State private var isAppearing = false

    var body: some View {
        ZStack {
            // Solid dark fallback behind the vibrancy layer
            Color.dsBackground

            // Frosted glass vibrancy
            ShortcutsVisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )

            // Content
            VStack(spacing: DSSpacing.xl) {
                // Header
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Choose Your Shortcuts")
                        .font(DSTypography.headlineLarge)
                        .foregroundColor(.dsTextPrimary)

                    Text("Pick how ScreenCapture responds to keyboard shortcuts.")
                        .font(DSTypography.bodySmall)
                        .foregroundColor(.dsTextSecondary)
                        .multilineTextAlignment(.center)
                }

                // Two cards side by side
                HStack(spacing: DSSpacing.md) {
                    ShortcutModeCard(
                        icon: "command",
                        title: "Standard",
                        modifierSymbol: "⌘⇧",
                        subtitle: "Matches macOS defaults",
                        note: "Requires disabling macOS shortcuts",
                        isRecommended: false,
                        action: onChooseStandard
                    )

                    ShortcutModeCard(
                        icon: "shield",
                        title: "Safe Mode",
                        modifierSymbol: "⌃⇧",
                        subtitle: "No conflicts with macOS",
                        note: nil,
                        isRecommended: true,
                        action: onChooseSafe
                    )
                }

                // Footer link
                DSCompactAction(
                    icon: "gear",
                    title: "Open System Keyboard Settings",
                    action: onOpenSettings
                )
            }
            .padding(.horizontal, DSSpacing.xxl)
            .padding(.vertical, DSSpacing.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl)
                .strokeBorder(Color.dsBorder, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            PickerCloseTrafficLight(action: onDismiss)
                .padding(.leading, 10)
                .padding(.top, 10)
        }
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.95)
        .onAppear {
            withAnimation(DSAnimation.spring) {
                isAppearing = true
            }
        }
        .onExitCommand {
            // Escape dismisses — defaults to safe mode
            onChooseSafe()
        }
    }
}

private struct PickerCloseTrafficLight: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 1, green: 0.38, blue: 0.36))
                    .frame(width: 12, height: 12)

                if isHovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(Color(white: 0.2))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Close")
    }
}

// MARK: - Shortcut Mode Card

private struct ShortcutModeCard: View {
    let icon: String
    let title: String
    let modifierSymbol: String
    let subtitle: String
    let note: String?
    let isRecommended: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(DSAnimation.springQuick) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            VStack(spacing: DSSpacing.md) {
                // Badge row
                HStack {
                    Spacer()
                    if isRecommended {
                        DSBadge(text: "Recommended", style: .systemAccent)
                    } else {
                        // Invisible placeholder to keep layout consistent
                        DSBadge(text: "Recommended", style: .systemAccent)
                            .opacity(0)
                    }
                }

                // Icon + Title
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isHovered ? .dsAccent : .dsTextSecondary)

                    Text(title)
                        .font(DSTypography.headlineSmall)
                        .foregroundColor(.dsTextPrimary)
                }

                // Shortcut keys
                VStack(spacing: DSSpacing.xs) {
                    ForEach(["3", "4", "5"], id: \.self) { number in
                        KeycapRow(keys: modifierSymbol + number)
                    }
                }

                // Subtitle
                Text(subtitle)
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)

                // Optional note
                if let note = note {
                    Text(note)
                        .font(DSTypography.caption)
                        .foregroundColor(.dsWarmAccent.opacity(0.8))
                        .multilineTextAlignment(.center)
                } else {
                    Text(" ")
                        .font(DSTypography.caption)
                        .opacity(0)
                }
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(Color.dsBackgroundElevated)

                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(isHovered ? Color.dsAccent.opacity(0.06) : Color.clear)

                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(
                            isHovered ? Color.dsBorderAccent : Color.dsBorder,
                            lineWidth: 1
                        )
                }
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: isHovered ? Color.dsAccent.opacity(0.15) : Color.clear,
                radius: 12,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}
