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
        case .screenshot:
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
    case recording = "Recording"
    case gif = "GIF"

    var prefix: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .recording: return "Recording"
        case .gif: return "GIF"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.fill"
        case .recording: return "video.fill"
        case .gif: return "photo.on.rectangle.angled"
        }
    }

    var color: NSColor {
        switch self {
        case .screenshot: return .systemBlue
        case .recording: return .systemRed
        case .gif: return .systemOrange
        }
    }

    var badgeStyle: DSBadge.Style {
        switch self {
        case .recording, .gif: return .systemAccent
        case .screenshot: return .neutral
        }
    }
}

/// Screen corner positions for popup windows
enum ScreenCorner: String, Codable, CaseIterable, Sendable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    /// System image icon for UI picker
    var icon: String {
        switch self {
        case .topLeft: return "arrow.up.left.square"
        case .topRight: return "arrow.up.right.square"
        case .bottomLeft: return "arrow.down.left.square"
        case .bottomRight: return "arrow.down.right.square"
        }
    }

    /// Calculate window origin for given screen and window size
    func windowOrigin(screenFrame: CGRect, windowSize: NSSize, padding: CGFloat = 20) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - windowSize.height - padding
            )
        case .topRight:
            return CGPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.maxY - windowSize.height - padding
            )
        case .bottomLeft:
            return CGPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        case .bottomRight:
            return CGPoint(
                x: screenFrame.maxX - windowSize.width - padding,
                y: screenFrame.minY + padding
            )
        }
    }

    /// Animation offset direction for entrance animation
    var entranceOffset: CGSize {
        switch self {
        case .topLeft:     return CGSize(width: -30, height: -30)
        case .topRight:    return CGSize(width: 30, height: -30)
        case .bottomLeft:  return CGSize(width: -30, height: 30)
        case .bottomRight: return CGSize(width: 30, height: 30)
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

private struct SkipDecodableValue: Decodable {}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []

        while !container.isAtEnd {
            do {
                items.append(try container.decode(Element.self))
            } catch {
                // Consume malformed entries so valid captures in the same file can still load.
                _ = try? container.decode(SkipDecodableValue.self)
            }
        }

        elements = items
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
            CaptureItem(type: .gif, filename: "animation1.gif", createdAt: Date().addingTimeInterval(-7200))
        ]
    }
}

class CaptureHistory: Codable {
    var items: [CaptureItem]
    var lastCleanup: Date

    private enum CodingKeys: String, CodingKey {
        case items
        case lastCleanup
    }

    init(items: [CaptureItem] = [], lastCleanup: Date = Date()) {
        self.items = items
        self.lastCleanup = lastCleanup
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedItems = try? container.decode(LossyDecodableArray<CaptureItem>.self, forKey: .items) {
            items = decodedItems.elements
        } else {
            items = []
        }

        lastCleanup = (try? container.decode(Date.self, forKey: .lastCleanup)) ?? Date()
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
