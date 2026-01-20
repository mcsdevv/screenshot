import Foundation
import AppKit

struct CaptureItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let type: CaptureType
    let filename: String
    let createdAt: Date
    var annotations: Data?
    var isFavorite: Bool

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(type.prefix) \(formatter.string(from: createdAt))"
    }

    var fileExtension: String {
        switch type {
        case .screenshot, .scrollingCapture:
            return "png"
        case .recording:
            return "mp4"
        case .gif:
            return "gif"
        }
    }

    init(
        id: UUID = UUID(),
        type: CaptureType,
        filename: String,
        createdAt: Date = Date(),
        annotations: Data? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.type = type
        self.filename = filename
        self.createdAt = createdAt
        self.annotations = annotations
        self.isFavorite = isFavorite
    }
}

enum CaptureType: String, Codable, CaseIterable, Sendable {
    case screenshot = "Screenshot"
    case scrollingCapture = "Scrolling"
    case recording = "Recording"
    case gif = "GIF"

    var prefix: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .scrollingCapture: return "Scrolling Capture"
        case .recording: return "Recording"
        case .gif: return "GIF"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.fill"
        case .scrollingCapture: return "scroll.fill"
        case .recording: return "video.fill"
        case .gif: return "photo.on.rectangle.angled"
        }
    }

    var color: NSColor {
        switch self {
        case .screenshot: return .systemBlue
        case .scrollingCapture: return .systemPurple
        case .recording: return .systemRed
        case .gif: return .systemOrange
        }
    }
}

struct CaptureMetadata: Codable, Sendable {
    var width: Int
    var height: Int
    var duration: TimeInterval?
    var frameCount: Int?
    var fileSize: Int64
    var colorSpace: String?

    init(
        width: Int = 0,
        height: Int = 0,
        duration: TimeInterval? = nil,
        frameCount: Int? = nil,
        fileSize: Int64 = 0,
        colorSpace: String? = nil
    ) {
        self.width = width
        self.height = height
        self.duration = duration
        self.frameCount = frameCount
        self.fileSize = fileSize
        self.colorSpace = colorSpace
    }

    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var dimensionsString: String {
        "\(width) x \(height)"
    }

    var durationString: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension CaptureItem {
    static func preview() -> CaptureItem {
        CaptureItem(
            type: .screenshot,
            filename: "preview.png",
            createdAt: Date()
        )
    }

    static func samples() -> [CaptureItem] {
        [
            CaptureItem(type: .screenshot, filename: "screenshot1.png", createdAt: Date()),
            CaptureItem(type: .recording, filename: "recording1.mp4", createdAt: Date().addingTimeInterval(-3600)),
            CaptureItem(type: .gif, filename: "animation1.gif", createdAt: Date().addingTimeInterval(-7200)),
            CaptureItem(type: .scrollingCapture, filename: "scroll1.png", createdAt: Date().addingTimeInterval(-86400))
        ]
    }
}

class CaptureHistory: Codable {
    var items: [CaptureItem]
    var lastCleanup: Date

    init(items: [CaptureItem] = [], lastCleanup: Date = Date()) {
        self.items = items
        self.lastCleanup = lastCleanup
    }

    convenience init(fileURL: URL, fileManager: FileManager = .default) {
        if let data = fileManager.contents(atPath: fileURL.path),
           let loadedHistory = try? JSONDecoder().decode(CaptureHistory.self, from: data) {
            self.init(items: loadedHistory.items, lastCleanup: loadedHistory.lastCleanup)
        } else {
            self.init()
        }
    }

    func add(_ item: CaptureItem) {
        items.insert(item, at: 0)
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func toggleFavorite(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isFavorite.toggle()
        }
    }

    func cleanup(olderThan days: Int = 30) {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
        items.removeAll { !$0.isFavorite && $0.createdAt < cutoffDate }
        lastCleanup = Date()
    }

    func filter(by type: CaptureType?) -> [CaptureItem] {
        guard let type = type else { return items }
        return items.filter { $0.type == type }
    }

    func search(query: String) -> [CaptureItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }
}
