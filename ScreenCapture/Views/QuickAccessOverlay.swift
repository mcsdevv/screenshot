import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Custom NSView that accepts first mouse to allow clicks without activation
class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// Use a class to safely manage the overlay's actions and lifecycle
@MainActor
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
        // Already on main actor - no thread check needed
        guard isVisible else { return }
        // Mark as not visible but DON'T trigger @Published updates yet
        // Setting @Published properties while SwiftUI is rendering causes crashes
        isVisible = false
        // Call dismiss action - the window cleanup will handle releasing resources
        // Do NOT set thumbnail = nil here as it triggers SwiftUI re-render during teardown
        dismissAction?()
    }

    func copyToClipboard() {
        debugLog("QuickAccess: Copy button clicked")
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        debugLog("QuickAccess: Copying image from: \(url.path)")

        if let image = NSImage(contentsOf: url) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            debugLog("QuickAccess: Image copied to clipboard successfully")
            NSSound(named: "Pop")?.play()
            ToastManager.shared.show(.copy)
        } else {
            errorLog("QuickAccess: Failed to load image for clipboard")
        }
        dismiss()
    }

    func saveToConfiguredLocation() {
        debugLog("QuickAccess: Reveal button clicked")
        // The file is already saved to screenshotsDirectory when captured
        let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)

        debugLog("QuickAccess: Looking for file at: \(fileURL.path)")

        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            debugLog("File found, revealing in Finder")
            NSSound(named: "Pop")?.play()
            ToastManager.shared.show(.save)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            // Try the default directory as fallback (in case settings changed after capture)
            let fallbackURL = storageManager.defaultDirectory.appendingPathComponent(capture.filename)
            debugLog("File not at configured location, checking default: \(fallbackURL.path)")

            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                debugLog("File found at default location, revealing in Finder")
                NSSound(named: "Pop")?.play()
                ToastManager.shared.show(.save)
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
        debugLog("QuickAccess: Annotate button clicked")
        // Post notification to open annotation editor with this capture
        NotificationCenter.default.post(
            name: .openAnnotationEditor,
            object: capture
        )
        dismiss()
    }

    func pinScreenshot() {
        debugLog("QuickAccess: Pin button clicked")
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            // Use the manager to retain the window reference
            _ = PinnedScreenshotManager.shared.pin(image: image)
            debugLog("QuickAccess: Screenshot pinned successfully")
            ToastManager.shared.show(.pin)
        } else {
            errorLog("QuickAccess: Failed to load image for pinning")
        }
        dismiss()
    }

    func performOCR() {
        debugLog("QuickAccess: OCR button clicked")
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorLog("QuickAccess: Failed to load image for OCR")
            dismiss()
            return
        }

        let ocrService = OCRService()
        ocrService.recognizeText(in: cgImage) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let text):
                    debugLog("QuickAccess: OCR successful, extracted \(text.count) characters")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ToastManager.shared.show(.ocr)
                case .failure(let error):
                    errorLog("QuickAccess: OCR failed: \(error)")
                }
                self?.dismiss()
            }
        }
    }

    func deleteCapture() {
        debugLog("QuickAccess: Delete button clicked")
        let deleted = storageManager.deleteCapture(capture)
        if deleted {
            debugLog("QuickAccess: Capture deleted")
            ToastManager.shared.show(.delete)
        } else {
            errorLog("QuickAccess: Failed to delete capture \(capture.filename)")
        }
        dismiss()
    }

}

// MARK: - Main Quick Access Overlay

struct QuickAccessOverlay: View {
    @ObservedObject var controller: QuickAccessOverlayController
    let corner: ScreenCorner
    @State private var isAppearing = false

    init(controller: QuickAccessOverlayController, corner: ScreenCorner = .bottomLeft) {
        self.controller = controller
        self.corner = corner
    }

    var body: some View {
        VStack(spacing: 0) {
            // Traffic light buttons
            HStack {
                DSTrafficLightButtons(onClose: controller.dismiss)
                Spacer()
            }
            .padding(.leading, DSSpacing.sm)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.xs)

            // Thumbnail preview with overlaid actions
            ZStack(alignment: .bottom) {
                thumbnailSection

                // Actions overlaid at bottom
                actionsSection
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.bottom, DSSpacing.md)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
        }
        .frame(width: 360)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .background(quickAccessBackground)
        .background(KeyboardShortcutHandler(controller: controller))
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.95)
        .offset(isAppearing ? .zero : corner.entranceOffset)
        .onAppear {
            controller.loadThumbnailIfNeeded()
            withAnimation(DSAnimation.spring) {
                isAppearing = true
            }
        }
        .onExitCommand {
            controller.dismiss()
        }
    }

    // MARK: - Background

    private var quickAccessBackground: some View {
        ZStack {
            // Ultra thin material for glassmorphism
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            // Gradient overlay for depth
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Top edge highlight
            VStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                Spacer()
            }
        }
    }

    // MARK: - Thumbnail Section

    private var thumbnailSection: some View {
        Group {
            if let thumbnail = controller.thumbnail {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    DSBadge(
                        text: controller.capture.type.rawValue.uppercased(),
                        style: .accent
                    )
                    .padding(.top, DSSpacing.sm)
                    .padding(.trailing, DSSpacing.sm)
                }
                .frame(maxWidth: 320, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            } else {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(Color.dsBackgroundSecondary)
                        .overlay(
                            VStack(spacing: DSSpacing.sm) {
                                Image(systemName: controller.capture.type.icon)
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.dsTextTertiary)
                                Text("Loading...")
                                    .font(DSTypography.caption)
                                    .foregroundColor(.dsTextTertiary)
                            }
                        )

                    DSBadge(
                        text: controller.capture.type.rawValue.uppercased(),
                        style: .accent
                    )
                    .padding(.top, DSSpacing.sm)
                    .padding(.trailing, DSSpacing.sm)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(Color.dsBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: DSSpacing.xs) {
            QuickAccessCompactAction(
                icon: "doc.on.clipboard",
                title: "Copy",
                action: controller.copyToClipboard
            )

            QuickAccessCompactAction(
                icon: "folder",
                title: "Reveal",
                action: controller.saveToConfiguredLocation
            )

            QuickAccessCompactAction(
                icon: "pencil.tip.crop.circle",
                title: "Edit",
                action: controller.openAnnotationEditor
            )

            QuickAccessCompactAction(
                icon: "pin.fill",
                title: "Pin",
                action: controller.pinScreenshot
            )

            QuickAccessCompactAction(
                icon: "text.viewfinder",
                title: "OCR",
                action: controller.performOCR
            )

            QuickAccessCompactAction(
                icon: "trash",
                title: "Delete",
                isDestructive: true,
                action: controller.deleteCapture
            )
        }
    }
}

// MARK: - Quick Access Compact Action

struct QuickAccessCompactAction: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(DSAnimation.springQuick) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(
                        isHovered ?
                        (isDestructive ? Color.dsDanger.opacity(0.3) : Color.dsAccent.opacity(0.3)) :
                        Color.black.opacity(0.5)
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(
                        isDestructive ?
                        (isHovered ? .dsDanger : .white) :
                        (isHovered ? .dsAccent : .white)
                    )
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help(title)
    }
}

// MARK: - Keyboard Shortcut Handler

struct KeyboardShortcutHandler: NSViewRepresentable {
    let controller: QuickAccessOverlayController

    func makeNSView(context: Context) -> NSView {
        let view = KeyboardView()
        view.controller = controller

        // Request first responder after a brief delay to ensure view hierarchy is ready
        // This is necessary for LSUIElement apps where keyboard focus doesn't happen automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = view.window {
                let success = window.makeFirstResponder(view)
                debugLog("KeyboardShortcutHandler: makeFirstResponder result: \(success)")
            } else {
                debugLog("KeyboardShortcutHandler: window not available yet")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-request first responder on updates if needed
        if let view = nsView as? KeyboardView, let window = view.window {
            if window.firstResponder !== view {
                DispatchQueue.main.async {
                    _ = window.makeFirstResponder(view)
                }
            }
        }
    }

    class KeyboardView: NSView {
        weak var controller: QuickAccessOverlayController?

        override var acceptsFirstResponder: Bool { true }

        // Accept first mouse click even when window is not active
        // This allows clicking buttons without first clicking to activate
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let controller = controller else {
                super.keyDown(with: event)
                return
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Handle Cmd+key shortcuts
            if modifiers.contains(.command) {
                switch key {
                case "c":
                    debugLog("KeyboardShortcutHandler: Cmd+C pressed")
                    controller.copyToClipboard()
                    return
                case "s":
                    debugLog("KeyboardShortcutHandler: Cmd+S pressed")
                    controller.saveToConfiguredLocation()
                    return
                case "e":
                    debugLog("KeyboardShortcutHandler: Cmd+E pressed")
                    controller.openAnnotationEditor()
                    return
                case "p":
                    debugLog("KeyboardShortcutHandler: Cmd+P pressed")
                    controller.pinScreenshot()
                    return
                case "t":
                    debugLog("KeyboardShortcutHandler: Cmd+T pressed")
                    controller.performOCR()
                    return
                default:
                    break
                }

                // Handle Cmd+Delete
                if event.keyCode == 51 { // Delete key
                    debugLog("KeyboardShortcutHandler: Cmd+Delete pressed")
                    controller.deleteCapture()
                    return
                }
            }

            // Handle Escape
            if event.keyCode == 53 {
                debugLog("KeyboardShortcutHandler: Escape pressed")
                controller.dismiss()
                return
            }

            super.keyDown(with: event)
        }
    }
}
