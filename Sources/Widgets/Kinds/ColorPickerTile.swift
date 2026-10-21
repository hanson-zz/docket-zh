import SwiftUI

/// 取色器：只管“最近颜色”。上面一排色板，点一下拷贝 HEX；下面是最新一个颜色的
/// HEX，右边一个吸管按钮顺手再取一个。
///
/// 颜色记在共享的取色历史里（`ColorHistory`），快速开关里的取色按钮取到的也在这里。
/// 以前记在卡片自己配置里的颜色接在后面，升级后一个不少。竖排扩展栏的窄卡片照旧
/// 是 2×2：三个最近颜色加吸管。
struct ColorPickerTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 只为了在别处（快速开关、面板）取到新颜色时重画。
    @AppStorage(ColorHistory.defaultsKey) private var stored = ""
    @AppStorage(ColorPalette.defaultsKey) private var palette = ""
    @AppStorage(ColorHistory.legacyRetiredKey) private var retired = false
    @State private var copied: String?

    /// 卡片上那排色块：设了「显示我的色板」且色板里有颜色时是色板，否则是最近。
    private var recent: [ColorCode] {
        if context.isPreview { return ColorPicking.samples }
        if instance.config.bool(ColorPalette.showKey) {
            let saved = ColorPalette.colors(palette)
            if !saved.isEmpty { return saved }
        }
        return ColorPicking.recent(instance, stored: stored, retired: retired)
    }

    private var style: ColorCopyStyle { ColorPicking.style(instance) }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) {
                    grid(cell: 18)
                    Text(recent.first.map { style.hexStyle.apply($0.hex) } ?? tr("取色"))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                row
            }
        }
        // 快速开关里的取色按钮没有卡片配置可读，按这张卡片设的格式拷贝。
        .onAppear { if !context.isPreview { style.save() } }
        .onChange(of: style) { _, next in if !context.isPreview { next.save() } }
    }

    // MARK: 横排：一排色板

    private static let swatchCount = 6

    private var row: some View {
        let colors = Array(recent.prefix(Self.swatchCount))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<Self.swatchCount, id: \.self) { index in
                    let color = index < colors.count ? colors[index] : nil
                    swatch(color, width: 19, height: 20, corner: 5, ring: index == 0 && color != nil)
                }
            }
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(recent.first.map { style.hexStyle.apply($0.hex) } ?? tr("还没有取色"))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(copied.map { tr("已拷贝 \($0)") } ?? tr("点色块拷贝"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                TileGlyph(symbol: "eyedropper", size: 9,
                          action: context.isPreview ? nil : { ColorPicking.pick(into: instance) })
                    .help(tr("从屏幕取色"))
                    .accessibilityLabel(tr("从屏幕取色"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 竖排：2×2

    private func grid(cell: CGFloat) -> some View {
        let gap: CGFloat = 2
        let colors = Array(recent.prefix(3))
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                swatch(colors.count > 0 ? colors[0] : nil, width: cell, height: cell, corner: 0)
                swatch(colors.count > 1 ? colors[1] : nil, width: cell, height: cell, corner: 0)
            }
            HStack(spacing: gap) {
                swatch(colors.count > 2 ? colors[2] : nil, width: cell, height: cell, corner: 0)
                dropper(cell: cell)
            }
        }
        .clipShape(.rect(cornerRadius: (cell * 2 + gap) * 0.26, style: .continuous))
    }

    private func swatch(_ color: ColorCode?, width: CGFloat, height: CGFloat, corner: CGFloat,
                        ring: Bool = false) -> some View {
        Button {
            guard !context.isPreview, let color else { return }
            let text = style.text(color)
            ColorSampling.copy(text)
            copied = style.format == .hex ? text : style.format.title
        } label: {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.map(\.swiftUIColor) ?? WidgetStyle.primary.opacity(0.07))
                .overlay {
                    if ring {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(color == nil)
        .help(color?.hex ?? "")
        .accessibilityLabel(color.map { tr("拷贝 \($0.hex)") } ?? tr("空"))
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
        .accessibilityLabel(tr("从屏幕取色"))
    }
}

/// 取色器卡片、面板和快速开关共用的取色历史（`ColorHistory`），加上每张卡片配置
/// 里以前存的旧颜色（`recent`，只读不写；删过或清空过一次后不再读）；收藏的
/// 「我的色板」（`ColorPalette`）也是共享的一份。
@MainActor
enum ColorPicking {
    static let samples: [ColorCode] = ["#FF453A", "#FFD60A", "#30D158", "#BF5AF2", "#FF9F0A", "#64D2FF"]
        .compactMap { ColorCode(hex: $0) }

    static var legacyRetired: Bool { UserDefaults.standard.bool(forKey: ColorHistory.legacyRetiredKey) }

    static func recent(_ instance: WidgetInstance, stored: String = ColorHistory.stored(),
                       retired: Bool? = nil) -> [ColorCode] {
        ColorHistory.shown(shared: stored, legacy: instance.config.strings(ColorHistory.legacyKey),
                           retired: retired ?? legacyRetired)
    }

    /// 这张卡片设的拷贝格式。
    static func style(_ instance: WidgetInstance) -> ColorCopyStyle {
        ColorCopyStyle(instance.config)
    }

    /// Opens the loupe; the colour picked is copied in the card's format and remembered.
    static func pick(into instance: WidgetInstance) {
        let copyStyle = ColorCopyStyle(instance.config)
        copyStyle.save()
        ColorSampling.sample { code in
            ColorSampling.copy(copyStyle.text(code))
            remember(code, in: instance)
        }
    }

    /// 记进共享历史；这张卡片以前的旧颜色一起并进去。
    static func remember(_ code: ColorCode, in instance: WidgetInstance) {
        ColorHistory.record(code, legacy: legacy(instance))
    }

    private static func legacy(_ instance: WidgetInstance) -> [String] {
        legacyRetired ? [] : instance.config.strings(ColorHistory.legacyKey)
    }

    /// 从最近里删一个。旧颜色先并进共享历史，再记下旧颜色已退休，删掉的不会冒回来。
    static func forget(_ code: ColorCode, in instance: WidgetInstance) {
        let defaults = UserDefaults.standard
        defaults.set(ColorHistory.removing(code, from: ColorHistory.stored(in: defaults),
                                           legacy: legacy(instance)),
                     forKey: ColorHistory.defaultsKey)
        defaults.set(true, forKey: ColorHistory.legacyRetiredKey)
    }

    /// 清空最近。我的色板不动。
    static func clearRecent() {
        let defaults = UserDefaults.standard
        defaults.set("", forKey: ColorHistory.defaultsKey)
        defaults.set(true, forKey: ColorHistory.legacyRetiredKey)
    }

    static func togglePalette(_ code: ColorCode) {
        let defaults = UserDefaults.standard
        defaults.set(ColorPalette.toggling(code, in: defaults.string(forKey: ColorPalette.defaultsKey) ?? ""),
                     forKey: ColorPalette.defaultsKey)
    }
}

extension ColorCode {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
