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

@MainActor
final class RecordingControlsStateModel: ObservableObject {
    @Published var showRecordButton = false
    @Published var countdownValue: Int?
}

struct RecordingControlsView: View {
    @ObservedObject var session: RecordingSessionModel
    @ObservedObject var controlsState: RecordingControlsStateModel
    let onRecord: () -> Void
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
                    HStack(spacing: DSSpacing.sm) {
                        if controlsState.showRecordButton {
                            if let countdownValue = controlsState.countdownValue {
                                RecordingControlCountdownBadge(countdownValue: countdownValue)
                            } else {
                                RecordingControlActionButton(
                                    title: "Record",
                                    icon: "record.circle.fill",
                                    foregroundColor: .black.opacity(0.85),
                                    backgroundColor: .white
                                ) {
                                    onRecord()
                                }
                            }
                        }

                        DSIconButton(icon: "stop.fill", size: 28) {
                            onStop()
                        }
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
        !isExportingGIF
    }

    private var statusText: String {
        if isExportingGIF {
            let percent = Int((session.gifExportProgress * 100).rounded())
            return "Exporting GIF \(percent)%"
        }

        if isStoppingState {
            return "Finalizing..."
        }

        if let countdownValue = controlsState.countdownValue, controlsState.showRecordButton {
            return "Starting in \(countdownValue)..."
        }

        if controlsState.showRecordButton && !isRecordingState {
            return "Ready to record"
        }

        return formatDuration(session.elapsedDuration)
    }

    private var statusColor: Color {
        if isExportingGIF { return .dsAccent }
        if isStoppingState { return .dsWarmAccent }
        if controlsState.countdownValue != nil && controlsState.showRecordButton { return .dsWarmAccent }
        if controlsState.showRecordButton && !isRecordingState { return .white.opacity(0.9) }
        return .dsDanger
    }
}

private struct RecordingControlActionButton: View {
    let title: String
    let icon: String
    let foregroundColor: Color
    let backgroundColor: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isPressed = false
                action()
            }
        }) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(DSTypography.labelMedium)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule()
                    .fill(backgroundColor.opacity(isHovered ? 0.9 : 1.0))
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct RecordingControlCountdownBadge: View {
    let countdownValue: Int

    var body: some View {
        Text("\(countdownValue)")
            .font(DSTypography.labelLarge)
            .foregroundColor(.black.opacity(0.85))
            .frame(width: 56, height: 28)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.95))
            )
    }
}

// MARK: - Adjustable Recording Overlay

struct AdjustableRecordingOverlayView: View {
    let screenFrame: CGRect
    let onRectChange: (CGRect) -> Void

    @State private var currentScreenRect: CGRect
    @State private var activeInteraction: DragInteraction?
    @State private var activeCursor: CursorKind = .arrow

    private static let minimumSize: CGFloat = 80
    private static let edgeHitThickness: CGFloat = 14
    private static let cornerHitSize: CGFloat = 24
    private static let bodyInset: CGFloat = 14

    init(initialRect: CGRect, screenFrame: CGRect, onRectChange: @escaping (CGRect) -> Void) {
        self.screenFrame = screenFrame
        self.onRectChange = onRectChange
        _currentScreenRect = State(initialValue: initialRect.standardized)
    }

    var body: some View {
        GeometryReader { geometry in
            let localRect = convertToViewCoordinates(currentScreenRect, localHeight: geometry.size.height)
            let bounds = CGRect(origin: .zero, size: geometry.size)

            ZStack {
                DimmingOverlay(rect: localRect, size: geometry.size, dimmingOpacity: 0.35)

                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundColor(.dsBorderActive)
                    .frame(width: localRect.width, height: localRect.height)
                    .position(x: localRect.midX, y: localRect.midY)

                ResizeHandles(rect: localRect)

                interactionLayer(for: localRect, bounds: bounds, localHeight: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            onRectChange(currentScreenRect)
        }
        .onDisappear {
            setCursor(.arrow)
        }
    }

    private func interactionLayer(for localRect: CGRect, bounds: CGRect, localHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateHoverCursor(at: location, in: localRect)
                case .ended:
                    if activeInteraction == nil {
                        setCursor(.arrow)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if activeInteraction == nil {
                            activeInteraction = interaction(for: value.startLocation, in: localRect)
                        }

                        guard let activeInteraction else { return }

                        switch activeInteraction {
                        case .move(let startRect):
                            let updated = moveRect(startRect, by: value.translation, in: bounds)
                            updateScreenRect(from: updated, localHeight: localHeight)
                            setCursor(.closedHand)
                        case .resize(let handle, let startRect):
                            let updated = resizeRect(
                                startRect,
                                with: value.translation,
                                handle: handle,
                                in: bounds
                            )
                            updateScreenRect(from: updated, localHeight: localHeight)
                            setCursor(cursor(for: handle))
                        }
                    }
                    .onEnded { value in
                        activeInteraction = nil

                        // Recompute cursor against latest rect for stable hover feedback.
                        let latestLocalRect = convertToViewCoordinates(currentScreenRect, localHeight: localHeight)
                        setCursor(cursor(for: value.location, in: latestLocalRect))
                    }
            )
    }

    private func updateHoverCursor(at location: CGPoint, in rect: CGRect) {
        guard activeInteraction == nil else { return }
        setCursor(cursor(for: location, in: rect))
    }

    private func cursor(for location: CGPoint, in rect: CGRect) -> CursorKind {
        if let handle = resizeHandle(at: location, in: rect) {
            return cursor(for: handle)
        }

        if bodyDragRect(for: rect).contains(location) {
            return .pointingHand
        }

        return .arrow
    }

    private func interaction(for location: CGPoint, in rect: CGRect) -> DragInteraction? {
        if let handle = resizeHandle(at: location, in: rect) {
            return .resize(handle: handle, startRect: rect)
        }

        if bodyDragRect(for: rect).contains(location) {
            return .move(startRect: rect)
        }

        return nil
    }

    private func bodyDragRect(for rect: CGRect) -> CGRect {
        rect.insetBy(dx: Self.bodyInset, dy: Self.bodyInset)
    }

    private func resizeHandle(at location: CGPoint, in rect: CGRect) -> ResizeHandle? {
        for handle in ResizeHandle.allCases {
            if resizeHandleHitRect(for: handle, in: rect).contains(location) {
                return handle
            }
        }
        return nil
    }

    private func resizeHandleHitRect(for handle: ResizeHandle, in rect: CGRect) -> CGRect {
        let cornerSize = Self.cornerHitSize
        let edgeThickness = Self.edgeHitThickness
        let cornerHalf = cornerSize / 2

        switch handle {
        case .topLeft:
            return CGRect(x: rect.minX - cornerHalf, y: rect.minY - cornerHalf, width: cornerSize, height: cornerSize)
        case .topRight:
            return CGRect(x: rect.maxX - cornerHalf, y: rect.minY - cornerHalf, width: cornerSize, height: cornerSize)
        case .bottomLeft:
            return CGRect(x: rect.minX - cornerHalf, y: rect.maxY - cornerHalf, width: cornerSize, height: cornerSize)
        case .bottomRight:
            return CGRect(x: rect.maxX - cornerHalf, y: rect.maxY - cornerHalf, width: cornerSize, height: cornerSize)
        case .top:
            return CGRect(
                x: rect.minX + cornerHalf,
                y: rect.minY - edgeThickness / 2,
                width: max(0, rect.width - cornerSize),
                height: edgeThickness
            )
        case .bottom:
            return CGRect(
                x: rect.minX + cornerHalf,
                y: rect.maxY - edgeThickness / 2,
                width: max(0, rect.width - cornerSize),
                height: edgeThickness
            )
        case .left:
            return CGRect(
                x: rect.minX - edgeThickness / 2,
                y: rect.minY + cornerHalf,
                width: edgeThickness,
                height: max(0, rect.height - cornerSize)
            )
        case .right:
            return CGRect(
                x: rect.maxX - edgeThickness / 2,
                y: rect.minY + cornerHalf,
                width: edgeThickness,
                height: max(0, rect.height - cornerSize)
            )
        }
    }

    private func cursor(for handle: ResizeHandle) -> CursorKind {
        switch handle {
        case .left, .right:
            return .resizeHorizontal
        case .top, .bottom:
            return .resizeVertical
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .crosshair
        }
    }

    private func moveRect(_ rect: CGRect, by translation: CGSize, in bounds: CGRect) -> CGRect {
        var moved = rect
        moved.origin.x += translation.width
        moved.origin.y += translation.height

        moved.origin.x = min(max(moved.origin.x, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.origin.y, bounds.minY), bounds.maxY - moved.height)

        return moved
    }

    private func resizeRect(_ rect: CGRect, with translation: CGSize, handle: ResizeHandle, in bounds: CGRect) -> CGRect {
        let minSize = Self.minimumSize

        var left = rect.minX
        var right = rect.maxX
        var top = rect.minY
        var bottom = rect.maxY

        if handle.affectsLeft {
            left = min(
                max(rect.minX + translation.width, bounds.minX),
                rect.maxX - minSize
            )
        }

        if handle.affectsRight {
            right = max(
                min(rect.maxX + translation.width, bounds.maxX),
                rect.minX + minSize
            )
        }

        if handle.affectsTop {
            top = min(
                max(rect.minY + translation.height, bounds.minY),
                rect.maxY - minSize
            )
        }

        if handle.affectsBottom {
            bottom = max(
                min(rect.maxY + translation.height, bounds.maxY),
                rect.minY + minSize
            )
        }

        return CGRect(
            x: left,
            y: top,
            width: max(minSize, right - left),
            height: max(minSize, bottom - top)
        )
    }

    private func updateScreenRect(from localRect: CGRect, localHeight: CGFloat) {
        let screenRect = convertToScreenCoordinates(localRect, localHeight: localHeight)
        currentScreenRect = screenRect
        onRectChange(screenRect)
    }

    private func handlePoint(for handle: ResizeHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func convertToViewCoordinates(_ rect: CGRect, localHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x - screenFrame.minX,
            y: localHeight - (rect.origin.y - screenFrame.minY) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func convertToScreenCoordinates(_ rect: CGRect, localHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x + screenFrame.minX,
            y: screenFrame.minY + (localHeight - rect.origin.y - rect.height),
            width: rect.width,
            height: rect.height
        ).standardized
    }

    private func setCursor(_ cursor: CursorKind) {
        guard cursor != activeCursor else { return }
        activeCursor = cursor
        cursor.nsCursor.set()
    }

    private enum DragInteraction {
        case move(startRect: CGRect)
        case resize(handle: ResizeHandle, startRect: CGRect)
    }

    private enum ResizeHandle: CaseIterable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left

        var affectsLeft: Bool {
            self == .topLeft || self == .left || self == .bottomLeft
        }

        var affectsRight: Bool {
            self == .topRight || self == .right || self == .bottomRight
        }

        var affectsTop: Bool {
            self == .topLeft || self == .top || self == .topRight
        }

        var affectsBottom: Bool {
            self == .bottomLeft || self == .bottom || self == .bottomRight
        }
    }

    private enum CursorKind: Equatable {
        case arrow
        case pointingHand
        case crosshair
        case closedHand
        case resizeHorizontal
        case resizeVertical

        var nsCursor: NSCursor {
            switch self {
            case .arrow:
                return .arrow
            case .pointingHand:
                return .pointingHand
            case .crosshair:
                return .crosshair
            case .closedHand:
                return .closedHand
            case .resizeHorizontal:
                return .resizeLeftRight
            case .resizeVertical:
                return .resizeUpDown
            }
        }
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
