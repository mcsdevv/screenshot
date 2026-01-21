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

    // Drag state tracking - simplified for immediate-move approach
    @State private var draggedAnnotationId: UUID?
    @State private var isDragTargeted = false

    // Track which annotation is currently being renamed (nil = none)
    @State private var editingNameAnnotationId: UUID?

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
                            isDragActive: draggedAnnotationId != nil,
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
                                draggedAnnotationId = nil
                            },
                            editingNameAnnotationId: $editingNameAnnotationId
                        )
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            targetId: annotation.id,
                            draggingId: $draggedAnnotationId,
                            annotations: reversedAnnotations,
                            moveAction: { fromId, toId in
                                performMove(fromId: fromId, toTargetId: toId)
                            }
                        ))
                    }

                    // Bottom drop zone for dropping below last item
                    if !reversedAnnotations.isEmpty && draggedAnnotationId != nil {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], delegate: BottomReorderDropDelegate(
                                lastAnnotationId: reversedAnnotations.last?.id,
                                draggingId: $draggedAnnotationId,
                                moveToBottom: { fromId in
                                    performMoveToBottom(fromId: fromId)
                                }
                            ))
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
        // Background tap gesture to dismiss editing when clicking empty areas
        .background {
            if editingNameAnnotationId != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingNameAnnotationId = nil
                    }
            }
        }
    }

    /// Performs move when dragging over a target row - moves immediately for responsive feedback
    private func performMove(fromId: UUID, toTargetId: UUID) {
        // Find indices in the original (non-reversed) array
        guard let fromIndex = state.annotations.firstIndex(where: { $0.id == fromId }),
              let targetIndex = state.annotations.firstIndex(where: { $0.id == toTargetId }) else {
            return
        }

        // In reversed display, moving to a row means taking its position
        // The target row shifts to accommodate the dragged item
        var newIndex = targetIndex

        // Adjust for removal of dragged item if it's before the target
        if fromIndex < newIndex {
            newIndex -= 1
        }

        // Clamp to valid range
        newIndex = max(0, min(newIndex, state.annotations.count - 1))

        if newIndex != fromIndex {
            withAnimation(DSAnimation.springQuick) {
                state.moveAnnotation(id: fromId, toIndex: newIndex)
            }
        }
    }

    /// Move item to the bottom (index 0 in original array)
    private func performMoveToBottom(fromId: UUID) {
        guard let fromIndex = state.annotations.firstIndex(where: { $0.id == fromId }) else {
            return
        }

        if fromIndex != 0 {
            withAnimation(DSAnimation.springQuick) {
                state.moveAnnotation(id: fromId, toIndex: 0)
            }
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
    let isDragActive: Bool  // True when any drag is in progress
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
    @Binding var editingNameAnnotationId: UUID?

    @State private var isHovered = false
    @State private var isEditingNumber = false
    @State private var editedNumber: String = ""
    @State private var editedName: String = ""
    @State private var shouldSaveOnEditEnd: Bool = true
    @State private var showColorPicker = false
    @FocusState private var isNameFieldFocused: Bool

    /// Whether this row is currently editing its name (derived from parent binding)
    private var isEditingName: Bool {
        editingNameAnnotationId == annotation.id
    }

    /// Commits the current name edit and exits editing mode
    /// Note: The actual save happens in onChange when editingNameAnnotationId changes
    private func commitNameEdit() {
        guard isEditingName else { return }
        // Setting this to nil triggers onChange which saves the edit
        editingNameAnnotationId = nil
        isNameFieldFocused = false
    }

    /// Cancels editing without saving
    private func cancelNameEdit() {
        shouldSaveOnEditEnd = false
        editingNameAnnotationId = nil
        isNameFieldFocused = false
    }

    /// Starts editing the name field
    private func startNameEditing() {
        editedName = annotation.name ?? typeName
        shouldSaveOnEditEnd = true
        editingNameAnnotationId = annotation.id
        // Delay focus slightly to ensure TextField is rendered
        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

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
        guard let inputRGB = Color.sRGBComponents(for: color) else {
            return "Gray"
        }

        var closestName = "Gray"
        var minDistance = Double.infinity

        for preset in Color.annotationColorPresets {
            let dr = inputRGB.r - preset.rgb.r
            let dg = inputRGB.g - preset.rgb.g
            let db = inputRGB.b - preset.rgb.b
            let distance = (dr * dr) + (dg * dg) + (db * db)

            if distance < minDistance {
                minDistance = distance
                closestName = preset.name
            }
        }

        return closestName
    }

    var body: some View {
        let showActionButtons = isHovered || isSelected
        let showVisibilityToggle = showActionButtons || !isVisible

        // Main row content (drop indicators removed - immediate move provides visual feedback)
        mainRowContent(showActionButtons: showActionButtons, showVisibilityToggle: showVisibilityToggle)
            .onDrag {
                onDragStarted?()
                return NSItemProvider(object: annotation.id.uuidString as NSString)
            } preview: {
                // Empty preview prevents confusing "return to origin" animation
                Color.clear.frame(width: 1, height: 1)
            }
            .contextMenu { contextMenuContent }
            .onChange(of: editingNameAnnotationId) { oldValue, newValue in
                // If we were editing this annotation and now we're not, save the edit
                if oldValue == annotation.id && newValue != annotation.id {
                    if shouldSaveOnEditEnd {
                        onRename?(editedName.isEmpty ? nil : editedName)
                    }
                    isNameFieldFocused = false
                    shouldSaveOnEditEnd = true // Reset for next time
                }
            }
    }

    // MARK: - Extracted Subviews

    @ViewBuilder
    private func mainRowContent(showActionButtons: Bool, showVisibilityToggle: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            selectableArea
            actionButtons(showActionButtons: showActionButtons, showVisibilityToggle: showVisibilityToggle)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(rowBackground)
        .overlay(rowBorder)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !isHovered {
                    withAnimation(DSAnimation.quick) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(DSAnimation.quick) {
                    isHovered = false
                }
            }
        }
        .opacity(isDragging ? 0.5 : (isVisible ? 1 : 0.5))
    }

    private var selectableArea: some View {
        HStack(spacing: DSSpacing.xs) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.dsTextTertiary.opacity(0.5))
                .frame(width: 12)

            // Layer position number
            Text("#\(displayNumber)")
                .font(DSTypography.monoSmall)
                .foregroundColor(.dsTextTertiary)
                .frame(width: 24)

            // Type icon with color
            typeIconView

            // Type name and property
            namePropertySection

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Clear editing state if any layer is being edited (not just this one)
            if editingNameAnnotationId != nil {
                editingNameAnnotationId = nil
            }
            onSelect()
        }
    }

    private var typeIconView: some View {
        Group {
            if annotation.type != .blur {
                // Use button + popover instead of native ColorPicker to avoid NSColorWell crash
                Button(action: { showColorPicker.toggle() }) {
                    Circle()
                        .fill(annotation.swiftUIColor)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDragActive)
                .popover(isPresented: $showColorPicker) {
                    ColorPickerView(
                        selectedColor: Binding(
                            get: { annotation.swiftUIColor },
                            set: { onColorChange?($0) }
                        ),
                        colors: Color.annotationColors
                    )
                }
            } else {
                Image(systemName: typeIcon)
                    .font(.system(size: 11))
                    .foregroundColor(.dsTextTertiary)
            }
        }
        .frame(width: 16, height: 16, alignment: .center)
    }

    private var namePropertySection: some View {
        VStack(alignment: .leading, spacing: 1) {
            nameField
            propertySummaryField
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            TextField("", text: $editedName)
                .font(DSTypography.labelSmall)
                .textFieldStyle(.plain)
                .frame(height: DSRowHeight.labelSmall)
                .focused($isNameFieldFocused)
                .onSubmit { commitNameEdit() }
                .onExitCommand { cancelNameEdit() }
                .onChange(of: isNameFieldFocused) { _, isFocused in
                    if !isFocused && isEditingName {
                        commitNameEdit()
                    }
                }
        } else {
            Text(annotation.name ?? typeName)
                .font(DSTypography.labelSmall)
                .foregroundColor(isVisible ? .dsTextPrimary : .dsTextTertiary)
                .frame(height: DSRowHeight.labelSmall)
                .onTapGesture(count: 2) { startNameEditing() }
        }
    }

    @ViewBuilder
    private var propertySummaryField: some View {
        if !propertySummary.isEmpty {
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

    @ViewBuilder
    private func actionButtons(showActionButtons: Bool, showVisibilityToggle: Bool) -> some View {
        HStack(spacing: 0) {
            // Move up button
            Button(action: { onBringForward?() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .help("Move up")
            .opacity(showActionButtons ? 1 : 0)
            .allowsHitTesting(showActionButtons)
            .accessibilityHidden(!showActionButtons)

            // Move down button
            Button(action: { onSendBackward?() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .help("Move down")
            .opacity(showActionButtons ? 1 : 0)
            .allowsHitTesting(showActionButtons)
            .accessibilityHidden(!showActionButtons)

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
                .opacity(showActionButtons ? 1 : 0)
                .allowsHitTesting(showActionButtons)
                .accessibilityHidden(!showActionButtons)
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
            .opacity(showVisibilityToggle ? 1 : 0)
            .allowsHitTesting(showVisibilityToggle)
            .accessibilityHidden(!showVisibilityToggle)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.dsTextTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .help("Delete layer")
            .opacity(showActionButtons ? 1 : 0)
            .allowsHitTesting(showActionButtons)
            .accessibilityHidden(!showActionButtons)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DSRadius.xs)
            .fill(
                isDragging ? Color.dsAccent.opacity(0.25) :
                (isSelected ? Color.dsAccent.opacity(0.15) :
                (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DSRadius.xs)
            .strokeBorder(
                isDragging ? Color.dsAccent.opacity(0.5) :
                (isSelected ? Color.dsAccent.opacity(0.3) : Color.clear),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private var contextMenuContent: some View {
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

        Button { startNameEditing() } label: {
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

// MARK: - Reorder Drop Delegate

/// Handles drops on layer rows - moves items immediately when entering a new row
struct ReorderDropDelegate: DropDelegate {
    let targetId: UUID
    @Binding var draggingId: UUID?
    let annotations: [Annotation]
    let moveAction: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingId, dragId != targetId else { return }
        // Move immediately when entering a new row for responsive feedback
        moveAction(dragId, targetId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

// MARK: - Bottom Reorder Drop Delegate

/// Handles drops on the bottom zone to move items below the last row
struct BottomReorderDropDelegate: DropDelegate {
    let lastAnnotationId: UUID?
    @Binding var draggingId: UUID?
    let moveToBottom: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingId, dragId != lastAnnotationId else { return }
        moveToBottom(dragId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}
