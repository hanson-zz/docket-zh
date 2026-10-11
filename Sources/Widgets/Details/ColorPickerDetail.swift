import AppKit
import SwiftUI

/// The picked colour large, its three codes to copy, and the history.
struct ColorPickerDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var selected: ColorCode?
    @State private var copied: String?

    private var recent: [ColorCode] {
        context.isPreview ? ColorPicking.samples : ColorPicking.recent(instance)
    }

    private var shown: ColorCode? { selected ?? recent.first }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: shown.map(\.swiftUIColor) ?? .gray)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                hero
                if let shown {
                    VStack(spacing: 6) {
                        code("HEX", shown.hex)
                        code("RGB", shown.rgb)
                        code("HSL", shown.hsl)
                    }
                }
                history
                PanelButton(title: "从屏幕取色", symbol: "eyedropper", prominent: true) {
                    guard !context.isPreview else { return }
                    let item = instance
                    ColorSampling.sample { picked in
                        ColorSampling.copy(picked.hex)
                        ColorPicking.remember(picked, in: item)
                    }
                    selected = nil
                }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(shown.map(\.swiftUIColor) ?? Color.white.opacity(0.1))
                .frame(width: 56, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(shown?.hex ?? "还没有取色")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetStyle.primary)
                Text(copied.map { "已拷贝 \($0)" } ?? "点按下方的值即可拷贝")
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }

    private func code(_ label: String, _ value: String) -> some View {
        Button {
            guard !context.isPreview else { return }
            ColorSampling.copy(value)
            copied = label
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 34, alignment: .leading)
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: copied == label ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .glassPane(cornerRadius: 9)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var history: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, color in
                Button {
                    selected = color
                    copied = nil
                } label: {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.swiftUIColor)
                        .frame(height: 30)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.white.opacity(color == shown ? 0.9 : 0.15),
                                              lineWidth: color == shown ? 1.5 : 0.5)
                        }
                }
                .buttonStyle(.plain)
                .help(color.hex)
            }
        }
        .frame(height: 66, alignment: .top)
    }
}
