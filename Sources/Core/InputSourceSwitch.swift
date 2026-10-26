import Foundation

// MARK: - 输入法自动切换
//
// 切到某个 App 时，按规则把输入法换成它要的那个；换了就从刘海落下一个小胶囊提示
// 一下。读和切输入法用系统的 Text Input Sources 接口（Carbon），在 Services 那边；
// 这里只有能测的判断：设置、规则、回退顺序、字形徽章、要不要提示、提示放哪。
//
// 免费：总开关、没有规则的 App 怎么办（用默认输入法 / 记住上次）、提示位置和停留时间。
// 码头 Pro：按 App 规则。没解锁时规则照旧存着，只是不生效（那些 App 按「没有规则」
// 处理），解锁或试用后自动回来，见 `ProLicenseGate.inputSourceRulesActive`。

/// 系统里的一个键盘输入法，只抄判断要用的几项。
public struct InputSourceInfo: Equatable, Hashable, Sendable, Identifiable {
    /// kTISPropertyInputSourceID，如 com.apple.keylayout.ABC、com.apple.inputmethod.SCIM.ITABC。
    public var id: String
    /// kTISPropertyLocalizedName，跟着系统语言，如「简体拼音」「ABC」。
    public var name: String
    /// kTISPropertyInputSourceLanguages，第一个是主语言，如 zh-Hans、en、ja。
    public var languages: [String]
    /// kTISPropertyInputSourceType 的值：键盘布局、输入模式、没有模式的输入法等。
    public var type: String
    /// kTISPropertyInputSourceIsSelectCapable：能不能被选中（带模式的输入法本身不能，它的模式能）。
    public var selectable: Bool
    /// kTISPropertyInputSourceIsEnabled：用户在系统设置里加上了。
    public var enabled: Bool

    public init(id: String, name: String, languages: [String] = [], type: String = InputSourceInfo.layoutType,
                selectable: Bool = true, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.languages = languages
        self.type = type
        self.selectable = selectable
        self.enabled = enabled
    }

    /// kTISTypeKeyboardLayout 等的值。
    public static let layoutType = "TISTypeKeyboardLayout"
    public static let inputModeType = "TISTypeKeyboardInputMode"
    public static let methodWithoutModesType = "TISTypeKeyboardInputMethodWithoutModes"
}

public enum InputSourceCatalog {
    /// 系统自带的「ABC」。默认输入法没设时用它。
    public static let abcID = "com.apple.keylayout.ABC"

    /// 不当成输入法的：表情与符号、重音符号长按、手写、日语假名面板、助听辅助键盘。
    static let excludedFragments = [
        "charactorpalette", "characterpalette", "pressandhold", "emoji", "handwriting",
        ".ink.", "50onpaletteim", "keyboardviewer", "assistivecontrol", "dictation",
    ]

    /// 能在菜单里选、能自动切过去的：用户加上了、能被选中、是键盘布局或输入模式或没有
    /// 模式的输入法，去掉面板类。按原顺序（系统输入法菜单的顺序），同一个 id 只留第一个。
    public static func selectable(_ all: [InputSourceInfo]) -> [InputSourceInfo] {
        let types: Set<String> = [InputSourceInfo.layoutType, InputSourceInfo.inputModeType,
                                  InputSourceInfo.methodWithoutModesType]
        var seen = Set<String>()
        return all.filter { source in
            let id = source.id.lowercased()
            guard source.enabled, source.selectable, types.contains(source.type), !id.isEmpty,
                  !excludedFragments.contains(where: { id.contains($0) }) else { return false }
            return seen.insert(source.id).inserted
        }
    }

    public static func find(_ id: String?, in sources: [InputSourceInfo]) -> InputSourceInfo? {
        guard let id, !id.isEmpty else { return nil }
        return sources.first { $0.id == id }
    }
}

// MARK: - 设置

/// 没有规则的 App 切过去时怎么办。
public enum InputSourceFallback: String, Codable, CaseIterable, Sendable {
    /// 默认：每次都换成默认输入法。
    case defaultSource
    /// 每个 App 用回离开时的输入法；第一次没有记录时用默认输入法。
    case remember

    public var title: String {
        switch self {
        case .defaultSource: tr("用默认输入法")
        case .remember: tr("记住上次")
        }
    }

    public var caption: String {
        switch self {
        case .defaultSource: tr("切过去时换成下面这个")
        case .remember: tr("每个 App 用回离开时的输入法")
        }
    }
}

/// 切换提示放哪。
public enum InputSourceHintPosition: String, Codable, CaseIterable, Sendable {
    /// 默认：从刘海落下的小胶囊；遇到拾掇的收纳架让位。没有刘海的屏幕放在菜单栏下面。
    case notch
    /// 贴着输入光标；要辅助功能权限，没权限或找不到光标时临时改用刘海下。
    case cursor
    /// 只切换，不提示。
    case off

    public var title: String {
        switch self {
        case .notch: tr("刘海下")
        case .cursor: tr("光标旁")
        case .off: tr("关闭", context: "off")
        }
    }

    public var caption: String {
        switch self {
        case .notch: tr("遇到拾掇的收纳架自动让位")
        case .cursor: tr("需要辅助功能权限")
        case .off: tr("只切换，不提示")
        }
    }

    /// 选这个时要不要显示辅助功能那一行。
    public var needsAccessibility: Bool { self == .cursor }
}

/// 一个 App 的规则：这个 App 的所有窗口共用。
public struct InputSourceRule: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    /// 添加时记下的显示名，App 卸载了也能认出是谁。
    public var appName: String
    public var sourceID: String

    public var id: String { bundleID }

    public init(bundleID: String, appName: String, sourceID: String) {
        self.bundleID = bundleID
        self.appName = appName
        self.sourceID = sourceID
    }
}

/// 设置 ▸ 输入法。总开关默认关。
public struct InputSourceSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    public var fallback: InputSourceFallback = .defaultSource
    /// 默认输入法。没设时是 ABC；装着的里面找不到时退回系统第一个键盘输入法。
    public var defaultSourceID: String = InputSourceCatalog.abcID
    /// 按 App 规则（码头 Pro）。一个 bundle id 一条，按添加顺序。
    public var rules: [InputSourceRule] = []
    public var hint: InputSourceHintPosition = .notch
    /// 提示停留几秒。
    public var seconds: Double = InputSourceSettings.defaultSeconds

    public static let defaultSeconds: Double = 1
    public static let secondChoices: [Double] = [0.5, 1, 1.5, 2, 3]

    /// 秒数写成字：0.5、1、1.5。
    public static func secondsText(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
    }

    public init() {}

    /// 存着的秒数不在选项里时按默认读。
    public var hintSeconds: Double {
        Self.secondChoices.contains(seconds) ? seconds : Self.defaultSeconds
    }

    public func rule(for bundleID: String?) -> InputSourceRule? {
        guard let key = InputSourceSettings.normalized(bundleID) else { return nil }
        return rules.first { InputSourceSettings.normalized($0.bundleID) == key }
    }

    /// 加一条或改一条（同一个 App 只留一条，位置不变）。码头自己不加。
    public mutating func setRule(bundleID: String, appName: String, sourceID: String) {
        guard let key = InputSourceSettings.normalized(bundleID), !InputSourceResolver.isOwn(bundleID),
              !sourceID.isEmpty else { return }
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = rules.firstIndex(where: { InputSourceSettings.normalized($0.bundleID) == key }) {
            rules[index].sourceID = sourceID
            if !name.isEmpty { rules[index].appName = name }
        } else {
            rules.append(InputSourceRule(bundleID: bundleID, appName: name.isEmpty ? bundleID : name,
                                         sourceID: sourceID))
        }
    }

    public mutating func removeRule(bundleID: String) {
        let key = InputSourceSettings.normalized(bundleID)
        rules.removeAll { InputSourceSettings.normalized($0.bundleID) == key }
    }

    static func normalized(_ bundleID: String?) -> String? {
        guard let raw = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        return raw
    }

    private enum CodingKeys: String, CodingKey { case enabled, fallback, defaultSourceID, rules, hint, seconds }

    /// 宽松解码：老状态文件没有这一组、或以后多了认不出的值，都照常读。重复的 App 只留第一条。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        if let raw = try? c.decodeIfPresent(String.self, forKey: .fallback),
           let value = InputSourceFallback(rawValue: raw) { fallback = value }
        if let raw = try? c.decodeIfPresent(String.self, forKey: .defaultSourceID), !raw.isEmpty {
            defaultSourceID = raw
        }
        if let raw = try? c.decodeIfPresent([InputSourceRule].self, forKey: .rules) {
            var seen = Set<String>()
            rules = raw.filter { rule in
                guard let key = InputSourceSettings.normalized(rule.bundleID), !rule.sourceID.isEmpty else { return false }
                return seen.insert(key).inserted
            }
        }
        if let raw = try? c.decodeIfPresent(String.self, forKey: .hint),
           let value = InputSourceHintPosition(rawValue: raw) { hint = value }
        seconds = (try? c.decodeIfPresent(Double.self, forKey: .seconds)) ?? Self.defaultSeconds
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(fallback.rawValue, forKey: .fallback)
        try c.encode(defaultSourceID, forKey: .defaultSourceID)
        try c.encode(rules, forKey: .rules)
        try c.encode(hint.rawValue, forKey: .hint)
        try c.encode(seconds, forKey: .seconds)
    }
}

// MARK: - 记住上次

/// 「记住上次」：按 bundle id 记离开时的输入法。只在本机存（UserDefaults），不进设置文件，
/// 免得每次切 App 都写一遍状态文件。最多记 `limit` 个 App，超出时丢最久没用的。
public struct InputSourceMemory: Codable, Equatable, Sendable {
    public static let limit = 200

    /// 小写的 bundle id → 输入法 id。
    public private(set) var sources: [String: String] = [:]
    /// 最近记的在最后。
    public private(set) var order: [String] = []

    public init() {}

    public mutating func record(_ sourceID: String?, for bundleID: String?) {
        guard let key = InputSourceSettings.normalized(bundleID), let sourceID, !sourceID.isEmpty,
              !InputSourceResolver.isOwn(bundleID) else { return }
        sources[key] = sourceID
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.limit {
            let dropped = order.removeFirst()
            sources[dropped] = nil
        }
    }

    public func source(for bundleID: String?) -> String? {
        guard let key = InputSourceSettings.normalized(bundleID) else { return nil }
        return sources[key]
    }
}

// MARK: - 切到哪个

public enum InputSourceResolver {
    /// 码头自己（正式版和截图工具）。码头被激活时不切，也不记。
    public static let ownBundleIDs: Set<String> = ["com.docket-zh.app", "com.docket-zh.app.shots"]

    public static func isOwn(_ bundleID: String?) -> Bool {
        guard let key = InputSourceSettings.normalized(bundleID) else { return false }
        return ownBundleIDs.contains(key)
    }

    /// 为什么切到这个。
    public enum Reason: Equatable, Sendable {
        /// 按 App 规则。
        case rule
        /// 规则指向的输入法被删了，暂用回退的那个。
        case ruleMissing
        /// 记住上次。
        case remembered
        /// 默认输入法。
        case defaultSource
        /// 默认输入法也没了，系统第一个键盘输入法。
        case firstAvailable
    }

    public struct Target: Equatable, Sendable {
        public var sourceID: String
        public var reason: Reason

        public init(sourceID: String, reason: Reason) {
            self.sourceID = sourceID
            self.reason = reason
        }
    }

    /// 默认输入法：设的那个还在就用它，否则系统第一个键盘输入法。一个都没有时 nil。
    public static func defaultTarget(_ settings: InputSourceSettings, available: [InputSourceInfo]) -> Target? {
        if InputSourceCatalog.find(settings.defaultSourceID, in: available) != nil {
            return Target(sourceID: settings.defaultSourceID, reason: .defaultSource)
        }
        return available.first.map { Target(sourceID: $0.id, reason: .firstAvailable) }
    }

    /// 切到这个 App 时该用哪个输入法。nil 是不切：总开关关着、码头自己、没有可用的输入法。
    ///
    /// 顺序：规则（Pro 解锁时）→ 规则的输入法被删了就用默认输入法 → 没有规则时按「用默认
    /// 输入法」或「记住上次」（第一次没有记录、记的那个被删了都用默认输入法）→ 默认输入法
    /// 也没了用系统第一个键盘输入法。
    public static func target(for bundleID: String?, settings: InputSourceSettings, rulesActive: Bool,
                              memory: InputSourceMemory, available: [InputSourceInfo]) -> Target? {
        guard settings.enabled, !isOwn(bundleID), !available.isEmpty else { return nil }
        if rulesActive, let rule = settings.rule(for: bundleID) {
            if InputSourceCatalog.find(rule.sourceID, in: available) != nil {
                return Target(sourceID: rule.sourceID, reason: .rule)
            }
            return defaultTarget(settings, available: available).map { Target(sourceID: $0.sourceID, reason: .ruleMissing) }
        }
        if settings.fallback == .remember, let remembered = memory.source(for: bundleID),
           InputSourceCatalog.find(remembered, in: available) != nil {
            return Target(sourceID: remembered, reason: .remembered)
        }
        return defaultTarget(settings, available: available)
    }

    /// 要不要真的切：有目标且和现在的不一样。已经是目标输入法时不切，也不提示。
    public static func shouldSwitch(current: String?, target: Target?) -> Bool {
        guard let target else { return false }
        return target.sourceID != current
    }
}

// MARK: - 规则卡片上写什么

public enum InputSourceRuleStatus: Equatable, Sendable {
    /// 输入法还在。
    case ok(InputSourceInfo)
    /// 被删了，暂用 `fallback`（默认输入法或系统第一个）；一个都没有时 nil。装回后自动恢复。
    case missing(fallback: InputSourceInfo?)

    public static func of(_ rule: InputSourceRule, settings: InputSourceSettings,
                          available: [InputSourceInfo]) -> InputSourceRuleStatus {
        if let source = InputSourceCatalog.find(rule.sourceID, in: available) { return .ok(source) }
        let fallback = InputSourceResolver.defaultTarget(settings, available: available)
        return .missing(fallback: InputSourceCatalog.find(fallback?.sourceID, in: available))
    }

    /// 卡片第二行：输入法名，或「已删除，暂用 XX」。
    public var caption: String {
        switch self {
        case .ok(let source): source.name
        case .missing(let fallback?): tr("已删除，暂用 \(fallback.name)")
        case .missing(nil): tr("已删除")
        }
    }

    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}

// MARK: - 字形徽章

/// 徽章的底色，界面那边映射成具体颜色。
public enum InputSourceGlyphTint: String, Sendable, CaseIterable {
    /// 中文：红。
    case chinese
    /// 拉丁字母（ABC、美式、法语等）：石墨灰。
    case latin
    /// 日语：紫。
    case japanese
    /// 韩语：青。
    case korean
    /// 其他文字（西里尔、希腊、阿拉伯、泰文等）：蓝。
    case other
    /// 已删除：灰。
    case missing
}

public struct InputSourceGlyph: Equatable, Sendable {
    /// 徽章上的一个字：拼、A、あ、한 等。
    public var text: String
    public var tint: InputSourceGlyphTint

    public init(_ text: String, _ tint: InputSourceGlyphTint) {
        self.text = text
        self.tint = tint
    }

    public static let missing = InputSourceGlyph("?", .missing)

    /// 按输入法 id 和语言推导。先认 id 里写明的输入方式（拼音、五笔、注音、仓颉、假名、
    /// 片假名、罗马字），再按主语言，最后用名字的第一个字。
    public static func of(_ source: InputSourceInfo) -> InputSourceGlyph {
        let id = source.id.lowercased()
        let language = (source.languages.first ?? "").lowercased()
        let base = language.split(separator: "-").first.map(String.init) ?? language

        // 日语：罗马字（直接打英文）是 A，片假名是ア，其余假名输入是あ。
        if id.contains("kotoeri") || id.contains("japanese") || base == "ja" {
            if id.hasSuffix(".roman") || id.contains("romajityping.roman") || id.contains(".alphanumeric") {
                return InputSourceGlyph("A", .latin)
            }
            if id.contains("katakana") { return InputSourceGlyph("ア", .japanese) }
            return InputSourceGlyph("あ", .japanese)
        }
        if id.contains("korean") || base == "ko" { return InputSourceGlyph("한", .korean) }

        // 中文：按输入方式。
        let chinese = base == "zh" || id.contains("scim") || id.contains("tcim") || id.contains("chinese")
        if chinese || id.contains("pinyin") || id.contains("wubi") || id.contains("zhuyin") || id.contains("cangjie") {
            if id.contains("shuangpin") { return InputSourceGlyph("双", .chinese) }
            // 系统自带的五笔是 SCIM.WBX（五笔型）和 SCIM.WBH（五笔画）。
            if id.contains("wubi") || id.hasSuffix(".wbx") || id.hasSuffix(".wbh") {
                return InputSourceGlyph("五", .chinese)
            }
            if id.contains("zhuyin") || id.contains("bopomofo") { return InputSourceGlyph("注", .chinese) }
            if id.contains("cangjie") { return InputSourceGlyph("仓", .chinese) }
            if id.contains("stroke") || id.contains("bihua") { return InputSourceGlyph("笔", .chinese) }
            if id.contains("handwriting") { return InputSourceGlyph("写", .chinese) }
            if id.contains("pinyin") || id.contains("itabc") || id.contains("sogou")
                || id.contains("wetype") || id.contains("baidu") || id.contains("rime") || id.contains("squirrel") {
                return InputSourceGlyph("拼", .chinese)
            }
            if source.type == InputSourceInfo.layoutType, !chinese { return InputSourceGlyph("A", .latin) }
            return InputSourceGlyph("中", .chinese)
        }

        let scripts: [String: String] = [
            "ru": "Я", "uk": "Я", "be": "Я", "bg": "Я", "sr": "Я", "mk": "Я", "kk": "Я", "mn": "Я",
            "el": "Ω", "ar": "ع", "fa": "ف", "ur": "ع", "he": "א", "yi": "א", "th": "ก",
            "hi": "अ", "mr": "अ", "ne": "अ", "bn": "অ", "ta": "த", "te": "త", "kn": "ಕ",
            "ml": "മ", "gu": "અ", "pa": "ਪ", "km": "ក", "lo": "ກ", "my": "က", "ka": "ა",
            "hy": "Ա", "am": "አ", "bo": "ཀ", "si": "අ", "vi": "Ư",
        ]
        if let glyph = scripts[base] { return InputSourceGlyph(glyph, base == "vi" ? .latin : .other) }

        // 拉丁字母的键盘布局，或说不出语言的布局：A。
        if source.type == InputSourceInfo.layoutType || base.isEmpty || latinLanguages.contains(base) {
            return InputSourceGlyph("A", .latin)
        }
        let first = source.name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        return InputSourceGlyph(first ?? "A", .other)
    }

    static let latinLanguages: Set<String> = [
        "en", "fr", "de", "es", "it", "pt", "nl", "sv", "da", "nb", "nn", "no", "fi", "is", "pl", "cs",
        "sk", "sl", "hr", "hu", "ro", "tr", "et", "lv", "lt", "ga", "cy", "mt", "sq", "az", "id", "ms",
        "tl", "sw", "ca", "eu", "gl", "la", "eo", "haw", "mi", "to", "sm",
    ]
}

// MARK: - 要不要提示、放哪

public enum InputSourceHint {
    /// 落下、收回的时长（秒）。
    public static let dropDuration: Double = 0.25
    public static let retractDuration: Double = 0.2
    /// 减少动态效果时淡入淡出的时长。
    public static let fadeDuration: Double = 0.2

    /// 胶囊：高、字形徽章边长、App 图标边长、左右内边距。
    public static let height: CGFloat = 44
    public static let glyphSize: CGFloat = 28
    public static let iconSize: CGFloat = 26
    /// 没有刘海的外接屏上的小胶囊高度。
    public static let smallHeight: CGFloat = 34
    /// 收纳架展开时刘海右侧那一截的宽度：徽章加 App 图标。
    public static let compactWidth: CGFloat = 64
    /// 接在刘海下时比刘海左右各宽出的总量。
    public static let notchOverhang: CGFloat = 24

    /// 码头自己的刘海内容占着时不提示，不排队：输入法提示是最低一档的灵动提示类。
    /// 全屏 > AI 刘海对话 > 提醒弹窗 > 消息卡 > 灵动提示（音量、亮度、会议）> 输入法提示。
    public struct Occupancy: Equatable, Sendable {
        public var fullscreen: Bool
        public var aiPanelOpen: Bool
        public var reminderShowing: Bool
        public var messageCardExpanded: Bool
        public var islandShowing: Bool

        public init(fullscreen: Bool = false, aiPanelOpen: Bool = false, reminderShowing: Bool = false,
                    messageCardExpanded: Bool = false, islandShowing: Bool = false) {
            self.fullscreen = fullscreen
            self.aiPanelOpen = aiPanelOpen
            self.reminderShowing = reminderShowing
            self.messageCardExpanded = messageCardExpanded
            self.islandShowing = islandShowing
        }

        public var blocked: Bool {
            fullscreen || aiPanelOpen || reminderShowing || messageCardExpanded || islandShowing
        }
    }

    /// 要不要提示：真的切了、提示没关、刘海区没被占着。
    public static func shouldShow(switched: Bool, position: InputSourceHintPosition, occupancy: Occupancy) -> Bool {
        switched && position != .off && !occupancy.blocked
    }

    /// 提示的样子和位置。
    public enum Placement: Equatable, Sendable {
        /// 从刘海落下：顶边在 `top`，`fromNotch` 时正接在刘海下（顶上画黑色过渡）。
        case hang(frame: CGRect, fromNotch: Bool)
        /// 拾掇的收纳架展开着：缩成刘海右侧的一截（菜单栏那一条里），只画徽章和 App 图标。
        case compact(frame: CGRect)
        /// 贴着输入光标。
        case cursor(frame: CGRect)
    }

    /// 实际用哪种位置：光标旁要辅助功能权限，还得读到光标位置，否则临时改用刘海下。
    public static func effectivePosition(_ position: InputSourceHintPosition, trusted: Bool,
                                         caret: CGRect?) -> InputSourceHintPosition {
        switch position {
        case .cursor: (trusted && caret != nil) ? .cursor : .notch
        default: position
        }
    }

    /// 放哪。`width` 是胶囊按内容算出的宽度。光标旁时 `caret` 是光标的位置（AppKit 坐标）。
    ///
    /// 刘海下复用消息灵动岛的让位判断（`NotchMessagePlacement.card` 的「自动让位」）：
    /// 刘海附近有拾掇等刘海 App 的窗口伸下来一点时落在它下面，它的面板（收纳架）展开时
    /// 缩成刘海右侧一截；没有刘海的屏幕放菜单栏下方的小胶囊。
    public static func placement(_ position: InputSourceHintPosition, screen: AINotchScreen,
                                 windows: [NotchForeignWindow], caret: CGRect?, width: CGFloat) -> Placement? {
        switch position {
        case .off:
            return nil
        case .cursor:
            guard let caret else { return placement(.notch, screen: screen, windows: windows, caret: nil, width: width) }
            return .cursor(frame: cursorFrame(caret: caret, screen: screen.frame, width: width))
        case .notch:
            break
        }
        let height = screen.notch == nil ? smallHeight : self.height
        switch NotchMessagePlacement.card(.auto, screen: screen, windows: windows, waited: .infinity) {
        case .hang(let top, let fromNotch):
            // 接在刘海下时至少比刘海宽一点，看起来是从刘海里落下来的。
            let wide = fromNotch ? max(width, (screen.notch?.width ?? 0) + notchOverhang) : width
            // 接在刘海下时顶上多出一条黑色过渡（`AINotchLayout.notchBlendHeight`），内容落在它下面。
            let tall = fromNotch ? height + AINotchLayout.notchBlendHeight : height
            let size = CGSize(width: wide, height: tall)
            return .hang(frame: NotchMessagePlacement.cardFrame(top: top, screen: screen, size: size),
                         fromNotch: fromNotch)
        case .wait, .capsule:
            return .compact(frame: compactFrame(screen: screen, windows: windows))
        }
    }

    /// 刘海右侧那一截：贴着刘海右边、和菜单栏一样高；那里有刘海 App 的窗口时排在它右边。
    /// 没有刘海时在菜单栏下沿正中。
    public static func compactFrame(screen: AINotchScreen, windows: [NotchForeignWindow]) -> CGRect {
        let bar = AINotchLayout.menuBar(of: screen)
        guard let notch = screen.notch else {
            return CGRect(x: screen.frame.midX - compactWidth / 2, y: bar.minY - 4 - smallHeight,
                          width: compactWidth, height: smallHeight)
        }
        var x = notch.maxX
        let band = CGRect(x: notch.maxX, y: bar.minY, width: screen.frame.maxX - notch.maxX, height: bar.height)
        for window in NotchMessagePlacement.neighbors(windows, screen: screen, width: screen.frame.width)
        where window.frame.intersects(band) && window.frame.minY >= bar.minY - 1 {
            x = max(x, window.frame.maxX + NotchMessagePlacement.capsuleGap)
        }
        x = min(x, screen.frame.maxX - compactWidth - NotchMessagePlacement.margin)
        return CGRect(x: x, y: bar.minY, width: compactWidth, height: bar.height)
    }

    /// 光标旁：放在光标下面空 6pt，左边对着光标；下面放不下就放到光标上面，左右收进屏幕。
    public static func cursorFrame(caret: CGRect, screen: CGRect, width: CGFloat) -> CGRect {
        let gap: CGFloat = 6
        let margin = NotchMessagePlacement.margin
        var x = caret.minX - 14
        x = min(max(x, screen.minX + margin), screen.maxX - width - margin)
        var y = caret.minY - gap - height
        if y < screen.minY + margin { y = caret.maxY + gap }
        y = min(y, screen.maxY - height - margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 胶囊宽度：左右内边距 9、徽章、间距 10、名字、间距 12、App 图标、右边 9。
    public static func capsuleWidth(nameWidth: CGFloat) -> CGFloat {
        let name = min(max(nameWidth, 24), 220)
        return 9 + glyphSize + 10 + name + 12 + iconSize + 9
    }
}
