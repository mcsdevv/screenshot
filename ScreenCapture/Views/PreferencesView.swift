import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab = .general

    enum PreferencesTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case capture = "Capture"
        case recording = "Recording"
        case storage = "Storage"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .shortcuts: return "command"
            case .capture: return "camera.fill"
            case .recording: return "video.fill"
            case .storage: return "externaldrive.fill"
            case .advanced: return "wrench.and.screwdriver.fill"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Spacer for traffic light buttons
                Spacer()
                    .frame(height: 28)

                // App icon and name
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.dsAccent, .dsAccent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("ScreenCapture")
                        .font(DSTypography.headlineSmall)
                        .foregroundColor(.dsTextPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, DSSpacing.xl)

                // Sidebar items
                VStack(spacing: DSSpacing.xxs) {
                    ForEach(PreferencesTab.allCases, id: \.self) { tab in
                        PreferencesSidebarItem(
                            icon: tab.icon,
                            title: tab.rawValue,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(DSAnimation.quick) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.md)

                Spacer()

                // Version info
                VStack(spacing: DSSpacing.xxs) {
                    Text(AppVersionInfo.sidebarVersionLabel)
                        .font(DSTypography.caption)
                        .foregroundColor(.dsTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, DSSpacing.lg)
            }
            .frame(width: 200)
            .background(
                ZStack {
                    Color.dsBackground
                    LinearGradient(
                        colors: [Color.white.opacity(0.02), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )

            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                        Text(selectedTab.rawValue)
                            .font(DSTypography.headlineLarge)
                            .foregroundColor(.dsTextPrimary)

                        Text(tabDescription(for: selectedTab))
                            .font(DSTypography.bodySmall)
                            .foregroundColor(.dsTextTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.md)

                DSDivider()
                    .padding(.horizontal, DSSpacing.xl)

                // Content area
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralPreferencesView()
                        case .shortcuts:
                            ShortcutsPreferencesView()
                        case .capture:
                            CapturePreferencesView()
                        case .recording:
                            RecordingPreferencesView()
                        case .storage:
                            StoragePreferencesView()
                        case .advanced:
                            AdvancedPreferencesView()
                        }
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.vertical, DSSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.dsBackgroundElevated)
        }
        .frame(minWidth: 700, minHeight: 550)
        .frame(width: 780, height: 620)
    }

    private func tabDescription(for tab: PreferencesTab) -> String {
        switch tab {
        case .general: return "Startup behavior and feedback settings"
        case .shortcuts: return "Keyboard shortcuts for quick access"
        case .capture: return "Screenshot capture options"
        case .recording: return "Screen recording configuration"
        case .storage: return "File storage and cleanup settings"
        case .advanced: return "Diagnostics and reset tools"
        }
    }
}

private enum AppVersionInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var sidebarVersionLabel: String {
        "Version \(shortVersion)"
    }

    static var aboutVersionLabel: String {
        "Version \(shortVersion) (Build \(buildNumber))"
    }
}

// MARK: - Sidebar Item

struct PreferencesSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
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
                        (isHovered ? Color.white.opacity(0.04) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(
                        isSelected ? Color.dsAccent.opacity(0.25) : Color.clear,
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

// MARK: - Preference Section

struct PreferenceSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title.uppercased())
                .font(DSTypography.captionMedium)
                .foregroundColor(.dsTextTertiary)
                .tracking(0.5)

            VStack(spacing: DSSpacing.sm) {
                content()
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(Color.dsBackgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(Color.dsBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Preference Row

struct PreferenceRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: () -> Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                Text(title)
                    .font(DSTypography.bodyMedium)
                    .foregroundColor(.dsTextPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(DSTypography.caption)
                        .foregroundColor(.dsTextTertiary)
                }
            }

            Spacer()

            content()
        }
    }
}

// MARK: - Custom Toggle

struct DSToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .dsAccent))
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("playSound") private var playSound = true
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("quickAccessDuration") private var quickAccessDuration = 5.0
    @AppStorage("popupCorner") private var popupCorner = ScreenCorner.bottomLeft.rawValue
    @AppStorage("afterCaptureAction") private var afterCaptureAction = "quickAccess"

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            PreferenceSection("Startup") {
                DSToggle(
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            guard launchAtLogin != newValue else { return }
                            launchAtLogin = newValue
                            updateLaunchAtLogin(newValue)
                        }
                    ),
                    label: "Launch ScreenCapture at login"
                )

                DSDivider()

                DSToggle(isOn: $showMenuBarIcon, label: "Show icon in menu bar")
            }

            PreferenceSection("Feedback") {
                DSToggle(isOn: $playSound, label: "Play sound after capture")

                DSDivider()

                DSToggle(isOn: $showQuickAccess, label: "Show Quick Access overlay after capture")

                if showQuickAccess {
                    DSDivider()

                    PreferenceRow("Auto-dismiss after") {
                        Picker("", selection: $quickAccessDuration) {
                            Text("3 seconds").tag(3.0)
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("Never").tag(0.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                        .tint(.dsAccent)
                        .accessibilityLabel("Auto-dismiss after")
                    }
                }

                DSDivider()

                PreferenceRow("Popup position", subtitle: "Corner for Quick Access and pinned screenshots") {
                    Picker("", selection: $popupCorner) {
                        ForEach(ScreenCorner.allCases, id: \.rawValue) { corner in
                            Label(corner.rawValue, systemImage: corner.icon)
                                .tag(corner.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .tint(.dsAccent)
                    .accessibilityLabel("Popup position")
                }
            }

            PreferenceSection("Default Actions") {
                PreferenceRow("After capture") {
                    Picker("", selection: $afterCaptureAction) {
                        Text("Show Quick Access").tag("quickAccess")
                        Text("Copy to Clipboard").tag("clipboard")
                        Text("Save to File").tag("save")
                        Text("Open in Editor").tag("editor")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    .tint(.dsAccent)
                    .accessibilityLabel("After capture")
                }
            }
        }
        .onAppear {
            syncLaunchAtLoginState()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorLog("Failed to update launch-at-login preference", error: error)
            syncLaunchAtLoginState()

            let alert = NSAlert()
            alert.messageText = "Launch at Login Update Failed"
            alert.informativeText = "ScreenCapture couldn't update the login item. macOS may require you to update this setting in System Settings → General → Login Items."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func syncLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shortcuts Preferences

struct ShortcutsPreferencesView: View {
    @StateObject private var shortcutManager = SystemShortcutManager.shared
    @State private var isUpdating = false

    private var useNativeShortcuts: Bool {
        shortcutManager.shortcutsRemapped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            // Shortcut Mode Section
            PreferenceSection("Shortcut Mode") {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                            Text("Use Standard macOS Screenshot Shortcuts")
                                .font(DSTypography.bodyMedium)
                                .foregroundColor(.dsTextPrimary)

                            Text(useNativeShortcuts
                                 ? "ScreenCapture is using the ⌘⇧ layout."
                                 : "ScreenCapture is using the ⌃⇧ safe layout.")
                                .font(DSTypography.caption)
                                .foregroundColor(.dsTextTertiary)
                        }

                        Spacer()

                        // Status indicator
                        HStack(spacing: DSSpacing.xs) {
                            Circle()
                                .fill(useNativeShortcuts ? Color.dsAccent : Color.dsTextTertiary)
                                .frame(width: 8, height: 8)
                            Text(useNativeShortcuts ? "Standard" : "Safe")
                                .font(DSTypography.caption)
                                .foregroundColor(useNativeShortcuts ? .dsAccent : .dsTextTertiary)
                        }
                    }

                    DSDivider()

                    HStack {
                        if useNativeShortcuts {
                            Text("If macOS screenshot shortcuts are still enabled, disable them manually in System Settings → Keyboard → Keyboard Shortcuts → Screenshots.")
                                .font(DSTypography.caption)
                                .foregroundColor(.dsTextTertiary)
                        } else {
                            Text("Use this mode to avoid conflicts with macOS built-in screenshot shortcuts.")
                                .font(DSTypography.caption)
                                .foregroundColor(.dsTextTertiary)
                        }

                        Spacer()

                        Button(action: toggleShortcutMode) {
                            HStack(spacing: DSSpacing.xs) {
                                if isUpdating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: useNativeShortcuts ? "keyboard.badge.ellipsis" : "keyboard.fill")
                                        .font(.system(size: 12))
                                }
                                Text(useNativeShortcuts ? "Use Safe Shortcuts" : "Use Standard Shortcuts")
                                    .font(DSTypography.labelSmall)
                            }
                            .foregroundColor(useNativeShortcuts ? .dsWarmAccent : .dsAccent)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, DSSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DSRadius.sm)
                                    .fill(useNativeShortcuts ? Color.dsWarmAccent.opacity(0.1) : Color.dsAccent.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdating)
                    }
                }
            }

            PreferenceSection("Screenshot Shortcuts") {
                ShortcutRow(name: "Capture Area", shortcut: shortcut(for: .captureArea))
                DSDivider()
                ShortcutRow(name: "Capture Window", shortcut: shortcut(for: .captureWindow))
                DSDivider()
                ShortcutRow(name: "Capture Fullscreen", shortcut: shortcut(for: .captureFullscreen))
            }

            PreferenceSection("Recording Shortcuts") {
                ShortcutRow(name: "Record Area", shortcut: shortcut(for: .recordArea))
                DSDivider()
                ShortcutRow(name: "Record Window", shortcut: shortcut(for: .recordWindow))
                DSDivider()
                ShortcutRow(name: "Record Fullscreen", shortcut: shortcut(for: .recordFullscreen))
            }

            PreferenceSection("Tool Shortcuts") {
                ShortcutRow(name: "Capture Text (OCR)", shortcut: shortcut(for: .ocr))
                DSDivider()
                ShortcutRow(name: "Pin Screenshot", shortcut: shortcut(for: .pinScreenshot))
                DSDivider()
                ShortcutRow(name: "All-in-One Menu", shortcut: shortcut(for: .allInOne))
                DSDivider()
                ShortcutRow(name: "Open Screenshots Folder", shortcut: shortcut(for: .openScreenshotsFolder))
            }
        }
    }

    private func shortcut(for shortcut: KeyboardShortcuts.Shortcut) -> String {
        shortcut.displayShortcut(useNativeShortcuts: useNativeShortcuts)
    }

    private func toggleShortcutMode() {
        let wasUsingNativeShortcuts = useNativeShortcuts
        isUpdating = true
        let success = wasUsingNativeShortcuts
            ? shortcutManager.enableNativeShortcuts()
            : shortcutManager.disableNativeShortcuts()
        isUpdating = false

        if success {
            NotificationCenter.default.post(name: .shortcutsRemapped, object: nil)
            if !wasUsingNativeShortcuts {
                showManualShortcutInstructions()
            }
        }
    }

    private func showManualShortcutInstructions() {
        let alert = NSAlert()
        alert.messageText = "Standard Shortcuts Enabled"
        alert.informativeText = "To avoid conflicts, disable built-in Screenshot shortcuts manually in System Settings → Keyboard → Keyboard Shortcuts → Screenshots."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(name)
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextPrimary)

            Spacer()

            Text(shortcut)
                .font(DSTypography.mono)
                .foregroundColor(.dsTextSecondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.xs)
                        .fill(Color.dsBackgroundTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.xs)
                        .strokeBorder(Color.dsBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Capture Preferences

struct CapturePreferencesView: View {
    @AppStorage("showCursor") private var showCursor = false
    @AppStorage("captureFormat") private var captureFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            PreferenceSection("Capture Options") {
                DSToggle(isOn: $showCursor, label: "Include cursor in screenshots")
            }

            PreferenceSection("Image Format") {
                PreferenceRow("Default format") {
                    Picker("", selection: $captureFormat) {
                        Text("PNG").tag("png")
                        Text("JPEG").tag("jpeg")
                        Text("TIFF").tag("tiff")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityLabel("Default format")
                }

                if captureFormat == "jpeg" {
                    DSDivider()

                    PreferenceRow("JPEG Quality", subtitle: "\(Int(jpegQuality * 100))%") {
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                            .frame(width: 150)
                            .tint(.dsAccent)
                            .accessibilityLabel("JPEG Quality")
                    }
                }
            }
        }
    }
}

// MARK: - Recording Preferences

struct RecordingPreferencesView: View {
    @AppStorage("recordingQuality") private var recordingQuality = "high"
    @AppStorage("recordingFPS") private var recordingFPS = 60
    @AppStorage("recordShowCursor") private var recordShowCursor = true
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("recordSystemAudio") private var recordSystemAudio = true
    @AppStorage("showMouseClicks") private var showMouseClicks = true
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            PreferenceSection("Video Recording") {
                PreferenceRow("Quality") {
                    Picker("", selection: $recordingQuality) {
                        Text("Low (720p)").tag("low")
                        Text("Medium (1080p)").tag("medium")
                        Text("High (Native)").tag("high")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .tint(.dsAccent)
                    .accessibilityLabel("Video quality")
                }

                DSDivider()

                PreferenceRow("Frame Rate") {
                    Picker("", selection: $recordingFPS) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .accessibilityLabel("Frame rate")
                }

                DSDivider()

                DSToggle(isOn: $recordShowCursor, label: "Show cursor")
            }

            PreferenceSection("Audio") {
                DSToggle(isOn: $recordMicrophone, label: "Record microphone")
                DSDivider()
                DSToggle(isOn: $recordSystemAudio, label: "Record system audio")
            }

            PreferenceSection("Visual Feedback") {
                DSToggle(isOn: $showMouseClicks, label: "Highlight mouse clicks")
                DSDivider()
                PreferenceRow("Keystroke overlay", subtitle: "Not available in native capture mode") {
                    Text("Unavailable")
                        .font(DSTypography.labelSmall)
                        .foregroundColor(.dsTextTertiary)
                }
            }

        }
    }
}

// MARK: - Storage Preferences

@MainActor
struct StoragePreferencesView: View {
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    @State private var storageLocation: String = "default"
    @State private var storageUsed: String = "Calculating..."
    @State private var currentPath: String = ""

    @MainActor private var storageManager: StorageManager {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.storageManager
        }
        return StorageManager()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            PreferenceSection("Storage Location") {
                HStack {
                    Text("Save screenshots to")
                        .font(DSTypography.bodyMedium)
                        .foregroundColor(.dsTextPrimary)

                    Spacer()

                    if storageLocation == "custom" {
                        DSSecondaryButton("Choose...", icon: "folder") {
                            chooseCustomLocation()
                        }
                    }

                    Picker("", selection: $storageLocation) {
                        Text("Default (App Support)").tag("default")
                        Text("Desktop").tag("desktop")
                        Text("Custom Folder").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .tint(.dsAccent)
                    .accessibilityLabel("Save screenshots to")
                    .onChange(of: storageLocation) { _, newValue in
                        if newValue != "custom" {
                            storageManager.setStorageLocation(newValue)
                            updateCurrentPath()
                        }
                    }
                }

                DSDivider()

                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                        Text("Current location")
                            .font(DSTypography.caption)
                            .foregroundColor(.dsTextTertiary)
                        Text(currentPath)
                            .font(DSTypography.monoSmall)
                            .foregroundColor(.dsTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    DSSecondaryButton("Open Folder", icon: "arrow.up.right") {
                        openScreenshotsFolder()
                    }
                }
            }

            PreferenceSection("Storage Management") {
                PreferenceRow("Storage used") {
                    HStack(spacing: DSSpacing.sm) {
                        Text(storageUsed)
                            .font(DSTypography.labelMedium)
                            .foregroundColor(.dsAccent)

                        // Storage indicator
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.dsAccent.opacity(0.3))
                            .frame(width: 60, height: 6)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.dsAccent)
                                    .frame(width: 20)
                            }
                    }
                }

                DSDivider()

                HStack(alignment: .center) {
                    Text("Automatically delete old captures")
                        .font(DSTypography.bodyMedium)
                        .foregroundColor(.dsTextPrimary)

                    Spacer()

                    if autoCleanup {
                        Picker("", selection: $cleanupDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .tint(.dsAccent)
                        .accessibilityLabel("Cleanup retention period")
                    }

                    Button(action: clearAllCaptures) {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Clear All Captures...")
                                .font(DSTypography.labelSmall)
                        }
                        .foregroundColor(.dsDanger)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.sm)
                                .fill(Color.dsDanger.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: $autoCleanup)
                        .toggleStyle(SwitchToggleStyle(tint: .dsAccent))
                        .labelsHidden()
                        .accessibilityLabel("Automatically delete old captures")
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
            calculateStorageUsed()
        }
        .onChange(of: autoCleanup) { _, _ in
            storageManager.applyCleanupPolicy()
            calculateStorageUsed()
        }
        .onChange(of: cleanupDays) { _, _ in
            storageManager.applyCleanupPolicy()
            calculateStorageUsed()
        }
    }

    private func loadCurrentSettings() {
        storageLocation = storageManager.getStorageLocation()
        updateCurrentPath()
    }

    private func updateCurrentPath() {
        currentPath = storageManager.screenshotsDirectory.path
    }

    private func chooseCustomLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to save screenshots"
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            if storageManager.setCustomFolder(url) {
                storageLocation = "custom"
                updateCurrentPath()
                debugLog("StoragePreferences: Custom folder set to \(url.path)")
            } else {
                let alert = NSAlert()
                alert.messageText = "Cannot Use This Folder"
                alert.informativeText = "ScreenCapture doesn't have permission to save files to this folder. Please choose a different location."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func openScreenshotsFolder() {
        NSWorkspace.shared.open(storageManager.screenshotsDirectory)
    }

    private func calculateStorageUsed() {
        let screenshotsDir = storageManager.screenshotsDirectory

        DispatchQueue.global(qos: .background).async {
            var totalSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: screenshotsDir, includingPropertiesForKeys: [.fileSizeKey]) {
                while let url = enumerator.nextObject() as? URL {
                    if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let formattedSize = formatter.string(fromByteCount: totalSize)

            DispatchQueue.main.async {
                self.storageUsed = formattedSize
            }
        }
    }

    private func clearAllCaptures() {
        let alert = NSAlert()
        alert.messageText = "Clear All Captures?"
        alert.informativeText = "This will permanently delete all screenshots and recordings. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            _ = storageManager.clearAllCaptures()
            calculateStorageUsed()
        }
    }
}

// MARK: - Advanced Preferences

struct AdvancedPreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            PreferenceSection("Diagnostics") {
                PreferenceRow("Debug log file") {
                    HStack(spacing: DSSpacing.sm) {
                        Text(DebugLogger.shared.logFilePath)
                            .font(DSTypography.monoSmall)
                            .foregroundColor(.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 300, alignment: .trailing)

                        DSSecondaryButton("Open Log", icon: "doc.text") {
                            openDebugLogFile()
                        }
                    }
                }

                DSDivider()

                PreferenceRow("Log directory") {
                    DSSecondaryButton("Open Folder", icon: "folder") {
                        openDebugLogFolder()
                    }
                }
            }

            PreferenceSection("Developer") {
                HStack(alignment: .center) {
                    Text("Reset all preferences")
                        .font(DSTypography.bodyMedium)
                        .foregroundColor(.dsTextPrimary)

                    Spacer()

                    Button(action: resetPreferences) {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                            Text("Reset All Preferences")
                                .font(DSTypography.labelSmall)
                        }
                        .foregroundColor(.dsWarmAccent)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DSRadius.sm)
                                .fill(Color.dsWarmAccent.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            PreferenceSection("About") {
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                        Text("ScreenCapture")
                            .font(DSTypography.headlineSmall)
                            .foregroundColor(.dsTextPrimary)
                        Text(AppVersionInfo.aboutVersionLabel)
                            .font(DSTypography.caption)
                            .foregroundColor(.dsTextTertiary)
                    }

                    Spacer()
                }
            }
        }
    }

    private func openDebugLogFile() {
        let url = URL(fileURLWithPath: DebugLogger.shared.logFilePath)
        NSWorkspace.shared.open(url)
    }

    private func openDebugLogFolder() {
        let url = URL(fileURLWithPath: DebugLogger.shared.logFilePath).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    private func resetPreferences() {
        let alert = NSAlert()
        alert.messageText = "Reset All Preferences?"
        alert.informativeText = "This will reset all settings to their default values."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
    }
}

// MARK: - Visual Effect View (for backwards compatibility)

struct VisualEffectView: NSViewRepresentable {
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
