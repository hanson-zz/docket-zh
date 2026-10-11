import SwiftUI

/// An eyedropper and the last colours it picked.
///
/// Four squares: the three most recent colours and the dropper itself. A
/// swatch copies its HEX; the dropper opens the system loupe, and whatever it
/// picks is copied straight away, because copying is why anybody picks a
/// colour off the screen.
struct ColorPickerTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var recent: [ColorCode] {
        if context.isPreview { return ColorPicking.samples }
        return ColorPicking.recent(instance)
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) {
                    grid(cell: 18)
                    Text(recent.first?.hex ?? "取色")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: 10) {
                    grid(cell: 20)
                    TileReading(value: recent.first?.hex ?? "取色",
                                caption: "取色器", valueSize: 14)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func grid(cell: CGFloat) -> some View {
        let gap: CGFloat = 2
        let colors = Array(recent.prefix(3))
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                swatch(colors.count > 0 ? colors[0] : nil, cell: cell, corner: .topLeading)
                swatch(colors.count > 1 ? colors[1] : nil, cell: cell, corner: .topTrailing)
            }
            HStack(spacing: gap) {
                swatch(colors.count > 2 ? colors[2] : nil, cell: cell, corner: .bottomLeading)
                dropper(cell: cell)
            }
        }
        .clipShape(.rect(cornerRadius: (cell * 2 + gap) * 0.26, style: .continuous))
    }

    private func swatch(_ color: ColorCode?, cell: CGFloat, corner: UnitPoint) -> some View {
        Button {
            guard !context.isPreview, let color else { return }
            ColorSampling.copy(color.hex)
        } label: {
            Rectangle()
                .fill(color.map(\.swiftUIColor) ?? WidgetStyle.primary.opacity(0.07))
                .frame(width: cell, height: cell)
        }
        .buttonStyle(.plain)
        .disabled(color == nil)
        .accessibilityLabel(color.map { "拷贝 \($0.hex)" } ?? "空")
    }

    private func dropper(cell: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            ColorPicking.pick(into: instance)
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: cell * 0.5, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .frame(width: cell, height: cell)
                .background(WidgetStyle.primary.opacity(0.12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("从屏幕取色")
    }
}

/// The picker's recent colours, kept as HEX strings in the widget's config.
///
/// Under a key the catalog does not default, so the Widgets tab does not
/// offer them as a text field.
@MainActor
enum ColorPicking {
    static let key = "recent"
    static let limit = 12

    static let samples: [ColorCode] = ["#FF453A", "#0A84FF", "#FFD60A", "#30D158"]
        .compactMap { ColorCode(hex: $0) }

    static func recent(_ instance: WidgetInstance) -> [ColorCode] {
        instance.config.strings(key).compactMap { ColorCode(hex: $0) }
    }

    /// Opens the loupe; the colour picked is copied and remembered.
    static func pick(into instance: WidgetInstance) {
        ColorSampling.sample { code in
            ColorSampling.copy(code.hex)
            remember(code, in: instance)
        }
    }

    static func remember(_ code: ColorCode, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { config in
            let list = RecentList.inserting(code.hex, into: config.strings(key), limit: limit)
            config.set(key, .list(list.map { .string($0) }))
        }
    }
}

extension ColorCode {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
