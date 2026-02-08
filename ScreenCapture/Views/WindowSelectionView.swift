import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Window Selection View

struct WindowSelectionView: View {
    let onWindowSelected: (SCWindow) -> Void
    let onCancel: () -> Void

    @State private var windows: [AppWindows] = []
    @State private var isLoading = true
    @State private var hoveredWindowID: CGWindowID?

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            windowPickerPanel
        }
        .onExitCommand { onCancel() }
        .task { await loadWindows() }
    }

    // MARK: - Window Picker Panel

    private var windowPickerPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Window to Record")
                    .font(DSTypography.headlineMedium)
                    .foregroundColor(.dsTextPrimary)

                Spacer()

                DSSecondaryButton("Cancel", icon: "xmark") {
                    onCancel()
                }
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.vertical, DSSpacing.lg)

            Divider().background(Color.dsBorder)

            // Window list
            if isLoading {
                loadingView
            } else if windows.isEmpty {
                emptyView
            } else {
                windowList
            }
        }
        .frame(maxWidth: 480, maxHeight: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }

    // MARK: - Window List

    private var windowList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(windows, id: \.appName) { appWindows in
                    ForEach(appWindows.windows, id: \.windowID) { window in
                        windowRow(window: window, appName: appWindows.appName, appIcon: appWindows.appIcon)
                        Divider().background(Color.dsBorder).padding(.leading, DSSpacing.huge)
                    }
                }
            }
        }
    }

    private func windowRow(window: SCWindow, appName: String, appIcon: NSImage?) -> some View {
        let isHovered = hoveredWindowID == window.windowID
        return Button {
            onWindowSelected(window)
        } label: {
            HStack(spacing: DSSpacing.md) {
                // App icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.dsTextTertiary)
                        .frame(width: 32, height: 32)
                }

                // Window info
                VStack(alignment: .leading, spacing: DSSpacing.xxxs) {
                    Text(appName)
                        .font(DSTypography.labelMedium)
                        .foregroundColor(.dsTextPrimary)

                    Text(windowTitle(for: window))
                        .font(DSTypography.bodySmall)
                        .foregroundColor(.dsTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Dimensions
                Text("\(Int(window.frame.width)) x \(Int(window.frame.height))")
                    .font(DSTypography.monoSmall)
                    .foregroundColor(.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.vertical, DSSpacing.md)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWindowID = hovering ? window.windowID : nil
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading windows...")
                .font(DSTypography.bodySmall)
                .foregroundColor(.dsTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 32))
                .foregroundColor(.dsTextTertiary)
            Text("No windows available")
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Helpers

    private func windowTitle(for window: SCWindow) -> String {
        let title = window.title ?? ""
        return title.isEmpty ? "Untitled Window" : title
    }

    private func loadWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier

            // Group windows by app, filtering out our own app and tiny windows
            var appWindowsMap: [String: AppWindows] = [:]

            for window in content.windows {
                guard let app = window.owningApplication,
                      app.bundleIdentifier != ownBundleID,
                      window.frame.width > 50 && window.frame.height > 50 else {
                    continue
                }

                let appName = app.applicationName
                let pid = app.processID
                let nsApp = NSRunningApplication(processIdentifier: pid)
                let icon = nsApp?.icon

                if appWindowsMap[appName] == nil {
                    appWindowsMap[appName] = AppWindows(appName: appName, appIcon: icon, windows: [])
                }
                appWindowsMap[appName]?.windows.append(window)
            }

            await MainActor.run {
                self.windows = appWindowsMap.values.sorted { $0.appName < $1.appName }
                self.isLoading = false
            }
        } catch {
            errorLog("Failed to load windows for selection", error: error)
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Supporting Types

struct AppWindows {
    let appName: String
    let appIcon: NSImage?
    var windows: [SCWindow]
}
