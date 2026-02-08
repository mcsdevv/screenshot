import SwiftUI
import AppKit

// MARK: - Design System
// Prismatic Dark: A sophisticated dark theme with Liquid Glass-inspired depth
// Designed for macOS 2026 - setting the standard for modern screenshot apps

// MARK: - Color Palette

extension Color {
    // MARK: Background Colors - Deep Obsidian Palette

    /// Primary background - deep, rich dark
    static let dsBackground = Color(red: 0.07, green: 0.07, blue: 0.09)

    /// Elevated surface - slightly lighter for cards/panels
    static let dsBackgroundElevated = Color(red: 0.10, green: 0.10, blue: 0.13)

    /// Secondary surface - for nested elements
    static let dsBackgroundSecondary = Color(red: 0.13, green: 0.13, blue: 0.16)

    /// Tertiary surface - subtle differentiation
    static let dsBackgroundTertiary = Color(red: 0.16, green: 0.16, blue: 0.19)

    // MARK: Accent Colors - Electric Cyan Palette

    /// Primary accent - vibrant electric cyan
    static let dsAccent = Color(red: 0.20, green: 0.78, blue: 0.98)

    /// Secondary accent - softer cyan
    static let dsAccentMuted = Color(red: 0.20, green: 0.78, blue: 0.98).opacity(0.7)

    /// Accent glow - for hover/focus states
    static let dsAccentGlow = Color(red: 0.20, green: 0.78, blue: 0.98).opacity(0.3)

    /// Warm accent - for highlights and alerts
    static let dsWarmAccent = Color(red: 1.0, green: 0.58, blue: 0.20)

    /// Success accent
    static let dsSuccess = Color(red: 0.30, green: 0.85, blue: 0.50)

    /// Danger accent
    static let dsDanger = Color(red: 1.0, green: 0.35, blue: 0.40)

    // MARK: Text Colors

    /// Primary text - high contrast
    static let dsTextPrimary = Color.white.opacity(0.95)

    /// Secondary text - reduced emphasis
    static let dsTextSecondary = Color.white.opacity(0.60)

    /// Tertiary text - low emphasis
    static let dsTextTertiary = Color.white.opacity(0.40)

    /// Disabled text
    static let dsTextDisabled = Color.white.opacity(0.25)

    // MARK: Border Colors

    /// Subtle border
    static let dsBorder = Color.white.opacity(0.08)

    /// Active border
    static let dsBorderActive = Color.white.opacity(0.15)

    /// Accent border
    static let dsBorderAccent = Color.dsAccent.opacity(0.5)

    // MARK: Gradient Definitions

    /// Background gradient mesh - subtle depth
    static let dsBackgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.08, blue: 0.12),
            Color(red: 0.06, green: 0.06, blue: 0.08),
            Color(red: 0.07, green: 0.05, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glass panel gradient
    static let dsGlassGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent gradient - for buttons and highlights
    static let dsAccentGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.82, blue: 1.0),
            Color(red: 0.15, green: 0.70, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm accent gradient
    static let dsWarmGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.65, blue: 0.30),
            Color(red: 1.0, green: 0.50, blue: 0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography

struct DSTypography {
    // Display - Hero text
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .rounded)

    // Headlines
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // Body text
    static let bodyLarge = Font.system(size: 14, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)

    // Labels
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

    // Captions
    static let caption = Font.system(size: 10, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 10, weight: .medium, design: .default)

    // Monospaced
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Row Heights

struct DSRowHeight {
    static let labelSmall: CGFloat = 14
}

// MARK: - Spacing

struct DSSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

// MARK: - Corner Radius

struct DSRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let full: CGFloat = 999
}

// MARK: - Shadows

struct DSShadow {
    static func soft() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    static func medium() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }

    static func strong() -> some View {
        EmptyView()
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
    }

    static func glow(color: Color = .dsAccent) -> some View {
        EmptyView()
            .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 0)
    }
}

// MARK: - Animation Curves

struct DSAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.2)
    static let smooth = Animation.easeInOut(duration: 0.3)
    static let slow = Animation.easeInOut(duration: 0.4)

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let springQuick = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

// MARK: - Glass Panel Component

struct DSGlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: () -> Content

    init(
        cornerRadius: CGFloat = DSRadius.lg,
        padding: CGFloat = DSSpacing.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    // Base glass
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.dsGlassGradient)

                    // Top highlight edge
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
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
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Dark Glass Panel (Solid Dark)

struct DSDarkPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: () -> Content

    init(
        cornerRadius: CGFloat = DSRadius.lg,
        padding: CGFloat = DSSpacing.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    // Solid dark base
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.dsBackgroundElevated)

                    // Subtle gradient for depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.dsBorder, lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Primary Button

struct DSPrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

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
            HStack(spacing: DSSpacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(DSTypography.labelLarge)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(.white)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .background(
                ZStack {
                    // Base gradient
                    RoundedRectangle(cornerRadius: DSRadius.md)
                        .fill(Color.dsAccentGradient)

                    // Hover glow
                    if isHovered {
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .fill(Color.white.opacity(0.15))
                    }
                }
            )
            .shadow(color: Color.dsAccent.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 12 : 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Secondary Button

struct DSSecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

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
            HStack(spacing: DSSpacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(DSTypography.labelMedium)
            }
            .foregroundColor(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .strokeBorder(isHovered ? Color.dsBorderActive : Color.dsBorder, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Icon Button

struct DSIconButton: View {
    let icon: String
    let size: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(
        icon: String,
        size: CGFloat = 32,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.isSelected = isSelected
        self.action = action
    }

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
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected ? .dsAccent :
                    (isHovered ? .dsTextPrimary : .dsTextSecondary)
                )
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(
                            isSelected ? Color.dsAccent.opacity(0.15) :
                            (isHovered ? Color.white.opacity(0.08) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .strokeBorder(
                            isSelected ? Color.dsAccent.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Action Card Button (for Quick Access style)

struct DSActionCard: View {
    let icon: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(
        icon: String,
        title: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

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
            VStack(spacing: DSSpacing.sm) {
                ZStack {
                    // Icon background circle
                    Circle()
                        .fill(
                            isHovered ?
                            Color.dsAccent.opacity(0.2) :
                            Color.white.opacity(0.08)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isHovered ? .dsAccent : .dsTextPrimary)
                }

                Text(title)
                    .font(DSTypography.labelSmall)
                    .foregroundColor(isHovered ? .dsTextPrimary : .dsTextSecondary)
            }
            .frame(width: 72, height: 76)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(
                        isHovered ? Color.dsBorderActive : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help(shortcut != nil ? "\(title) (\(shortcut!))" : title)
    }
}

// MARK: - Compact Action Button

struct DSCompactAction: View {
    let icon: String
    let title: String
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
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(DSTypography.labelSmall)
            }
            .foregroundColor(isHovered ? .dsTextPrimary : .dsTextTertiary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Chip/Tag Component

struct DSChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        _ title: String,
        icon: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(title)
                    .font(DSTypography.labelSmall)
            }
            .foregroundColor(
                isSelected ? .white :
                (isHovered ? .dsTextPrimary : .dsTextSecondary)
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule()
                    .fill(
                        isSelected ? Color.dsAccent :
                        (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color.dsBorder,
                        lineWidth: 1
                    )
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

// MARK: - Color Swatch

struct DSColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    init(
        color: Color,
        isSelected: Bool = false,
        size: CGFloat = 28,
        action: @escaping () -> Void
    ) {
        self.color = color
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Color fill
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)

                // Selection ring
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: size + 4, height: size + 4)
                }

                // Hover ring
                if isHovered && !isSelected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: size + 2, height: size + 2)
                }
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Divider

struct DSDivider: View {
    let orientation: Axis
    let thickness: CGFloat

    init(_ orientation: Axis = .horizontal, thickness: CGFloat = 1) {
        self.orientation = orientation
        self.thickness = thickness
    }

    var body: some View {
        Rectangle()
            .fill(Color.dsBorder)
            .frame(
                width: orientation == .vertical ? thickness : nil,
                height: orientation == .horizontal ? thickness : nil
            )
    }
}

// MARK: - Input Field

struct DSTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String?

    init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.dsTextTertiary)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.md)
                .fill(Color.dsBackgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.md)
                .strokeBorder(Color.dsBorder, lineWidth: 1)
        )
    }
}

// MARK: - Sidebar Item

struct DSSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .dsAccent : .dsTextSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(DSTypography.bodyMedium)
                    .foregroundColor(isSelected ? .dsTextPrimary : .dsTextSecondary)

                Spacer()
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(
                        isSelected ? Color.dsAccent.opacity(0.12) :
                        (isHovered ? Color.white.opacity(0.05) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(
                        isSelected ? Color.dsAccent.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
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

// MARK: - Thumbnail Card

struct DSThumbnailCard: View {
    let image: NSImage?
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isFavorite: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            // Thumbnail
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.dsBackgroundSecondary)
                        .frame(width: 200, height: 140)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(.dsTextTertiary)
                        )
                }

                // Favorite badge
                if isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.dsWarmAccent)
                                .padding(DSSpacing.sm)
                        }
                        Spacer()
                    }
                }

                // Hover overlay with actions
                if isHovered {
                    Color.black.opacity(0.5)

                    HStack(spacing: DSSpacing.md) {
                        DSIconButton(icon: "doc.on.clipboard", size: 36) {}
                        DSIconButton(icon: "pencil", size: 36) {}
                        DSIconButton(icon: "square.and.arrow.up", size: 36) {}
                    }
                }
            }
            .frame(width: 200, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(
                        isSelected ? Color.dsAccent :
                        (isHovered ? Color.dsBorderActive : Color.dsBorder),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.dsAccent.opacity(0.3) : .black.opacity(0.2),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: 4
            )

            // Info
            VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                Text(title)
                    .font(DSTypography.labelMedium)
                    .foregroundColor(.dsTextPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }
            .frame(width: 200, alignment: .leading)
        }
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Badge

struct DSBadge: View {
    let text: String
    let style: Style

    enum Style {
        case accent
        case systemAccent
        case success
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .accent: return .dsAccent
            case .systemAccent: return Color.accentColor
            case .success: return .dsSuccess
            case .warning: return .dsWarmAccent
            case .danger: return .dsDanger
            case .neutral: return .dsTextTertiary
            }
        }
    }

    var body: some View {
        Text(text)
            .font(DSTypography.captionMedium)
            .foregroundColor(style.color)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xxxs)
            .background(
                Capsule()
                    .fill(style.color.opacity(0.15))
            )
    }
}

// MARK: - Traffic Light Buttons

/// Custom macOS-style traffic light buttons (close, minimize, zoom)
/// Can be used when system traffic lights are hidden but you want the same visual style
struct DSTrafficLightButtons: View {
    /// Optional custom close action. If nil, uses NSApp.keyWindow?.close()
    var onClose: (() -> Void)?

    @State private var hoveredButton: TrafficLightButton?

    enum TrafficLightButton {
        case close, minimize, zoom
    }

    var body: some View {
        HStack(spacing: 8) {
            // Close button (red)
            trafficLightButton(
                type: .close,
                color: Color(red: 1, green: 0.38, blue: 0.36),
                hoverIcon: "xmark"
            ) {
                if let onClose = onClose {
                    onClose()
                } else {
                    NSApp.keyWindow?.close()
                }
            }

            // Minimize button (yellow)
            trafficLightButton(
                type: .minimize,
                color: Color(red: 1, green: 0.74, blue: 0.2),
                hoverIcon: "minus"
            ) {
                NSApp.keyWindow?.miniaturize(nil)
            }

            // Zoom button (green) - toggles fullscreen
            trafficLightButton(
                type: .zoom,
                color: Color(red: 0.15, green: 0.8, blue: 0.26),
                hoverIcon: "arrow.up.left.and.arrow.down.right"
            ) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .padding(.leading, 7)
    }

    private func trafficLightButton(
        type: TrafficLightButton,
        color: Color,
        hoverIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                if hoveredButton != nil {
                    Image(systemName: hoverIcon)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(Color(white: 0.2))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredButton = type
            } else if hoveredButton == type {
                hoveredButton = nil
            }
        }
    }
}

// MARK: - Tooltip

struct DSTooltipData: Equatable {
    let text: String
    let anchor: Anchor<CGRect>
}

struct DSTooltipPreferenceKey: PreferenceKey {
    static var defaultValue: DSTooltipData?
    static func reduce(value: inout DSTooltipData?, nextValue: () -> DSTooltipData?) {
        value = nextValue() ?? value
    }
}

struct DSTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovered = false
    @State private var showTooltip = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if isHovered { showTooltip = true }
                    }
                } else {
                    showTooltip = false
                }
            }
            .anchorPreference(key: DSTooltipPreferenceKey.self, value: .bounds) { anchor in
                showTooltip ? DSTooltipData(text: text, anchor: anchor) : nil
            }
    }
}

struct DSTooltipRootModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(DSTooltipPreferenceKey.self) { data in
                GeometryReader { geometry in
                    if let data = data {
                        let rect = geometry[data.anchor]
                        let showAbove = rect.maxY + 32 > geometry.size.height
                        let tipY = showAbove ? rect.minY - 16 : rect.maxY + 16
                        Text(data.text)
                            .font(DSTypography.caption)
                            .foregroundColor(.dsTextPrimary)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: DSRadius.xs)
                                    .fill(Color.dsBackgroundElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DSRadius.xs)
                                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            )
                            .fixedSize()
                            .position(x: rect.midX, y: tipY)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply the design system's dark background
    func dsBackground() -> some View {
        self.background(Color.dsBackgroundGradient)
    }

    /// Show a tooltip on hover after a short delay (requires dsTooltipRoot() on an ancestor)
    func dsTooltip(_ text: String) -> some View {
        modifier(DSTooltipModifier(text: text))
    }

    /// Renders tooltip overlays from descendant dsTooltip() modifiers. Apply to root view.
    func dsTooltipRoot() -> some View {
        modifier(DSTooltipRootModifier())
    }

    /// Apply glass panel styling
    func dsGlassPanel(cornerRadius: CGFloat = DSRadius.lg, padding: CGFloat = DSSpacing.lg) -> some View {
        DSGlassPanel(cornerRadius: cornerRadius, padding: padding) {
            self
        }
    }

    /// Apply dark panel styling
    func dsDarkPanel(cornerRadius: CGFloat = DSRadius.lg, padding: CGFloat = DSSpacing.lg) -> some View {
        DSDarkPanel(cornerRadius: cornerRadius, padding: padding) {
            self
        }
    }
}
