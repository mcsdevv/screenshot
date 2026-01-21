import SwiftUI
import AppKit

class PinnedScreenshotWindow {
    private var window: NSWindow?
    private let image: NSImage
    private let id: UUID
    private let onCloseCallback: ((UUID) -> Void)?

    init(image: NSImage, id: UUID = UUID(), onClose: ((UUID) -> Void)? = nil) {
        self.image = image
        self.id = id
        self.onCloseCallback = onClose
    }

    func show() {
        let initialSize = calculateInitialSize()

        // Create window first so we can reference it in callbacks
        guard let screen = NSScreen.main else { return }

        // Position in bottom-left corner like macOS screenshot preview
        let padding: CGFloat = 20
        let posX = screen.visibleFrame.minX + padding
        let posY = screen.visibleFrame.minY + padding

        let newWindow = PinnedWindow(
            contentRect: NSRect(x: posX, y: posY, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window = newWindow

        let pinnedView = PinnedScreenshotView(
            image: image,
            initialSize: initialSize,
            onClose: { [weak self] in
                self?.close()
            },
            onLockChanged: { [weak newWindow] isLocked in
                newWindow?.isMovableByWindowBackground = !isLocked
            }
        )

        let hostingView = NSHostingView(rootView: pinnedView)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)

        // CRITICAL: Prevent double-release crash under ARC
        newWindow.isReleasedWhenClosed = false

        newWindow.contentView = hostingView
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.level = .floating
        newWindow.hasShadow = true
        newWindow.isMovableByWindowBackground = true
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let windowToClose = window else { return }
        window = nil

        // Notify the manager that this window is closing
        onCloseCallback?(id)

        // Hide window immediately but defer all cleanup to next run loop
        windowToClose.orderOut(nil)

        DispatchQueue.main.async {
            windowToClose.contentView = nil
            windowToClose.close()
        }
    }

    private func calculateInitialSize() -> NSSize {
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 300

        let imageSize = image.size
        let aspectRatio = imageSize.width / imageSize.height

        var width = min(imageSize.width, maxWidth)
        var height = width / aspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        return NSSize(width: width, height: height)
    }
}

class PinnedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PinnedScreenshotView: View {
    let image: NSImage
    let initialSize: NSSize
    let onClose: () -> Void
    let onLockChanged: (Bool) -> Void

    @State private var opacity: Double = 1.0
    @State private var isLocked = false
    @State private var showControls = false
    @State private var currentSize: CGSize
    @State private var showOpacityMenu = false

    init(image: NSImage, initialSize: NSSize, onClose: @escaping () -> Void, onLockChanged: @escaping (Bool) -> Void) {
        self.image = image
        self.initialSize = initialSize
        self.onClose = onClose
        self.onLockChanged = onLockChanged
        self._currentSize = State(initialValue: CGSize(width: initialSize.width, height: initialSize.height))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: currentSize.width, height: currentSize.height)
                .opacity(opacity)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            if showControls {
                controlsOverlay
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = hovering
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { scale in
                    let newWidth = initialSize.width * scale
                    let newHeight = initialSize.height * scale
                    currentSize = CGSize(width: newWidth, height: newHeight)
                }
        )
        .background(keyboardShortcuts)
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background(
                Group {
                    Button("") { zoomOut() }
                        .keyboardShortcut("-", modifiers: .command)
                    Button("") { zoomIn() }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("") { toggleLock() }
                        .keyboardShortcut("l", modifiers: .command)
                    Button("") { showOpacityMenu.toggle() }
                        .keyboardShortcut("o", modifiers: [])
                    Button("") { copyToClipboard() }
                        .keyboardShortcut("c", modifiers: .command)
                    Button("") { onClose() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .opacity(0)
            )
    }

    // MARK: - Actions

    private func zoomOut() {
        withAnimation {
            let scale = max(0.5, currentSize.width / initialSize.width - 0.1)
            currentSize = CGSize(
                width: initialSize.width * scale,
                height: initialSize.height * scale
            )
        }
    }

    private func zoomIn() {
        withAnimation {
            let scale = min(3.0, currentSize.width / initialSize.width + 0.1)
            currentSize = CGSize(
                width: initialSize.width * scale,
                height: initialSize.height * scale
            )
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func toggleLock() {
        isLocked.toggle()
        onLockChanged(isLocked)
    }

    private var controlsOverlay: some View {
        HStack(spacing: 8) {
            PinnedControlButton(icon: "minus.magnifyingglass", tooltip: "Zoom Out (⌘-)") {
                zoomOut()
            }

            PinnedControlButton(icon: "plus.magnifyingglass", tooltip: "Zoom In (⌘=)") {
                zoomIn()
            }

            Divider()
                .frame(height: 16)

            PinnedControlButton(icon: isLocked ? "lock.fill" : "lock.open", tooltip: isLocked ? "Unlock Position (⌘L)" : "Lock Position (⌘L)") {
                toggleLock()
            }

            Menu {
                ForEach([100, 80, 60, 40, 20], id: \.self) { value in
                    Button("\(value)%") {
                        opacity = Double(value) / 100.0
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Opacity (O)")

            Divider()
                .frame(height: 16)

            PinnedControlButton(icon: "doc.on.clipboard", tooltip: "Copy to Clipboard (⌘C)") {
                copyToClipboard()
            }

            PinnedControlButton(icon: "xmark", tooltip: "Close (Esc)") {
                onClose()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding(8)
    }
}

struct PinnedControlButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(isHovered ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

class PinnedScreenshotManager {
    static let shared = PinnedScreenshotManager()

    private var pinnedWindows: [UUID: PinnedScreenshotWindow] = [:]

    private init() {}

    func pin(image: NSImage) -> UUID {
        let id = UUID()
        let window = PinnedScreenshotWindow(image: image, id: id) { [weak self] closedId in
            // Remove from dictionary when window is closed via X button
            self?.pinnedWindows.removeValue(forKey: closedId)
        }
        pinnedWindows[id] = window
        window.show()
        return id
    }

    func unpin(id: UUID) {
        pinnedWindows[id]?.close()
        // Note: close() will call the callback which removes from dictionary
    }

    func unpinAll() {
        // Make a copy of values to iterate since close() modifies the dictionary
        let windows = Array(pinnedWindows.values)
        windows.forEach { $0.close() }
    }

    var pinnedCount: Int {
        pinnedWindows.count
    }
}
