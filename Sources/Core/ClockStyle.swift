import Foundation

/// 时钟小组件的样式注册表：添加小组件面板列哪几个样式、每个样式有哪些
/// 子选项、哪些是 Pro、旧版本存下的 layout 值读成哪个样式加哪些选项，都在这里。
///
/// 样式存在小组件配置的 `layout` 键里（值就是 `ClockStyle.id`），子选项各占
/// 一个以 `clock` 开头的键（如 `clockSize`），所以同一张卡片换样式时别的
/// 样式的选项原样留着，换回来还是原来的样子。
///
/// ## 如何新增时钟样式
///
/// 1. 在 `ClockFace` 里加一个画法（要画的东西，不是名字）。
/// 2. 在下面的 `ClockStyles.all` 里加一项 `ClockStyle`：`id` 是存进 `layout`
///    的值（定了就别改，改了已放好的卡片会认不出），`title` 用 `tr()` 包住，
///    `isPro` 决定整个样式是不是 Pro；有子选项就写在 `options` 里，选项的键
///    一律以 `clock` 开头，免得和别的小组件撞名；`face` 把选项值换成画法。
/// 3. 在 Sources/Widgets/Kinds/ClockTile.swift 的 `face(_:)` 里给新的
///    `ClockFace` 写绘制视图（`switch` 不写 default，漏了编译不过）。
/// 4. 新文字在 Resources/Localization/Localizable.xcstrings 里加英文，
///    在 Tests/ClockStyleTests.swift 补一条测试。
///
/// 添加小组件面板、设置里的“样式”和子选项、Pro 判定（`ProFeatures`）都从
/// 这里读，不用另外改。要把一个旧样式并进别的样式，把它的旧 id 写进目标样式的
/// `legacyLayouts`，读取时会映射过去，已放好的卡片样子不变。
public struct ClockStyle: Sendable, Identifiable {

    /// 一个子选项：设置里的一个单选。
    public struct Option: Sendable {
        public struct Choice: Sendable, Equatable {
            public var title: String
            public var value: String
            public init(_ title: String, _ value: String) {
                self.title = title
                self.value = value
            }
        }

        /// 存在配置里的键，以 `clock` 开头。
        public var key: String
        /// 设置里显示的名字。
        public var title: String
        public var choices: [Choice]
        /// 没存过时用哪个值，必须是 `choices` 里的一个。
        public var defaultValue: String
        /// 这些值是 Pro。
        public var proValues: Set<String> = []
        /// 别的选项是这些值时，这个选项没有意义，设置里不列。
        public var hiddenWhen: [String: String] = [:]

        public init(key: String, title: String, choices: [Choice], defaultValue: String,
                    proValues: Set<String> = [], hiddenWhen: [String: String] = [:]) {
            self.key = key
            self.title = title
            self.choices = choices
            self.defaultValue = defaultValue
            self.proValues = proValues
            self.hiddenWhen = hiddenWhen
        }

        /// 存的值认得就用，认不出（或没存）就用默认值。
        public func value(in values: [String: WidgetConfig.Value]) -> String {
            if case .string(let raw) = values[key], choices.contains(where: { $0.value == raw }) { return raw }
            return defaultValue
        }
    }

    /// 存进 `layout` 的值。
    public var id: String
    /// 添加小组件面板和样式菜单里的名字。
    public var title: String
    /// 整个样式是 Pro。
    public var isPro: Bool
    public var options: [Option]
    /// 并进这个样式的旧 layout 值，和它们对应的选项值。
    public var legacyLayouts: [String: [String: String]]
    /// 选项值（每个选项都有值）换成要画的东西。
    public var face: @Sendable ([String: String]) -> ClockFace

    public init(id: String, title: String, isPro: Bool = false, options: [Option] = [],
                legacyLayouts: [String: [String: String]] = [:],
                face: @escaping @Sendable ([String: String]) -> ClockFace) {
        self.id = id
        self.title = title
        self.isPro = isPro
        self.options = options
        self.legacyLayouts = legacyLayouts
        self.face = face
    }
}

/// 时钟卡片实际画哪一种。一个样式加上它的选项落到这里的一个画法，
/// 绘制视图按它分支（见 ClockTile.swift）。
public enum ClockFace: Equatable, Sendable {
    /// 标准：左边小表盘，右边时间和日期。`bold` 是粗细选“粗”。
    case standard(bold: Bool)
    /// 大号数字：大号时间，秒小字跟在旁边。`heavy` 是粗细选“粗”（原“大号数字”）。
    case bigDigits(heavy: Bool)
    /// 模拟表盘：带秒针的完整表盘。
    case analog
    /// 秒圈：一分钟转满一圈的圆环（原“秒圈”）。
    case secondsRing
    /// 翻页卡片。
    case flip
    /// 折叠翻页（原“折叠翻页”）。
    case foldFlip
    /// 深色大号翻页卡，标时分秒（原“极简”，Pro）。
    case bigFlipCards
    case pixel
    case words
    case neon
    case nixie
    case lcd

    /// 画成标准：时间旁边一只小表盘（时钟「标准」卡片秒针画在它上面）。
    public var hasSmallDial: Bool {
        if case .standard = self { return true }
        return false
    }
}

/// 一张卡片现在的样式和选项。
public struct ClockLook: Equatable, Sendable {
    public var styleID: String
    public var options: [String: String]
    public var face: ClockFace
    /// 样式或某个选项值是 Pro。
    public var isPro: Bool
}

public enum ClockStyles {

    // MARK: 选项的键和值

    public enum Key {
        public static let size = "clockSize"
        public static let weight = "clockWeight"
        public static let dial = "clockDial"
        public static let flip = "clockFlip"
        public static let card = "clockCard"
    }

    public static let layoutKey = "layout"
    public static let defaultStyleID = "standard"
    /// Pro 样式没解锁时画成翻页（和原来一样），复制过来的配置也能看时间。
    public static let lockedFallback: ClockFace = .flip

    // MARK: 注册表

    /// 添加小组件面板按这个顺序列。新增样式见 `ClockStyle` 顶上的说明。
    public static let all: [ClockStyle] = [
        ClockStyle(
            id: "standard", title: tr("标准"),
            options: [
                .init(key: Key.size, title: tr("大小"),
                      choices: [.init(tr("普通"), "normal"), .init(tr("大号"), "large")],
                      defaultValue: "normal"),
                .init(key: Key.weight, title: tr("粗细"),
                      choices: [.init(tr("常规"), "regular"), .init(tr("粗"), "bold")],
                      defaultValue: "regular"),
            ],
            // 原“大号数字”：大号、粗。
            legacyLayouts: ["digital": [Key.size: "large", Key.weight: "bold"]],
            face: { o in
                let bold = o[Key.weight] == "bold"
                return o[Key.size] == "large" ? .bigDigits(heavy: bold) : .standard(bold: bold)
            }),
        ClockStyle(
            id: "analog", title: tr("模拟表盘"),
            options: [
                .init(key: Key.dial, title: tr("表盘"),
                      choices: [.init(tr("指针"), "hands"), .init(tr("秒圈"), "ring")],
                      defaultValue: "hands"),
            ],
            // 原“秒圈”。
            legacyLayouts: ["ring": [Key.dial: "ring"]],
            face: { o in o[Key.dial] == "ring" ? .secondsRing : .analog }),
        ClockStyle(
            id: "flip", title: tr("翻页"),
            options: [
                .init(key: Key.card, title: tr("卡片"),
                      choices: [.init(tr("紧凑"), "compact"), .init(tr("大号带时分秒"), "large")],
                      defaultValue: "compact", proValues: ["large"]),
                // 大号卡片有自己的翻法，这一项只管紧凑卡片。
                .init(key: Key.flip, title: tr("翻法"),
                      choices: [.init(tr("普通"), "plain"), .init(tr("折叠"), "fold")],
                      defaultValue: "plain", hiddenWhen: [Key.card: "large"]),
            ],
            // 原“折叠翻页”和原“极简”（Pro，并入后“大号带时分秒”仍是 Pro）。
            legacyLayouts: [FoldFlip.clockLayout: [Key.flip: "fold"],
                            "minimal": [Key.card: "large"]],
            face: { o in
                if o[Key.card] == "large" { return .bigFlipCards }
                return o[Key.flip] == "fold" ? .foldFlip : .flip
            }),
        ClockStyle(id: "pixel", title: tr("像素"), face: { _ in .pixel }),
        // layout 值仍是 lcd，原名“简约”，和“极简”容易混，改叫“液晶”。
        ClockStyle(id: "lcd", title: tr("液晶"), isPro: true, face: { _ in .lcd }),
        ClockStyle(id: "words", title: tr("中文"), face: { _ in .words }),
        ClockStyle(id: "neon", title: tr("霓虹"), isPro: true, face: { _ in .neon }),
        ClockStyle(id: "nixie", title: tr("实景"), isPro: true, face: { _ in .nixie }),
    ]

    // MARK: 查表

    public static func style(_ id: String) -> ClockStyle? { all.first { $0.id == id } }

    /// 一个旧 layout 值并进了哪个样式、带哪些选项值。
    public static func legacy(_ layout: String) -> (style: ClockStyle, options: [String: String])? {
        for style in all {
            if let options = style.legacyLayouts[layout] { return (style, options) }
        }
        return nil
    }

    /// 所有旧 layout 值。
    public static var legacyLayoutIDs: Set<String> { Set(all.flatMap(\.legacyLayouts.keys)) }

    /// 所有子选项，按注册表顺序，同一个键只列一次。
    public static var allOptions: [ClockStyle.Option] {
        var seen = Set<String>()
        return all.flatMap(\.options).filter { seen.insert($0.key).inserted }
    }

    public static var optionKeys: [String] { allOptions.map(\.key) }

    public static func option(_ key: String) -> ClockStyle.Option? { allOptions.first { $0.key == key } }

    /// 放进目录默认配置里的选项默认值。
    public static var defaultOptionValues: [String: WidgetConfig.Value] {
        Dictionary(uniqueKeysWithValues: allOptions.map { ($0.key, .string($0.defaultValue)) })
    }

    // MARK: 读取

    /// 一份配置现在的样式和选项。旧 layout 值映射成新样式，它隐含的选项值
    /// 盖过存着的（存着的多半只是目录补上的默认值），所以样子不变。
    /// 认不出的 layout 按标准读。
    public static func resolve(_ values: [String: WidgetConfig.Value]) -> ClockLook {
        var layout = defaultStyleID
        if case .string(let raw) = values[layoutKey] { layout = raw }
        var found = style(layout)
        var implied: [String: String] = [:]
        if found == nil, let old = legacy(layout) {
            found = old.style
            implied = old.options
        }
        let chosen = found ?? all[0]
        var options: [String: String] = [:]
        for option in chosen.options {
            options[option.key] = implied[option.key] ?? option.value(in: values)
        }
        let pro = chosen.isPro || chosen.options.contains { option in
            option.proValues.contains(options[option.key] ?? option.defaultValue) && isShown(option, options)
        }
        return ClockLook(styleID: chosen.id, options: options, face: chosen.face(options), isPro: pro)
    }

    public static func resolve(_ config: WidgetConfig) -> ClockLook { resolve(config.values) }

    /// 要画的东西；Pro 样式没解锁时画成翻页。添加面板的预览照样画原样。
    public static func face(_ config: WidgetConfig, unlocked: Bool, preview: Bool = false) -> ClockFace {
        let look = resolve(config)
        if look.isPro, !unlocked, !preview { return lockedFallback }
        return look.face
    }

    /// 读旧配置时调一次（`WidgetInstance` 解码时）：旧 layout 值改写成新样式，
    /// 并把它隐含的选项值写进去。新 layout 值原样返回。
    public static func migrating(_ config: WidgetConfig) -> WidgetConfig {
        guard case .string(let layout) = config.values[layoutKey],
              style(layout) == nil, let old = legacy(layout) else { return config }
        var copy = config
        copy.set(layoutKey, .string(old.style.id))
        for (key, value) in old.options { copy.set(key, .string(value)) }
        return copy
    }

    // MARK: 设置

    private static func isShown(_ option: ClockStyle.Option, _ options: [String: String]) -> Bool {
        !option.hiddenWhen.contains { options[$0.key] == $0.value }
    }

    /// 设置里这个键对现在的样式有没有意义：是这个样式的选项，且没被别的选项藏起来。
    /// 两个秒开关按画法分开列（`ClockHands.applies`）：画成标准（带小表盘）时列
    /// 「表盘秒针」，其他画法（含标准样式选了大号数字）列「显示秒」。其余不是
    /// 时钟选项的键一律算有意义。
    public static func applies(_ key: String, to config: WidgetConfig) -> Bool {
        let look = resolve(config)
        if let seconds = ClockHands.applies(key, isStandard: look.face.hasSmallDial) { return seconds }
        guard option(key) != nil else { return true }
        guard let current = style(look.styleID),
              let option = current.options.first(where: { $0.key == key }) else { return false }
        return isShown(option, look.options)
    }

    // MARK: Pro

    /// Pro 的 layout 值：Pro 样式，加上并进来以后隐含 Pro 选项值的旧值（极简）。
    public static var proLayouts: Set<String> {
        var ids = Set(all.filter(\.isPro).map(\.id))
        for style in all {
            for (old, values) in style.legacyLayouts
            where style.options.contains(where: { option in
                guard let value = values[option.key] else { return false }
                return option.proValues.contains(value)
            }) {
                ids.insert(old)
            }
        }
        return ids
    }

    /// 一组样式覆盖（目录卡片、样式菜单一项、一个选项的一个值）有没有选到
    /// 时钟的 Pro 样式或 Pro 选项值。选项键都以 clock 开头，不会和别的小组件撞。
    public static func isProOverrides(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        if case .string(let layout) = overrides[layoutKey], proLayouts.contains(layout) { return true }
        for option in allOptions {
            if case .string(let raw) = overrides[option.key], option.proValues.contains(raw) { return true }
        }
        return false
    }
}
