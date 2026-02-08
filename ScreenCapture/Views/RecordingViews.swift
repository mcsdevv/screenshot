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
    @State private var startScreenPoint: CGPoint?
    @State private var currentScreenPoint: CGPoint?
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
            .gesture(selectionGesture())
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
                    DSSecondaryButton("Record Window", icon: "video") {
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

    private func selectionGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isSelecting {
                    startPoint = value.startLocation
                    startScreenPoint = NSEvent.mouseLocation
                    isSelecting = true
                }
                currentPoint = value.location
                currentScreenPoint = NSEvent.mouseLocation
            }
            .onEnded { value in
                if let start = startPoint {
                    let localRect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )

                    if localRect.width > 5 && localRect.height > 5, let startScreenPoint {
                        let endScreenPoint = currentScreenPoint ?? NSEvent.mouseLocation
                        let screenRect = CGRect(
                            x: min(startScreenPoint.x, endScreenPoint.x),
                            y: min(startScreenPoint.y, endScreenPoint.y),
                            width: abs(endScreenPoint.x - startScreenPoint.x),
                            height: abs(endScreenPoint.y - startScreenPoint.y)
                        )
                        onSelection(screenRect.standardized)
                    }
                }

                isSelecting = false
                startPoint = nil
                currentPoint = nil
                startScreenPoint = nil
                currentScreenPoint = nil
            }
    }
}

// MARK: - Recording Controls View

struct RecordingControlsView: View {
    @ObservedObject var session: RecordingSessionModel
    let onStop: () -> Void

    @State private var isBlinking = false

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.lg) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .opacity(isRecordingState ? (isBlinking ? 0.3 : 1.0) : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            isBlinking = true
                        }
                    }

                Text(statusText)
                    .font(DSTypography.mono)
                    .foregroundColor(.dsTextPrimary)

                Spacer()

                if canStop {
                    DSIconButton(icon: "stop.fill", size: 28) {
                        onStop()
                    }
                }
            }

            if isExportingGIF {
                ProgressView(value: session.gifExportProgress)
                    .progressViewStyle(.linear)
                    .tint(.dsAccent)
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

    private var isRecordingState: Bool {
        if case .recording = session.state { return true }
        return false
    }

    private var isStoppingState: Bool {
        if case .stopping = session.state { return true }
        return false
    }

    private var isExportingGIF: Bool {
        if case .exportingGIF = session.state { return true }
        return false
    }

    private var canStop: Bool {
        isRecordingState
    }

    private var statusText: String {
        if isExportingGIF {
            let percent = Int((session.gifExportProgress * 100).rounded())
            return "Exporting GIF \(percent)%"
        }

        if isStoppingState {
            return "Finalizing..."
        }

        return formatDuration(session.elapsedDuration)
    }

    private var statusColor: Color {
        if isExportingGIF { return .dsAccent }
        if isStoppingState { return .dsWarmAccent }
        return .dsDanger
    }
}

// MARK: - Recording Overlay

struct RecordingOverlayView: View {
    let recordingRect: CGRect
    let screenFrame: CGRect

    var body: some View {
        GeometryReader { geometry in
            let viewRect = convertToViewCoordinates(recordingRect, localHeight: geometry.size.height)

            ZStack {
                DimmingOverlay(rect: viewRect, size: geometry.size, dimmingOpacity: 0.35)

                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundColor(.dsBorderActive)
                    .frame(width: viewRect.width, height: viewRect.height)
                    .position(x: viewRect.midX, y: viewRect.midY)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func convertToViewCoordinates(_ rect: CGRect, localHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x - screenFrame.minX,
            y: localHeight - (rect.origin.y - screenFrame.minY) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
