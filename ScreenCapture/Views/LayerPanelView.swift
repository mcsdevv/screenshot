import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Position Enum

enum LayerDropPosition {
    case above, below
}

// MARK: - Layer Panel View

struct LayerPanelView: View {
    @Bindable var state: AnnotationState
    let onClose: () -> Void

    // Drag state tracking
    @State private var draggedAnnotationId: UUID?
    @State private var dropTargetId: UUID?
    @State private var dropPosition: LayerDropPosition = .above
    @State private var isDragTargeted = false

    // Get reversed annotations for display (top layers first)
    private var reversedAnnotations: [Annotation] {
        Array(state.annotations.reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Layer list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Reversed to show top layers first (newest on top visually)
                    ForEach(Array(reversedAnnotations.enumerated()), id: \.element.id) { displayIndex, annotation in
                        DraggableLayerRow(
                            annotation: annotation,
                            displayNumber: displayIndex + 1,
                            isSelected: annotation.id == state.selectedAnnotationId,
                            isVisible: state.isAnnotationVisible(annotation.id),
                            isDragging: draggedAnnotationId == annotation.id,
                            isDropTarget: dropTargetId == annotation.id,
                            dropPosition: dropPosition,
                            onSelect: {
                                state.selectedAnnotationId = annotation.id
                            },
                            onToggleVisibility: {
                                state.toggleAnnotationVisibility(id: annotation.id)
                            },
                            onDelete: {
                                state.deleteAnnotation(id: annotation.id, renumberSteps: true)
                            },
                            onUpdateStepNumber: annotation.type == .numberedStep ? { newNumber in
                                state.setStepNumber(id: annotation.id, number: newNumber)
                            } : nil,
                            onToggleLock: annotation.type == .numberedStep ? {
                                state.toggleStepNumberLock(id: annotation.id)
                            } : nil,
                            onBringToFront: {
                                state.bringToFront(id: annotation.id)
                            },
                            onSendToBack: {
                                state.sendToBack(id: annotation.id)
                            },
                            onBringForward: {
                                state.bringForward(id: annotation.id)
                            },
                            onSendBackward: {
                                state.sendBackward(id: annotation.id)
                            },
                            onDuplicate: {
                                if let newId = state.duplicateAnnotation(id: annotation.id) {
                                    state.selectedAnnotationId = newId
                                }
                            },
                            onColorChange: { newColor in
                                state.updateAnnotationColor(id: annotation.id, color: newColor)
                            },
                            onRename: { newName in
                                state.updateAnnotationName(id: annotation.id, name: newName)
                            },
                            onDragStarted: {
                                draggedAnnotationId = annotation.id
                            },
                            onDragEnded: {
                                // Perform the move if we have a valid drop target
                                if let draggedId = draggedAnnotationId,
                                   let targetId = dropTargetId,
                                   draggedId != targetId {
                                    performMove(draggedId: draggedId, targetId: targetId, position: dropPosition)
                                }
                                draggedAnnotationId = nil
                                dropTargetId = nil
                            },
                            onDropTargetChanged: { targetId, position in
                                dropTargetId = targetId
                                dropPosition = position
                            }
                        )
                    }
                }
                .padding(.bottom, DSSpacing.xs)
            }
            .frame(maxHeight: .infinity)
            .onDrop(of: [.text], isTargeted: $isDragTargeted) { _ in
                // Let row delegates handle actual drop behavior.
                false
            }
            .onChange(of: isDragTargeted) { _, isTargeted in
                if !isTargeted {
                    draggedAnnotationId = nil
                    dropTargetId = nil
                }
            }

            // Footer with renumber button (only show if there are numbered steps)
            if state.annotations.contains(where: { $0.type == .numberedStep }) {
                DSDivider()
                HStack {
                    Button(action: {
                        state.renumberSteps(force: true)
                    }) {
                        Text("Renumber All")
                            .font(DSTypography.labelSmall)
                            .foregroundColor(.dsTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(DSRadius.xs)

                    Spacer()
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(Color.dsBackgroundElevated)
            }
        }
        .frame(width: 280)
        .background(Color.dsBackground)
        .overlay(
            Rectangle()
                .fill(Color.dsBorder)
                .frame(width: 1),
            alignment: .leading
        )
    }

    /// Performs the move operation, accounting for reversed display order
    private func performMove(draggedId: UUID, targetId: UUID, position: LayerDropPosition) {
        // Find indices in the original (non-reversed) array
        guard let draggedIndex = state.annotations.firstIndex(where: { $0.id == draggedId }),
              let targetIndex = state.annotations.firstIndex(where: { $0.id == targetId }) else {
            return
        }

        // In the UI, we show reversed order (top = highest index in original array)
        // "above" in UI means higher z-order = higher index in original array
        // "below" in UI means lower z-order = lower index in original array

        var newIndex: Int
        if position == .above {
            // Moving above target in UI = moving to higher index in original array
            newIndex = targetIndex + 1
        } else {
            // Moving below target in UI = moving to lower index (or same position as target)
            newIndex = targetIndex
        }

        // Adjust for removal of dragged item if it's before the target
        if draggedIndex < newIndex {
            newIndex -= 1
        }

        // Clamp to valid range
        newIndex = max(0, min(newIndex, state.annotations.count - 1))

        if newIndex != draggedIndex {
            state.moveAnnotation(id: draggedId, toIndex: newIndex)
        }
    }
}

// MARK: - Draggable Layer Row

struct DraggableLayerRow: View {
    let annotation: Annotation
    let displayNumber: Int
    let isSelected: Bool
    let isVisible: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let dropPosition: LayerDropPosition
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void
    var onUpdateStepNumber: ((Int) -> Void)? = nil
    var onToggleLock: (() -> Void)? = nil
    var onBringToFront: (() -> Void)? = nil
    var onSendToBack: (() -> Void)? = nil
    var onBringForward: (() -> Void)? = nil
    var onSendBackward: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onColorChange: ((Color) -> Void)? = nil
    var onRename: ((String?) -> Void)? = nil
    var onDragStarted: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onDropTargetChanged: ((UUID?, LayerDropPosition) -> Void)? = nil

    @State private var isHovered = false
    @State private var isEditingNumber = false
    @State private var editedNumber: String = ""
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    private var typeIcon: String {
        switch annotation.type {
        case .rectangleOutline: return "rectangle"
        case .rectangleSolid: return "rectangle.fill"
        case .circleOutline: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "character"
        case .blur: return "aqi.medium"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .numberedStep: return "number"
        }
    }

    private var typeName: String {
        switch annotation.type {
        case .rectangleOutline: return "Rectangle"
        case .rectangleSolid: return "Filled Rect"
        case .circleOutline: return "Circle"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .blur: return "Blur"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlight"
        case .numberedStep: return "Step"
        }
    }

    private var propertySummary: String {
        switch annotation.type {
        case .text:
            let text = annotation.text ?? ""
            return text.count > 10 ? String(text.prefix(10)) + "..." : text
        case .numberedStep:
            if let num = annotation.stepNumber {
                return "#\(num)" + (annotation.isNumberLocked ? " [locked]" : "")
            }
            return ""
        default:
            return colorName(for: annotation.swiftUIColor)
        }
    }

    private func colorName(for color: Color) -> String {
        // Simple color name detection
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent

        if r > 0.8 && g < 0.3 && b < 0.3 { return "Red" }
        if r > 0.8 && g > 0.4 && g < 0.7 && b < 0.3 { return "Orange" }
        if r > 0.8 && g > 0.8 && b < 0.3 { return "Yellow" }
        if r < 0.3 && g > 0.6 && b < 0.3 { return "Green" }
        if r < 0.3 && g < 0.5 && b > 0.7 { return "Blue" }
        if r > 0.4 && g < 0.3 && b > 0.6 { return "Purple" }
        if r > 0.8 && g < 0.5 && b > 0.6 { return "Pink" }
        if r > 0.9 && g > 0.9 && b > 0.9 { return "White" }
        if r < 0.2 && g < 0.2 && b < 0.2 { return "Black" }
        return "Gray"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drop indicator above
            if isDropTarget && dropPosition == .above {
                DropIndicatorLine()
            }

            // Main row content
            HStack(spacing: DSSpacing.xs) {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary.opacity(0.5))
                    .frame(width: 12)

                // Layer position number (updates after reordering)
                Text("#\(displayNumber)")
                    .font(DSTypography.monoSmall)
                    .foregroundColor(.dsTextTertiary)
                    .frame(width: 24)

                // Type icon with color (color picker for non-blur annotations)
                // Use consistent container frame for all icon types to ensure alignment
                Group {
                    if annotation.type != .blur {
                        ColorPicker("", selection: Binding(
                            get: { annotation.swiftUIColor },
                            set: { newColor in onColorChange?(newColor) }
                        ))
                        .labelsHidden()
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: typeIcon)
                            .font(.system(size: 11))
                            .foregroundColor(.dsTextTertiary)
                    }
                }
                .frame(width: 16, height: 16, alignment: .center)

                // Type name and property
                VStack(alignment: .leading, spacing: 1) {
                    // Layer name (custom or type name)
                    if isEditingName {
                        TextField("", text: $editedName)
                            .font(DSTypography.labelSmall)
                            .textFieldStyle(.plain)
                            .frame(height: DSRowHeight.labelSmall)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                onRename?(editedName.isEmpty ? nil : editedName)
                                isEditingName = false
                            }
                            .onExitCommand {
                                isEditingName = false
                            }
                            .onChange(of: isNameFieldFocused) { _, isFocused in
                                if !isFocused && isEditingName {
                                    onRename?(editedName.isEmpty ? nil : editedName)
                                    isEditingName = false
                                }
                            }
                    } else {
                        Text(annotation.name ?? typeName)
                            .font(DSTypography.labelSmall)
                            .foregroundColor(isVisible ? .dsTextPrimary : .dsTextTertiary)
                            .frame(height: DSRowHeight.labelSmall)
                            .onTapGesture(count: 2) {
                                editedName = annotation.name ?? typeName
                                isEditingName = true
                                isNameFieldFocused = true
                            }
                    }

                    if !propertySummary.isEmpty {
                        // For numbered steps, allow editing
                        if annotation.type == .numberedStep, isEditingNumber {
                            TextField("", text: $editedNumber)
                                .font(DSTypography.monoSmall)
                                .foregroundColor(.dsTextSecondary)
                                .textFieldStyle(.plain)
                                .frame(width: 40)
                                .onSubmit {
                                    if let num = Int(editedNumber), num > 0 {
                                        onUpdateStepNumber?(num)
                                    }
                                    isEditingNumber = false
                                }
                        } else {
                            Text(propertySummary)
                                .font(DSTypography.monoSmall)
                                .foregroundColor(.dsTextSecondary)
                                .lineLimit(1)
                                .onTapGesture {
                                    if annotation.type == .numberedStep {
                                        editedNumber = "\(annotation.stepNumber ?? 1)"
                                        isEditingNumber = true
                                    }
                                }
                        }
                    }
                }
                .frame(minWidth: 80, alignment: .leading)

                Spacer()

                // Other action buttons (shown on hover or selection only)
                if isHovered || isSelected {
                    // Move up button (bring forward in z-order)
                    Button(action: { onBringForward?() }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                            .foregroundColor(.dsTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Move up")

                    // Move down button (send backward in z-order)
                    Button(action: { onSendBackward?() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.dsTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Move down")

                    // Lock toggle for numbered steps
                    if annotation.type == .numberedStep {
                        Button(action: { onToggleLock?() }) {
                            Image(systemName: annotation.isNumberLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 10))
                                .foregroundColor(annotation.isNumberLocked ? .dsAccent : .dsTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                        .help(annotation.isNumberLocked ? "Unlock number" : "Lock number")
                    }

                    // Visibility toggle
                    Button(action: onToggleVisibility) {
                        Image(systemName: isVisible ? "eye" : "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(isVisible ? .dsTextTertiary : .dsTextTertiary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(isVisible ? "Hide layer" : "Show layer")

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.dsTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Delete layer")
                }

                // Always show visibility icon for hidden layers (even when not hovered/selected)
                if !isVisible && !isHovered && !isSelected {
                    Button(action: onToggleVisibility) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(.dsTextTertiary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Show layer")
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.xs)
                    .fill(
                        isDragging ? Color.dsAccent.opacity(0.25) :
                        (isSelected ? Color.dsAccent.opacity(0.15) :
                        (isHovered ? Color.white.opacity(0.05) : Color.clear))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xs)
                    .strokeBorder(
                        isDragging ? Color.dsAccent.opacity(0.5) :
                        (isSelected ? Color.dsAccent.opacity(0.3) : Color.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }
            .onHover { hovering in
                withAnimation(DSAnimation.quick) {
                    isHovered = hovering
                }
            }
            .opacity(isDragging ? 0.5 : (isVisible ? 1 : 0.5))

            // Drop indicator below
            if isDropTarget && dropPosition == .below {
                DropIndicatorLine()
            }
        }
        .onDrag {
            onDragStarted?()
            return NSItemProvider(object: annotation.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: LayerDropDelegate(
            targetAnnotationId: annotation.id,
            onDropTargetChanged: onDropTargetChanged,
            onDragEnded: onDragEnded
        ))
        .contextMenu {
            Button {
                onBringToFront?()
            } label: {
                Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button {
                onBringForward?()
            } label: {
                Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled")
            }
            .keyboardShortcut("]", modifiers: .command)

            Button {
                onSendBackward?()
            } label: {
                Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled")
            }
            .keyboardShortcut("[", modifiers: .command)

            Button {
                onSendToBack?()
            } label: {
                Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button {
                onDuplicate?()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("d", modifiers: .command)

            Button {
                editedName = annotation.name ?? typeName
                isEditingName = true
                isNameFieldFocused = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Divider()

            Button {
                onToggleVisibility()
            } label: {
                Label(isVisible ? "Hide" : "Show", systemImage: isVisible ? "eye.slash" : "eye")
            }
        }
    }
}

// MARK: - Drop Indicator Line

struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.dsAccent)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.dsAccent)
                .frame(height: 2)
            Circle()
                .fill(Color.dsAccent)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 2)
    }
}

// MARK: - Layer Drop Delegate

struct LayerDropDelegate: DropDelegate {
    let targetAnnotationId: UUID
    var onDropTargetChanged: ((UUID?, LayerDropPosition) -> Void)?
    var onDragEnded: (() -> Void)?

    func dropEntered(info: DropInfo) {
        // Determine if we're dropping above or below based on position within the row
        let position: LayerDropPosition = info.location.y < 20 ? .above : .below
        onDropTargetChanged?(targetAnnotationId, position)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let position: LayerDropPosition = info.location.y < 20 ? .above : .below
        onDropTargetChanged?(targetAnnotationId, position)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Don't clear yet - let performDrop or another row handle it
    }

    func performDrop(info: DropInfo) -> Bool {
        onDragEnded?()
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        return true
    }
}
