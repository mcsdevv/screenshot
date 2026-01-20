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
        } else {
            errorLog("QuickAccess: Failed to load image for clipboard")
        }
        dismiss()
    }

    func saveToConfiguredLocation() {
        debugLog("QuickAccess: Save button clicked")
        // The file is already saved to screenshotsDirectory when captured
        let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)

        debugLog("QuickAccess: Looking for file at: \(fileURL.path)")

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
                case .failure(let error):
                    errorLog("QuickAccess: OCR failed: \(error)")
                }
                self?.dismiss()
            }
        }
    }

    func deleteCapture() {
        debugLog("QuickAccess: Delete button clicked")
        storageManager.deleteCapture(capture)
        debugLog("QuickAccess: Capture deleted")
        dismiss()
    }

    func openInFinder() {
        debugLog("QuickAccess: Open button clicked")
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        debugLog("QuickAccess: Opened in Finder: \(url.path)")
        dismiss()
    }
}

// MARK: - Main Quick Access Overlay

struct QuickAccessOverlay: View {
    @ObservedObject var controller: QuickAccessOverlayController
    @State private var isAppearing = false

    var body: some View {
        VStack(spacing: 0) {
            // Traffic light buttons
            HStack {
                DSTrafficLightButtons(onClose: controller.dismiss)
                Spacer()
            }
            .frame(height: 32)
            .padding(.top, DSSpacing.sm)

            // Thumbnail preview
            thumbnailSection
                .padding(.horizontal, DSSpacing.lg)

            // Primary actions
            primaryActionsSection
                .padding(.top, DSSpacing.lg)
                .padding(.horizontal, DSSpacing.lg)

            DSDivider()
                .padding(.horizontal, DSSpacing.xl)
                .padding(.vertical, DSSpacing.md)

            // Secondary actions
            secondaryActionsSection
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
        }
        .frame(width: 360)
        .background(quickAccessBackground)
        .background(KeyboardShortcutHandler(controller: controller))
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.95)
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
        ZStack {
            if let thumbnail = controller.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
            } else {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(Color.dsBackgroundSecondary)
                    .frame(height: 180)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .strokeBorder(Color.dsBorder, lineWidth: 1)
                    )
            }

            // Type badge
            VStack {
                HStack {
                    Spacer()
                    DSBadge(
                        text: controller.capture.type.rawValue.uppercased(),
                        style: .accent
                    )
                    .padding(DSSpacing.sm)
                }
                Spacer()
            }
        }
    }

    // MARK: - Primary Actions

    private var primaryActionsSection: some View {
        HStack(spacing: DSSpacing.sm) {
            QuickAccessActionCard(
                icon: "doc.on.clipboard",
                title: "Copy",
                shortcut: "C",
                action: controller.copyToClipboard
            )

            QuickAccessActionCard(
                icon: "square.and.arrow.down",
                title: "Save",
                shortcut: "S",
                action: controller.saveToConfiguredLocation
            )

            QuickAccessActionCard(
                icon: "pencil.tip.crop.circle",
                title: "Edit",
                shortcut: "E",
                action: controller.openAnnotationEditor
            )

            QuickAccessActionCard(
                icon: "pin.fill",
                title: "Pin",
                shortcut: "P",
                action: controller.pinScreenshot
            )
        }
    }

    // MARK: - Secondary Actions

    private var secondaryActionsSection: some View {
        HStack(spacing: DSSpacing.lg) {
            QuickAccessSecondaryAction(
                icon: "text.viewfinder",
                title: "OCR",
                action: controller.performOCR
            )

            QuickAccessSecondaryAction(
                icon: "folder",
                title: "Reveal",
                action: controller.openInFinder
            )

            QuickAccessSecondaryAction(
                icon: "trash",
                title: "Delete",
                isDestructive: true,
                action: controller.deleteCapture
            )

            Spacer()

            // Dismiss hint
            HStack(spacing: DSSpacing.xxs) {
                Text("esc")
                    .font(DSTypography.monoSmall)
                    .foregroundColor(.dsTextTertiary)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxxs)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.xs)
                            .fill(Color.white.opacity(0.05))
                    )
                Text("to close")
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }
        }
    }
}

// MARK: - Quick Access Action Card

struct QuickAccessActionCard: View {
    let icon: String
    let title: String
    let shortcut: String
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
            VStack(spacing: DSSpacing.sm) {
                // Icon with glow effect
                ZStack {
                    // Glow background
                    if isHovered {
                        Circle()
                            .fill(Color.dsAccent.opacity(0.2))
                            .frame(width: 48, height: 48)
                            .blur(radius: 8)
                    }

                    // Icon circle
                    Circle()
                        .fill(
                            isHovered ?
                            Color.dsAccent.opacity(0.2) :
                            Color.white.opacity(0.06)
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isHovered ? Color.dsAccent.opacity(0.5) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isHovered ? .dsAccent : .dsTextPrimary)
                }

                // Title
                Text(title)
                    .font(DSTypography.labelSmall)
                    .foregroundColor(isHovered ? .dsTextPrimary : .dsTextSecondary)

                // Shortcut hint
                Text("⌘\(shortcut)")
                    .font(DSTypography.monoSmall)
                    .foregroundColor(.dsTextTertiary)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.xs)
                            .fill(Color.white.opacity(0.04))
                    )
                    .opacity(isHovered ? 1 : 0.6)
            }
            .frame(width: 76, height: 100)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(
                        isHovered ? Color.white.opacity(0.1) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .help("\(title) (⌘\(shortcut))")
    }
}

// MARK: - Quick Access Secondary Action

struct QuickAccessSecondaryAction: View {
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
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(DSTypography.labelSmall)
            }
            .foregroundColor(
                isDestructive ?
                (isHovered ? .dsDanger : .dsDanger.opacity(0.7)) :
                (isHovered ? .dsTextPrimary : .dsTextTertiary)
            )
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
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
                case "o":
                    debugLog("KeyboardShortcutHandler: Cmd+O pressed")
                    controller.openInFinder()
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
