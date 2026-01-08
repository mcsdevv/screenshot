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
            case .general: return "gear"
            case .shortcuts: return "keyboard"
            case .capture: return "camera"
            case .recording: return "video"
            case .storage: return "externaldrive"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Spacer for traffic light buttons
                Spacer()
                    .frame(height: 38)

                // Sidebar items
                VStack(spacing: 2) {
                    ForEach(PreferencesTab.allCases, id: \.self) { tab in
                        SidebarItem(
                            icon: tab.icon,
                            title: tab.rawValue,
                            isSelected: selectedTab == tab
                        ) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .frame(width: 200)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))

            // Main content
            VStack(spacing: 0) {
                // Toolbar area
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(height: 52)
                .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))

                Divider()

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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 700, minHeight: 550)
        .frame(width: 750, height: 600)
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

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

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("playSound") private var playSound = true
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("quickAccessDuration") private var quickAccessDuration = 5.0

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch ScreenCapture at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }

                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
            }

            Section("Feedback") {
                Toggle("Play sound after capture", isOn: $playSound)

                Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)

                if showQuickAccess {
                    HStack {
                        Text("Auto-dismiss after")
                        Picker("", selection: $quickAccessDuration) {
                            Text("3 seconds").tag(3.0)
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("Never").tag(0.0)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            }

            Section("Default Actions") {
                Picker("After capture", selection: .constant("quickAccess")) {
                    Text("Show Quick Access").tag("quickAccess")
                    Text("Copy to Clipboard").tag("clipboard")
                    Text("Save to File").tag("save")
                    Text("Open in Editor").tag("editor")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

struct ShortcutsPreferencesView: View {
    var body: some View {
        Form {
            Section("Screenshot Shortcuts") {
                ShortcutRow(name: "Capture Area", shortcut: "⌘⇧4")
                ShortcutRow(name: "Capture Window", shortcut: "⌘⇧5")
                ShortcutRow(name: "Capture Fullscreen", shortcut: "⌘⇧3")
                ShortcutRow(name: "Scrolling Capture", shortcut: "⌘⇧6")
            }

            Section("Recording Shortcuts") {
                ShortcutRow(name: "Record Screen", shortcut: "⌘⇧7")
                ShortcutRow(name: "Record GIF", shortcut: "⌘⇧8")
            }

            Section("Tool Shortcuts") {
                ShortcutRow(name: "Capture Text (OCR)", shortcut: "⌘⇧O")
                ShortcutRow(name: "Pin Screenshot", shortcut: "⌘⇧P")
                ShortcutRow(name: "All-in-One Menu", shortcut: "⌘⇧⌥A")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

struct CapturePreferencesView: View {
    @AppStorage("hideDesktopIcons") private var hideDesktopIcons = false
    @AppStorage("showCursor") private var showCursor = false
    @AppStorage("showDimensions") private var showDimensions = true
    @AppStorage("showMagnifier") private var showMagnifier = true
    @AppStorage("captureFormat") private var captureFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9

    var body: some View {
        Form {
            Section("Capture Options") {
                Toggle("Hide desktop icons during capture", isOn: $hideDesktopIcons)
                Toggle("Include cursor in screenshots", isOn: $showCursor)
                Toggle("Show selection dimensions", isOn: $showDimensions)
                Toggle("Show magnifier when selecting", isOn: $showMagnifier)
            }

            Section("Image Format") {
                Picker("Default format", selection: $captureFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("TIFF").tag("tiff")
                }

                if captureFormat == "jpeg" {
                    HStack {
                        Text("JPEG Quality")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                        Text("\(Int(jpegQuality * 100))%")
                            .frame(width: 40)
                    }
                }
            }

            Section("Window Capture") {
                Toggle("Capture window shadow", isOn: .constant(true))
                Toggle("Capture rounded corners", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct RecordingPreferencesView: View {
    @AppStorage("recordingQuality") private var recordingQuality = "high"
    @AppStorage("recordingFPS") private var recordingFPS = 60
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("recordSystemAudio") private var recordSystemAudio = true
    @AppStorage("showMouseClicks") private var showMouseClicks = true
    @AppStorage("showKeystrokes") private var showKeystrokes = false
    @AppStorage("gifFPS") private var gifFPS = 15
    @AppStorage("gifQuality") private var gifQuality = "medium"

    var body: some View {
        Form {
            Section("Video Recording") {
                Picker("Quality", selection: $recordingQuality) {
                    Text("Low (720p)").tag("low")
                    Text("Medium (1080p)").tag("medium")
                    Text("High (Native)").tag("high")
                }

                Picker("Frame Rate", selection: $recordingFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
            }

            Section("Audio") {
                Toggle("Record microphone", isOn: $recordMicrophone)
                Toggle("Record system audio", isOn: $recordSystemAudio)
            }

            Section("Visual Feedback") {
                Toggle("Highlight mouse clicks", isOn: $showMouseClicks)
                Toggle("Show keystrokes", isOn: $showKeystrokes)
            }

            Section("GIF Recording") {
                Picker("Frame Rate", selection: $gifFPS) {
                    Text("10 FPS").tag(10)
                    Text("15 FPS").tag(15)
                    Text("20 FPS").tag(20)
                }

                Picker("Quality", selection: $gifQuality) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct StoragePreferencesView: View {
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    @State private var storageLocation: String = "default"
    @State private var customLocationPath: String = "Not set"
    @State private var storageUsed: String = "Calculating..."
    @State private var currentPath: String = ""

    // Access StorageManager from environment or create reference
    private var storageManager: StorageManager {
        // Get from app delegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.storageManager
        }
        // Fallback - shouldn't happen
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
                .onChange(of: storageLocation) { _, newValue in
                    if newValue != "custom" {
                        storageManager.setStorageLocation(newValue)
                        updateCurrentPath()
                    }
                }

                if storageLocation == "custom" {
                    HStack {
                        Text(customLocationPath)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
                            chooseCustomLocation()
                        }
                    }
                }

                HStack {
                    Text("Current location:")
                        .foregroundColor(.secondary)
                    Text(currentPath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)

                Button("Open Screenshots Folder") {
                    openScreenshotsFolder()
                }
            }

            Section("Storage Management") {
                HStack {
                    Text("Storage used")
                    Spacer()
                    Text(storageUsed)
                        .foregroundColor(.secondary)
                }

                Toggle("Automatically delete old captures", isOn: $autoCleanup)

                if autoCleanup {
                    Picker("Delete captures older than", selection: $cleanupDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }

                    Text("Favorites are never automatically deleted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Clear All Captures...", role: .destructive) {
                    clearAllCaptures()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadCurrentSettings()
            calculateStorageUsed()
        }
    }

    private func loadCurrentSettings() {
        storageLocation = storageManager.getStorageLocation()
        updateCurrentPath()

        if let customURL = storageManager.getCustomFolderURL() {
            customLocationPath = customURL.path
        }
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
                customLocationPath = url.path
                storageLocation = "custom"
                updateCurrentPath()
                debugLog("StoragePreferences: Custom folder set to \(url.path)")
            } else {
                // Show error
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
            // Clear captures
            calculateStorageUsed()
        }
    }
}

struct AdvancedPreferencesView: View {
    @AppStorage("enableHardwareAcceleration") private var enableHardwareAcceleration = true
    @AppStorage("reducedMotion") private var reducedMotion = false
    @AppStorage("debugMode") private var debugMode = false

    var body: some View {
        Form {
            Section("Performance") {
                Toggle("Enable hardware acceleration", isOn: $enableHardwareAcceleration)
                Toggle("Reduce motion effects", isOn: $reducedMotion)
            }

            Section("Developer") {
                Toggle("Enable debug mode", isOn: $debugMode)

                Button("Reset All Preferences") {
                    resetPreferences()
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                Link("View on GitHub", destination: URL(string: "https://github.com")!)
                Link("Report an Issue", destination: URL(string: "https://github.com")!)
            }
        }
        .formStyle(.grouped)
        .padding()
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
