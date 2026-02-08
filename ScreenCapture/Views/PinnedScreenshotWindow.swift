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

        // Use corner preference for initial position
        let cornerRawValue = UserDefaults.standard.string(forKey: "popupCorner") ?? ScreenCorner.bottomLeft.rawValue
        let corner = ScreenCorner(rawValue: cornerRawValue) ?? .bottomLeft
        let origin = corner.windowOrigin(screenFrame: screen.visibleFrame, windowSize: initialSize, padding: DSSpacing.lg)

        let newWindow = PinnedWindow(
            contentRect: NSRect(origin: origin, size: initialSize),
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
            },
            onResize: { [weak newWindow] newSize, corner in
                guard let window = newWindow else { return }
                let currentFrame = window.frame

                // Calculate new origin based on which corner is being dragged
                // The opposite corner should stay anchored
                var newOrigin = currentFrame.origin
                let deltaWidth = newSize.width - currentFrame.width
                let deltaHeight = newSize.height - currentFrame.height

                switch corner {
                case .topLeft:
                    // Bottom-right stays anchored
                    newOrigin.x -= deltaWidth
                    // In macOS, y=0 is at bottom, so no y adjustment needed
                case .topRight:
                    // Bottom-left stays anchored (origin stays same)
                    break
                case .bottomLeft:
                    // Top-right stays anchored
                    newOrigin.x -= deltaWidth
                    newOrigin.y -= deltaHeight
                case .bottomRight:
                    // Top-left stays anchored
                    newOrigin.y -= deltaHeight
                }

                let newFrame = NSRect(origin: newOrigin, size: NSSize(width: newSize.width, height: newSize.height))
                window.setFrame(newFrame, display: true, animate: false)
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

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct PinnedScreenshotView: View {
    let image: NSImage
    let initialSize: NSSize
    let onClose: () -> Void
    let onLockChanged: (Bool) -> Void
    let onResize: (CGSize, ResizeCorner) -> Void

    @State private var opacity: Double = 1.0
    @State private var isLocked = false
    @State private var showControls = false
    @State private var currentSize: CGSize
    @State private var showOpacityMenu = false

    private let minSize: CGFloat = 100
    private let maxScale: CGFloat = 3.0
    private let aspectRatio: CGFloat

    init(image: NSImage, initialSize: NSSize, onClose: @escaping () -> Void, onLockChanged: @escaping (Bool) -> Void, onResize: @escaping (CGSize, ResizeCorner) -> Void) {
        self.image = image
        self.initialSize = initialSize
        self.onClose = onClose
        self.onLockChanged = onLockChanged
        self.onResize = onResize
        self._currentSize = State(initialValue: CGSize(width: initialSize.width, height: initialSize.height))
        self.aspectRatio = initialSize.width / initialSize.height
    }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: currentSize.width, height: currentSize.height)
                .opacity(opacity)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            // Corner resize handles
            cornerHandles

            // Controls overlay (top-right)
            if showControls {
                VStack {
                    HStack {
                        Spacer()
                        controlsOverlay
                    }
                    Spacer()
                }
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

    // MARK: - Corner Handles

    @ViewBuilder
    private var cornerHandles: some View {
        ZStack {
            // Top-left
            CornerResizeHandle(corner: .topLeft) { delta in
                handleResize(delta: delta, corner: .topLeft)
            }
            .position(x: 0, y: 0)

            // Top-right
            CornerResizeHandle(corner: .topRight) { delta in
                handleResize(delta: delta, corner: .topRight)
            }
            .position(x: currentSize.width, y: 0)

            // Bottom-left
            CornerResizeHandle(corner: .bottomLeft) { delta in
                handleResize(delta: delta, corner: .bottomLeft)
            }
            .position(x: 0, y: currentSize.height)

            // Bottom-right
            CornerResizeHandle(corner: .bottomRight) { delta in
                handleResize(delta: delta, corner: .bottomRight)
            }
            .position(x: currentSize.width, y: currentSize.height)
        }
    }

    private func handleResize(delta: CGSize, corner: ResizeCorner) {
        // Calculate new size maintaining aspect ratio
        let deltaX = delta.width
        let deltaY = delta.height

        // Use the larger delta to determine resize amount (maintaining aspect ratio)
        let primaryDelta: CGFloat
        switch corner {
        case .topLeft:
            primaryDelta = max(-deltaX, -deltaY)
        case .topRight:
            primaryDelta = max(deltaX, -deltaY)
        case .bottomLeft:
            primaryDelta = max(-deltaX, deltaY)
        case .bottomRight:
            primaryDelta = max(deltaX, deltaY)
        }

        let newWidth = currentSize.width + primaryDelta

        // Enforce min/max constraints
        let maxWidth = initialSize.width * maxScale
        let minWidth = minSize
        let constrainedWidth = min(max(newWidth, minWidth), maxWidth)
        let constrainedHeight = constrainedWidth / aspectRatio

        let newSize = CGSize(width: constrainedWidth, height: constrainedHeight)

        if newSize.width != currentSize.width {
            currentSize = newSize
            onResize(newSize, corner)
        }
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

struct CornerResizeHandle: View {
    let corner: ResizeCorner
    let onDrag: (CGSize) -> Void

    @State private var isHovered = false
    @GestureState private var dragOffset: CGSize = .zero

    private let handleSize: CGFloat = 20
    private let visualSize: CGFloat = 8

    var body: some View {
        ZStack {
            // Invisible hit area
            Color.clear
                .frame(width: handleSize, height: handleSize)

            // Subtle visual indicator - diagonal corner lines
            cornerLines
        }
        .frame(width: handleSize, height: handleSize)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onChanged { value in
                    onDrag(value.translation)
                }
        )
    }

    @ViewBuilder
    private var cornerLines: some View {
        Canvas { context, size in
            let lineLength: CGFloat = visualSize
            let lineWidth: CGFloat = 1.5
            let opacity: Double = isHovered ? 0.8 : 0.4

            var path = Path()

            switch corner {
            case .topLeft:
                // Horizontal line going right
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2 + lineLength, y: size.height / 2))
                // Vertical line going down
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + lineLength))

            case .topRight:
                // Horizontal line going left
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2 - lineLength, y: size.height / 2))
                // Vertical line going down
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + lineLength))

            case .bottomLeft:
                // Horizontal line going right
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2 + lineLength, y: size.height / 2))
                // Vertical line going up
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 - lineLength))

            case .bottomRight:
                // Horizontal line going left
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2 - lineLength, y: size.height / 2))
                // Vertical line going up
                path.move(to: CGPoint(x: size.width / 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 - lineLength))
            }

            context.stroke(
                path,
                with: .color(.white.opacity(opacity)),
                lineWidth: lineWidth
            )
        }
        .frame(width: handleSize, height: handleSize)
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
