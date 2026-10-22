import Foundation

/// 小熊猫的竹篮的两种样式：竹篮（默认，原来的竹叶和月度竹篮）和今日三环。
/// 存在小组件 config 的 `basketStyle` 里，没存过的老卡片是竹篮。
public enum PerfectDayStyle: String, CaseIterable, Sendable {
    case basket, rings

    public var title: String {
        switch self {
        case .basket: tr("竹篮")
        case .rings: tr("三环")
        }
    }
}

/// 三环样式的卡片大小：小卡（三环 + 百分比）和中卡（三环 + 右边三项数字）。
public enum TodayRingsCard: String, CaseIterable, Sendable {
    case small, medium

    public var title: String {
        switch self {
        case .small: tr("小")
        case .medium: tr("中")
        }
    }
}

/// 一圈弧画到哪里：第一圈 0...1，超过 100% 的部分同色加深从起点再绕第二圈，
/// 第二圈最多也是一整圈（200% 以上不再画第三圈）。
public struct TodayRingLaps: Equatable, Sendable {
    public var first: Double
    public var second: Double

    public init(first: Double, second: Double) {
        self.first = first
        self.second = second
    }
}

/// 近 7 天里的一天：全满的日子点亮成那天的竹叶。
public struct TodayRingsDay: Equatable, Sendable, Identifiable {
    public var key: String
    public var date: Date
    /// 星期几的一个字，今天写「今天」。
    public var label: String
    public var isToday: Bool
    /// 这一天的记录（没有记录时为 nil：小组件还没放上，或那天码头没开）。
    public var record: PerfectDayRecord?

    public var id: String { key }
    /// 参加的几项全部达标：点亮成竹叶。
    public var isFull: Bool { record.map { TodayRings.isFull($0) } ?? false }
    /// 点亮时画哪一档竹叶，按竹篮现有的发叶规则。
    public var leaf: PerfectDayTier? { isFull ? record?.tier : nil }
}

/// 今日三环：竹篮的另一种外观，同一份数据（`PerfectDayProgress`、`PerfectDayRecord`），
/// 不新增小组件种类。这里放三环要的纯逻辑：杯数换算、超 100% 的圈数、
/// 百分比、连续全满天数和面板上的几句话。
///
/// - 喝水以杯数为主：今天喝的毫升 ÷ 喝水小组件的一杯（cupSize，默认 250 毫升），
///   毫升写在下面一行。
/// - 专注：今天的分钟 ÷ 每日目标；习惯：今天完成的项数 ÷ 总项数。
/// - 中间的百分比：参加的几项各自封顶 100% 后取平均。
/// - 全满：参加的几项全部达标（至少一项参加），按竹篮的规则得到对应的竹叶。
public enum TodayRings {
    public static let styleKey = "basketStyle"
    public static let cardKey = "ringsCard"

    /// 从外到内：喝水、专注、习惯。
    public static let order: [PerfectDayItem] = [.water, .focus, .habit]
    /// 弧张开的角度：约 270°，开口朝下。
    public static let sweep = 270.0
    /// 起点在左下（从 3 点钟方向顺时针 135°），顺时针绕到右下。
    public static let startAngle = 135.0

    public static func style(_ config: WidgetConfig) -> PerfectDayStyle {
        PerfectDayStyle(rawValue: config.string(styleKey, default: PerfectDayStyle.basket.rawValue)) ?? .basket
    }

    public static func card(_ config: WidgetConfig) -> TodayRingsCard {
        TodayRingsCard(rawValue: config.string(cardKey, default: TodayRingsCard.small.rawValue)) ?? .small
    }

    public static func isRings(_ config: WidgetConfig) -> Bool { style(config) == .rings }

    /// 扩展栏横排时卡片的宽：小卡 168，中卡 320。高度和别的卡片一样。
    public static func tileWidth(_ config: WidgetConfig) -> Double {
        card(config) == .medium ? 320 : 168
    }

    /// 竖排时的高度：三环加一行百分比。
    public static let columnHeight: Double = 88

    // MARK: Laps

    public static func laps(_ ratio: Double) -> TodayRingLaps {
        guard ratio.isFinite, ratio > 0 else { return TodayRingLaps(first: 0, second: 0) }
        return TodayRingLaps(first: min(1, ratio), second: min(1, max(0, ratio - 1)))
    }

    // MARK: Cups

    /// 喝了几杯：不满一杯不算（1.9 杯写 1 杯）。
    public static func cups(ml: Int, cupSize: Int) -> Int {
        guard cupSize > 0, ml > 0 else { return 0 }
        return ml / cupSize
    }

    /// 目标几杯：四舍五入，至少 1 杯（2000 毫升、一杯 250 是 8 杯；一杯 300 是 7 杯）。
    public static func goalCups(goal: Int, cupSize: Int) -> Int {
        guard cupSize > 0, goal > 0 else { return 0 }
        return max(1, Int((Double(goal) / Double(cupSize)).rounded()))
    }

    /// 卡片和面板上写的「喝了几杯 / 目标几杯」。目标四舍五入后可能和毫升差一点，
    /// 这里让两者对得上：按毫升已达标时杯数至少写到目标，没达标时最多写到目标少一杯，
    /// 不会出现「8 / 8 杯」却没达标、或达标了却只有「7 / 8 杯」。
    public static func shownCups(ml: Int, goal: Int, cupSize: Int) -> (cups: Int, goal: Int) {
        let target = goalCups(goal: goal, cupSize: cupSize)
        var drunk = cups(ml: ml, cupSize: cupSize)
        guard target > 0 else { return (drunk, 0) }
        if ml >= goal { drunk = max(drunk, target) } else { drunk = min(drunk, target - 1) }
        return (max(0, drunk), target)
    }

    public static func shownCups(_ progress: PerfectDayProgress) -> (cups: Int, goal: Int) {
        let cup = progress.cupSize > 0 ? progress.cupSize : WaterIntake.defaultCup
        return shownCups(ml: progress.amount, goal: progress.goal, cupSize: cup)
    }

    // MARK: Percent

    /// 一项的百分比，不封顶：125% 写 125。
    public static func percent(_ progress: PerfectDayProgress) -> Int {
        Int((progress.ratio * 100).rounded())
    }

    /// 中间的百分比：参加的几项各自封顶 100% 后取平均，一项都不参加时是 0。
    public static func percent(_ items: [PerfectDayProgress]) -> Int {
        let taking = items.filter { $0.mark.takesPart }
        guard !taking.isEmpty else { return 0 }
        let sum = taking.reduce(0.0) { $0 + min(1, $1.ratio) }
        return Int((sum / Double(taking.count) * 100).rounded())
    }

    // MARK: Full

    public static func isFull(_ record: PerfectDayRecord) -> Bool {
        record.participating > 0 && record.metCount == record.participating
    }

    public static func isFull(_ items: [PerfectDayProgress]) -> Bool {
        isFull(PerfectDay.record(items, key: ""))
    }

    /// 参加了还没达标的几环。
    public static func ringsLeft(_ items: [PerfectDayProgress]) -> Int {
        items.filter { $0.mark == .missed }.count
    }

    /// 连续几天全满，到今天为止。今天还没满时接着算到昨天的那一串：今天还没过完。
    public static func fullStreak(_ records: [PerfectDayRecord], today: Date,
                                  calendar: Calendar = PerfectDay.calendar) -> Int {
        let full = Set(records.filter { isFull($0) }.map(\.key))
        var day = calendar.startOfDay(for: today)
        if !full.contains(HabitTracker.dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while full.contains(HabitTracker.dayKey(day, calendar: calendar)), count <= PerfectDay.keptDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// 近 7 天，从六天前到今天。
    public static func week(_ records: [PerfectDayRecord], today: Date,
                            calendar: Calendar = PerfectDay.calendar) -> [TodayRingsDay] {
        let byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
        let start = calendar.startOfDay(for: today)
        let names = [tr("日"), tr("一"), tr("二"), tr("三"), tr("四"), tr("五"), tr("六")]
        return (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let key = HabitTracker.dayKey(date, calendar: calendar)
            let weekday = calendar.component(.weekday, from: date)
            return TodayRingsDay(key: key, date: date,
                                 label: back == 0 ? tr("今天") : names[(weekday - 1) % 7],
                                 isToday: back == 0, record: byKey[key])
        }
    }

    // MARK: Words

    /// 面板右上角的小胶囊："全部达标" 或 "1 / 3 达标"。
    public static func status(_ items: [PerfectDayProgress]) -> String {
        let taking = items.filter { $0.mark.takesPart }
        if isFull(items) { return tr("全部达标") }
        let met = taking.filter { $0.mark == .met }.count
        return tr("\(met) / \(taking.count) 达标")
    }

    /// 小卡百分比下面一行："全满"、"还差 2 环"。
    public static func cardCaption(_ items: [PerfectDayProgress]) -> String {
        if isFull(items) { return tr("全满") }
        let left = ringsLeft(items)
        return left > 0 ? tr("还差 \(left) 环") : tr("还没有可计的环")
    }

    /// 一项还差多少："喝水 2 杯"、"专注 15 分钟"、"习惯 1 项"。达标或不计入时为 nil。
    public static func shortfall(_ progress: PerfectDayProgress) -> String? {
        guard progress.mark == .missed else { return nil }
        switch progress.item {
        case .water:
            let cups = shownCups(progress)
            return tr("喝水 \(max(1, cups.goal - cups.cups)) 杯")
        case .focus:
            return tr("专注 \(max(1, progress.goal - progress.amount)) 分钟")
        case .habit:
            return tr("习惯 \(max(1, progress.goal - progress.amount)) 项")
        }
    }

    /// 三环下面那一句：还差什么，全满时是庆祝行（见 `celebration`）。
    public static func remainingLine(_ items: [PerfectDayProgress]) -> String {
        let parts = order.compactMap { item in items.first { $0.item == item }.flatMap(shortfall) }
        if parts.isEmpty {
            return items.contains { $0.mark.takesPart } ? tr("今天三环全满") : tr("放上喝水、专注计时或习惯打卡小组件就能开始")
        }
        return tr("还差\(parts.joined(separator: tr("、")))")
    }

    /// 全满那天的庆祝行，竹叶按竹篮的发叶规则："今天三环全满 · 得到一片金竹叶"。
    /// 只有两项参加时写「两环」，一项写「一环」（一项只能得铜竹叶）。没全满时为 nil。
    public static func celebration(_ items: [PerfectDayProgress]) -> String? {
        let record = PerfectDay.record(items, key: "")
        guard isFull(record), let tier = record.tier else { return nil }
        switch record.participating {
        case 3: return tr("今天三环全满 · 得到一片\(tier.leafName)")
        case 2: return tr("今天两环全满 · 得到一片\(tier.leafName)")
        default: return tr("今天一环全满 · 得到一片\(tier.leafName)")
        }
    }

    /// 面板一行的数字："10" 和 "/ 8 杯"、"35" 和 "/ 50 分钟"、"2" 和 "/ 3 项"。
    public static func figure(_ progress: PerfectDayProgress) -> (value: String, unit: String) {
        guard progress.mark.takesPart else { return ("", tr("未计入")) }
        switch progress.item {
        case .water:
            let cups = shownCups(progress)
            return ("\(cups.cups)", tr("/ \(cups.goal) 杯"))
        case .focus:
            return ("\(progress.amount)", tr("/ \(progress.goal) 分钟"))
        case .habit:
            return ("\(progress.amount)", tr("/ \(progress.goal) 项"))
        }
    }

    /// 面板一行的第二行：喝水写毫升，专注写还差或超出几分钟，习惯写还差哪一项。
    /// 不计入时写原因（没放小组件、没设习惯）。
    public static func note(_ progress: PerfectDayProgress) -> String {
        guard progress.mark.takesPart else { return progress.detail }
        switch progress.item {
        case .water:
            return tr("\(progress.amount) / \(progress.goal) 毫升")
        case .focus:
            let diff = progress.amount - progress.goal
            if diff < 0 { return tr("还差 \(-diff) 分钟") }
            return diff == 0 ? tr("刚好达标") : tr("超出 \(diff) 分钟")
        case .habit:
            guard let first = progress.pending.first, progress.mark == .missed else { return tr("全部打卡") }
            return progress.pending.count == 1 ? tr("还差「\(first)」") : tr("还差「\(first)」等 \(progress.pending.count) 项")
        }
    }

    /// 三环的示例：喝水超额绕第二圈、专注 70%、习惯 2/3（库里的卡片和截图用）。
    public static let sample: [PerfectDayProgress] = [
        PerfectDayProgress(item: .water, mark: .met, fraction: 1, detail: tr("2500/2000 毫升"),
                           amount: 2500, goal: 2000, cupSize: 250),
        PerfectDayProgress(item: .habit, mark: .missed, fraction: 2.0 / 3.0, detail: tr("2/3 项"),
                           amount: 2, goal: 3, pending: [tr("读书")]),
        PerfectDayProgress(item: .focus, mark: .missed, fraction: 0.7, detail: tr("35/50 分钟"),
                           amount: 35, goal: 50),
    ]
}
