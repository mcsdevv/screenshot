import Foundation
import AppKit
import Combine

class StorageManager: ObservableObject {
    @Published var history: CaptureHistory

    let screenshotsDirectory: URL
    private let historyFile: URL
    private var autoSaveTimer: Timer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("ScreenCapture", isDirectory: true)

        screenshotsDirectory = appDirectory.appendingPathComponent("Screenshots", isDirectory: true)
        historyFile = appDirectory.appendingPathComponent("history.json")

        try? FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: historyFile),
           let loadedHistory = try? JSONDecoder().decode(CaptureHistory.self, from: data) {
            history = loadedHistory
        } else {
            history = CaptureHistory()
        }

        setupAutoSave()
        cleanupOldCaptures()
    }

    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.saveHistory()
        }
    }

    private func cleanupOldCaptures() {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -30, to: Date())!

        history.items.removeAll { item in
            if item.isFavorite { return false }
            if item.createdAt < cutoffDate {
                deleteFile(named: item.filename)
                return true
            }
            return false
        }

        saveHistory()
    }

    func saveCapture(image: NSImage, type: CaptureType) -> CaptureItem {
        let filename = generateFilename(for: type)
        let url = screenshotsDirectory.appendingPathComponent(filename)

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }

        let capture = CaptureItem(type: type, filename: filename)
        history.add(capture)
        saveHistory()

        return capture
    }

    func saveRecording(url: URL) -> CaptureItem {
        let filename = url.lastPathComponent
        let capture = CaptureItem(type: .recording, filename: filename)
        history.add(capture)
        saveHistory()
        return capture
    }

    func saveGIF(url: URL) -> CaptureItem {
        let filename = url.lastPathComponent
        let capture = CaptureItem(type: .gif, filename: filename)
        history.add(capture)
        saveHistory()
        return capture
    }

    func getCapture(id: UUID) -> CaptureItem? {
        history.items.first { $0.id == id }
    }

    func deleteCapture(_ capture: CaptureItem) {
        deleteFile(named: capture.filename)
        history.remove(id: capture.id)
        saveHistory()
    }

    func toggleFavorite(_ capture: CaptureItem) {
        history.toggleFavorite(id: capture.id)
        saveHistory()
    }

    func updateAnnotations(for capture: CaptureItem, annotations: Data) {
        if let index = history.items.firstIndex(where: { $0.id == capture.id }) {
            history.items[index].annotations = annotations
            saveHistory()
        }
    }

    func generateRecordingURL() -> URL {
        let filename = generateFilename(for: .recording)
        return screenshotsDirectory.appendingPathComponent(filename)
    }

    func generateGIFURL() -> URL {
        let filename = generateFilename(for: .gif)
        return screenshotsDirectory.appendingPathComponent(filename)
    }

    private func generateFilename(for type: CaptureType) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateString = formatter.string(from: Date())

        let ext: String
        switch type {
        case .screenshot, .scrollingCapture: ext = "png"
        case .recording: ext = "mp4"
        case .gif: ext = "gif"
        }

        return "\(type.prefix) \(dateString).\(ext)"
    }

    private func deleteFile(named filename: String) {
        let url = screenshotsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFile)
        }
    }

    func getMetadata(for capture: CaptureItem) -> CaptureMetadata {
        let url = screenshotsDirectory.appendingPathComponent(capture.filename)

        var metadata = CaptureMetadata()

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            metadata.fileSize = fileSize
        }

        switch capture.type {
        case .screenshot, .scrollingCapture:
            if let image = NSImage(contentsOf: url) {
                metadata.width = Int(image.size.width)
                metadata.height = Int(image.size.height)
            }

        case .recording, .gif:
            // Could use AVAsset to get video metadata
            break
        }

        return metadata
    }

    func exportCapture(_ capture: CaptureItem, to destinationURL: URL) throws {
        let sourceURL = screenshotsDirectory.appendingPathComponent(capture.filename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func importCapture(from url: URL) -> CaptureItem? {
        let filename = url.lastPathComponent
        let destinationURL = screenshotsDirectory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)

            let type: CaptureType
            switch url.pathExtension.lowercased() {
            case "png", "jpg", "jpeg": type = .screenshot
            case "mp4", "mov": type = .recording
            case "gif": type = .gif
            default: return nil
            }

            let capture = CaptureItem(type: type, filename: filename)
            history.add(capture)
            saveHistory()
            return capture
        } catch {
            return nil
        }
    }

    var totalStorageUsed: Int64 {
        let enumerator = FileManager.default.enumerator(at: screenshotsDirectory, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0

        while let url = enumerator?.nextObject() as? URL {
            if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                total += Int64(fileSize)
            }
        }

        return total
    }

    var formattedStorageUsed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalStorageUsed)
    }

    deinit {
        autoSaveTimer?.invalidate()
        saveHistory()
    }
}
