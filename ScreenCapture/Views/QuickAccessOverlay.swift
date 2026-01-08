import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Use a class to safely manage the overlay's actions and lifecycle
class QuickAccessOverlayController: ObservableObject {
    let capture: CaptureItem
    let storageManager: StorageManager
    private var dismissAction: (() -> Void)?

    // NOT @Published - we manually control when SwiftUI updates
    // This prevents crashes from @Published updates during teardown
    var thumbnail: NSImage?
    var isVisible = true

    init(capture: CaptureItem, storageManager: StorageManager) {
        self.capture = capture
        self.storageManager = storageManager
        // Don't load thumbnail in init - do it when view appears
    }

    func setDismissAction(_ action: @escaping () -> Void) {
        self.dismissAction = action
    }

    func loadThumbnailIfNeeded() {
        guard thumbnail == nil, isVisible else { return }
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            self.thumbnail = image
            // Manually trigger SwiftUI update - only do this when visible
            objectWillChange.send()
        }
    }

    func dismiss() {
        // Ensure we're on main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.dismiss() }
            return
        }
        guard isVisible else { return }
        // Mark as not visible but DON'T trigger @Published updates yet
        // Setting @Published properties while SwiftUI is rendering causes crashes
        isVisible = false
        // Call dismiss action - the window cleanup will handle releasing resources
        // Do NOT set thumbnail = nil here as it triggers SwiftUI re-render during teardown
        dismissAction?()
    }

    func copyToClipboard() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        debugLog("Copying image from: \(url.path)")

        if let image = NSImage(contentsOf: url) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            debugLog("Image copied to clipboard successfully")
            NSSound(named: "Pop")?.play()
        } else {
            debugLog("Failed to load image for clipboard")
        }
        dismiss()
    }

    func saveToConfiguredLocation() {
        // The file is already saved to screenshotsDirectory when captured
        let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)

        debugLog("Save button pressed")
        debugLog("Looking for file at: \(fileURL.path)")

        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            debugLog("File found, revealing in Finder")
            NSSound(named: "Pop")?.play()
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            // Try the default directory as fallback (in case settings changed after capture)
            let fallbackURL = storageManager.defaultDirectory.appendingPathComponent(capture.filename)
            debugLog("File not at configured location, checking default: \(fallbackURL.path)")

            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                debugLog("File found at default location, revealing in Finder")
                NSSound(named: "Pop")?.play()
                NSWorkspace.shared.activateFileViewerSelecting([fallbackURL])
            } else {
                errorLog("File not found at: \(fileURL.path) or \(fallbackURL.path)")
                let alert = NSAlert()
                alert.messageText = "File Not Found"
                alert.informativeText = "The screenshot file could not be located at:\n\(fileURL.path)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }

        dismiss()
    }

    func openAnnotationEditor() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func pinScreenshot() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            // Use the manager to retain the window reference
            _ = PinnedScreenshotManager.shared.pin(image: image)
        }
        dismiss()
    }

    func performOCR() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            dismiss()
            return
        }

        let ocrService = OCRService()
        ocrService.recognizeText(in: cgImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                case .failure:
                    break
                }
                self?.dismiss()
            }
        }
    }

    func deleteCapture() {
        storageManager.deleteCapture(capture)
        dismiss()
    }

    func openInFinder() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismiss()
    }
}

struct QuickAccessOverlay: View {
    @ObservedObject var controller: QuickAccessOverlayController

    var body: some View {
        VStack(spacing: 0) {
            // Spacer for title bar area (traffic light buttons)
            Spacer()
                .frame(height: 28)

            if let thumbnail = controller.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 160)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: controller.capture.type.icon)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "doc.on.clipboard",
                    title: "Copy",
                    shortcut: "⌘C",
                    tooltipText: "Copy the screenshot to your clipboard for pasting into other apps.",
                    action: { controller.copyToClipboard() },
                    iconSize: 15
                )

                QuickActionButton(
                    icon: "square.and.arrow.down",
                    title: "Save",
                    shortcut: "⌘S",
                    tooltipText: "Save the screenshot to your configured folder."
                ) {
                    controller.saveToConfiguredLocation()
                }

                QuickActionButton(
                    icon: "pencil",
                    title: "Annotate",
                    shortcut: "⌘E",
                    tooltipText: "Open the annotation editor to draw, add text, or highlight areas."
                ) {
                    controller.openAnnotationEditor()
                }

                QuickActionButton(
                    icon: "pin",
                    title: "Pin",
                    shortcut: "⌘P",
                    tooltipText: "Pin the screenshot as a floating window that stays on top.",
                    action: { controller.pinScreenshot() },
                    iconSize: 15
                )
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                SecondaryActionButton(
                    icon: "text.viewfinder",
                    title: "OCR",
                    shortcut: "⌘T",
                    tooltipText: "Extract text from the screenshot and copy it to clipboard."
                ) {
                    controller.performOCR()
                }

                SecondaryActionButton(
                    icon: "folder",
                    title: "Open",
                    shortcut: "⌘O",
                    tooltipText: "Show the screenshot file in Finder."
                ) {
                    controller.openInFinder()
                }

                SecondaryActionButton(
                    icon: "trash",
                    title: "Delete",
                    shortcut: "⌘⌫",
                    tooltipText: "Delete this screenshot permanently."
                ) {
                    controller.deleteCapture()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Load thumbnail when view appears, not during init
            controller.loadThumbnailIfNeeded()
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let shortcut: String
    let tooltipText: String
    let action: () -> Void
    var iconSize: CGFloat = 18

    @State private var isHovered = false
    @State private var showTooltip = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Fixed size container for icon to ensure alignment
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .frame(width: 28, height: 28)
                    .foregroundColor(isHovered ? .accentColor : .primary)

                Spacer()
                    .frame(height: 6)

                // Text anchored at bottom
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .primary)
            }
            .frame(width: 64, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            // Show tooltip after a short delay
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(tooltipText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(width: 200, alignment: .leading)
        }
    }
}

struct SecondaryActionButton: View {
    let icon: String
    let title: String
    let shortcut: String
    let tooltipText: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var showTooltip = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        showTooltip = true
                    }
                }
            } else {
                showTooltip = false
            }
        }
        .popover(isPresented: $showTooltip, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(tooltipText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(width: 200, alignment: .leading)
        }
    }
}
