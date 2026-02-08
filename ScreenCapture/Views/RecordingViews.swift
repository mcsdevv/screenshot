import SwiftUI
import AppKit

// MARK: - Recording Selection View

struct RecordingSelectionView: View {
    let onSelection: (CGRect) -> Void
    let onFullscreen: () -> Void
    let onWindowSelect: (() -> Void)?
    let onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isSelecting = false
    @State private var mousePosition: CGPoint = .zero

    init(
        onSelection: @escaping (CGRect) -> Void,
        onFullscreen: @escaping () -> Void,
        onWindowSelect: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.onSelection = onSelection
        self.onFullscreen = onFullscreen
        self.onWindowSelect = onWindowSelect
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()

                if let start = startPoint, let current = currentPoint {
                    SelectionRectangle(start: start, end: current, geometry: geometry)
                }

                if !isSelecting {
                    SelectionCrosshairs(position: mousePosition, geometry: geometry)
                }

                SelectionInfoPanel(position: mousePosition, selection: currentSelectionRect)

                if !isSelecting {
                    VStack {
                        instructionBar
                            .padding(.top, DSSpacing.xxl)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(selectionGesture(in: geometry))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mousePosition = location
                case .ended:
                    break
                }
            }
            .onExitCommand {
                onCancel()
            }
        }
    }

    // MARK: - Instruction Bar

    private var instructionBar: some View {
        VStack(spacing: DSSpacing.sm) {
            Text("Drag to select area, or choose an option below")
                .font(DSTypography.bodyMedium)
                .foregroundColor(.dsTextSecondary)

            HStack(spacing: DSSpacing.md) {
                DSPrimaryButton("Record Fullscreen", icon: "rectangle.inset.filled") {
                    onFullscreen()
                }

                if let onWindowSelect = onWindowSelect {
                    DSSecondaryButton("Record Window", icon: "macwindow") {
                        onWindowSelect()
                    }
                }

                DSSecondaryButton("Cancel", icon: "xmark") {
                    onCancel()
                }
            }
        }
        .padding(.horizontal, DSSpacing.xxl)
        .padding(.vertical, DSSpacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    // MARK: - Selection Geometry

    private var currentSelectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func selectionGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isSelecting {
                    startPoint = value.startLocation
                    isSelecting = true
                }
                currentPoint = value.location
            }
            .onEnded { value in
                if let start = startPoint {
                    let rect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )

                    if rect.width > 5 && rect.height > 5 {
                        onSelection(convertToScreenCoordinates(rect, in: geometry))
                    }
                }

                isSelecting = false
                startPoint = nil
                currentPoint = nil
            }
    }

    private func convertToScreenCoordinates(_ rect: CGRect, in geometry: GeometryProxy) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let screenHeight = screen.frame.height

        return CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

// MARK: - Recording Controls View

struct RecordingControlsView: View {
    @Binding var duration: TimeInterval
    @Binding var isPaused: Bool
    let onStop: () -> Void
    let onPause: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.lg) {
            Circle()
                .fill(Color.dsDanger)
                .frame(width: 12, height: 12)
                .opacity(isPaused ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: !isPaused)

            Text(formatDuration(duration))
                .font(DSTypography.mono)
                .foregroundColor(.dsTextPrimary)

            Spacer()

            DSIconButton(icon: isPaused ? "play.fill" : "pause.fill", size: 28) {
                onPause()
            }

            DSIconButton(icon: "stop.fill", size: 28) {
                onStop()
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
