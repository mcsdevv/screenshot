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

            Button("Capture Area ⌘⇧4") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureArea()
                }
            }

            Button("Capture Window ⌘⇧5") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureWindow()
                }
            }

            Button("Capture Fullscreen ⌘⇧3") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureFullscreen()
                }
            }

            Button("Scrolling Capture ⌘⇧6") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureScrolling()
                }
            }

            Divider()

            Text("Record")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Record Screen ⌘⇧7") {
                Task { @MainActor in
                    appDelegate.screenRecordingManager.toggleRecording()
                }
            }

            Button("Record GIF ⌘⇧8") {
                Task { @MainActor in
                    appDelegate.screenRecordingManager.toggleGIFRecording()
                }
            }

            Divider()

            Text("Tools")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Capture Text (OCR) ⌘⇧O") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureForOCR()
                }
            }

            Button("Pin Screenshot ⌘⇧P") {
                Task { @MainActor in
                    appDelegate.screenshotManager.captureForPinning()
                }
            }

            Divider()

            Button("Open Screenshots Folder") {
                NSWorkspace.shared.open(appDelegate.storageManager.screenshotsDirectory)
            }

            SettingsLink {
                Text("Preferences...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit ScreenCapture") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
