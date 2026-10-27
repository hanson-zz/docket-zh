import Foundation

// MARK: - 桌面卡片 · 数据组（天气、行情、开发、工具）
//
// 钉在桌面的天气、加密货币、自选股、股票、GitHub、Codex 用量、邮件、「算」、翻译、取色器、
// 表情符号不再是放大的扩展栏卡片或塞进卡片里的面板，而是给 160×160 / 340×160 / 340×340
// 专门排的布局（视图在 App 层 `DesktopCardsData`）。这里放纯判断：哪些种类由本组接管、
// 每档显示几条、溢出时写「还有 N」、Codex 小号挑哪个额度、用量柱怎么归一。
//
// 收入三件（Stripe、Paddle、Shopify）不在这里：小组件库里没有它们的条目、也没有数据接口，
// 扩展栏上放不出来，所以钉不出来，做布局也没人看得到。

public enum DesktopCardsDataPlan {
    /// 本组接管的种类：三档都有专属布局（「算」小号沿用原来的直接输入）。
    public static let kinds: Set<WidgetKind> = [
        .weather, .crypto, .watchlist, .stock, .github, .aiUsage, .mail,
        .calculator, .translate, .colorPicker, .emoji,
    ]

    /// 面板比 340 宽、通用展开会被挤窄，但有专属布局，所以照样能钉：股票、自选股。
    public static let widePanelKinds: Set<WidgetKind> = [.stock, .watchlist]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 每档列几条（行情的币 / 股、邮件、仓库、记录、色块、表情、小时）。0 表示这一档不列。
    public static func rows(_ kind: WidgetKind, size: DesktopPinSize) -> Int {
        switch (kind, size) {
        case (.crypto, .small): 1
        case (.crypto, .medium): 3
        case (.crypto, .large): 6
        case (.watchlist, .small): 2
        case (.watchlist, .medium): 4
        case (.watchlist, .large): 7
        case (.stock, .large): 6
        case (.mail, .medium): 2
        case (.mail, .large): 4
        case (.github, .medium): 3
        case (.github, .large): 4
        case (.calculator, .large): 4
        case (.translate, .large): 2
        case (.aiUsage, .large): 2
        case (.weather, .medium): 4
        case (.weather, .large): 6
        case (.colorPicker, .medium): 8
        case (.colorPicker, .large): 12
        case (.emoji, .small): 9
        case (.emoji, .medium): 14
        case (.emoji, .large): 18
        default: 0
        }
    }

    /// 天气大号下面几天预报（今天起）。
    public static let weatherDays = 4

    /// 表情的格子怎么排：小号 3×3，中号 7×2，大号收藏 6×3（下面另有一排最近用过）。
    public static func emojiGrid(_ size: DesktopPinSize) -> (columns: Int, rows: Int) {
        switch size {
        case .small: (3, 3)
        case .medium: (7, 2)
        case .large: (6, 3)
        }
    }

    /// 大号表情下面那排「最近用过」几个。
    public static let emojiRecent = 6

    /// 取色器色块怎么排：中号 4×2，大号 6×2。小号只有最新一个大色块。
    public static func colorGrid(_ size: DesktopPinSize) -> (columns: Int, rows: Int) {
        switch size {
        case .small: (1, 1)
        case .medium: (4, 2)
        case .large: (6, 2)
        }
    }

    /// 列表放得下几条、藏了几条。放不下时最后一格让给「还有 N 条」，所以显示 `capacity - 1`。
    public struct Overflow: Equatable, Sendable {
        public var shown: Int
        public var hidden: Int
        public init(shown: Int, hidden: Int) {
            self.shown = shown
            self.hidden = hidden
        }
    }

    public static func overflow(count: Int, capacity: Int) -> Overflow {
        let count = max(count, 0), capacity = max(capacity, 0)
        guard count > capacity else { return Overflow(shown: count, hidden: 0) }
        guard capacity > 1 else { return Overflow(shown: capacity, hidden: count - capacity) }
        return Overflow(shown: capacity - 1, hidden: count - capacity + 1)
    }

    /// Codex 小号只放一个大圆环：挑用掉最多的那个额度（一样多时取前面的，5 小时在前）。
    public static func featuredWindow(usedFractions: [Double]) -> Int? {
        var best: Int?
        for (index, used) in usedFractions.enumerated() where used.isFinite {
            if let current = best, usedFractions[current] >= used { continue }
            best = index
        }
        return best
    }

    /// Codex 大号最近几天的用量柱：取最后 `count` 天，按其中最多的一天归一到 0...1。
    /// 天数不够时前面补 0；全是 0 时都是 0。
    public static func usageBars(_ tokens: [Int], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let recent = Array(tokens.suffix(count)).map { max($0, 0) }
        let padded = Array(repeating: 0, count: count - recent.count) + recent
        let peak = padded.max() ?? 0
        guard peak > 0 else { return padded.map { _ in 0 } }
        return padded.map { Double($0) / Double(peak) }
    }

    /// 一天温度在几天总范围里的位置（天气大号的温度条）：返回起点和终点，0...1。
    public static func rangeBar(low: Double, high: Double, scaleLow: Double, scaleHigh: Double) -> (start: Double, end: Double) {
        let span = scaleHigh - scaleLow
        guard span > 0, low.isFinite, high.isFinite else { return (0, 1) }
        let a = min(max((low - scaleLow) / span, 0), 1)
        let b = min(max((high - scaleLow) / span, 0), 1)
        return (min(a, b), max(a, b))
    }
}
