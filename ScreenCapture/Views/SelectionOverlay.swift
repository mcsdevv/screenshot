import SwiftUI
import AppKit

struct SelectionOverlay: View {
    let onSelection: (CGRect) -> Void
    let onCancel: () -> Void
    var screenFrame: CGRect?

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isSelecting = false
    @State private var mousePosition: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()

                if let start = startPoint, let current = currentPoint {
                    SelectionRectangle(start: start, end: current, geometry: geometry)
                }

                SelectionCrosshairs(position: mousePosition, geometry: geometry)

                SelectionInfoPanel(position: mousePosition, selection: currentSelectionRect)
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
        let frame = screenFrame ?? NSScreen.main?.frame ?? CGRect(origin: .zero, size: geometry.size)

        return CGRect(
            x: frame.minX + rect.origin.x,
            y: frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

struct SelectionRectangle: View {
    let start: CGPoint
    let end: CGPoint
    let geometry: GeometryProxy

    private var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var body: some View {
        ZStack {
            DimmingOverlay(rect: rect, size: geometry.size)

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .background(Color.clear)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)

            ResizeHandles(rect: rect)

            DimensionsBadge(rect: rect)
        }
    }
}

struct DimmingOverlay: View {
    let rect: CGRect
    let size: CGSize
    var dimmingOpacity: Double = 0.5

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: canvasSize))

            var cutout = Path()
            cutout.addRect(rect)

            context.fill(path, with: .color(.black.opacity(dimmingOpacity)))
            context.blendMode = .destinationOut
            context.fill(cutout, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

struct ResizeHandles: View {
    let rect: CGRect
    private let handleSize: CGFloat = 8

    var body: some View {
        ForEach(HandlePosition.allCases, id: \.self) { position in
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.3), radius: 1)
                .position(handlePoint(for: position))
        }
    }

    private func handlePoint(for position: HandlePosition) -> CGPoint {
        switch position {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }
}

struct DimensionsBadge: View {
    let rect: CGRect

    var body: some View {
        Text("\(Int(rect.width)) x \(Int(rect.height))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .position(x: rect.midX, y: rect.minY - 20)
    }
}

struct SelectionCrosshairs: View {
    let position: CGPoint
    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: position.x, y: 0))
                path.addLine(to: CGPoint(x: position.x, y: geometry.size.height))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)

            Path { path in
                path.move(to: CGPoint(x: 0, y: position.y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: position.y))
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct SelectionInfoPanel: View {
    let position: CGPoint
    let selection: CGRect?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 12))
                Text("\(Int(position.x)), \(Int(position.y))")
                    .font(.system(size: 11, design: .monospaced))
            }

            if let rect = selection {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle")
                        .font(.system(size: 12))
                    Text("\(Int(rect.width)) x \(Int(rect.height))")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .foregroundColor(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.75)))
        .position(x: position.x + 80, y: position.y + 50)
    }
}
