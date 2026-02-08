import SwiftUI
import AppKit

// MARK: - Shortcut Data Models

struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}

struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let shortcuts: [ShortcutItem]
}

// MARK: - Main Overlay View

struct KeyboardShortcutsOverlay: View {
    let useNativeShortcuts: Bool
    let onClose: () -> Void

    @State private var isAppearing = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // Dynamically generate shortcut groups based on current modifier settings
    private var shortcutGroups: [ShortcutGroup] {
        let mod = useNativeShortcuts ? "⌘⇧" : "⌃⇧"
        let modOpt = useNativeShortcuts ? "⌘⇧⌥" : "⌃⇧⌥"

        return [
            ShortcutGroup(
                title: "Capturing",
                icon: "camera.fill",
                shortcuts: [
                    ShortcutItem(keys: "\(mod)3", description: "Capture Fullscreen"),
                    ShortcutItem(keys: "\(mod)4", description: "Capture Area"),
                    ShortcutItem(keys: "\(mod)5", description: "Capture Window"),
                ]
            ),
            ShortcutGroup(
                title: "Recording",
                icon: "video.fill",
                shortcuts: [
                    ShortcutItem(keys: "\(mod)7", description: "Record Screen"),
                    ShortcutItem(keys: "\(mod)8", description: "Record GIF"),
                ]
            ),
            ShortcutGroup(
                title: "Tools",
                icon: "wrench.and.screwdriver.fill",
                shortcuts: [
                    ShortcutItem(keys: "\(mod)O", description: "Capture Text (OCR)"),
                    ShortcutItem(keys: "\(mod)P", description: "Pin Screenshot"),
                    ShortcutItem(keys: "\(mod)S", description: "Open Screenshots Folder"),
                    ShortcutItem(keys: "\(mod)W", description: "Toggle Webcam"),
                    ShortcutItem(keys: "\(modOpt)A", description: "All-in-One Menu"),
                ]
            ),
            ShortcutGroup(
                title: "Quick Access",
                icon: "bolt.fill",
                shortcuts: [
                    ShortcutItem(keys: "⌘C", description: "Copy to Clipboard"),
                    ShortcutItem(keys: "⌘S", description: "Reveal in Finder"),
                    ShortcutItem(keys: "⌘E", description: "Edit / Annotate"),
                    ShortcutItem(keys: "⌘P", description: "Pin Screenshot"),
                    ShortcutItem(keys: "⌘T", description: "Extract Text (OCR)"),
                    ShortcutItem(keys: "⌘⌫", description: "Delete"),
                    ShortcutItem(keys: "⎋", description: "Dismiss"),
                ]
            ),
            ShortcutGroup(
                title: "Annotation Editor",
                icon: "pencil.tip.crop.circle",
                shortcuts: [
                    ShortcutItem(keys: "⌘Z", description: "Undo"),
                    ShortcutItem(keys: "⌘⇧Z", description: "Redo"),
                    ShortcutItem(keys: "⌫", description: "Delete Selected"),
                    ShortcutItem(keys: "⎋", description: "Deselect / Cancel"),
                ]
            ),
            ShortcutGroup(
                title: "App",
                icon: "app.fill",
                shortcuts: [
                    ShortcutItem(keys: "⌘,", description: "Preferences"),
                    ShortcutItem(keys: "⌘⇧H", description: "Capture History"),
                    ShortcutItem(keys: "⌘/", description: "Keyboard Shortcuts"),
                    ShortcutItem(keys: "⌘H", description: "Hide App"),
                    ShortcutItem(keys: "⌘Q", description: "Quit"),
                ]
            ),
        ]
    }

    private var filteredGroups: [ShortcutGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return shortcutGroups }

        return shortcutGroups.compactMap { group in
            let groupMatches = group.title.lowercased().contains(query)
            let matchingShortcuts = groupMatches
                ? group.shortcuts
                : group.shortcuts.filter {
                    $0.description.lowercased().contains(query) ||
                    $0.keys.lowercased().contains(query)
                }

            guard !matchingShortcuts.isEmpty else { return nil }
            return ShortcutGroup(title: group.title, icon: group.icon, shortcuts: matchingShortcuts)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with traffic lights and title
            headerSection

            searchSection

            DSDivider()
                .padding(.horizontal, DSSpacing.lg)

            // Scrollable shortcuts content
            ScrollView {
                LazyVStack(spacing: DSSpacing.xl) {
                    if filteredGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredGroups) { group in
                            ShortcutGroupView(group: group)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.xl)
            }

            // Footer with mode indicator
            footerSection
        }
        .frame(width: 560, height: 680)
        .background(overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl)
                .strokeBorder(Color.dsBorder, lineWidth: 1)
        )
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.95)
        .onExitCommand(perform: onClose)
        .background(closeShortcut)
        .onAppear {
            withAnimation(DSAnimation.spring) {
                isAppearing = true
            }
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dsTextSecondary)

                Text("Keyboard Shortcuts")
                    .font(DSTypography.headlineLarge)
                    .foregroundColor(.dsTextPrimary)
            }

            Spacer()

            closeButton
        }
        .frame(height: 48)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.sm)
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dsTextTertiary)

            TextField("Search shortcuts...", text: $searchText)
                .textFieldStyle(.plain)
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.md)
                .fill(Color.dsBackgroundSecondary.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.md)
                .strokeBorder(Color.dsBorderActive, lineWidth: 1)
        )
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            // Mode indicator
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(useNativeShortcuts ? Color.dsSuccess : Color.dsAccent)
                    .frame(width: 6, height: 6)
                Text(useNativeShortcuts ? "Standard Shortcuts (⌘⇧)" : "Alt Shortcuts (⌃⇧)")
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }

            Spacer()

            // Dismiss hint
            HStack(spacing: DSSpacing.xxs) {
                KeycapRow(keys: "⌘/")
                Text("or")
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
                KeycapRow(keys: "⎋")
                Text("to close")
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(Color.dsBackgroundElevated.opacity(0.5))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.dsTextSecondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.dsBackgroundSecondary)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.dsBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var closeShortcut: some View {
        Button(action: onClose) {
            EmptyView()
        }
        .keyboardShortcut("/", modifiers: [.command])
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.sm) {
            Text("No shortcuts found")
                .font(DSTypography.headlineSmall)
                .foregroundColor(.dsTextSecondary)
            Text("Try a different search term.")
                .font(DSTypography.bodySmall)
                .foregroundColor(.dsTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
    }

    // MARK: - Background

    private var overlayBackground: some View {
        ZStack {
            ShortcutsVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                Spacer()
            }
        }
    }
}

// MARK: - Shortcut Group View

struct ShortcutGroupView: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Group header
            Text(group.title.uppercased())
                .font(DSTypography.captionMedium)
                .foregroundColor(.dsTextTertiary)
                .tracking(0.6)

            // Shortcuts list
            VStack(spacing: DSSpacing.xs) {
                ForEach(group.shortcuts) { shortcut in
                    ShortcutRowView(shortcut: shortcut)
                }
            }
        }
    }
}

// MARK: - Shortcut Row View

struct ShortcutRowView: View {
    let shortcut: ShortcutItem

    var body: some View {
        HStack {
            Text(shortcut.description)
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)

            Spacer()

            KeycapRow(keys: shortcut.keys)
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

// MARK: - Keycap Views

struct KeycapRow: View {
    let keys: String

    private var tokens: [String] {
        keys.map { String($0) }
    }

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(tokens.indices, id: \.self) { index in
                KeycapView(text: tokens[index])
            }
        }
    }
}

struct KeycapView: View {
    let text: String

    private var displayText: String {
        text.uppercased()
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.dsTextSecondary)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.xs)
                    .fill(Color.dsBackgroundTertiary.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xs)
                    .strokeBorder(Color.dsBorderActive, lineWidth: 1)
            )
    }
}

// MARK: - Visual Effect View

struct ShortcutsVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
