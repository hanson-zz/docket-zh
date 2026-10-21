import SwiftUI
import AppKit

// MARK: - 面板语义色（液态玻璃）
//
// 面板原来画在一张固定深色的石墨卡上，所以到处写死 `.white` / `.white.opacity(x)`。
// 现在卡片是 macOS 26 的液态玻璃，跟着设置里的「跟随系统 / 浅色 / 深色」
// （AppAppearance → NSApp.appearance → 环境里的 colorScheme）走，白字落在浅色玻璃上
// 就看不见了。下面这些颜色都是动态色：深色外观下等于原来的白，浅色外观下换成深字。
// 例外面板用 `DetailCard(forceDark: true)` 或 `.panelForceDark()`，环境变成深色，
// 这些颜色自动回到原来的白，所以替换后例外面板长得和以前一样。
//
// 旧写法 → 新写法（其他子任务照表机械替换，只看透明度，不用自己挑）
//
// 文字、图标（foregroundStyle / foregroundColor / Text 颜色 / 图标颜色）：
//   .white                              → .panelPrimary
//   .white.opacity(0.8 ... 0.99)        → .panelPrimary
//   .white.opacity(0.6 ... 0.79)        → .panelSecondary
//   .white.opacity(0.4 ... 0.59)        → .panelTertiary
//   .white.opacity(低于 0.4，当文字)      → .panelQuaternary（只用于占位、装饰，不放要读的字）
//   Color.white（同上，按透明度）          → Color.panelPrimary 等
//
// 底色、填充（fill / background，白色低透明度当「玻璃小块」）：
//   .white.opacity(0.04 ... 0.12) 当底  → .panelFill        （薄玻璃填充、分组底、chip 底）
//   .white.opacity(0.13 ... 0.3) 当底   → 按用途二选一：
//       列表行、格子的选中，悬停、拖起，小标签、图标占位 → .panelSelected（浅色灰，黑 0.12）
//       分段控件、选项胶囊的选中项，独立按钮底 → .panelRaised + 形状上挂 .panelLift()
//       （浅色实心白加柔和阴影浮在淡灰上；深色两者都是白 0.18，和以前一样）
//   .panelFillStrong 是旧名字，等于 .panelSelected
//   进度条、圆环的空轨道 .white.opacity(x) → .panelTrack
//   .white.opacity(x) 当描边 / 细线       → .panelStroke（玻璃块边）或 .panelSeparator（分隔线）
//   Divider().overlay(.white.opacity(x)) → Divider().overlay(.panelSeparator)
//
// 压暗（黑色半透明，盖在内容或底上）：
//   .black.opacity(0.2 ... 0.5)         → .panelShade       （浅色下只压一点点）
//   .black.opacity(低于 0.2)             → .panelShadeSoft
//   阴影 .shadow(color: .black.opacity(x)) 可以不改
//
// 白底黑字的选中胶囊（反色）：
//   .fill(Color.white) + .foregroundStyle(.black)  → .fill(.panelPrimary) + .foregroundStyle(.panelOnPrimary)
//   按钮、胶囊的白色描边 .white.opacity(0.2...0.4) → .panelQuaternary（浅色下是淡灰线）
//
// 写法：都挂在 `ShapeStyle where Self == Color` 上，所以
//   .foregroundStyle(.panelPrimary)、.fill(.panelFill)、Color.panelSecondary、
//   colors: [.panelPrimary, .panelTertiary]、.panelPrimary.opacity(0.5) 都能直接写。
//
// 主题色当文字（主题色、强调色、红绿涨跌写成字或细图标时）：
//   .foregroundStyle(accent)            → .foregroundStyle(accent.panelReadable)
//   或 Color.panelText(accent)           （同一个东西，浅色下加深到近白上对比度 4.5，深色下不变）
//   圆环、色条这类图形要在浅色下加深：accent.panelGraphic（不到 3:1 才压）
//   主题色当底色、圆点、色块时不用换。
//
// 不要换的：
//   实心主题色按钮上的白字（底是实心色，不是玻璃）保持 .white。
//   照片、封面、插画上的字和黑胶囊保持原样（例外面板）。
//
// 去掉强制深色：
//   .environment(\.colorScheme, .dark) / .colorScheme(.dark) → 删掉；
//   确实要保持暗色的例外面板 → DetailCard(forceDark: true) { ... } 或 .panelForceDark()
//
// 判断当前是不是浅色：@Environment(\.colorScheme) private var scheme，scheme == .light。

extension ShapeStyle where Self == Color {
    /// 主文字：深色下白，浅色下近黑（#18161C）。替换 `.white`。
    static var panelPrimary: Color {
        Color.panelDynamic(dark: NSColor.white,
                           light: NSColor(srgbRed: 0.094, green: 0.086, blue: 0.11, alpha: 1))
    }
    /// 次级文字：说明、单位、副标题。替换 `.white.opacity(0.6...0.79)`。
    static var panelSecondary: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.68),
                           light: NSColor(srgbRed: 0.094, green: 0.086, blue: 0.11, alpha: 0.68))
    }
    /// 三级文字：小标签、时间戳。替换 `.white.opacity(0.4...0.59)`。
    static var panelTertiary: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.5),
                           light: NSColor(srgbRed: 0.094, green: 0.086, blue: 0.11, alpha: 0.54))
    }
    /// 四级：占位、装饰、禁用。替换当文字用的 `.white.opacity(<0.4)`。
    static var panelQuaternary: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.3),
                           light: NSColor(srgbRed: 0.094, green: 0.086, blue: 0.11, alpha: 0.3))
    }

    /// 薄玻璃填充：分组底、chip 底、未选中的格子和按钮。替换当底的 `.white.opacity(0.04...0.12)`。
    /// 浅色下是很淡的灰（黑 0.05，同 macOS 浅色里控件的轨道和未选中底）：近白玻璃上
    /// 再叠白几乎看不出，灰一点才能和浮起的白色选中块、加深的灰色选中行分开。深色不变。
    static var panelFill: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.09),
                           light: NSColor.black.withAlphaComponent(0.05))
    }
    /// 选中、悬停、拖起的那一块（列表行、格子、悬停卡片），以及小标签、图标占位这类
    /// 「比 panelFill 重一档」的底。浅色下是加深一档的灰（黑 0.12），深色白 0.18。
    static var panelSelected: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.18),
                           light: NSColor.black.withAlphaComponent(0.12))
    }
    /// 浮起的选中块：分段控件、选项胶囊里选中的那一项，和独立的按钮底。浅色下是
    /// 实心白（0.95），配 `.panelLift()` 的柔和阴影浮在 panelFill 的淡灰轨道上
    /// （同 macOS 浅色分段控件和按钮）；深色白 0.18，不加阴影，和以前一样。
    static var panelRaised: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.18),
                           light: NSColor.white.withAlphaComponent(0.95))
    }
    /// 旧名字，等于 `panelSelected`。新代码按用途选 `panelSelected` 或 `panelRaised`。
    static var panelFillStrong: Color { panelSelected }
    /// 进度条、圆环的空轨道：浅色玻璃上白轨道看不见，换成淡淡的深色。
    static var panelTrack: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.15),
                           light: NSColor.black.withAlphaComponent(0.08))
    }
    /// 玻璃小块的描边（亮边）。
    static var panelStroke: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.14),
                           light: NSColor.white.withAlphaComponent(0.8))
    }
    /// 分隔线。
    static var panelSeparator: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.12),
                           light: NSColor.black.withAlphaComponent(0.1))
    }
    /// 压暗：替换 `.black.opacity(0.2...0.5)`，浅色下只压一点。
    static var panelShade: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.3),
                           light: NSColor.black.withAlphaComponent(0.08))
    }
    /// 轻压暗：替换 `.black.opacity(<0.2)`。
    static var panelShadeSoft: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.15),
                           light: NSColor.black.withAlphaComponent(0.05))
    }

    /// 实心主文字色块上的字（选中的胶囊：底 .panelPrimary，字用这个）。
    /// 替换「白底黑字」里的 `.black`。
    static var panelOnPrimary: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.88), light: NSColor.white)
    }
}

extension Color {
    /// 主题色当文字：深色下原样，浅色下往黑里压，至少 30%，压到在近白玻璃
    /// （#F4F4F6）上对比度够 `minContrast` 为止（默认 4.5，正文）。算法在
    /// Core 的 `PanelContrast`（有测试）：紫、蓝这类深主题色还是压 30%，
    /// 计算器黄、天气浅蓝这类高亮度色多压一些。透明度保持原样。
    static func panelText(_ accent: Color, minContrast: Double = PanelContrast.textContrast,
                          atLeast: Double = PanelContrast.minimumFraction) -> Color {
        let base = NSColor(accent)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let resolved = base.usingColorSpace(.sRGB) ?? base
            guard !appearance.panelIsDark else { return resolved }
            return NSColor.panelDeepened(resolved, minContrast: minContrast, atLeast: atLeast)
        })
    }

    /// 同 `Color.panelText(self)`：`.foregroundStyle(accent.panelReadable)`。
    var panelReadable: Color { Color.panelText(self) }

    /// 按指定对比度加深（至少 30%，同 `panelReadable`）。
    func panelReadable(minContrast: Double) -> Color { Color.panelText(self, minContrast: minContrast) }

    /// 主题色当图形（圆环、色条、细图标）：深色下原样；浅色下只在近白玻璃上
    /// 不到 3:1 时往黑里压，压到刚好够，本来够深的（紫、蓝）不动。
    var panelGraphic: Color {
        Color.panelText(self, minContrast: PanelContrast.graphicContrast, atLeast: 0)
    }

    /// 一个深色、浅色各一份的动态色，跟着环境里的 colorScheme 解析。
    static func panelDynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.panelIsDark ? dark : light })
    }
}

extension NSColor {
    /// 浅色外观下的加深版（不是动态色）：按 `PanelContrast` 算比例往黑里压，透明度不变。
    static func panelDeepened(_ color: NSColor, minContrast: Double = PanelContrast.textContrast,
                              atLeast: Double = PanelContrast.minimumFraction) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let code = ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                             blue: Double(rgb.blueComponent))
        let fraction = PanelContrast.fraction(for: code, minContrast: minContrast, atLeast: atLeast)
        let dark = PanelContrast.darkened(code, by: fraction)
        return NSColor(srgbRed: CGFloat(dark.red), green: CGFloat(dark.green), blue: CGFloat(dark.blue),
                       alpha: rgb.alphaComponent)
    }
}

extension NSAppearance {
    /// 这个外观是不是深色（含高对比度深色）。
    var panelIsDark: Bool {
        bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                         .accessibilityHighContrastDarkAqua]).map {
            $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua
        } ?? false
    }
}

// MARK: - 浮起的选中块

extension View {
    /// 浅色下给浮起的选中块加一道柔和阴影（黑 0.10，半径 2，下移 1），深色和保持暗色
    /// 的例外不加。挂在填充形状上（`Capsule().fill(.panelRaised).panelLift()`），
    /// 不挂在带字的整块上，免得字也带阴影。
    func panelLift(_ on: Bool = true) -> some View {
        modifier(PanelLiftModifier(on: on))
    }
}

private struct PanelLiftModifier: ViewModifier {
    var on: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(on && scheme == .light ? 0.10 : 0), radius: 2, y: 1)
    }
}

// MARK: - 保持暗色的开关

extension EnvironmentValues {
    /// 面板卡片要不要保持原来的暗色石墨（收音机、相框、壁纸这类例外）。
    @Entry var panelForcedDark: Bool = false
}

extension View {
    /// 例外面板用：内容和卡片底都保持暗色，语义色解析成原来的白。
    func panelForceDark(_ on: Bool = true) -> some View {
        modifier(PanelForceDarkModifier(on: on))
    }
}

private struct PanelForceDarkModifier: ViewModifier {
    var on: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .environment(\.panelForcedDark, on)
            .environment(\.colorScheme, on ? .dark : scheme)
    }
}
