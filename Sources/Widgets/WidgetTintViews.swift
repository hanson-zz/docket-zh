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
    /// 外观 ▸ 颜色里的色调强度：光晕和细描边有多显眼，默认「中」。
    var strength: WidgetTint.Strength
    /// 外观 ▸ 颜色里的文字颜色：压在主题色上的字，默认「自动」。
    var textInk: WidgetTint.TextInk

    /// 没解锁码头 Pro 时，自定义颜色退回默认、渐变背景退回无背景
    /// （`WidgetTint.shownChoice`、`shownBackground`）。
    init(kind: WidgetKind, config: WidgetConfig, unlocked: Bool = ProAccess.isUnlocked) {
        choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        palette = WidgetTint.palette(choice, kind: kind)
        kindPalette = WidgetTint.defaultPalette(kind)
        background = WidgetTint.offersBackground(kind) ? WidgetTint.shownBackground(config, unlocked: unlocked) : .plain
        self.kind = kind
        strength = WidgetTint.strength(config)
        textInk = WidgetTint.textInk(config)
    }

    /// 卡片顶上主题色光晕的不透明度：默认 0，选了颜色时按色调强度给，不超过 15%。
    func glowOpacity(dark: Bool) -> Double {
        WidgetTint.cardGlowOpacity(choice, kind: kind, background: background, dark: dark, strength: strength)
    }

    /// 卡片一圈主题色细描边的不透明度：默认 0。
    func edgeOpacity(dark: Bool) -> Double {
        WidgetTint.edgeOpacity(choice, kind: kind, dark: dark, strength: strength)
    }

    /// 光晕往下铺到卡片高度的多少，跟着色调强度。
    func glowReach(dark: Bool) -> Double {
        WidgetTint.glowLevels(strength, dark: dark).reach
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
    /// 光晕往下铺到多深，跟着色调强度。
    var reach: Double

    /// 默认（没选过颜色）是 nil。没解锁码头 Pro 时自定义颜色退回默认，和卡片一样。
    init?(kind: WidgetKind, config: WidgetConfig, unlocked: Bool = ProAccess.isUnlocked) {
        let choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        let textInk = WidgetTint.textInk(config)
        switch WidgetTint.panelAccent(choice, kind: kind) {
        case .own:
            return nil
        case .system:
            color = .accentColor
            // 字色按此刻系统强调色解：「自动」白字不到 4.5 换深色，手选的检查对比度。
            if let code = Self.accentCode() {
                ink = Color(code: WidgetTint.resolveInk(textInk, accent: code, on: code).color)
            } else {
                ink = .white
            }
        case .color(let code):
            color = Color(code: code)
            ink = Color(code: WidgetTint.resolveInk(textInk, accent: code, on: code).color)
        }
        let levels = WidgetTint.glowLevels(choice, kind: kind, strength: WidgetTint.strength(config), dark: true)
        glow = levels.glow
        reach = levels.reach
    }

    /// 此刻系统强调色的 sRGB 值，算手选字色的对比度用。
    private static func accentCode() -> ColorCode? {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return nil }
        return ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                         blue: Double(rgb.blueComponent))
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
    /// 往下铺到多深（0...1），跟着色调强度，默认是原来的深度。
    var reach: Double = WidgetTint.glowReach

    var body: some View {
        LinearGradient(stops: [
            .init(color: color.opacity(min(WidgetTint.maxGlowOpacity, max(0, opacity))), location: 0),
            .init(color: color.opacity(0), location: min(0.95, max(0.05, reach))),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 背景

/// 卡片背景，用 SwiftUI 画：无、压暗一层的深色、压暗的主题色渐变。
/// 扩展栏卡片和颜色面板的实时预览卡共用。深色玻璃风格不变，不发光。
struct TintBackgroundView: View {
    var background: WidgetTint.Background
    var style: WidgetTintStyle?
    var dark: Bool

    var body: some View {
        switch background {
        case .plain:
            Color.clear
        case .dark:
            Color.black.opacity(0.55)
        case .gradient:
            gradient
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
    private var strength: WidgetTint.Strength { WidgetTint.strength(instance.config) }
    private var textInk: WidgetTint.TextInk { WidgetTint.textInk(instance.config) }

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
                // 色调强度和文字颜色：只在选了非默认颜色时生效，默认时灰掉。
                tuning
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
                                .font(.system(size: 13))
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

    // MARK: 强度和文字颜色

    /// 两行分段：色调强度（淡 / 浓）和文字颜色（自动 / 主题色）。
    /// 默认颜色时也能点：点了自动改用「跟随系统强调色」再生效，避免灰掉被当成坏了。
    private var tuning: some View {
        let active = choice.isChosen
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("色调强度")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Picker("色调强度", selection: Binding(
                    get: { strength },
                    set: { value in pickStrength(value) })) {
                    ForEach(WidgetTint.Strength.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 140, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("文字颜色")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Picker("文字颜色", selection: Binding(
                    get: { textInk },
                    set: { value in pickInk(value) })) {
                    ForEach(WidgetTint.TextInk.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 180, alignment: .leading)
            }
            if !active {
                Text("现在是默认颜色。调这两项会自动改用系统强调色。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 默认颜色下调强度或文字颜色时，先切到免费的「跟随系统强调色」，让改动马上看得见。
    private func adoptSystemTintIfDefault(_ config: inout WidgetConfig) {
        if !WidgetTint.choice(config).isChosen {
            config.set(WidgetTint.key, .string(WidgetTint.Choice.system.raw))
        }
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

    /// 默认的「中」写回时删掉键，读回来一样是「中」。
    private func pickStrength(_ value: WidgetTint.Strength) {
        write { config in
            adoptSystemTintIfDefault(&config)
            config.set(WidgetTint.strengthKey, value.raw.isEmpty ? nil : .string(value.raw))
        }
    }

    /// 默认的「自动」写回时删掉键。
    private func pickInk(_ value: WidgetTint.TextInk) {
        write { config in
            adoptSystemTintIfDefault(&config)
            config.set(WidgetTint.inkKey, value.raw.isEmpty ? nil : .string(value.raw))
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

/// 颜色面板里的示意卡，做成一块能点的迷你面板：图标底板、标题、数字、进度条、
/// 一组分段和一个主按钮，按这张卡片此刻的颜色、色调强度和文字颜色画，改哪一项
/// 都立刻跟着变。点「＋10%」加一格（满了回到 0），在进度条上点或拖直接定百分比，
/// 分段可以切换，好看清主题色在不同进度、选中态下的样子。选了颜色时顶上那一抹
/// 光晕和细描边按强度画出来，主按钮和选中分段的字按文字颜色画（对比度不够时
/// 退回「自动」），选了背景（深色、渐变）时底板上画出同样的背景，和扩展栏上的
/// 卡片、展开面板用的是同一套规则（`WidgetTint`）。没解锁时渐变退回无背景。
/// 固定画成深色玻璃：卡片和面板卡片的默认外观。
struct TintSampleCard: View {
    var kind: WidgetKind
    var config: WidgetConfig
    var unlocked: Bool

    /// 示意进度，0...1，只在这张示意卡里用，不写进配置。
    @State private var progress: Double = 0.72
    /// 示意分段选中的是第几个，只在示意卡里用。
    @State private var segment = 1

    private var style: WidgetTintStyle { WidgetTintStyle(kind: kind, config: config, unlocked: unlocked) }

    private func step() {
        let next = (progress * 10).rounded() / 10 + 0.1
        progress = next > 1.0001 ? 0 : min(next, 1)
    }

    /// 已经调到在深色卡片上看得清的主色；跟随系统强调色时是 nil。
    private var code: ColorCode? {
        style.palette.map { WidgetTint.readable($0.main, dark: true) }
    }

    private var main: Color { code.map { Color(code: $0) } ?? .accentColor }

    /// 压在主色上的字：和展开面板一样按文字颜色解，默认颜色时照旧按亮度选。
    private var inkResolution: WidgetTint.InkResolution? {
        guard let code else { return nil }
        guard style.isChosen else {
            return WidgetTint.InkResolution(color: WidgetTint.autoInk(on: code), fellBack: false)
        }
        return WidgetTint.resolveInk(style.textInk, accent: code, on: code)
    }

    private var ink: Color {
        inkResolution.map { Color(code: $0.color) } ?? .white
    }

    private var segments: [String] { [tr("今天"), tr("本周"), tr("本月")] }

    var body: some View {
        let glow = style.glowOpacity(dark: true)
        let edge = style.edgeOpacity(dark: true)
        let reach = style.glowReach(dark: true)
        VStack(alignment: .leading, spacing: 6) {
            Text("实时预览")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                header
                bar
                HStack(spacing: 8) {
                    segmentRow
                    Spacer(minLength: 4)
                    stepButton
                }
            }
            .padding(12)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.14))
                    .overlay {
                        // 选了背景时和扩展栏卡片一样画在底板上、光晕下面。
                        if style.background != .plain {
                            TintBackgroundView(background: style.background, style: style, dark: true)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .overlay {
                        if glow > 0 {
                            TintGlow(color: main, opacity: glow, reach: reach)
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
            Text(style.isChosen
                 ? tr("卡片顶上会加一抹淡淡的主题色，展开面板里的强调元素一起换色。")
                 : tr("默认颜色：卡片和展开面板保持各自原来的样子。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if style.isChosen, inkResolution?.fellBack == true {
                Text("对比度不足 4.5，文字颜色已退回「自动」。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(main)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(main.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(main.opacity(0.3), lineWidth: 0.5)
                        }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("迷你面板")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(tr("强度 \(style.strength.title) · 文字 \(style.textInk.title)"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 4)
            Text(verbatim: "\(Int((progress * 100).rounded()))%")
                .contentTransition(.numericText(value: progress))
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(main)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(main).frame(width: geo.size.width * progress)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard geo.size.width > 0 else { return }
                progress = min(max(value.location.x / geo.size.width, 0), 1)
            })
        }
        .frame(height: 16)
        .help(tr("点或拖动进度条调节"))
    }

    /// 示意分段：选中的一格是主色底加文字颜色，其余是淡白字。
    private var segmentRow: some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { index in
                let selected = index == segment
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { segment = index }
                } label: {
                    Text(segments[index])
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ink : Color.white.opacity(0.7))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background {
                            Capsule().fill(selected ? main : Color.clear)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var stepButton: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { step() } }) {
            Text(verbatim: "＋10%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(main))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("点一下加 10%，满了回到 0"))
    }
}
