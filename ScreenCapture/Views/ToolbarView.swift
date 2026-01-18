import SwiftUI

struct ToolbarView: View {
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    @Binding var isFilled: Bool

    @State private var isExpanded = true
    @State private var showColorPicker = false
    @State private var showStrokeOptions = false

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                expandedToolbar
            } else {
                collapsedToolbar
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private var expandedToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { withAnimation { isExpanded = false } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)

            Divider()
                .frame(height: 28)

            toolButtons

            Divider()
                .frame(height: 28)

            colorButton

            strokeButton

            if selectedTool == .rectangleOutline || selectedTool == .rectangleSolid || selectedTool == .circleOutline {
                fillToggle
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var collapsedToolbar: some View {
        Button(action: { withAnimation { isExpanded = true } }) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 40)
    }

    private var toolButtons: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases.prefix(10), id: \.self) { tool in
                ToolbarButton(
                    icon: tool.icon,
                    isSelected: selectedTool == tool,
                    tooltip: tool.rawValue
                ) {
                    selectedTool = tool
                }
            }
        }
    }

    private var colorButton: some View {
        Button(action: { showColorPicker.toggle() }) {
            Circle()
                .fill(selectedColor)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPicker) {
            ColorPickerView(selectedColor: $selectedColor, colors: Color.annotationColors)
        }
    }

    private var strokeButton: some View {
        Button(action: { showStrokeOptions.toggle() }) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 20, height: strokeWidth.clamped(to: 1...6))
                    .foregroundColor(.primary)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showStrokeOptions) {
            StrokeOptionsView(strokeWidth: $strokeWidth)
        }
    }

    private var fillToggle: some View {
        Button(action: { isFilled.toggle() }) {
            Image(systemName: isFilled ? "rectangle.fill" : "rectangle")
                .font(.system(size: 14))
                .foregroundColor(isFilled ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
    }
}

struct ToolbarButton: View {
    let icon: String
    let isSelected: Bool
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : (isHovered ? .primary : .secondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

struct StrokeOptionsView: View {
    @Binding var strokeWidth: CGFloat
    @State private var hoveredWidth: CGFloat?

    let widths: [CGFloat] = [1, 2, 3, 5, 8, 12]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(widths, id: \.self) { width in
                Button(action: { strokeWidth = width }) {
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 40, height: width)
                            .foregroundColor(.primary)

                        Spacer()

                        if strokeWidth == width {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredWidth == width ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredWidth = hovering ? width : nil
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 120)
    }
}

struct FloatingToolbar: View {
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    @Binding var isFilled: Bool

    let onUndo: () -> Void
    let onRedo: () -> Void
    let canUndo: Bool
    let canRedo: Bool

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(AnnotationTool.allCases.prefix(6), id: \.self) { tool in
                    FloatingToolButton(
                        icon: tool.icon,
                        isSelected: selectedTool == tool
                    ) {
                        selectedTool = tool
                    }
                }
            }

            Divider()
                .frame(width: 28)

            VStack(spacing: 4) {
                ForEach(AnnotationTool.allCases.dropFirst(6).prefix(4), id: \.self) { tool in
                    FloatingToolButton(
                        icon: tool.icon,
                        isSelected: selectedTool == tool
                    ) {
                        selectedTool = tool
                    }
                }
            }

            Divider()
                .frame(width: 28)

            Circle()
                .fill(selectedColor)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))

            Divider()
                .frame(width: 28)

            FloatingToolButton(icon: "arrow.uturn.backward", isSelected: false) {
                onUndo()
            }
            .disabled(!canUndo)
            .opacity(canUndo ? 1 : 0.4)

            FloatingToolButton(icon: "arrow.uturn.forward", isSelected: false) {
                onRedo()
            }
            .disabled(!canRedo)
            .opacity(canRedo ? 1 : 0.4)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct FloatingToolButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : (isHovered ? .primary : .secondary))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
