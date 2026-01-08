import SwiftUI
import AppKit

struct QuickAccessOverlay: View {
    let capture: CaptureItem
    let storageManager: StorageManager
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            if let thumbnail = thumbnail {
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
                        Image(systemName: capture.type.icon)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                QuickActionButton(icon: "doc.on.clipboard", title: "Copy", shortcut: "⌘C") {
                    copyToClipboard()
                }

                QuickActionButton(icon: "square.and.arrow.down", title: "Save", shortcut: "⌘S") {
                    saveToDesktop()
                }

                QuickActionButton(icon: "pencil", title: "Annotate", shortcut: "⌘E") {
                    openAnnotationEditor()
                }

                QuickActionButton(icon: "pin", title: "Pin", shortcut: "⌘P") {
                    pinScreenshot()
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                SecondaryActionButton(icon: "text.viewfinder", title: "OCR") {
                    performOCR()
                }

                SecondaryActionButton(icon: "trash", title: "Delete") {
                    deleteCapture()
                }

                SecondaryActionButton(icon: "folder", title: "Open") {
                    openInFinder()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .onAppear {
            loadThumbnail()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func loadThumbnail() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            thumbnail = image
        }
    }

    private func copyToClipboard() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            showFeedback(message: "Copied to clipboard")
        }
        onDismiss()
    }

    private func saveToDesktop() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let destinationURL = desktopURL.appendingPathComponent(capture.filename)

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            showFeedback(message: "Saved to Desktop")
        } catch {
            print("Save error: \(error)")
        }
        onDismiss()
    }

    private func openAnnotationEditor() {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if NSApp.delegate is AppDelegate {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func pinScreenshot() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            let pinnedWindow = PinnedScreenshotWindow(image: image)
            pinnedWindow.show()
        }
        onDismiss()
    }

    private func performOCR() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let ocrService = OCRService()
        ocrService.recognizeText(in: cgImage) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.showFeedback(message: "Text copied to clipboard")
                case .failure:
                    self.showFeedback(message: "OCR failed")
                }
                self.onDismiss()
            }
        }
    }

    private func deleteCapture() {
        storageManager.deleteCapture(capture)
        onDismiss()
    }

    private func openInFinder() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onDismiss()
    }

    private func showFeedback(message: String) {
        // Could implement a toast notification here
        print(message)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isHovered ? .accentColor : .primary)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .primary)
            }
            .frame(width: 60, height: 50)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(title) (\(shortcut))")
    }
}

struct SecondaryActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(isHovered ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
