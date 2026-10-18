import Foundation

/// 喝水面板的「今天」页：杯子是主角，角色站在杯子旁边，两者的水位都是今天
/// 的进度。角色身上照旧是原来的灰/彩水位效果（水面以下全彩，以上去饱和
/// 发灰，中间一条白色波浪水面，见 WaterPanda），表情照旧按 `WaterMood`
/// 切换，渴成骷髅照旧按 `WaterParched`。
///
/// 这里放面板和卡片共用、不依赖界面的那部分：三只杯量按钮、还差几杯、
/// 今天时间轴的刻度和位置、记录默认显示几条、什么时候画骷髅、静止水面
/// 的相位。
public enum WaterCupPage {

    // MARK: 三只杯量按钮

    public enum CupSize: String, CaseIterable, Sendable {
        case small, cup, large

        public var title: String {
            switch self {
            case .small: tr("小杯")
            case .cup: tr("一杯")
            case .large: tr("大杯")
            }
        }
    }

    public struct CupButton: Equatable, Sendable {
        public var size: CupSize
        public var amount: Int
    }

    /// 小杯 100、一杯（设置里的一杯容量，默认 250）、大杯 500。一杯本身就
    /// 很小或很大时，另外两只跟着让开，三只按钮的量总是从小到大、互不相同。
    public static func cupButtons(cup: Int) -> [CupButton] {
        let cup = min(WaterIntake.cupRange.upperBound, max(WaterIntake.cupRange.lowerBound, cup))
        let small = cup > 100 ? 100 : max(25, cup / 2)
        let large = cup < 500 ? 500 : min(2000, cup * 2)
        return [CupButton(size: .small, amount: small),
                CupButton(size: .cup, amount: cup),
                CupButton(size: .large, amount: large)]
    }

    // MARK: 还差几杯

    /// 按一杯的容量还差几杯，向上取整；达标后是 0。
    public static func cupsLeft(total: Int, goal: Int, cup: Int) -> Int {
        guard cup > 0, goal > total else { return 0 }
        return (goal - total + cup - 1) / cup
    }

    /// 一整天要几杯才达标，向上取整。
    public static func cupsToGoal(goal: Int, cup: Int) -> Int {
        guard cup > 0, goal > 0 else { return 0 }
        return (goal + cup - 1) / cup
    }

    // MARK: 角色

    /// 渴成骷髅时画骷髅，但刚喝下的那几秒先举着杯子（和卡片一样）。
    public static func showsSkeleton(parched: Bool, mood: WaterMood) -> Bool {
        parched && mood != .drink
    }

    /// 卡片上的水面不随时间动（扩展栏一整天不重画），相位跟着水位走：
    /// 涨水的那半秒里水位在过渡，水面的波也跟着漂一段，停下就静止。
    public static func restingPhase(level: Double) -> Double {
        0.3 + min(1, max(0, level)) * 4.5
    }

    // MARK: 今天时间轴

    /// 时间轴的范围，都是当天零点起的分钟数，整点对齐。
    public struct Axis: Equatable, Sendable {
        public var start: Int
        public var end: Int
        /// 标在下面的整点（分钟数）。
        public var ticks: [Int]

        /// 0...1，超出范围的夹到两头。
        public func fraction(_ minute: Int) -> Double {
            guard end > start else { return 0 }
            return min(1, max(0, Double(minute - start) / Double(end - start)))
        }
    }

    /// 最短跨度，免得一大早只有一杯时几个点挤在一起。
    public static let minimumSpan = 6 * 60

    /// 默认是提醒时段（比如 09 到 21），装得下今天的每一杯、现在和下次
    /// 提醒；时段是一整天（结束不晚于开始）时从 0 点到 24 点。
    public static func axis(window: WaterReminder, entries: [Int], now: Int?, next: Int?) -> Axis {
        let whole = window.end <= window.start
        var low = whole ? 0 : window.start
        var high = whole ? 1440 : window.end
        for minute in entries + [now, next].compactMap({ $0 }) {
            low = min(low, minute)
            high = max(high, minute)
        }
        low = max(0, (low / 60) * 60)
        high = min(1440, ((high + 59) / 60) * 60)
        if high - low < minimumSpan {
            high = min(1440, low + minimumSpan)
            low = max(0, high - minimumSpan)
        }
        let span = high - low
        let step = span <= 12 * 60 ? 120 : span <= 18 * 60 ? 180 : 240
        let ticks = Array(stride(from: low, through: high, by: step))
        return Axis(start: low, end: high, ticks: ticks)
    }

    /// 刻度上的字：两位数的小时，“09”“24”。
    public static func tickLabel(_ minute: Int) -> String {
        String(format: "%02d", minute / 60)
    }

    // MARK: 记录

    /// 收起时显示最新的几条。
    public static let collapsedRows = 3

    /// 显示几条：收起时最多 `collapsedRows` 条，展开时全部。
    public static func shownRows(count: Int, expanded: Bool) -> Int {
        expanded ? max(0, count) : min(max(0, count), collapsedRows)
    }

    /// 要不要出现“展开全部 N 条”。
    public static func canExpand(count: Int) -> Bool { count > collapsedRows }
}
