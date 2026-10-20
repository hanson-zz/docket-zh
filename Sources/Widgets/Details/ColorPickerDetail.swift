import AppKit
import SwiftUI

/// The picked colour large, its codes to copy, the palette and the history.
///
/// 从上到下：大色块和按「取色后拷贝」写出的值（星标收藏到我的色板）；四种写法
/// 各一格，点哪格拷哪种；取色后拷贝的格式（HEX / rgb() / hsl() / SwiftUI）和
/// HEX 写法（大写 / 小写 / 不带 #）；我的色板（不会被挤掉，最多 24 个）；最近
/// 12 个（右键拷贝、收藏、删除，右上角清空）；从屏幕取色。
///
/// 历史和卡片、快速开关里的取色按钮共用一份（`ColorHistory`），色板也是共享的
/// 一份（`ColorPalette`）；格式是这张卡片的设置，设置页里也能改。
struct ColorPickerDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var selected: ColorCode?
    @State private var copied: String?
    @State private var confirmClear = false
    /// 共享的取色历史（快速开关里取的颜色也在这里），变了就重画。
    @AppStorage(ColorHistory.defaultsKey) private var stored = ""
    @AppStorage(ColorPalette.defaultsKey) private var paletteRaw = ""
    @AppStorage(ColorHistory.legacyRetiredKey) private var retired = false

    private var recent: [ColorCode] {
        context.isPreview ? ColorPicking.samples : ColorPicking.recent(instance, stored: stored, retired: retired)
    }

    private var palette: [ColorCode] {
        context.isPreview ? Array(ColorPicking.samples.prefix(3)) : ColorPalette.colors(paletteRaw)
    }

    private var style: ColorCopyStyle { ColorPicking.style(instance) }

    private var shown: ColorCode? { selected ?? recent.first ?? palette.first }

    private static let paletteColumns = 8
    private static let recentColumns = 6

    var body: some View {
        DetailCard {
            MeshBackdrop(color: shown.map(\.swiftUIColor) ?? .gray, fixed: true)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                hero
                if let shown { codes(shown) }
                formatSection
                paletteSection
                recentSection
                PanelButton(title: tr("从屏幕取色"), symbol: "eyedropper", prominent: true) {
                    guard !context.isPreview else { return }
                    ColorPicking.pick(into: instance)
                    selected = nil
                    copied = nil
                }
            }
        }
        .onAppear { if !context.isPreview { style.save() } }
        .onChange(of: style) { _, next in if !context.isPreview { next.save() } }
    }

    // MARK: 大色块

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
                Text(verbatim: shown.map { style.text($0) } ?? tr("还没有取色"))
                    .font(.system(size: 19, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(copied.map { tr("已拷贝 \($0)") } ?? tr("点按下方的值即可拷贝"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let shown { star(shown) }
        }
    }

    /// 星标：收藏到我的色板，或从色板移出。色板满了时灰掉。
    private func star(_ color: ColorCode) -> some View {
        let saved = palette.contains(color)
        let full = !saved && palette.count >= ColorPalette.limit
        return Button {
            guard !context.isPreview else { return }
            ColorPicking.togglePalette(color)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(saved ? Color(hex: "#FFD43B") : .white.opacity(0.75))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.4 : 1)
        .help(saved ? tr("从我的色板移出") : full ? tr("色板满了（最多 \(ColorPalette.limit) 个）") : tr("收藏到我的色板"))
        .accessibilityLabel(saved ? tr("从我的色板移出") : tr("收藏到我的色板"))
    }

    // MARK: 四种写法

    private func codes(_ color: ColorCode) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ColorCopyFormat.allCases, id: \.self) { format in
                code(format, color.text(format, hexStyle: style.hexStyle))
            }
        }
    }

    private func code(_ format: ColorCopyFormat, _ value: String) -> some View {
        Button {
            guard !context.isPreview else { return }
            ColorSampling.copy(value)
            copied = format.title
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: format.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    Image(systemName: copied == format.title ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(verbatim: value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .glassPane(cornerRadius: 9)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(tr("拷贝 \(value)"))
    }

    // MARK: 取色后拷贝

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("取色后拷贝"))
            DetailSegmented(pages: ColorCopyFormat.allCases, title: \.title, selected: style.format) { choice in
                write(ColorCopyFormat.key, choice.rawValue)
            }
            // HEX 写法只管 HEX：选别的格式时收起，省一行。
            if style.format == .hex {
                DetailSegmented(pages: ColorHexStyle.allCases, title: \.sample, selected: style.hexStyle) { choice in
                    write(ColorHexStyle.key, choice.rawValue)
                }
            }
        }
    }

    private func write(_ key: String, _ value: String) {
        guard !context.isPreview else { return }
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { $0.set(key, .string(value)) }
    }

    // MARK: 我的色板

    private var paletteSection: some View {
        let colors = palette
        let canAdd = (shown.map { !colors.contains($0) } ?? false) && colors.count < ColorPalette.limit
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.paletteColumns)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionTitle(tr("我的色板"))
                Text(tr("不会被挤掉"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                Text(verbatim: "\(colors.count)/\(ColorPalette.limit)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(colors, id: \.self) { color in
                    swatch(color, height: 26, starred: true)
                        .contextMenu {
                            Button(tr("拷贝 \(style.text(color))")) { copy(color) }
                            Button(tr("从我的色板移出"), role: .destructive) {
                                guard !context.isPreview else { return }
                                ColorPicking.togglePalette(color)
                            }
                        }
                }
                if canAdd, let shown {
                    Button {
                        guard !context.isPreview else { return }
                        ColorPicking.togglePalette(shown)
                    } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: 26)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(tr("把上面这个颜色收藏到色板"))
                    .accessibilityLabel(tr("收藏到我的色板"))
                }
            }
        }
    }

    // MARK: 最近

    private var recentSection: some View {
        let colors = recent
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.recentColumns)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle(tr("最近"))
                Spacer(minLength: 0)
                if !colors.isEmpty {
                    Button(tr("清空")) { confirmClear = true }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white.opacity(0.7))
                        .disabled(context.isPreview)
                        .confirmationDialog(tr("清空最近的颜色？"), isPresented: $confirmClear) {
                            Button(tr("清空"), role: .destructive) {
                                ColorPicking.clearRecent()
                                selected = nil
                            }
                            Button(tr("取消"), role: .cancel) {}
                        } message: {
                            Text(tr("我的色板里的颜色不受影响。"))
                        }
                }
            }
            if colors.isEmpty {
                Text(tr("取到的颜色会出现在这里，右键可收藏或删除"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(colors, id: \.self) { color in
                        swatch(color, height: 30, starred: false)
                            .contextMenu { recentMenu(color) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentMenu(_ color: ColorCode) -> some View {
        let saved = palette.contains(color)
        Button(tr("拷贝 \(style.text(color))")) { copy(color) }
        if saved {
            Button(tr("从我的色板移出")) {
                guard !context.isPreview else { return }
                ColorPicking.togglePalette(color)
            }
        } else {
            Button(tr("收藏到色板")) {
                guard !context.isPreview else { return }
                ColorPicking.togglePalette(color)
            }
            .disabled(palette.count >= ColorPalette.limit)
        }
        Button(tr("删除"), role: .destructive) {
            guard !context.isPreview else { return }
            if selected == color { selected = nil }
            ColorPicking.forget(color, in: instance)
        }
    }

    // MARK: 零件

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(WidgetStyle.label(13))
            .foregroundStyle(.white.opacity(0.85))
    }

    private func swatch(_ color: ColorCode, height: CGFloat, starred: Bool) -> some View {
        Button {
            selected = color
            copied = nil
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.swiftUIColor)
                .frame(height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(color == shown ? 0.9 : 0.15),
                                      lineWidth: color == shown ? 1.5 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(color.isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.85))
                            .padding(3)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(style.hexStyle.apply(color.hex))
        .accessibilityLabel(color.hex)
    }

    private func copy(_ color: ColorCode) {
        guard !context.isPreview else { return }
        selected = color
        ColorSampling.copy(style.text(color))
        copied = style.format.title
    }
}
