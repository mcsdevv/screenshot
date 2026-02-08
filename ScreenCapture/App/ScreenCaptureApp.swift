import SwiftUI
import AppKit

@main
struct ScreenCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(ScreenRecordingManager.recordWindowSelectionModeKey) private var isSelectingRecordWindow = false

    private var menuBarSymbolName: String {
        isSelectingRecordWindow ? "video" : "camera.viewfinder"
    }

    var body: some Scene {
        // Menu bar extra - this is the SwiftUI native way to create menu bar items
        MenuBarExtra("ScreenCapture", systemImage: menuBarSymbolName, isInserted: $showMenuBarIcon) {
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
    @StateObject private var shortcutManager = SystemShortcutManager.shared

    /// Returns the appropriate modifier keys based on shortcut mode
    private var captureModifiers: EventModifiers {
        shortcutManager.shortcutsRemapped ? [.command, .shift] : [.control, .shift]
    }

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
                .keyboardShortcut("4", modifiers: captureModifiers)

                Button {
                    debugLog("MenuBar: Capture Window clicked")
                    appDelegate.screenshotManager.captureWindow()
                } label: {
                    Label("Capture Window", systemImage: "macwindow")
                }
                .keyboardShortcut("5", modifiers: captureModifiers)

                Button {
                    debugLog("MenuBar: Capture Fullscreen clicked")
                    appDelegate.screenshotManager.captureFullscreen()
                } label: {
                    Label("Capture Fullscreen", systemImage: "rectangle.inset.filled")
                }
                .keyboardShortcut("3", modifiers: captureModifiers)

                Button {
                    debugLog("MenuBar: Scrolling Capture clicked")
                    appDelegate.screenshotManager.captureScrolling()
                } label: {
                    Label("Scrolling Capture", systemImage: "scroll")
                }
                .keyboardShortcut("6", modifiers: captureModifiers)
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
                .keyboardShortcut("7", modifiers: captureModifiers)

                Button {
                    debugLog("MenuBar: Record Window clicked")
                    appDelegate.screenRecordingManager.startWindowRecordingSelection()
                } label: {
                    Label("Record Window", systemImage: "video")
                }
                .keyboardShortcut("8", modifiers: [.shift, .option])
            } header: {
                Label("Record", systemImage: "video.fill")
            }

            Divider()

            Section {
                Button {
                    debugLog("MenuBar: Capture Text (OCR) clicked")
                    appDelegate.screenshotManager.captureForOCR()
                } label: {
                    Label("Capture Text (OCR)", systemImage: "text.viewfinder")
                }
                .keyboardShortcut("o", modifiers: captureModifiers)

                Button {
                    debugLog("MenuBar: Pin Screenshot clicked")
                    appDelegate.screenshotManager.captureForPinning()
                } label: {
                    Label("Pin Screenshot", systemImage: "pin.fill")
                }
                .keyboardShortcut("p", modifiers: captureModifiers)
                
                Divider()
                
                Button {
                    debugLog("MenuBar: Toggle Webcam clicked")
                    if let webcamManager = appDelegate.webcamManager {
                        webcamManager.toggleWebcam()
                    }
                } label: {
                    if let webcamManager = appDelegate.webcamManager, webcamManager.isWebcamVisible {
                        Label("Hide Webcam", systemImage: "video.slash")
                    } else {
                        Label("Show Webcam", systemImage: "video")
                    }
                }
                .keyboardShortcut("w", modifiers: captureModifiers)
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
                appDelegate.requestQuit()
            } label: {
                Label("Quit ScreenCapture", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
