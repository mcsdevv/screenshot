import SwiftUI
import AppKit

struct BackgroundToolView: View {
    let image: NSImage
    let onSave: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var selectedBackground: BackgroundStyle = .gradient1
    @State private var padding: CGFloat = 40
    @State private var cornerRadius: CGFloat = 12
    @State private var shadowEnabled = true
    @State private var shadowRadius: CGFloat = 20
    @State private var scale: CGFloat = 1.0

    var body: some View {
        HSplitView {
            previewArea
                .frame(minWidth: 400)

            optionsPanel
                .frame(width: 280)
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var previewArea: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            composedImage
                .scaleEffect(0.8)
        }
    }

    private var composedImage: some View {
        ZStack {
            selectedBackground.view
                .frame(
                    width: image.size.width * scale + padding * 2,
                    height: image.size.height * scale + padding * 2
                )

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(
                    color: shadowEnabled ? .black.opacity(0.3) : .clear,
                    radius: shadowEnabled ? shadowRadius : 0,
                    x: 0,
                    y: shadowEnabled ? shadowRadius / 2 : 0
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var optionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Background")
                    .font(.headline)

                backgroundPicker

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Adjustments")
                        .font(.headline)

                    SliderOption(label: "Padding", value: $padding, range: 0...100, unit: "px")
                    SliderOption(label: "Corner Radius", value: $cornerRadius, range: 0...40, unit: "px")
                    SliderOption(label: "Scale", value: $scale, range: 0.5...1.5, unit: "x")
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Shadow")
                        .font(.headline)

                    Toggle("Enable Shadow", isOn: $shadowEnabled)

                    if shadowEnabled {
                        SliderOption(label: "Blur", value: $shadowRadius, range: 0...50, unit: "px")
                    }
                }

                Divider()

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Export") {
                        exportImage()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var backgroundPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
            ForEach(BackgroundStyle.allCases, id: \.self) { style in
                BackgroundPreview(
                    style: style,
                    isSelected: selectedBackground == style
                ) {
                    selectedBackground = style
                }
            }
        }
    }

    private func exportImage() {
        let totalWidth = image.size.width * scale + padding * 2
        let totalHeight = image.size.height * scale + padding * 2

        let exportedImage = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        exportedImage.lockFocus()

        // Draw background
        let bgRect = NSRect(origin: .zero, size: NSSize(width: totalWidth, height: totalHeight))
        selectedBackground.nsColor.setFill()
        bgRect.fill()

        // Draw image with shadow
        let imageRect = NSRect(
            x: padding,
            y: padding,
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        if shadowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = shadowRadius
            shadow.shadowOffset = NSSize(width: 0, height: -shadowRadius / 2)
            shadow.set()
        }

        let path = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: imageRect)

        exportedImage.unlockFocus()

        onSave(exportedImage)
    }
}

enum BackgroundStyle: String, CaseIterable {
    case gradient1 = "Purple-Pink"
    case gradient2 = "Blue-Cyan"
    case gradient3 = "Orange-Yellow"
    case gradient4 = "Green-Teal"
    case gradient5 = "Red-Orange"
    case solid1 = "Dark"
    case solid2 = "Light"
    case solid3 = "Blue"
    case transparent = "Transparent"
    case custom = "Custom"

    var view: some View {
        Group {
            switch self {
            case .gradient1:
                LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .gradient2:
                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .gradient3:
                LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .gradient4:
                LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .gradient5:
                LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .solid1:
                Color(white: 0.1)
            case .solid2:
                Color(white: 0.95)
            case .solid3:
                Color.blue
            case .transparent:
                Color.clear
            case .custom:
                Color.gray
            }
        }
    }

    var nsColor: NSColor {
        switch self {
        case .gradient1: return NSColor.purple
        case .gradient2: return NSColor.blue
        case .gradient3: return NSColor.orange
        case .gradient4: return NSColor.green
        case .gradient5: return NSColor.red
        case .solid1: return NSColor(white: 0.1, alpha: 1)
        case .solid2: return NSColor(white: 0.95, alpha: 1)
        case .solid3: return NSColor.blue
        case .transparent: return NSColor.clear
        case .custom: return NSColor.gray
        }
    }
}

struct BackgroundPreview: View {
    let style: BackgroundStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            style.view
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SliderOption: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Slider(value: $value, in: range)
        }
    }
}

@MainActor
class BackgroundToolWindow {
    private static var currentWindow: NSWindow?

    static func show(for image: NSImage, storageManager: StorageManager) {
        // Close any existing window first
        closeWindow()

        let view = BackgroundToolView(
            image: image,
            onSave: { exportedImage in
                Task { @MainActor in
                    let capture = storageManager.saveCapture(image: exportedImage, type: .screenshot)
                    NotificationCenter.default.post(name: .captureCompleted, object: capture)
                    // Defer close to avoid deallocating view during callback
                    closeWindow()
                }
            },
            onCancel: {
                Task { @MainActor in
                    // Defer close to avoid deallocating view during callback
                    closeWindow()
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Prevent double-release crash under ARC
        window.isReleasedWhenClosed = false

        window.title = "Background Tool"
        window.contentView = NSHostingView(rootView: view)
        window.center()

        currentWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    static func closeWindow() {
        guard let windowToClose = currentWindow else { return }
        currentWindow = nil

        windowToClose.orderOut(nil)
        windowToClose.contentView = nil
        windowToClose.close()
    }
}
