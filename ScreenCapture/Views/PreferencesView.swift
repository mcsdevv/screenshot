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
        NavigationSplitView {
            List(PreferencesTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
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
            .frame(minWidth: 500, minHeight: 400)
            .navigationTitle(selectedTab.rawValue)
        }
        .frame(width: 700, height: 500)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ScreenCapture Settings")
                    .font(.headline)
            }
        }
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
    @AppStorage("storageLocation") private var storageLocation = "default"
    @AppStorage("autoCleanup") private var autoCleanup = true
    @AppStorage("cleanupDays") private var cleanupDays = 30

    @State private var customLocation: URL?
    @State private var storageUsed: String = "Calculating..."

    var body: some View {
        Form {
            Section("Storage Location") {
                Picker("Save screenshots to", selection: $storageLocation) {
                    Text("Default Location").tag("default")
                    Text("Desktop").tag("desktop")
                    Text("Custom...").tag("custom")
                }

                if storageLocation == "custom" {
                    HStack {
                        Text(customLocation?.path ?? "Not set")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Choose...") {
                            chooseCustomLocation()
                        }
                    }
                }

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
            calculateStorageUsed()
        }
    }

    private func chooseCustomLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            customLocation = panel.url
        }
    }

    private func openScreenshotsFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let screenshotsDir = appSupport.appendingPathComponent("ScreenCapture/Screenshots")
        NSWorkspace.shared.open(screenshotsDir)
    }

    private func calculateStorageUsed() {
        DispatchQueue.global(qos: .background).async {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let screenshotsDir = appSupport.appendingPathComponent("ScreenCapture/Screenshots")

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
