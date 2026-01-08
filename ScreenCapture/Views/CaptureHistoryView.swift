import SwiftUI
import AppKit
import QuickLookUI

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
            Divider()
            filterBar
            Divider()

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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var historyToolbar: some View {
        HStack(spacing: 16) {
            Text("Capture History")
                .font(.title2.bold())

            Spacer()

            HStack(spacing: 8) {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedType == nil) {
                    selectedType = nil
                }

                ForEach(CaptureType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }

                Spacer()

                Text("\(filteredCaptures.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)], spacing: 16) {
                ForEach(filteredCaptures) { capture in
                    CaptureGridItem(
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
            .padding(20)
        }
    }

    private var listView: some View {
        List(selection: $selectedCaptures) {
            ForEach(filteredCaptures) { capture in
                CaptureListItem(capture: capture, storageManager: storageManager)
                    .tag(capture.id)
                    .contextMenu {
                        captureContextMenu(for: capture)
                    }
            }
        }
        .listStyle(.inset)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Captures Yet")
                .font(.title2.bold())

            Text("Your screenshots and recordings will appear here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Take a Screenshot") {
                Task { @MainActor in
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.screenshotManager.captureArea()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func captureContextMenu(for capture: CaptureItem) -> some View {
        Button("Open") { openCapture(capture) }
        Button("Open in Annotation Editor") { openInEditor(capture) }
        Divider()
        Button("Copy") { copyCapture(capture) }
        Button("Save As...") { saveCapture(capture) }
        Divider()
        Button("Show in Finder") { showInFinder(capture) }
        Divider()
        Button(capture.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            storageManager.toggleFavorite(capture)
        }
        Divider()
        Button("Delete", role: .destructive) { deleteCapture(capture) }
    }

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
        // Would open the annotation editor
    }

    private func copyCapture(_ capture: CaptureItem) {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
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

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct CaptureGridItem: View {
    let capture: CaptureItem
    let storageManager: StorageManager
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 200, height: 140)
                        .overlay(
                            Image(systemName: capture.type.icon)
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        )
                }

                if capture.isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                if isHovered {
                    Color.black.opacity(0.3)
                        .overlay(
                            HStack(spacing: 12) {
                                GridActionButton(icon: "doc.on.clipboard") {
                                    copyToClipboard()
                                }
                                GridActionButton(icon: "square.and.arrow.up") {
                                    share()
                                }
                                GridActionButton(icon: "pencil") {
                                    // Open editor
                                }
                            }
                        )
                }
            }
            .frame(width: 200, height: 140)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(capture.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(formatDate(capture.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(width: 200, alignment: .leading)
        }
        .onAppear { loadThumbnail() }
        .onHover { hovering in isHovered = hovering }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture { onSelect() }
    }

    private func loadThumbnail() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            thumbnail = image
        }
    }

    private func copyToClipboard() {
        if let image = thumbnail {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    private func share() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        _ = NSSharingServicePicker(items: [url])
        // TODO: Show picker with proper view reference
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct GridActionButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}

struct CaptureListItem: View {
    let capture: CaptureItem
    let storageManager: StorageManager

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 45)
                    .clipped()
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 60, height: 45)
                    .overlay(
                        Image(systemName: capture.type.icon)
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(capture.displayName)
                        .font(.system(size: 13, weight: .medium))

                    if capture.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                }

                Text(capture.type.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(formatDate(capture.createdAt))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(capture.filename)
        if let image = NSImage(contentsOf: url) {
            thumbnail = image
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
