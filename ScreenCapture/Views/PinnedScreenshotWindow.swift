import SwiftUI
import AppKit

class PinnedScreenshotWindow {
    private var window: NSWindow?
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
    }

    func show() {
        let initialSize = calculateInitialSize()
        let pinnedView = PinnedScreenshotView(
            image: image,
            initialSize: initialSize,
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: pinnedView)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)

        guard let screen = NSScreen.main else { return }
        let centerX = screen.frame.midX - initialSize.width / 2
        let centerY = screen.frame.midY - initialSize.height / 2

        window = PinnedWindow(
            contentRect: NSRect(x: centerX, y: centerY, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window?.contentView = hostingView
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.level = .floating
        window?.hasShadow = true
        window?.isMovableByWindowBackground = true
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
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

    @State private var opacity: Double = 1.0
    @State private var isLocked = false
    @State private var showControls = false
    @State private var currentSize: CGSize

    init(image: NSImage, initialSize: NSSize, onClose: @escaping () -> Void) {
        self.image = image
        self.initialSize = initialSize
        self.onClose = onClose
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
    }

    private var controlsOverlay: some View {
        HStack(spacing: 8) {
            PinnedControlButton(icon: "minus.magnifyingglass") {
                withAnimation {
                    let scale = max(0.5, currentSize.width / initialSize.width - 0.1)
                    currentSize = CGSize(
                        width: initialSize.width * scale,
                        height: initialSize.height * scale
                    )
                }
            }

            PinnedControlButton(icon: "plus.magnifyingglass") {
                withAnimation {
                    let scale = min(3.0, currentSize.width / initialSize.width + 0.1)
                    currentSize = CGSize(
                        width: initialSize.width * scale,
                        height: initialSize.height * scale
                    )
                }
            }

            Divider()
                .frame(height: 16)

            PinnedControlButton(icon: isLocked ? "lock.fill" : "lock.open") {
                isLocked.toggle()
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
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)

            Divider()
                .frame(height: 16)

            PinnedControlButton(icon: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }

            PinnedControlButton(icon: "xmark") {
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
    }
}

class PinnedScreenshotManager {
    static let shared = PinnedScreenshotManager()

    private var pinnedWindows: [UUID: PinnedScreenshotWindow] = [:]

    private init() {}

    func pin(image: NSImage) -> UUID {
        let id = UUID()
        let window = PinnedScreenshotWindow(image: image)
        pinnedWindows[id] = window
        window.show()
        return id
    }

    func unpin(id: UUID) {
        pinnedWindows[id]?.close()
        pinnedWindows.removeValue(forKey: id)
    }

    func unpinAll() {
        pinnedWindows.values.forEach { $0.close() }
        pinnedWindows.removeAll()
    }

    var pinnedCount: Int {
        pinnedWindows.count
    }
}
