import SwiftUI
import AppKit

@main
struct ScreenCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar extra - this is the SwiftUI native way to create menu bar items
        MenuBarExtra("ScreenCapture", systemImage: "camera.viewfinder") {
            MenuBarMenuView(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) { }
        }

        WindowGroup("Capture History", id: "history") {
            CaptureHistoryView()
                .environmentObject(appDelegate.storageManager)
                .navigationTitle("Capture History")
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 900, height: 600)

        WindowGroup("Annotation Editor", id: "editor", for: UUID.self) { $captureId in
            if let id = captureId,
               let capture = appDelegate.storageManager.getCapture(id: id) {
                AnnotationEditor(capture: capture)
                    .environmentObject(appDelegate.storageManager)
            }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
    }
}

struct MenuBarMenuView: View {
    let appDelegate: AppDelegate

    var body: some View {
        Group {
            Text("Capture")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Capture Area") {
                debugLog("MenuBar: Capture Area clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureArea()
                }
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            Button("Capture Window") {
                debugLog("MenuBar: Capture Window clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureWindow()
                }
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            Button("Capture Fullscreen") {
                debugLog("MenuBar: Capture Fullscreen clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureFullscreen()
                }
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])

            Button("Scrolling Capture") {
                debugLog("MenuBar: Scrolling Capture clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureScrolling()
                }
            }
            .keyboardShortcut("6", modifiers: [.command, .shift])

            Divider()

            Text("Record")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Record Screen") {
                debugLog("MenuBar: Record Screen clicked")
                Task { @MainActor in
                    appDelegate.screenRecordingManager.toggleRecording()
                }
            }
            .keyboardShortcut("7", modifiers: [.command, .shift])

            Button("Record GIF") {
                debugLog("MenuBar: Record GIF clicked")
                Task { @MainActor in
                    appDelegate.screenRecordingManager.toggleGIFRecording()
                }
            }
            .keyboardShortcut("8", modifiers: [.command, .shift])

            Divider()

            Text("Tools")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Capture Text (OCR)") {
                debugLog("MenuBar: Capture Text (OCR) clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureForOCR()
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Pin Screenshot") {
                debugLog("MenuBar: Pin Screenshot clicked")
                Task { @MainActor in
                    appDelegate.screenshotManager.captureForPinning()
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("Open Screenshots Folder") {
                debugLog("MenuBar: Open Screenshots Folder clicked")
                NSWorkspace.shared.open(appDelegate.storageManager.screenshotsDirectory)
            }

            SettingsLink {
                Text("Preferences...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit ScreenCapture") {
                debugLog("MenuBar: Quit clicked")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
