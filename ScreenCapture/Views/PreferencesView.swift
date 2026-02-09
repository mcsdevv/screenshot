import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsPreferencesView()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

            CapturePreferencesView()
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }

            RecordingPreferencesView()
                .tabItem {
                    Label("Recording", systemImage: "video")
                }

            StoragePreferencesView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }

            AdvancedPreferencesView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 500)
    }
}

private enum AppVersionInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var aboutVersionLabel: String {
        "Version \(shortVersion) (Build \(buildNumber))"
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
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        guard launchAtLogin != newValue else { return }
                        launchAtLogin = newValue
                        updateLaunchAtLogin(newValue)
                    }
                ))
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
            }

            Section("Feedback") {
                Toggle("Play sound after capture", isOn: $playSound)
                Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)

                if showQuickAccess {
                    Picker("Auto-dismiss after", selection: $quickAccessDuration) {
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("Never").tag(0.0)
                    }
                }

                Picker("Popup position", selection: $popupCorner) {
                    ForEach(ScreenCorner.allCases, id: \.rawValue) { corner in
                        Text(corner.rawValue).tag(corner.rawValue)
                    }
                }
            }

            Section("Default Actions") {
                Picker("After capture", selection: $afterCaptureAction) {
                    Text("Show Quick Access").tag("quickAccess")
                    Text("Copy to Clipboard").tag("clipboard")
                    Text("Save to File").tag("save")
                    Text("Open in Editor").tag("editor")
                }
            }
        }
        .formStyle(.grouped)
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
            alert.informativeText = "ScreenCapture couldn't update the login item. macOS may require you to update this setting in System Settings \u{2192} General \u{2192} Login Items."
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
        Form {
            Section {
                LabeledContent {
                    Text(useNativeShortcuts ? "Standard" : "Safe")
                        .foregroundStyle(useNativeShortcuts ? Color.green : .secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shortcut Mode")
                        Text(useNativeShortcuts
                             ? "Using standard macOS shortcuts (\u{2318}\u{21E7})"
                             : "Using safe shortcuts (\u{2303}\u{21E7})")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if useNativeShortcuts {
                    Text("Disable built-in Screenshot shortcuts in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(useNativeShortcuts ? "Switch to Safe Shortcuts" : "Switch to Standard Shortcuts") {
                    toggleShortcutMode()
                }
                .disabled(isUpdating)
            }

            Section("Screenshot Shortcuts") {
                shortcutRow("Capture Area", shortcut: .captureArea)
                shortcutRow("Capture Window", shortcut: .captureWindow)
                shortcutRow("Capture Fullscreen", shortcut: .captureFullscreen)
            }

            Section("Recording Shortcuts") {
                shortcutRow("Record Area", shortcut: .recordArea)
                shortcutRow("Record Window", shortcut: .recordWindow)
                shortcutRow("Record Fullscreen", shortcut: .recordFullscreen)
            }

            Section("Tool Shortcuts") {
                shortcutRow("Capture Text (OCR)", shortcut: .ocr)
                shortcutRow("Pin Screenshot", shortcut: .pinScreenshot)
                shortcutRow("All-in-One Menu", shortcut: .allInOne)
                shortcutRow("Open Screenshots Folder", shortcut: .openScreenshotsFolder)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func shortcutRow(_ name: String, shortcut: KeyboardShortcuts.Shortcut) -> some View {
        LabeledContent(name) {
            Text(shortcut.displayShortcut(useNativeShortcuts: useNativeShortcuts))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
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
        alert.informativeText = "To avoid conflicts, disable built-in Screenshot shortcuts manually in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Screenshots."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - Capture Preferences

struct CapturePreferencesView: View {
    @AppStorage("showCursor") private var showCursor = false
    @AppStorage("captureFormat") private var captureFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9

    var body: some View {
        Form {
            Section("Capture Options") {
                Toggle("Include cursor in screenshots", isOn: $showCursor)
            }

            Section("Image Format") {
                Picker("Default format", selection: $captureFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("TIFF").tag("tiff")
                }
                .pickerStyle(.segmented)

                if captureFormat == "jpeg" {
                    LabeledContent("JPEG quality \u{2014} \(Int(jpegQuality * 100))%") {
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                            .frame(width: 150)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section("Video") {
                Picker("Quality", selection: $recordingQuality) {
                    Text("Low (720p)").tag("low")
                    Text("Medium (1080p)").tag("medium")
                    Text("High (Native)").tag("high")
                }

                Picker("Frame rate", selection: $recordingFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                .pickerStyle(.segmented)

                Toggle("Show cursor", isOn: $recordShowCursor)
            }

            Section("Audio") {
                Toggle("Record microphone", isOn: $recordMicrophone)
                Toggle("Record system audio", isOn: $recordSystemAudio)
            }

            Section("Visual Feedback") {
                Toggle("Highlight mouse clicks", isOn: $showMouseClicks)
                LabeledContent("Keystroke overlay") {
                    Text("Unavailable")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage Preferences

enum StorageLocationSelectionAction: Equatable {
    case ignore
    case setStorageLocation(String)
    case chooseCustomFolder(revertTo: String)
}

enum StorageLocationSelectionCoordinator {
    static func actionForChange(
        oldValue: String,
        newValue: String,
        suppressNextChange: Bool
    ) -> StorageLocationSelectionAction {
        if suppressNextChange || oldValue == newValue {
            return .ignore
        }

        if newValue == "custom" {
            return .chooseCustomFolder(revertTo: oldValue)
        }

        return .setStorageLocation(newValue)
    }

    static func selectionAfterCustomFolderPicker(
        isConfirmed: Bool,
        didPersistCustomFolder: Bool,
        currentSelection: String,
        revertSelection: String?
    ) -> String {
        guard isConfirmed else {
            return revertSelection ?? currentSelection
        }

        guard didPersistCustomFolder else {
            return revertSelection ?? currentSelection
        }

        return "custom"
    }
}

@MainActor
struct StoragePreferencesView: View {
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    @State private var storageLocation: String = "default"
    @State private var previousStorageLocation: String = "default"
    @State private var suppressStorageLocationChange = false
    @State private var storageUsed: String = "Calculating..."
    @State private var currentPath: String = ""

    @MainActor private var storageManager: StorageManager {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.storageManager
        }
        return StorageManager()
    }

    var body: some View {
        Form {
            Section("Storage Location") {
                Picker("Save screenshots to", selection: $storageLocation) {
                    Text("Default (App Support)").tag("default")
                    Text("Desktop").tag("desktop")
                    Text("Custom Folder").tag("custom")
                }
                .onChange(of: storageLocation) { oldValue, newValue in
                    handleStorageLocationSelectionChange(from: oldValue, to: newValue)
                }

                if storageLocation == "custom" {
                    Button("Choose Folder...") {
                        chooseCustomLocation()
                    }
                }

                LabeledContent("Current location") {
                    Text(currentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Reveal in Finder") {
                    openScreenshotsFolder()
                }
            }

            Section("Storage Management") {
                LabeledContent("Storage used") {
                    Text(storageUsed)
                }

                Toggle("Automatically delete old captures", isOn: $autoCleanup)

                if autoCleanup {
                    Picker("Delete after", selection: $cleanupDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                }

                Button("Clear All Captures\u{2026}", role: .destructive) {
                    clearAllCaptures()
                }
            }
        }
        .formStyle(.grouped)
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
        applyStorageSelection(storageManager.getStorageLocation())
        updateCurrentPath()
    }

    private func applyStorageSelection(_ selection: String) {
        let didChangeSelection = storageLocation != selection
        suppressStorageLocationChange = didChangeSelection
        if didChangeSelection {
            storageLocation = selection
        }
        previousStorageLocation = selection
    }

    private func handleStorageLocationSelectionChange(from oldValue: String, to newValue: String) {
        let action = StorageLocationSelectionCoordinator.actionForChange(
            oldValue: oldValue,
            newValue: newValue,
            suppressNextChange: suppressStorageLocationChange
        )

        if suppressStorageLocationChange {
            suppressStorageLocationChange = false
            previousStorageLocation = newValue
        }

        switch action {
        case .ignore:
            return
        case .setStorageLocation(let location):
            storageManager.setStorageLocation(location)
            previousStorageLocation = location
            updateCurrentPath()
        case .chooseCustomFolder(let revertTo):
            chooseCustomLocation(revertSelection: revertTo)
        }
    }

    private func updateCurrentPath() {
        currentPath = storageManager.screenshotsDirectory.path
    }

    private func chooseCustomLocation(revertSelection: String? = nil) {
        let fallbackSelection = revertSelection ?? previousStorageLocation
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to save screenshots"
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            if storageManager.setCustomFolder(url) {
                storageLocation = "custom"
                previousStorageLocation = "custom"
                updateCurrentPath()
                debugLog("StoragePreferences: Custom folder set to \(url.path)")
            } else {
                let alert = NSAlert()
                alert.messageText = "Cannot Use This Folder"
                alert.informativeText = "ScreenCapture doesn't have permission to save files to this folder. Please choose a different location."
                alert.alertStyle = .warning
                alert.runModal()
                let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
                    isConfirmed: true,
                    didPersistCustomFolder: false,
                    currentSelection: storageLocation,
                    revertSelection: fallbackSelection
                )
                applyStorageSelection(selection)
                updateCurrentPath()
            }
            return
        }

        let selection = StorageLocationSelectionCoordinator.selectionAfterCustomFolderPicker(
            isConfirmed: false,
            didPersistCustomFolder: false,
            currentSelection: storageLocation,
            revertSelection: fallbackSelection
        )
        applyStorageSelection(selection)
        updateCurrentPath()
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
        Form {
            Section("Diagnostics") {
                LabeledContent("Debug log") {
                    HStack(spacing: 8) {
                        Text(DebugLogger.shared.logFilePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 250, alignment: .trailing)

                        Button("Open") {
                            openDebugLogFile()
                        }
                    }
                }

                LabeledContent("Log directory") {
                    Button("Reveal in Finder") {
                        openDebugLogFolder()
                    }
                }
            }

            Section("Developer") {
                Button("Reset All Preferences\u{2026}", role: .destructive) {
                    resetPreferences()
                }
            }

            Section("About") {
                LabeledContent("App") {
                    Text("ScreenCapture")
                }
                LabeledContent("Version") {
                    Text(AppVersionInfo.aboutVersionLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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

// MARK: - Visual Effect View (used by QuickAccessOverlay)

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
