import SwiftUI
import AppKit

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    let colors: [Color]

    @State private var showCustomPicker = false

    private let columns = [
        GridItem(.adaptive(minimum: 28, maximum: 32), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    ColorSwatch(
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }

            Divider()

            Button(action: { showCustomPicker = true }) {
                HStack {
                    Image(systemName: "eyedropper")
                    Text("Custom Color")
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 180)
        .sheet(isPresented: $showCustomPicker) {
            CustomColorPicker(selectedColor: $selectedColor)
        }
    }
}

struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)

                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(color == .white ? .black : .white)
                }

                Circle()
                    .stroke(Color.primary.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CustomColorPicker: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var hexValue: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Color")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(spacing: 12) {
                    ColorGradientPicker(hue: $hue, saturation: $saturation, brightness: $brightness)
                        .frame(width: 200, height: 200)

                    HueSlider(hue: $hue)
                        .frame(width: 200, height: 20)
                }

                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(currentColor)
                        .frame(width: 80, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        ColorSlider(label: "H", value: $hue, range: 0...1, color: .clear)
                        ColorSlider(label: "S", value: $saturation, range: 0...1, color: currentColor)
                        ColorSlider(label: "B", value: $brightness, range: 0...1, color: currentColor)
                    }

                    HStack {
                        Text("#")
                            .foregroundColor(.secondary)
                        TextField("", text: $hexValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: hexValue) { _, newValue in
                                updateFromHex(newValue)
                            }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    selectedColor = currentColor
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            initializeFromColor()
        }
    }

    private var currentColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func initializeFromColor() {
        let nsColor = NSColor(selectedColor)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)

        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        updateHexValue()
    }

    private func updateHexValue() {
        let nsColor = NSColor(currentColor)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        hexValue = String(format: "%02X%02X%02X", r, g, b)
    }

    private func updateFromHex(_ hex: String) {
        guard hex.count == 6 else { return }

        var hexInt: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&hexInt)

        let r = Double((hexInt >> 16) & 0xFF) / 255
        let g = Double((hexInt >> 8) & 0xFF) / 255
        let b = Double(hexInt & 0xFF) / 255

        let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var br: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &br, alpha: nil)

        hue = Double(h)
        saturation = Double(s)
        brightness = Double(br)
    }
}

struct ColorGradientPicker: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(
                        x: saturation * geometry.size.width,
                        y: (1 - brightness) * geometry.size.height
                    )
            }
            .cornerRadius(8)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(value.location.x / geometry.size.width, 0), 1)
                        brightness = 1 - min(max(value.location.y / geometry.size.height, 0), 1)
                    }
            )
        }
    }
}

struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                LinearGradient(
                    gradient: Gradient(colors: (0...10).map { Color(hue: Double($0) / 10, saturation: 1, brightness: 1) }),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .cornerRadius(10)

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: hue * (geometry.size.width - 16))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
            )
        }
    }
}

struct ColorSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Slider(value: $value, in: range)
                .accentColor(color)

            Text("\(Int(value * 100))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30)
        }
    }
}

struct RecentColorsView: View {
    let colors: [Color]
    let onSelect: (Color) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(colors.prefix(8), id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .onTapGesture {
                            onSelect(color)
                        }
                }
            }
        }
    }
}
