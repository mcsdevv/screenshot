import Foundation
import AppKit
import Combine

struct StorageConfig: @unchecked Sendable {
    let baseDirectory: URL
    let userDefaults: UserDefaults
    let fileManager: FileManager

    static var live: StorageConfig {
        StorageConfig(
            baseDirectory: StorageManager.defaultBaseDirectory(),
            userDefaults: .standard,
            fileManager: .default
        )
    }

    static func test(baseDirectory: URL, userDefaults: UserDefaults) -> StorageConfig {
        StorageConfig(baseDirectory: baseDirectory, userDefaults: userDefaults, fileManager: .default)
    }
}

@MainActor
class StorageManager: ObservableObject {
    @Published var history: CaptureHistory
    @Published var storageVerified: Bool = false

    private let config: StorageConfig

    /// The current screenshots directory based on user preferences
    var screenshotsDirectory: URL {
        return resolveStorageDirectory()
    }

    /// The default app support directory (always available)
    let defaultDirectory: URL

    private let appDirectory: URL
    private let historyFile: URL
    private var autoSaveTimer: Timer?
    private var activeSecurityScopedDirectory: URL?

    // UserDefaults keys
    private static let storageLocationKey = "storageLocation"
    private static let customFolderBookmarkKey = "customFolderBookmark"
    private static let autoCleanupKey = "autoCleanup"
    private static let cleanupDaysKey = "cleanupDays"
    private static let captureFormatKey = "captureFormat"
    private static let jpegQualityKey = "jpegQuality"

    init(config: StorageConfig = .live) {
        self.config = config
        appDirectory = config.baseDirectory

        defaultDirectory = appDirectory.appendingPathComponent("Screenshots", isDirectory: true)
        historyFile = appDirectory.appendingPathComponent("history.json")

        // Create default directory
        do {
            try config.fileManager.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
            debugLog("StorageManager: Created/verified default directory at \(defaultDirectory.path)")
        } catch {
            errorLog("StorageManager: Failed to create default directory", error: error)
        }

        history = CaptureHistory(fileURL: historyFile, fileManager: config.fileManager)

        setupAutoSave()
        cleanupOldCaptures()

        // Verify storage permissions on startup
        verifyStoragePermissions()
    }

    nonisolated static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ScreenCapture", isDirectory: true)
    }

    /// Resolves the storage directory based on user preferences
    private func resolveStorageDirectory() -> URL {
        let storageLocation = config.userDefaults.string(forKey: Self.storageLocationKey) ?? "default"

        switch storageLocation {
        case "desktop":
            stopAccessingSecurityScopedDirectory()
            return config.fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first!
        case "custom":
            if let customURL = resolveCustomFolderURL() {
                return customURL
            }
            debugLog("StorageManager: Custom folder not accessible, falling back to default")
            return defaultDirectory
        default:
            stopAccessingSecurityScopedDirectory()
            return defaultDirectory
        }
    }

    /// Gets the custom folder URL from the stored security-scoped bookmark
    func getCustomFolderURL() -> URL? {
        resolveCustomFolderURL()
    }

    private func resolveCustomFolderURL() -> URL? {
        guard let bookmarkData = config.userDefaults.data(forKey: Self.customFolderBookmarkKey) else {
            stopAccessingSecurityScopedDirectory()
            return nil
        }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)

            if isStale {
                debugLog("StorageManager: Bookmark is stale, need to re-select folder")
                config.userDefaults.removeObject(forKey: Self.customFolderBookmarkKey)
                stopAccessingSecurityScopedDirectory()
                return nil
            }

            let scopedURL = url.standardizedFileURL
            if activeSecurityScopedDirectory?.standardizedFileURL == scopedURL {
                return scopedURL
            }

            guard scopedURL.startAccessingSecurityScopedResource() else {
                errorLog("StorageManager: Failed to access security-scoped resource")
                stopAccessingSecurityScopedDirectory()
                return nil
            }

            stopAccessingSecurityScopedDirectory()
            activeSecurityScopedDirectory = scopedURL
            debugLog("StorageManager: Accessed custom folder at \(scopedURL.path)")
            return scopedURL
        } catch {
            errorLog("StorageManager: Failed to resolve bookmark", error: error)
            stopAccessingSecurityScopedDirectory()
            return nil
        }
    }

    private func stopAccessingSecurityScopedDirectory() {
        guard let activeSecurityScopedDirectory else { return }
        activeSecurityScopedDirectory.stopAccessingSecurityScopedResource()
        self.activeSecurityScopedDirectory = nil
    }

    func releaseSecurityScopedAccess() {
        stopAccessingSecurityScopedDirectory()
    }

    /// Sets a custom folder and stores a security-scoped bookmark
    func setCustomFolder(_ url: URL) -> Bool {
        do {
            // Create a security-scoped bookmark
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            config.userDefaults.set(bookmarkData, forKey: Self.customFolderBookmarkKey)
            config.userDefaults.set("custom", forKey: Self.storageLocationKey)

            debugLog("StorageManager: Set custom folder to \(url.path)")

            // Verify we can write to it
            verifyStoragePermissions()

            return true
        } catch {
            errorLog("StorageManager: Failed to create bookmark for custom folder", error: error)
            return false
        }
    }

    /// Sets the storage location preference
    func setStorageLocation(_ location: String) {
        config.userDefaults.set(location, forKey: Self.storageLocationKey)
        if location != "custom" {
            stopAccessingSecurityScopedDirectory()
        }
        debugLog("StorageManager: Storage location set to \(location)")
        verifyStoragePermissions()
    }

    /// Gets the current storage location preference
    func getStorageLocation() -> String {
        return config.userDefaults.string(forKey: Self.storageLocationKey) ?? "default"
    }

    /// Verifies that we have write permissions to the storage directory
    func verifyStoragePermissions() {
        debugLog("StorageManager: Verifying storage permissions...")

        // Test write access by creating a temporary file
        let testFile = screenshotsDirectory.appendingPathComponent(".write_test_\(UUID().uuidString)")

        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try config.fileManager.removeItem(at: testFile)
            storageVerified = true
            debugLog("StorageManager: Storage permissions verified successfully")
            debugLog("StorageManager: Screenshots will be saved to: \(screenshotsDirectory.path)")
        } catch {
            storageVerified = false
            errorLog("StorageManager: Storage permission verification failed", error: error)

            // Already on main actor, call directly
            showStoragePermissionAlert()
        }
    }

    private func showStoragePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Storage Permission Required"
        alert.informativeText = "ScreenCapture cannot write to the screenshots folder:\n\n\(screenshotsDirectory.path)\n\nPlease ensure the app has permission to access this location."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open in Finder")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            // Try to create the directory and open parent in Finder
            let parentDir = screenshotsDirectory.deletingLastPathComponent()
            NSWorkspace.shared.open(parentDir)
        }
    }

    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.saveHistory()
            }
        }
    }

    private func cleanupOldCaptures() {
        guard isAutoCleanupEnabled else { return }

        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -cleanupDays, to: Date())!
        var removedAny = false

        history.items.removeAll { item in
            if item.isFavorite { return false }
            if item.createdAt < cutoffDate {
                _ = deleteFile(named: item.filename)
                removeAnnotationSidecar(named: item.filename)
                removedAny = true
                return true
            }
            return false
        }

        if removedAny {
            saveHistory()
        }
    }

    func applyCleanupPolicy() {
        cleanupOldCaptures()
    }

    func saveCapture(image: NSImage, type: CaptureType) -> CaptureItem {
        let filename = generateFilename(for: type)
        let url = screenshotsDirectory.appendingPathComponent(filename)

        debugLog("StorageManager: Saving capture to \(url.path)")

        // Ensure directory exists
        do {
            try config.fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
            debugLog("StorageManager: Directory verified at \(screenshotsDirectory.path)")
        } catch {
            errorLog("StorageManager: Failed to create directory", error: error)
        }

        guard let imageData = encodedCaptureData(from: image, type: type) else {
            errorLog("StorageManager: Failed to encode capture image data")
            let capture = CaptureItem(type: type, filename: filename)
            history.add(capture)
            saveHistory()
            return capture
        }

        do {
            try imageData.write(to: url)
            debugLog("StorageManager: Successfully wrote \(imageData.count) bytes to \(url.path)")

            // Verify file exists
            if config.fileManager.fileExists(atPath: url.path) {
                debugLog("StorageManager: File verified at \(url.path)")
            } else {
                errorLog("StorageManager: File not found after write!")
            }
        } catch {
            errorLog("StorageManager: Failed to write file", error: error)
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

    @discardableResult
    func deleteCapture(_ capture: CaptureItem) -> Bool {
        let deleted = deleteFile(named: capture.filename)
        removeAnnotationSidecar(named: capture.filename)
        history.remove(id: capture.id)
        saveHistory()
        return deleted
    }

    @discardableResult
    func clearAllCaptures() -> Int {
        let captures = history.items
        var deletedCount = 0

        for capture in captures {
            if deleteFile(named: capture.filename) {
                deletedCount += 1
            }
            removeAnnotationSidecar(named: capture.filename)
        }

        history.items.removeAll()
        saveHistory()
        return deletedCount
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
        case .screenshot, .scrollingCapture:
            ext = screenshotFileExtension
        case .recording: ext = "mp4"
        case .gif: ext = "gif"
        }

        return "\(type.prefix) \(dateString).\(ext)"
    }

    private func removeAnnotationSidecar(named filename: String) {
        let imageURL = screenshotsDirectory.appendingPathComponent(filename)
        let sidecarURL = AnnotationDocument.sidecarURL(for: imageURL)
        if config.fileManager.fileExists(atPath: sidecarURL.path) {
            try? config.fileManager.removeItem(at: sidecarURL)
        }
    }

    private func deleteFile(named filename: String) -> Bool {
        let url = screenshotsDirectory.appendingPathComponent(filename)
        guard config.fileManager.fileExists(atPath: url.path) else {
            return true
        }

        do {
            try config.fileManager.removeItem(at: url)
            return true
        } catch {
            errorLog("StorageManager: Failed to delete file at \(url.path)", error: error)
            return false
        }
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFile)
        }
    }

    func getMetadata(for capture: CaptureItem) -> CaptureMetadata {
        let url = screenshotsDirectory.appendingPathComponent(capture.filename)

        var metadata = CaptureMetadata()

        if let attributes = try? config.fileManager.attributesOfItem(atPath: url.path),
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
        try config.fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func importCapture(from url: URL) -> CaptureItem? {
        let filename = url.lastPathComponent
        let destinationURL = screenshotsDirectory.appendingPathComponent(filename)

        do {
            try config.fileManager.copyItem(at: url, to: destinationURL)

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
        let enumerator = config.fileManager.enumerator(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
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
        // Note: Cannot call @MainActor-isolated saveHistory() from deinit.
        // Auto-save timer handles periodic saves; final save happens in AppDelegate termination hook.
    }
}

private extension StorageManager {
    enum ScreenshotFormat: String {
        case png
        case jpeg
        case tiff
    }

    var screenshotFileExtension: String {
        screenshotFormat.rawValue == ScreenshotFormat.jpeg.rawValue ? "jpg" : screenshotFormat.rawValue
    }

    var screenshotFormat: ScreenshotFormat {
        ScreenshotFormat(rawValue: (config.userDefaults.string(forKey: Self.captureFormatKey) ?? "png").lowercased()) ?? .png
    }

    var jpegCompression: CGFloat {
        let raw = config.userDefaults.object(forKey: Self.jpegQualityKey) as? Double ?? 0.9
        return max(0.1, min(1.0, CGFloat(raw)))
    }

    var isAutoCleanupEnabled: Bool {
        guard config.userDefaults.object(forKey: Self.autoCleanupKey) != nil else { return true }
        return config.userDefaults.bool(forKey: Self.autoCleanupKey)
    }

    var cleanupDays: Int {
        let value = config.userDefaults.integer(forKey: Self.cleanupDaysKey)
        let validValues = [7, 14, 30, 90]
        return validValues.contains(value) ? value : 30
    }

    func encodedCaptureData(from image: NSImage, type: CaptureType) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        switch type {
        case .screenshot, .scrollingCapture:
            switch screenshotFormat {
            case .png:
                return bitmap.representation(using: .png, properties: [:])
            case .jpeg:
                return bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegCompression])
            case .tiff:
                return bitmap.representation(using: .tiff, properties: [:])
            }
        case .recording, .gif:
            return bitmap.representation(using: .png, properties: [:])
        }
    }
}
