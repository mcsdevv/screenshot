import SwiftUI

// MARK: - Layer Panel View

struct LayerPanelView: View {
    @Bindable var state: AnnotationState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Layers")
                    .font(DSTypography.labelMedium)
                    .foregroundColor(.dsTextPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.dsTextTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(Color.dsBackgroundElevated)

            DSDivider()

            // Layer list
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Reversed to show top layers first (newest on top visually)
                    ForEach(state.annotations.reversed()) { annotation in
                        LayerRowView(
                            annotation: annotation,
                            isSelected: annotation.id == state.selectedAnnotationId,
                            isVisible: state.isAnnotationVisible(annotation.id),
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
                            } : nil
                        )
                    }
                    .onMove { from, to in
                        // Convert indices since we're showing reversed
                        let count = state.annotations.count
                        let fromIndex = count - 1 - from.first!
                        let toIndex = count - 1 - (to > from.first! ? to - 1 : to)
                        state.moveAnnotation(id: state.annotations[fromIndex].id, toIndex: toIndex)
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
            .frame(maxHeight: .infinity)

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
        .frame(width: 200)
        .background(Color.dsBackground)
        .overlay(
            Rectangle()
                .fill(Color.dsBorder)
                .frame(width: 1),
            alignment: .leading
        )
    }
}

// MARK: - Layer Row View

struct LayerRowView: View {
    let annotation: Annotation
    let isSelected: Bool
    let isVisible: Bool
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void
    var onUpdateStepNumber: ((Int) -> Void)? = nil
    var onToggleLock: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isEditingNumber = false
    @State private var editedNumber: String = ""

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
                return "#\(num)" + (annotation.isNumberLocked ? " 🔒" : "")
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
        HStack(spacing: DSSpacing.xs) {
            // Creation order number
            Text("#\(annotation.creationOrder)")
                .font(DSTypography.monoSmall)
                .foregroundColor(.dsTextTertiary)
                .frame(width: 24)

            // Type icon with color
            Image(systemName: typeIcon)
                .font(.system(size: 11))
                .foregroundColor(annotation.swiftUIColor)
                .frame(width: 16)

            // Type name and property
            VStack(alignment: .leading, spacing: 1) {
                Text(typeName)
                    .font(DSTypography.labelSmall)
                    .foregroundColor(isVisible ? .dsTextPrimary : .dsTextTertiary)

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

            Spacer()

            // Action buttons (shown on hover or selection)
            if isHovered || isSelected {
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
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.xs)
                .fill(
                    isSelected ? Color.dsAccent.opacity(0.15) :
                    (isHovered ? Color.white.opacity(0.05) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xs)
                .strokeBorder(
                    isSelected ? Color.dsAccent.opacity(0.3) : Color.clear,
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
        .opacity(isVisible ? 1 : 0.5)
    }
}
