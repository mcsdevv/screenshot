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
            // Capture section
            Section {
                Button {
                    debugLog("MenuBar: Capture Area clicked")
                    appDelegate.screenshotManager.captureArea()
                } label: {
                    Label("Capture Area", systemImage: "rectangle.dashed")
                }
                .keyboardShortcut("4", modifiers: [.control, .shift])

                Button {
                    debugLog("MenuBar: Capture Window clicked")
                    appDelegate.screenshotManager.captureWindow()
                } label: {
                    Label("Capture Window", systemImage: "macwindow")
                }
                .keyboardShortcut("5", modifiers: [.control, .shift])

                Button {
                    debugLog("MenuBar: Capture Fullscreen clicked")
                    appDelegate.screenshotManager.captureFullscreen()
                } label: {
                    Label("Capture Fullscreen", systemImage: "rectangle.inset.filled")
                }
                .keyboardShortcut("3", modifiers: [.control, .shift])

                Button {
                    debugLog("MenuBar: Scrolling Capture clicked")
                    appDelegate.screenshotManager.captureScrolling()
                } label: {
                    Label("Scrolling Capture", systemImage: "scroll")
                }
                .keyboardShortcut("6", modifiers: [.control, .shift])
            } header: {
                Label("Capture", systemImage: "camera.fill")
            }

            Divider()

            // Record section
            Section {
                Button {
                    debugLog("MenuBar: Record Screen clicked")
                    appDelegate.screenRecordingManager.toggleRecording()
                } label: {
                    Label("Record Screen", systemImage: "record.circle")
                }
                .keyboardShortcut("7", modifiers: [.control, .shift])

                Button {
                    debugLog("MenuBar: Record GIF clicked")
                    appDelegate.screenRecordingManager.toggleGIFRecording()
                } label: {
                    Label("Record GIF", systemImage: "gift")
                }
                .keyboardShortcut("8", modifiers: [.control, .shift])
            } header: {
                Label("Record", systemImage: "video.fill")
            }

            Divider()

            // Tools section
            Section {
                Button {
                    debugLog("MenuBar: Capture Text (OCR) clicked")
                    appDelegate.screenshotManager.captureForOCR()
                } label: {
                    Label("Capture Text (OCR)", systemImage: "text.viewfinder")
                }
                .keyboardShortcut("o", modifiers: [.control, .shift])

                Button {
                    debugLog("MenuBar: Pin Screenshot clicked")
                    appDelegate.screenshotManager.captureForPinning()
                } label: {
                    Label("Pin Screenshot", systemImage: "pin.fill")
                }
                .keyboardShortcut("p", modifiers: [.control, .shift])
            } header: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }

            Divider()

            // Other actions
            Button {
                debugLog("MenuBar: Open Screenshots Folder clicked")
                NSWorkspace.shared.open(appDelegate.storageManager.screenshotsDirectory)
            } label: {
                Label("Open Screenshots Folder", systemImage: "folder")
            }

            SettingsLink {
                Label("Preferences...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button {
                debugLog("MenuBar: Quit clicked")
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit ScreenCapture", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
