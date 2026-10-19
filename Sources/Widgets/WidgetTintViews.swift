import AppKit
import SwiftUI

// 小组件颜色主题的界面部分：卡片读的颜色（环境值）、背景、设置里的
// 两排圆形色块，以及世界时钟的城市列表。规则都在 Core 的 `WidgetTint`
// 和 `WorldCities` 里，这里只负责画。

extension Color {
    init(code: ColorCode) {
        self = Color(.sRGB, red: code.red, green: code.green, blue: code.blue, opacity: 1)
    }
}

/// 一张卡片这一刻用的颜色：由 `WidgetTile` 按小组件自己的配置放进环境，
/// 图标方底、圆环、进度条、液态水从这里取。不在扩展栏上（面板、引导）
/// 时环境里没有，各处退回原来的样子。
struct WidgetTintStyle: Equatable, Sendable {
    var choice: WidgetTint.Choice
    /// nil 是跟随系统强调色。
    var palette: WidgetTint.Palette?
    /// 跟随系统强调色时对比色仍用这种小组件自己的。
    var kindPalette: WidgetTint.Palette
    var background: WidgetTint.Background
    /// 哪种小组件：卡片光晕按它判断这种卡片能不能选颜色。
    var kind: WidgetKind

    /// 没解锁码头 Pro 时，自定义颜色退回默认、渐变背景退回无背景
    /// （`WidgetTint.shownChoice`、`shownBackground`）。
    init(kind: WidgetKind, config: WidgetConfig, unlocked: Bool = ProAccess.isUnlocked) {
        choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        palette = WidgetTint.palette(choice, kind: kind)
        kindPalette = WidgetTint.defaultPalette(kind)
        background = WidgetTint.offersBackground(kind) ? WidgetTint.shownBackground(config, unlocked: unlocked) : .plain
        self.kind = kind
    }

    /// 卡片顶上主题色光晕的不透明度：默认 0，选了颜色时不超过 15%。
    func glowOpacity(dark: Bool) -> Double {
        WidgetTint.cardGlowOpacity(choice, kind: kind, background: background, dark: dark)
    }

    /// 卡片一圈主题色细描边的不透明度：默认 0。
    func edgeOpacity(dark: Bool) -> Double {
        WidgetTint.edgeOpacity(choice, kind: kind, dark: dark)
    }

    /// 用户在颜色面板里自己选过（不是默认）。
    var isChosen: Bool { choice.isChosen }

    /// 主色，调到在当前外观的卡片上看得清。
    func main(dark: Bool) -> Color {
        guard let palette else { return .accentColor }
        return Color(code: WidgetTint.readable(palette.main, dark: dark))
    }

    /// 渐变浅的那一端。
    func light(dark: Bool) -> Color {
        guard let palette else { return Color.accentColor.opacity(0.7) }
        return Color(code: WidgetTint.readable(palette.light, dark: dark))
    }

    /// 对比辅助色。
    func contrast(dark: Bool) -> Color {
        Color(code: WidgetTint.readable((palette ?? kindPalette).contrast, dark: dark))
    }

    /// 没调过亮度的主色，画在自己有底色的地方（摸鱼时钟的彩色底）。
    var rawMain: Color {
        palette.map { Color(code: $0.main) } ?? .accentColor
    }

    /// 用户自己选过颜色时的主色（没调亮度），没选过是 nil。有自己状态色或
    /// 底色的卡片用它决定换不换颜色。
    static func chosenColor(kind: WidgetKind, config: WidgetConfig) -> Color? {
        let style = WidgetTintStyle(kind: kind, config: config)
        return style.isChosen ? style.rawMain : nil
    }

    /// 压在主色上的字用黑还是白。跟随系统强调色时按白字。
    var ink: Color {
        guard let palette else { return .white }
        return WidgetTint.inkIsDark(on: palette.main) ? .black : .white
    }
}

extension Optional where Wrapped == WidgetTintStyle {
    /// 卡片上原来写死的统一强调色（闹钟和倒计时的橙、收音机的暖光、音量的
    /// 粉、日历的橙……）：用户在颜色面板里选过颜色就换成选的，默认照旧。
    func chosen(or own: Color, dark: Bool) -> Color {
        guard let style = self, style.isChosen else { return own }
        return style.main(dark: dark)
    }
}

struct WidgetTintKey: EnvironmentKey {
    static let defaultValue: WidgetTintStyle? = nil
}

extension EnvironmentValues {
    var widgetTint: WidgetTintStyle? {
        get { self[WidgetTintKey.self] }
        set { self[WidgetTintKey.self] = newValue }
    }
}

// MARK: - 面板强调色

/// 展开面板这一刻用的强调色：由 `WidgetDetailChrome` 按小组件自己的配置
/// 放进环境，各面板（Details）里原来表示“本小组件主题色”的进度环、强调
/// 数字、主按钮、选中态、开关、图例主色、链接色从这里取。
///
/// 没选过颜色时环境里是 nil，各面板写 `panelTint.accent(or: 原来的颜色)`，
/// 照旧用自己原来的颜色，所以默认外观一点不变。有意思的颜色（红涨绿跌、
/// 警告、电量、日历原色、天气、封面）不读它。
struct PanelTint: Equatable, Sendable {
    /// 强调色本身，已经调到在深色面板卡片上看得清。
    var color: Color
    /// 压在强调色上的字（主按钮、选中的分段），按亮度选深色或白色。
    var ink: Color
    /// 面板顶上那一抹光晕的不透明度，不超过 `WidgetTint.maxGlowOpacity`。
    var glow: Double

    /// 默认（没选过颜色）是 nil。没解锁码头 Pro 时自定义颜色退回默认，和卡片一样。
    init?(kind: WidgetKind, config: WidgetConfig, unlocked: Bool = ProAccess.isUnlocked) {
        let choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        switch WidgetTint.panelAccent(choice, kind: kind) {
        case .own:
            return nil
        case .system:
            color = .accentColor
            ink = .white
        case .color(let code):
            color = Color(code: code)
            ink = WidgetTint.labelIsDark(on: code) ? .black : .white
        }
        glow = WidgetTint.glowOpacity(choice, kind: kind, dark: true)
    }
}

struct PanelTintKey: EnvironmentKey {
    static let defaultValue: PanelTint? = nil
}

extension EnvironmentValues {
    var panelTint: PanelTint? {
        get { self[PanelTintKey.self] }
        set { self[PanelTintKey.self] = newValue }
    }
}

extension Optional where Wrapped == PanelTint {
    /// 选了颜色用选的，没选用面板自己原来的颜色。
    func accent(or own: Color) -> Color { self?.color ?? own }

    /// 主按钮上的字：选了颜色按亮度选，没选照旧。
    func ink(or own: Color) -> Color { self?.ink ?? own }

    /// 选中态的底：选了颜色是一层半透明的强调色，没选照旧用原来的底。
    func fill(_ opacity: Double, or own: Color) -> Color {
        self.map { $0.color.opacity(opacity) } ?? own
    }

    /// 给系统控件（开关、分段、滑块）的 `.tint`：没选是 nil，控件照旧。
    var control: Color? { self?.color }
}

/// 顶边一抹淡淡的主题色，往下渐隐。卡片、面板和预览小样共用。
struct TintGlow: View {
    var color: Color
    var opacity: Double

    var body: some View {
        LinearGradient(stops: [
            .init(color: color.opacity(min(WidgetTint.maxGlowOpacity, max(0, opacity))), location: 0),
            .init(color: color.opacity(0), location: WidgetTint.glowReach),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 背景

/// 卡片背景，全部用 SwiftUI 画。深色玻璃风格不变：颜色只是一层淡淡的
/// 纹理或压暗的渐变，不发光。
struct TintBackgroundView: View {
    var background: WidgetTint.Background
    var style: WidgetTintStyle?
    var dark: Bool

    private var main: Color { style?.main(dark: dark) ?? WidgetStyle.primary }

    var body: some View {
        switch background {
        case .plain:
            Color.clear
        case .dark:
            Color.black.opacity(0.55)
        case .frosted:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(dark ? 0.04 : 0.12))
        case .gradient:
            gradient
        case .dots:
            Canvas { context, size in
                let step = 6.0
                var y = step / 2
                var row = 0
                while y < size.height {
                    var x = step / 2 + (row.isMultiple(of: 2) ? 0 : step / 2)
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)),
                                     with: .color(main.opacity(0.32)))
                        x += step
                    }
                    y += step
                    row += 1
                }
            }
        case .lines:
            Canvas { context, size in
                var path = Path()
                let step = 7.0
                var offset = -size.height
                while offset < size.width {
                    path.move(to: CGPoint(x: offset, y: size.height))
                    path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                    offset += step
                }
                context.stroke(path, with: .color(main.opacity(0.2)), lineWidth: 0.8)
            }
        }
    }

    /// 主色和对比色都压得很暗，左上到右下，卡片上的字固定用浅色。
    private var gradient: some View {
        let palette = style?.palette ?? style?.kindPalette
        let black = ColorCode(red: 0, green: 0, blue: 0)
        let start = palette.map { Color(code: $0.main.mixed(with: black, by: 0.5)) } ?? Color.accentColor.opacity(0.4)
        let end = palette.map { Color(code: $0.contrast.mixed(with: black, by: 0.62)) } ?? Color.black.opacity(0.6)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(0.92)
    }
}

// MARK: - 颜色面板

/// 设置里的颜色面板：两排圆形色块（默认、自定义取色、十五种预设、跟随
/// 系统强调色），选中的外面一圈绿色描边；下面一排背景；最下面同一张卡片
/// 在浅色和深色外观下的实时预览。
struct WidgetTintPicker: View {
    var instance: WidgetInstance
    /// 一排几个色块。设置页 9 个；详情面板窄，按面板宽度算
    /// （`WidgetAppearance.swatchColumns`）。
    var columns = 9
    /// 浅色和深色两张预览卡片。详情面板里不画：扩展栏上那张真卡片就在旁边。
    var showsPreview = true
    var write: ((inout WidgetConfig) -> Void) -> Void

    /// 一个色块连同选中描边占的宽度，和格子间距，详情面板按它们算一排几个。
    static let swatchCell: CGFloat = swatch + 6
    static let swatchSpacing: CGFloat = 6

    private static let swatch: CGFloat = 22
    private static let ring = Color(red: 0.2, green: 0.78, blue: 0.35)

    private var choice: WidgetTint.Choice { WidgetTint.choice(instance.config) }
    private var background: WidgetTint.Background { WidgetTint.background(instance.config) }

    /// 让试用到期、激活或解绑时色块的小锁立刻跟着变。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if WidgetTint.offersColor(instance.kind) {
                Text("颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.swatchCell), spacing: Self.swatchSpacing),
                                         count: max(1, columns)),
                          alignment: .leading, spacing: Self.swatchSpacing) {
                    defaultSwatch
                    customSwatch
                    ForEach(WidgetTint.Preset.allCases) { preset in
                        swatchButton(selected: choice == .preset(preset), help: preset.title,
                                     action: { pick(.preset(preset)) }) {
                            Circle().fill(Color(hex: preset.hex))
                        }
                    }
                    systemSwatch
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 点色块立刻看到：示意卡跟着这张卡片的配置重画。
                TintSampleCard(kind: instance.kind, config: instance.config, unlocked: unlocked)
            }

            if WidgetTint.offersColor(instance.kind) || WidgetTint.offersBackground(instance.kind) {
                // 预设免费；自定义取色和渐变背景是码头 Pro，没解锁时点了弹付费墙。
                HStack(spacing: 5) {
                    ProBadge()
                    Text("自定义颜色和渐变背景为 Pro 专属，预设颜色免费")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if WidgetTint.offersBackground(instance.kind) {
                Text("背景")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(WidgetTint.Background.allCases) { option in
                        VStack(spacing: 3) {
                            swatchButton(selected: background == option,
                                         help: ProFeatures.menuTitle(option.title,
                                                                     isPro: WidgetTint.isProBackground(option)),
                                         action: { pickBackground(option) }) {
                                backgroundDisc(option)
                                    .overlay(alignment: .bottomTrailing) {
                                        if !ProLicenseGate.canChooseBackground(option, unlocked: unlocked) {
                                            lockMark
                                        }
                                    }
                            }
                            Text(option.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if showsPreview {
                preview
            }
        }
        .padding(.vertical, 4)
    }

    private var caption: String {
        switch choice {
        case .kindDefault: tr("默认：这种小组件自己的颜色")
        case .system: tr("跟随系统强调色")
        case .preset(let preset): preset.title
        case .custom(let code): tr("自定义 \(code.hex)")
        }
    }

    // MARK: 色块

    private func swatchButton<Disc: View>(selected: Bool, help: String,
                                          action: @escaping () -> Void,
                                          @ViewBuilder disc: () -> Disc) -> some View {
        Button(action: action) {
            disc()
                .frame(width: Self.swatch, height: Self.swatch)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                .padding(3)
                .overlay { Circle().strokeBorder(Self.ring, lineWidth: 2).opacity(selected ? 1 : 0) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 默认：这种小组件自己的主色，中间一个“回到默认”的小箭头。
    private var defaultSwatch: some View {
        let palette = WidgetTint.defaultPalette(instance.kind)
        return swatchButton(selected: choice == .kindDefault, help: tr("默认"),
                            action: { pick(.kindDefault) }) {
            Circle()
                .fill(Color(code: palette.main))
                .overlay {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WidgetTint.inkIsDark(on: palette.main) ? Color.black : Color.white)
                }
        }
    }

    /// 自定义：彩虹色圆，点开系统取色器。取色器本身几乎透明地盖在上面，
    /// 选过自定义时中间显示选的颜色。
    private var customSwatch: some View {
        let selectedCode: ColorCode? = {
            if case .custom(let code) = choice { return code }
            return nil
        }()
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center))
                .frame(width: Self.swatch, height: Self.swatch)
                .overlay {
                    if let selectedCode {
                        Circle().fill(Color(code: selectedCode))
                            .frame(width: 10, height: 10)
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                    }
                }
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                .padding(3)
                .overlay { Circle().strokeBorder(Self.ring, lineWidth: 2).opacity(selectedCode != nil ? 1 : 0) }
            if unlocked {
                ColorPicker("", selection: Binding(
                    get: { selectedCode.map { Color(code: $0) } ?? Color(code: WidgetTint.defaultPalette(instance.kind).main) },
                    set: { color in
                        if let code = Self.code(color) { pick(.custom(code)) }
                    }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: Self.swatch + 6, height: Self.swatch + 6)
                    .opacity(0.02)
            } else {
                // 自定义取色是码头 Pro：没解锁时不开取色器，点了弹付费墙。
                Button { PaywallWindow.shared.show() } label: {
                    Color.clear
                        .frame(width: Self.swatch + 6, height: Self.swatch + 6)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                lockMark
                    .frame(width: Self.swatch + 6, height: Self.swatch + 6, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
        .help(ProFeatures.menuTitle(tr("自定义颜色"), isPro: true))
        .accessibilityLabel(ProFeatures.menuTitle(tr("自定义颜色"), isPro: true))
    }

    /// 跟随系统强调色。
    private var systemSwatch: some View {
        swatchButton(selected: choice == .system, help: tr("跟随系统强调色"),
                     action: { pick(.system) }) {
            Circle()
                .fill(Color.accentColor)
                .overlay {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }

    private func backgroundDisc(_ option: WidgetTint.Background) -> some View {
        let style = WidgetTintStyle(kind: instance.kind, config: instance.config)
        return ZStack {
            Circle().fill(Color.gray.opacity(0.25))
            TintBackgroundView(background: option, style: style, dark: true)
                .clipShape(Circle())
            if option == .plain {
                Image(systemName: "nosign")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 预览

    /// 同一张卡片在浅色和深色外观下各一张，卡片是真的小组件（预览模式）。
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("预览")
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    previewTile(dark: false)
                    previewTile(dark: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    previewTile(dark: false)
                    previewTile(dark: true)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func previewTile(dark: Bool) -> some View {
        let context = WidgetContext(position: .bottom, now: .now, isPreview: true)
        let size = WidgetCatalog.contentSize(instance, position: .bottom)
        let scale = min(0.8, 190 / max(size.width, 1))
        return WidgetTile(instance: instance, context: context)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dark ? Color(white: 0.16) : Color(white: 0.88))
            }
            .environment(\.colorScheme, dark ? .dark : .light)
            .allowsHitTesting(false)
    }

    // MARK: 写回

    /// 没解锁的 Pro 色块右下角的小锁。
    private var lockMark: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .padding(2.5)
            .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
            .accessibilityHidden(true)
    }

    private func pick(_ choice: WidgetTint.Choice) {
        if !ProLicenseGate.canChooseTint(choice, unlocked: unlocked) {
            PaywallWindow.shared.show()
            return
        }
        write { config in
            let raw = choice.raw
            config.set(WidgetTint.key, raw.isEmpty ? nil : .string(raw))
        }
    }

    private func pickBackground(_ option: WidgetTint.Background) {
        if !ProLicenseGate.canChooseBackground(option, unlocked: unlocked) {
            PaywallWindow.shared.show()
            return
        }
        write { config in
            config.set(WidgetTint.backgroundKey, option == .plain ? nil : .string(option.rawValue))
        }
    }

    static func code(_ color: Color) -> ColorCode? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                         blue: Double(rgb.blueComponent))
    }
}

// MARK: - 实时预览小样

/// 颜色面板里的示意卡：图标底板、数字、进度条和一个按钮，按这张卡片此刻
/// 的颜色画，点不同的色块立刻跟着变。选了颜色时顶上那一抹光晕和细描边也
/// 画出来，和扩展栏上的卡片、展开面板用的是同一套规则（`WidgetTint`）。
/// 固定画成深色玻璃：卡片和面板卡片的默认外观。
struct TintSampleCard: View {
    var kind: WidgetKind
    var config: WidgetConfig
    var unlocked: Bool

    private var style: WidgetTintStyle { WidgetTintStyle(kind: kind, config: config, unlocked: unlocked) }

    /// 已经调到在深色卡片上看得清的主色；跟随系统强调色时是 nil。
    private var code: ColorCode? {
        style.palette.map { WidgetTint.readable($0.main, dark: true) }
    }

    private var main: Color { code.map { Color(code: $0) } ?? .accentColor }

    private var ink: Color {
        guard let code else { return .white }
        return WidgetTint.labelIsDark(on: code) ? .black : .white
    }

    var body: some View {
        let glow = style.glowOpacity(dark: true)
        let edge = style.edgeOpacity(dark: true)
        VStack(alignment: .leading, spacing: 6) {
            Text("实时预览")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(main)
                    .frame(width: 38, height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(main.opacity(0.18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(main.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "72%")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(main)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(main).frame(width: geo.size.width * 0.72)
                        }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("按钮")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(main))
            }
            .padding(12)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.14))
                    .overlay {
                        if glow > 0 {
                            TintGlow(color: main, opacity: glow)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(edge > 0 ? main.opacity(edge) : Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.2), value: style)
            .accessibilityHidden(true)
            Text(style.isChosen
                 ? tr("卡片顶上会加一抹淡淡的主题色，展开面板里的强调元素一起换色。")
                 : tr("默认颜色：卡片和展开面板保持各自原来的样子。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 世界时钟的城市列表

/// 可以搜索的城市列表：内置常用城市（中文名、英文、拼音、国家都能搜），
/// 再加系统认识的全部时区。点一行就选中，由调用方写回 `zone` 和 `city`。
struct WorldCityPicker: View {
    var zone: String
    var city: String
    var onPick: (WorldCity) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索城市、国家或时区", text: $query)
                .textFieldStyle(.roundedBorder)
            let results = WorldCities.search(query)
            if results.isEmpty {
                Text("没有找到，试试英文名或时区，例如 Kathmandu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { item in
                            row(item)
                        }
                    }
                }
                .frame(height: 210)
            }
        }
    }

    private func row(_ item: WorldCity) -> some View {
        let selected = item.zone == zone && item.name == city
        return Button { onPick(item) } label: {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.region.isEmpty ? item.zone : item.region)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let tz = TimeZone(identifier: item.zone) {
                    Text(ClockFormat.time(.now, zone: tz))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                    .opacity(selected ? 1 : 0)
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.1 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name)，\(item.zone)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 写回小组件配置：时区和卡片上的城市名一起改。
    static func apply(_ city: WorldCity, to config: inout WidgetConfig) {
        config.set("zone", .string(city.zone))
        config.set("city", .string(city.name))
    }
}
