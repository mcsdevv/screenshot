import SwiftUI
import AppKit
import QuickLookUI
import AVFoundation
import ImageIO

struct CaptureHistoryView: View {
    @EnvironmentObject var storageManager: StorageManager
    @State private var searchText = ""
    @State private var selectedType: CaptureType?
    @State private var selectedCaptures: Set<UUID> = []
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var viewMode: ViewMode = .grid

    enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name A-Z"
        case nameDescending = "Name Z-A"

        var icon: String {
            switch self {
            case .dateDescending: return "arrow.down"
            case .dateAscending: return "arrow.up"
            case .nameAscending: return "textformat.abc"
            case .nameDescending: return "textformat.abc"
            }
        }
    }

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    var filteredCaptures: [CaptureItem] {
        var captures = storageManager.history.items

        if let type = selectedType {
            captures = captures.filter { $0.type == type }
        }

        if !searchText.isEmpty {
            captures = captures.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .dateDescending:
            captures.sort { $0.createdAt > $1.createdAt }
        case .dateAscending:
            captures.sort { $0.createdAt < $1.createdAt }
        case .nameAscending:
            captures.sort { $0.displayName < $1.displayName }
        case .nameDescending:
            captures.sort { $0.displayName > $1.displayName }
        }

        return captures
    }

    var body: some View {
        VStack(spacing: 0) {
            historyToolbar
            DSDivider()
            filterBar
            DSDivider()

            if filteredCaptures.isEmpty {
                emptyStateView
            } else {
                if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color.dsBackground)
    }

    // MARK: - Toolbar

    private var historyToolbar: some View {
        HStack(spacing: DSSpacing.lg) {
            // Title
            VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                Text("Capture History")
                    .font(DSTypography.displaySmall)
                    .foregroundColor(.dsTextPrimary)
                Text("\(filteredCaptures.count) items")
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }

            Spacer()

            // Search field
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.dsTextTertiary)

                TextField("Search captures...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DSTypography.bodyMedium)
                    .foregroundColor(.dsTextPrimary)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.dsTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(Color.dsBackgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .strokeBorder(Color.dsBorder, lineWidth: 1)
            )

            // Sort picker
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                    Text("Sort")
                        .font(DSTypography.labelSmall)
                }
                .foregroundColor(.dsTextSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.md)
                        .fill(Color.dsBackgroundSecondary)
                )
            }
            .menuStyle(.borderlessButton)

            // View mode toggle
            HStack(spacing: 0) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button(action: { viewMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                            .foregroundColor(viewMode == mode ? .dsAccent : .dsTextTertiary)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: DSRadius.sm)
                                    .fill(viewMode == mode ? Color.dsAccent.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DSSpacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(Color.dsBackgroundSecondary)
            )
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.vertical, DSSpacing.lg)
        .background(Color.dsBackgroundElevated)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                DSChip("All", isSelected: selectedType == nil) {
                    selectedType = nil
                }

                ForEach(CaptureType.allCases, id: \.self) { type in
                    DSChip(type.rawValue, icon: type.icon, isSelected: selectedType == type) {
                        selectedType = type
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.vertical, DSSpacing.md)
        }
        .background(Color.dsBackgroundElevated)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: DSSpacing.lg)],
                spacing: DSSpacing.lg
            ) {
                ForEach(filteredCaptures) { capture in
                    CaptureGridCard(
                        capture: capture,
                        storageManager: storageManager,
                        isSelected: selectedCaptures.contains(capture.id),
                        onSelect: { toggleSelection(capture.id) },
                        onDoubleClick: { openCapture(capture) }
                    )
                    .contextMenu {
                        captureContextMenu(for: capture)
                    }
                }
            }
            .padding(DSSpacing.xl)
        }
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.sm) {
                ForEach(filteredCaptures) { capture in
                    CaptureListRow(
                        capture: capture,
                        storageManager: storageManager,
                        isSelected: selectedCaptures.contains(capture.id),
                        onSelect: { toggleSelection(capture.id) },
                        onDoubleClick: { openCapture(capture) }
                    )
                    .contextMenu {
                        captureContextMenu(for: capture)
                    }
                }
            }
            .padding(DSSpacing.xl)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DSSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.dsAccent.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.dsAccent)
            }

            VStack(spacing: DSSpacing.sm) {
                Text("No Captures Yet")
                    .font(DSTypography.headlineLarge)
                    .foregroundColor(.dsTextPrimary)

                Text("Your screenshots and recordings will appear here.")
                    .font(DSTypography.bodyMedium)
                    .foregroundColor(.dsTextSecondary)
                    .multilineTextAlignment(.center)
            }

            DSPrimaryButton("Take a Screenshot", icon: "camera") {
                Task { @MainActor in
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.screenshotManager.captureArea()
                    }
                }
            }
            .padding(.top, DSSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func captureContextMenu(for capture: CaptureItem) -> some View {
        Button { openCapture(capture) } label: {
            Label("Open", systemImage: "arrow.up.right")
        }

        Button { openInEditor(capture) } label: {
            Label("Open in Editor", systemImage: "pencil")
        }

        Divider()

        Button { copyCapture(capture) } label: {
            Label("Copy", systemImage: "doc.on.clipboard")
        }

        Button { saveCapture(capture) } label: {
            Label("Save As...", systemImage: "square.and.arrow.down")
        }

        Divider()

        Button { showInFinder(capture) } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button { storageManager.toggleFavorite(capture) } label: {
            Label(
                capture.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: capture.isFavorite ? "star.slash" : "star"
            )
        }

        Divider()

        Button(role: .destructive) { deleteCapture(capture) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedCaptures.contains(id) {
            selectedCaptures.remove(id)
        } else {
            selectedCaptures.insert(id)
        }
    }

    private func openCapture(_ capture: CaptureItem) {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.open(url)
    }

    private func openInEditor(_ capture: CaptureItem) {
        NotificationCenter.default.post(name: .openAnnotationEditor, object: capture)
    }

    private func copyCapture(_ capture: CaptureItem) {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            NSSound(named: "Pop")?.play()
        }
    }

    private func saveCapture(_ capture: CaptureItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = capture.filename

        if panel.runModal() == .OK, let destinationURL = panel.url {
            let sourceURL = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func showInFinder(_ capture: CaptureItem) {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteCapture(_ capture: CaptureItem) {
        storageManager.deleteCapture(capture)
    }
}

// MARK: - Capture Grid Card

struct CaptureGridCard: View {
    let capture: CaptureItem
    let storageManager: StorageManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 150)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.dsBackgroundSecondary)
                        .frame(width: 220, height: 150)
                        .overlay(
                            Image(systemName: capture.type.icon)
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.dsTextTertiary)
                        )
                }

                // Favorite badge
                if capture.isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.dsWarmAccent)
                                .padding(DSSpacing.sm)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                )
                        }
                        Spacer()
                    }
                    .padding(DSSpacing.sm)
                }

                // Hover overlay
                if isHovered {
                    Color.black.opacity(0.5)

                    HStack(spacing: DSSpacing.md) {
                        GridHoverButton(icon: "doc.on.clipboard") {
                            copyToClipboard()
                        }
                        GridHoverButton(icon: "pencil") {
                            NotificationCenter.default.post(name: .openAnnotationEditor, object: capture)
                        }
                        GridHoverButton(icon: "square.and.arrow.up") {
                            // Share
                        }
                    }
                }

                // Type badge
                VStack {
                    Spacer()
                    HStack {
                        DSBadge(text: capture.type.rawValue, style: capture.type.badgeStyle)
                        Spacer()
                    }
                    .padding(DSSpacing.sm)
                }
            }
            .frame(width: 220, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(
                        isSelected ? Color.dsAccent :
                        (isHovered ? Color.dsBorderActive : Color.dsBorder),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.dsAccent.opacity(0.25) : .black.opacity(0.15),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: 4
            )

            // Info
            VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                Text(capture.displayName)
                    .font(DSTypography.labelMedium)
                    .foregroundColor(.dsTextPrimary)
                    .lineLimit(1)

                Text(formatDate(capture.createdAt))
                    .font(DSTypography.caption)
                    .foregroundColor(.dsTextTertiary)
            }
            .frame(width: 220, alignment: .leading)
        }
        .onAppear { loadThumbnail() }
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture { onSelect() }
    }

    private func loadThumbnail() {
        Task { @MainActor in
            let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
            let captureType = capture.type
            let image = await Task.detached(priority: .userInitiated) {
                await makeThumbnailImage(for: captureType, at: url, maxPixelSize: 440)
            }.value

            if let image {
                thumbnail = image
            }
        }
    }

    private func copyToClipboard() {
        if let image = thumbnail {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            NSSound(named: "Pop")?.play()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Grid Hover Button

struct GridHoverButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isHovered ? Color.dsAccent : Color.white.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Capture List Row

struct CaptureListRow: View {
    let capture: CaptureItem
    let storageManager: StorageManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 56)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.dsBackgroundSecondary)
                        .frame(width: 80, height: 56)
                        .overlay(
                            Image(systemName: capture.type.icon)
                                .font(.system(size: 20))
                                .foregroundColor(.dsTextTertiary)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .strokeBorder(Color.dsBorder, lineWidth: 1)
            )

            // Info
            VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                HStack(spacing: DSSpacing.sm) {
                    Text(capture.displayName)
                        .font(DSTypography.labelMedium)
                        .foregroundColor(.dsTextPrimary)

                    if capture.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.dsWarmAccent)
                    }
                }

                HStack(spacing: DSSpacing.sm) {
                    DSBadge(text: capture.type.rawValue, style: capture.type.badgeStyle)

                    Text(formatDate(capture.createdAt))
                        .font(DSTypography.caption)
                        .foregroundColor(.dsTextTertiary)
                }
            }

            Spacer()

            // Quick actions (on hover)
            if isHovered {
                HStack(spacing: DSSpacing.xs) {
                    DSIconButton(icon: "doc.on.clipboard", size: 28) {
                        copyToClipboard()
                    }
                    DSIconButton(icon: "pencil", size: 28) {
                        NotificationCenter.default.post(name: .openAnnotationEditor, object: capture)
                    }
                    DSIconButton(icon: "folder", size: 28) {
                        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(
                    isSelected ? Color.dsAccent.opacity(0.1) :
                    (isHovered ? Color.dsBackgroundSecondary : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(
                    isSelected ? Color.dsAccent.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
        .onAppear { loadThumbnail() }
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture { onSelect() }
    }

    private func loadThumbnail() {
        Task { @MainActor in
            let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
            let captureType = capture.type
            let image = await Task.detached(priority: .userInitiated) {
                await makeThumbnailImage(for: captureType, at: url, maxPixelSize: 160)
            }.value

            if let image {
                thumbnail = image
            }
        }
    }

    private func copyToClipboard() {
        if let image = thumbnail {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            NSSound(named: "Pop")?.play()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Components (for backwards compatibility)

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        DSChip(title, icon: icon, isSelected: isSelected, action: action)
    }
}

struct CaptureGridItem: View {
    let capture: CaptureItem
    let storageManager: StorageManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    var body: some View {
        CaptureGridCard(
            capture: capture,
            storageManager: storageManager,
            isSelected: isSelected,
            onSelect: onSelect,
            onDoubleClick: onDoubleClick
        )
    }
}

struct GridActionButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        GridHoverButton(icon: icon, action: action)
    }
}

struct CaptureListItem: View {
    let capture: CaptureItem
    let storageManager: StorageManager

    var body: some View {
        CaptureListRow(
            capture: capture,
            storageManager: storageManager,
            isSelected: false,
            onSelect: {},
            onDoubleClick: {}
        )
    }
}

private func makeThumbnailImage(for type: CaptureType, at url: URL, maxPixelSize: CGFloat) async -> NSImage? {
    switch type {
    case .recording:
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        if let cgImage = try? await generator.generateCGImageAsync(at: CMTime(seconds: 0.1, preferredTimescale: 600)) {
            return NSImage(cgImage: cgImage, size: .zero)
        }
        if let cgImage = try? await generator.generateCGImageAsync(at: .zero) {
            return NSImage(cgImage: cgImage, size: .zero)
        }
        return nil

    case .screenshot, .gif:
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
