import Foundation

/// 小熊猫的竹篮：喝水、习惯、专注三件事，每天按达标几项给小熊猫一片竹叶。
///
/// 内部类型名和小组件的 kind（`perfect-day`）沿用最初的命名，这样已经放上
/// 扩展栏的小组件和已有的 perfect-day.json 都能照常读出来；用户看到的文案
/// 和图形都是码头自己的竹叶、竹篮主题。
///
/// The three sources keep their own logs and know nothing about this:
///
/// - 喝水 is met when a 喝水 widget's day reached its goal (`WaterDay.isMet`,
///   the goal frozen once the day is over, see WaterIntake).
/// - 习惯 is met when every habit, across every 习惯打卡 widget, reached its
///   daily goal that day (`Habit.days`, so a habit done 3 of 8 times is not
///   done yet). With no habits at all it does not take part.
/// - 专注 is met when the minutes in the app's `FocusLog` for the day reach
///   its daily goal (set in the 专注计时 panel, 50 minutes by default). It
///   takes part when a 专注计时 widget is placed somewhere, or when anything
///   was logged that day.
///
/// 喝水 takes part when a 喝水 widget is placed somewhere. An item that does
/// not take part is neither met nor missed.
///
/// The tier, by how many items took part and how many of them were met:
///
/// - every item met, with at least two taking part: 满篮一天, a gold leaf;
/// - two met and one missed (three taking part): 丰收一天, a silver leaf;
/// - exactly one met: 小有收获, a bronze leaf, whatever took part, so a day
///   with only one item to do can never be a gold one;
/// - nothing met, or nothing taking part: no leaf.
///
/// So with two items, both is gold and one is bronze; with one item, met is
/// bronze. Those are the "fewer than three" rules, and `tier` is the one place
/// they are written.
public enum PerfectDayTier: String, CaseIterable, Sendable, Hashable, Comparable, Identifiable {
    case bronze
    case silver
    case gold

    public var id: String { rawValue }

    /// 满篮一天 / 丰收一天 / 小有收获.
    public var title: String {
        switch self {
        case .gold: tr("满篮一天")
        case .silver: tr("丰收一天")
        case .bronze: tr("小有收获")
        }
    }

    /// 金竹叶 / 银竹叶 / 铜竹叶.
    public var leafName: String {
        switch self {
        case .gold: tr("金竹叶")
        case .silver: tr("银竹叶")
        case .bronze: tr("铜竹叶")
        }
    }

    /// Light and deep stops of the leaf, as hex.
    public var hexes: (light: String, deep: String) {
        switch self {
        case .gold: ("#FFE27A", "#D99A12")
        case .silver: ("#F1F4F8", "#98A3B3")
        case .bronze: ("#F3BC8C", "#A9622C")
        }
    }

    private var rank: Int {
        switch self {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        }
    }

    public static func < (lhs: PerfectDayTier, rhs: PerfectDayTier) -> Bool { lhs.rank < rhs.rank }
}

/// The three things a day is judged on, in the order they are stored.
public enum PerfectDayItem: String, CaseIterable, Sendable, Hashable, Identifiable {
    case water
    case habit
    case focus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: tr("喝水")
        case .habit: tr("习惯")
        case .focus: tr("专注")
        }
    }

    public var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .habit: "checkmark"
        case .focus: "timer"
        }
    }

    /// The colour of its little ring, as hex. 竹篮和今日三环共用这一套：喝水青绿、
    /// 专注珊瑚橙、习惯竹黄绿（原来是蓝、绿、紫）。三环的弧从 `hex` 渐变到
    /// `lightHex`，超过 100% 的第二圈用加深一档的 `deepHex`。
    public var hex: String {
        switch self {
        case .water: "#0FA89A"
        case .habit: "#7FB21E"
        case .focus: "#F2603A"
        }
    }

    /// 弧的末端，渐变的浅色一头。
    public var lightHex: String {
        switch self {
        case .water: "#4FD8C4"
        case .habit: "#C4E04A"
        case .focus: "#FFA25C"
        }
    }

    /// 同色加深一档（`hex` 的 80%）：超过 100% 时绕的第二圈。
    public var deepHex: String {
        switch self {
        case .water: "#0C867B"
        case .habit: "#668E18"
        case .focus: "#C24D2E"
        }
    }
}

/// How one item stood on one day.
public enum PerfectDayMark: String, Sendable, Hashable {
    /// Did not take part (no widget, no habits): neither met nor missed.
    case off = "-"
    case missed = "0"
    case met = "1"

    public var takesPart: Bool { self != .off }
}

/// One settled day: how each item stood. The tier is derived, never stored,
/// so a rule change re-reads the history instead of trusting old tiers.
public struct PerfectDayRecord: Equatable, Hashable, Sendable {
    /// `yyyyMMdd`.
    public var key: String
    public var water: PerfectDayMark
    public var habit: PerfectDayMark
    public var focus: PerfectDayMark

    public init(key: String, water: PerfectDayMark = .off, habit: PerfectDayMark = .off,
                focus: PerfectDayMark = .off) {
        self.key = key
        self.water = water
        self.habit = habit
        self.focus = focus
    }

    public func mark(_ item: PerfectDayItem) -> PerfectDayMark {
        switch item {
        case .water: water
        case .habit: habit
        case .focus: focus
        }
    }

    public var marks: [PerfectDayMark] { [water, habit, focus] }
    public var participating: Int { marks.filter(\.takesPart).count }
    public var metCount: Int { marks.filter { $0 == .met }.count }
    public var tier: PerfectDayTier? { PerfectDay.tier(met: metCount, participating: participating) }

    /// `yyyyMMdd|wwf`, one character per item: `1` met, `0` missed, `-` off.
    public var encoded: String { "\(key)|\(water.rawValue)\(habit.rawValue)\(focus.rawValue)" }

    public init?(decoding raw: String) {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, HabitTracker.isDayKey(String(parts[0])) else { return nil }
        let chars = Array(parts[1])
        guard chars.count == 3,
              let w = PerfectDayMark(rawValue: String(chars[0])),
              let h = PerfectDayMark(rawValue: String(chars[1])),
              let f = PerfectDayMark(rawValue: String(chars[2])) else { return nil }
        self.init(key: String(parts[0]), water: w, habit: h, focus: f)
    }
}

/// One item today, as the tile's little ring draws it.
public struct PerfectDayProgress: Equatable, Hashable, Sendable, Identifiable {
    public var item: PerfectDayItem
    public var mark: PerfectDayMark
    /// 0...1 toward met.
    public var fraction: Double
    /// "1200 / 2000 毫升"（喝水小组件设成盎司时按盎司）, "2/3 项", "30/50 分钟", or why it does not count.
    public var detail: String
    /// 今日三环用的原始数：喝了几毫升、打了几项卡、专注几分钟。不计入时是 0。
    public var amount: Int = 0
    /// 对应的目标：毫升、习惯总项数、分钟。不计入时是 0。
    public var goal: Int = 0
    /// 喝水的一杯多少毫升（喝水小组件的 cupSize），其他项是 0。
    public var cupSize: Int = 0
    /// 今天还没完成的习惯名，按习惯打卡里的顺序。
    public var pending: [String] = []
    /// 喝水小组件设成盎司：三环面板的毫升那一行按盎司写（`unit` 为 oz）。
    public var ounces = false

    public var id: String { item.rawValue }

    /// 不封顶的进度：125% 是 1.25。没有目标时退回 `fraction`。
    public var ratio: Double {
        guard mark.takesPart else { return 0 }
        guard goal > 0 else { return max(0, fraction) }
        return max(0, Double(amount) / Double(goal))
    }
}

/// A day as the panel's calendar and frequency strip draw it.
public struct PerfectDayCell: Equatable, Hashable, Sendable {
    public var key: String
    public var date: Date
    public var day: Int
    public var tier: PerfectDayTier?
    public var isToday: Bool
    public var isFuture: Bool

    /// 已过、今天还是还没到：分享图的日历按这个决定画不画叶子。
    public var phase: PerfectDayPhase { isToday ? .today : (isFuture ? .future : .past) }
}

/// 空月分享图上的一行拿叶规则：什么条件给哪一档。
public struct PerfectDayRuleLine: Equatable, Hashable, Sendable, Identifiable {
    public var tier: PerfectDayTier
    public var condition: String

    public var id: PerfectDayTier { tier }
}

/// 日历里一天相对今天的位置。
///
/// - past：已经过去，收到了就是那片叶子，没收到留一片虚线叶；
/// - today：绿色小胶囊，收到了画叶子，还没收到画一片淡虚线叶（今天还在等）；
/// - future：还没到，只写日期不画叶。
public enum PerfectDayPhase: String, Sendable, Hashable {
    case past
    case today
    case future
}

/// 面板「今天」卡片上缺的那一项直接给的小胶囊：没设习惯是「＋ 新习惯」，
/// 没放喝水或专注计时小组件是「＋ 放上去」。
public enum PerfectDayFix: String, Sendable, Hashable {
    case newHabit
    case place

    public var title: String {
        switch self {
        case .newHabit: tr("＋ 新习惯")
        case .place: tr("＋ 放上去")
        }
    }
}

/// Everything 小熊猫的竹篮 keeps, as one small file: the settled days and the
/// badges earned with the day each was earned. Focus minutes are not here:
/// they are the app's one `FocusLog`, kept by `FocusLogStore`.
public struct PerfectDayArchive: Codable, Equatable, Sendable {
    public var days: [String]
    /// Badge id to the `yyyyMMdd` it was earned on. Once in, never out: a
    /// badge is not taken back because old days were trimmed.
    public var earned: [String: String]
    /// 节日徽章 id 到收下它的公历年份。旧存档没有这一项，读出来是空的。
    public var festivalYears: [String: [Int]]
    /// 喝水累计杯数里已经折起来的部分（见 `PerfectBadges.countingCups`）。
    public var cupsFolded: Int
    /// 最近还在喝水记录里的日子各自几杯。
    public var cupDays: [String: Int]

    public init(days: [String] = [], earned: [String: String] = [:], festivalYears: [String: [Int]] = [:],
                cupsFolded: Int = 0, cupDays: [String: Int] = [:]) {
        self.days = days
        self.earned = earned
        self.festivalYears = festivalYears
        self.cupsFolded = cupsFolded
        self.cupDays = cupDays
    }

    /// Lenient like `TimerState`: a missing key is empty, not a thrown error.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String].self, forKey: .days) ?? []
        earned = try c.decodeIfPresent([String: String].self, forKey: .earned) ?? [:]
        festivalYears = (try? c.decodeIfPresent([String: [Int]].self, forKey: .festivalYears)) ?? [:]
        cupsFolded = (try? c.decodeIfPresent(Int.self, forKey: .cupsFolded)) ?? 0
        cupDays = (try? c.decodeIfPresent([String: Int].self, forKey: .cupDays)) ?? [:]
    }

    /// 喝水累计杯数。
    public var cupCount: Int { max(0, cupsFolded) + cupDays.values.reduce(0) { $0 + max(0, $1) } }

    public var records: [PerfectDayRecord] {
        var byKey: [String: PerfectDayRecord] = [:]
        for raw in days { if let record = PerfectDayRecord(decoding: raw) { byKey[record.key] = record } }
        return byKey.values.sorted { $0.key < $1.key }
    }

    public mutating func setRecords(_ records: [PerfectDayRecord]) {
        days = records.sorted { $0.key < $1.key }.map(\.encoded)
    }
}

public enum PerfectDay {
    /// 竹子的绿色：小组件的主题色、面板的底色和分享图的点缀。
    public static let bambooHex = "#4E9A3E"
    /// 竹篮的浅、深两种藤色。
    public static let basketHexes = (light: "#E2B878", deep: "#9A6A34")

    /// Settled days kept: a couple of years of calendar.
    public static let keptDays = 800
    /// How far back a gap (the Mac was off, the app not running) is filled
    /// from the sources' own history. Water keeps 120 days of its own.
    public static let backfillDays = 60

    public static var calendar: Calendar { HabitTracker.calendar }

    // MARK: The rule

    /// See the type's comment for the table.
    public static func tier(met: Int, participating: Int) -> PerfectDayTier? {
        let met = max(0, min(met, participating))
        guard participating > 0, met > 0 else { return nil }
        if met == participating, participating >= 2 { return .gold }
        if met == 2 { return .silver }
        if met == 1 { return .bronze }
        // Three met of three is gold above; nothing else reaches here.
        return nil
    }

    // MARK: Reading the sources

    /// 喝水 on `date`: met if any 喝水 widget met its goal that day (today
    /// against the current goal, earlier days against the goal they had).
    public static func water(_ configs: [WidgetConfig], on date: Date, today: Date,
                             calendar: Calendar = PerfectDay.calendar) -> PerfectDayProgress {
        guard !configs.isEmpty else {
            return PerfectDayProgress(item: .water, mark: .off, fraction: 0, detail: tr("没有放喝水小组件"))
        }
        let key = HabitTracker.dayKey(date, calendar: calendar)
        let isToday = key == HabitTracker.dayKey(today, calendar: calendar)
        // Two 喝水 widgets (one per layout) are the same person drinking:
        // the one furthest along speaks for the day.
        let candidates = configs.map { config -> (day: WaterDay, cup: Int, ounces: Bool) in
            let days = WaterIntake.days(config)
            let goal = WaterIntake.goal(config, now: date, calendar: calendar)
            let cup = WaterIntake.cupSize(config)
            let ounces = WaterIntake.usesOunces(config)
            if isToday { return (WaterIntake.today(days, goal: goal, now: date, calendar: calendar), cup, ounces) }
            return (days.first { $0.key == key } ?? WaterDay(key: key, goal: goal), cup, ounces)
        }
        let best = candidates.max {
            WaterIntake.progress(total: $0.day.total, goal: $0.day.goal)
                < WaterIntake.progress(total: $1.day.total, goal: $1.day.goal)
        } ?? (day: WaterDay(key: key, goal: WaterIntake.defaultGoal), cup: WaterIntake.defaultCup, ounces: false)
        let day = best.day
        return PerfectDayProgress(item: .water, mark: day.isMet ? .met : .missed,
                                  fraction: WaterIntake.progress(total: day.total, goal: day.goal),
                                  detail: WaterIntake.tally(total: day.total, goal: day.goal, ounces: best.ounces),
                                  amount: day.total, goal: day.goal, cupSize: best.cup, ounces: best.ounces)
    }

    /// 习惯 on `date`: every habit of every 习惯打卡 widget checked in. Two
    /// widgets holding the same habit (a copied layout) count it once.
    public static func habits(_ configs: [WidgetConfig], on date: Date,
                              calendar: Calendar = PerfectDay.calendar) -> PerfectDayProgress {
        var seen = Set<String>()
        var all: [Habit] = []
        for config in configs {
            for habit in HabitTracker.habits(config) where !seen.contains(habit.id) {
                seen.insert(habit.id)
                all.append(habit)
            }
        }
        guard !all.isEmpty else {
            return PerfectDayProgress(item: .habit, mark: .off, fraction: 0, detail: tr("还没有设置习惯"))
        }
        let done = HabitTracker.doneToday(all, today: date, calendar: calendar)
        let pending = all.filter { !HabitTracker.isDone($0, on: date, calendar: calendar) }.map(\.name)
        return PerfectDayProgress(item: .habit, mark: done >= all.count ? .met : .missed,
                                  fraction: Double(done) / Double(all.count),
                                  detail: tr("\(done)/\(all.count) 项"),
                                  amount: done, goal: all.count, pending: pending)
    }

    /// 专注 on `date`.
    public static func focus(minutes: Int, goal: Int, hasTimer: Bool) -> PerfectDayProgress {
        guard hasTimer || minutes > 0 else {
            return PerfectDayProgress(item: .focus, mark: .off, fraction: 0, detail: tr("没有放专注计时小组件"))
        }
        let goal = max(1, goal)
        return PerfectDayProgress(item: .focus, mark: minutes >= goal ? .met : .missed,
                                  fraction: min(1, Double(minutes) / Double(goal)),
                                  detail: tr("\(minutes)/\(goal) 分钟"),
                                  amount: max(0, minutes), goal: goal)
    }

    /// The three items on `date`, in order.
    public static func progress(water waterConfigs: [WidgetConfig], habits habitConfigs: [WidgetConfig],
                                focusMinutes: [String: Int], focusGoal: Int, hasTimer: Bool,
                                on date: Date, today: Date,
                                calendar: Calendar = PerfectDay.calendar) -> [PerfectDayProgress] {
        [water(waterConfigs, on: date, today: today, calendar: calendar),
         habits(habitConfigs, on: date, calendar: calendar),
         focus(minutes: focusMinutes[HabitTracker.dayKey(date, calendar: calendar)] ?? 0,
               goal: focusGoal, hasTimer: hasTimer)]
    }

    public static func record(_ progress: [PerfectDayProgress], key: String) -> PerfectDayRecord {
        func mark(_ item: PerfectDayItem) -> PerfectDayMark { progress.first { $0.item == item }?.mark ?? .off }
        return PerfectDayRecord(key: key, water: mark(.water), habit: mark(.habit), focus: mark(.focus))
    }

    // MARK: Settling

    /// The history brought up to `today`.
    ///
    /// - Today and yesterday are always read again from the sources: today
    ///   is still going, and a habit checked in late for yesterday (which
    ///   习惯打卡 allows) should still count.
    /// - Earlier days are frozen as they were settled, so deleting a widget
    ///   or raising a goal never rewrites last month.
    /// - A gap since the last settled day (the app was not running) is filled
    ///   from the sources' own history, at most `backfillDays` back. Nothing
    ///   before the first settled day is filled in: the history starts the
    ///   day the widget was first placed.
    /// - Days older than `keptDays` are dropped.
    public static func settled(_ records: [PerfectDayRecord], today: Date,
                               calendar: Calendar = PerfectDay.calendar,
                               reading: (Date) -> PerfectDayRecord) -> [PerfectDayRecord] {
        var byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
        let start = calendar.startOfDay(for: today)
        let todayKey = HabitTracker.dayKey(start, calendar: calendar)
        let first = records.map(\.key).min() ?? todayKey

        for back in 0...backfillDays {
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { break }
            let key = HabitTracker.dayKey(date, calendar: calendar)
            guard key >= first else { break }
            if back <= 1 || byKey[key] == nil {
                var record = reading(date)
                record.key = key
                byKey[key] = record
            }
        }
        // Nothing is settled ahead of today (a clock set back).
        byKey = byKey.filter { $0.key <= todayKey }
        if let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: start) {
            let key = HabitTracker.dayKey(cutoff, calendar: calendar)
            byKey = byKey.filter { $0.key > key }
        }
        return byKey.values.sorted { $0.key < $1.key }
    }

    // MARK: Months

    /// The settled days of the month containing `month`, keyed by day key.
    public static func monthRecords(_ records: [PerfectDayRecord], month: Date,
                                    calendar: Calendar = PerfectDay.calendar) -> [PerfectDayRecord] {
        let prefix = String(HabitTracker.dayKey(month, calendar: calendar).prefix(6))
        return records.filter { $0.key.hasPrefix(prefix) }
    }

    /// How many of each leaf the month holds.
    public static func counts(_ records: [PerfectDayRecord], month: Date,
                              calendar: Calendar = PerfectDay.calendar) -> [PerfectDayTier: Int] {
        var result: [PerfectDayTier: Int] = [.gold: 0, .silver: 0, .bronze: 0]
        for record in monthRecords(records, month: month, calendar: calendar) {
            if let tier = record.tier { result[tier, default: 0] += 1 }
        }
        return result
    }

    /// The month's leaves in day order: the basket piles them as they were earned.
    public static func leaves(_ records: [PerfectDayRecord], month: Date,
                            calendar: Calendar = PerfectDay.calendar) -> [PerfectDayTier] {
        monthRecords(records, month: month, calendar: calendar).compactMap(\.tier)
    }

    /// Every day of the month, first to last: the frequency strip.
    public static func monthDays(_ records: [PerfectDayRecord], month: Date, today: Date,
                                 calendar: Calendar = PerfectDay.calendar) -> [PerfectDayCell] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
        let todayKey = HabitTracker.dayKey(today, calendar: calendar)
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let key = HabitTracker.dayKey(date, calendar: calendar)
            return PerfectDayCell(key: key, date: date, day: offset + 1,
                                  tier: key > todayKey ? nil : byKey[key]?.tier,
                                  isToday: key == todayKey, isFuture: key > todayKey)
        }
    }

    /// The month as weeks of seven starting on `firstWeekday` (1 Sunday,
    /// 2 Monday, as `Calendar` counts), nil outside the month.
    public static func monthGrid(_ records: [PerfectDayRecord], month: Date, today: Date, firstWeekday: Int,
                                 calendar: Calendar = PerfectDay.calendar) -> [[PerfectDayCell?]] {
        let days = monthDays(records, month: month, today: today, calendar: calendar)
        guard let first = days.first else { return [] }
        let weekStart = min(7, max(1, firstWeekday))
        let lead = (calendar.component(.weekday, from: first.date) - weekStart + 7) % 7
        var cells: [PerfectDayCell?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// 周日 … 周六, rotated to start on `firstWeekday`.
    public static func weekdaySymbols(firstWeekday: Int) -> [String] {
        let names = [tr("日"), tr("一"), tr("二"), tr("三"), tr("四"), tr("五"), tr("六")]
        let start = min(7, max(1, firstWeekday)) - 1
        return (0..<7).map { names[(start + $0) % 7] }
    }

    // MARK: Runs

    /// Consecutive days, ending today, with a leaf. Today without one yet
    /// keeps the run that ended yesterday: the day is not over.
    public static func currentStreak(_ records: [PerfectDayRecord], today: Date,
                                     calendar: Calendar = PerfectDay.calendar) -> Int {
        let leafy = Set(records.filter { $0.tier != nil }.map(\.key))
        var day = calendar.startOfDay(for: today)
        if !leafy.contains(HabitTracker.dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while leafy.contains(HabitTracker.dayKey(day, calendar: calendar)), count <= keptDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The longest run of consecutive calendar days among `keys`.
    public static func longestRun(_ keys: Set<String>, calendar: Calendar = PerfectDay.calendar) -> Int {
        let dates = keys.compactMap { HabitTracker.date(fromKey: $0, calendar: calendar) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }

    // MARK: Words

    /// The tile's line for today.
    public static func headline(_ tier: PerfectDayTier?) -> String {
        tier?.title ?? tr("还没有竹叶")
    }

    /// The panel's line under the headline.
    public static func subline(_ tier: PerfectDayTier?) -> String {
        tier.map { tr("小熊猫收到一片\($0.leafName)") } ?? tr("达标一项，小熊猫就能收到铜竹叶")
    }

    /// 怎么算: the rule in words, for the panel's foot.
    public static func rules(focusGoal: Int) -> String {
        tr("喝水达到当日目标；习惯当天全部完成；专注达到每日目标（\(max(1, focusGoal)) 分钟，在专注计时面板里设置）。")
            + tr("三项全部达标是\(PerfectDayTier.gold.title)（\(PerfectDayTier.gold.leafName)），")
            + tr("差一项是\(PerfectDayTier.silver.title)（\(PerfectDayTier.silver.leafName)），")
            + tr("只达标一项是\(PerfectDayTier.bronze.title)（\(PerfectDayTier.bronze.leafName)）。")
            + tr("没放喝水或专注计时小组件、或没设习惯时，那一项不计入：两项都达标算金竹叶，只达标一项算铜竹叶。")
            + tr("每天的竹叶放进本月的竹篮，记录从放上这个小组件那天开始，按这台 Mac 的本地日历结算。")
    }

    // MARK: Share card

    /// 这个月到今天为止过了几天（含今天）：本月是今天的日期，往月是整月天数，
    /// 还没到的月份是 0。分享图状态行里的「已过 N 天」。
    public static func daysPassed(month: Date, today: Date, calendar: Calendar = PerfectDay.calendar) -> Int {
        monthDays([], month: month, today: today, calendar: calendar).filter { $0.phase != .future }.count
    }

    /// 这个月到今天为止收到几片竹叶。今天之后的日子不算（时钟拨回去时也不会多算）。
    public static func leavesSoFar(_ records: [PerfectDayRecord], month: Date, today: Date,
                                   calendar: Calendar = PerfectDay.calendar) -> Int {
        monthDays(records, month: month, today: today, calendar: calendar).filter { $0.tier != nil }.count
    }

    /// 空月：到今天为止一片竹叶都没收到。
    public static func isEmptyMonth(_ records: [PerfectDayRecord], month: Date, today: Date,
                                    calendar: Calendar = PerfectDay.calendar) -> Bool {
        leavesSoFar(records, month: month, today: today, calendar: calendar) == 0
    }

    /// 分享图的标题，数字两侧留空格："2026 年 10 月的竹篮"。
    public static func shareTitle(_ month: Date, calendar: Calendar = PerfectDay.calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: month)
        return tr("\(c.year ?? 0) 年 \(c.month ?? 0) 月的竹篮")
    }

    /// 分享图竹篮下面那一行："还是空篮子" 或 "篮里 13 片竹叶"。
    public static func basketCaption(leaves: Int) -> String {
        leaves > 0 ? tr("篮里 \(leaves) 片竹叶") : tr("还是空篮子")
    }

    /// 分享图日历上方的一行状态，替代原来的 31 格频率条：
    /// "已过 18 天 · 收到 13 片竹叶"；空的本月再加一句"今天喝杯水，第一片就来了"，
    /// 空的往月只写"已过 31 天 · 收到 0 片"。
    public static func shareStatus(_ records: [PerfectDayRecord], month: Date, today: Date,
                                   calendar: Calendar = PerfectDay.calendar) -> String {
        let passed = daysPassed(month: month, today: today, calendar: calendar)
        let got = leavesSoFar(records, month: month, today: today, calendar: calendar)
        guard got == 0 else { return tr("已过 \(passed) 天 · 收到 \(got) 片竹叶") }
        let line = tr("已过 \(passed) 天 · 收到 0 片")
        guard monthDays([], month: month, today: today, calendar: calendar).contains(where: \.isToday) else {
            return line
        }
        return line + " · " + tr("今天喝杯水，第一片就来了")
    }

    /// 面板分享按钮在空月时的提示（按钮置灰）；有竹叶时为 nil，照常分享。
    public static func shareBlockedHint(_ records: [PerfectDayRecord], month: Date, today: Date,
                                        calendar: Calendar = PerfectDay.calendar) -> String? {
        guard isEmptyMonth(records, month: month, today: today, calendar: calendar) else { return nil }
        let isCurrent = monthDays([], month: month, today: today, calendar: calendar).contains(where: \.isToday)
        return isCurrent ? tr("今天先喝杯水再分享") : tr("这个月没有收到竹叶")
    }

    // MARK: Panel

    /// 面板标题里的月份，数字两侧留空格："2026 年 10 月"。
    public static func panelMonthTitle(_ month: Date, calendar: Calendar = PerfectDay.calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: month)
        return tr("\(c.year ?? 0) 年 \(c.month ?? 0) 月")
    }

    /// 面板竹篮右边的三行图例：每档的名字下面一句拿叶条件，和 `tier` 一致。
    public static var legendLines: [PerfectDayRuleLine] {
        [PerfectDayRuleLine(tier: .gold, condition: tr("三项全达标")),
         PerfectDayRuleLine(tier: .silver, condition: tr("达标两项")),
         PerfectDayRuleLine(tier: .bronze, condition: tr("达标一项"))]
    }

    /// 今天这一项缺了什么：不计入（没设习惯、没放小组件）时给一个小胶囊，
    /// 计入的项目（哪怕还没达标）不给。
    public static func fix(for progress: PerfectDayProgress) -> PerfectDayFix? {
        guard progress.mark == .off else { return nil }
        return progress.item == .habit ? .newHabit : .place
    }

    /// 空月分享图右侧的"每天怎么拿竹叶"：三档各一行，和 `tier` 的规则一一对应。
    public static var shareRuleLines: [PerfectDayRuleLine] {
        [PerfectDayRuleLine(tier: .gold, condition: tr("三项全部达标")),
         PerfectDayRuleLine(tier: .silver, condition: tr("三项达标两项")),
         PerfectDayRuleLine(tier: .bronze, condition: tr("只达标一项"))]
    }

    /// 规则下面的两行小字：不到三项时怎么算（见 `tier`）。
    public static var shareRuleNotes: [String] {
        [tr("只开了两项：都达标也是金叶"), tr("只开了一项：达标算铜叶")]
    }

    /// "2026年10月".
    public static func monthTitle(_ month: Date, calendar: Calendar = PerfectDay.calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: month)
        return tr("\(c.year ?? 0)年\(c.month ?? 0)月")
    }

    /// A believable month for the library and the screenshots: leaves on most
    /// days so far, three items taking part.
    public static func sample(today: Date, calendar: Calendar = PerfectDay.calendar) -> [PerfectDayRecord] {
        let pattern: [(PerfectDayMark, PerfectDayMark, PerfectDayMark)] = [
            (.met, .met, .met), (.met, .met, .missed), (.met, .missed, .missed), (.met, .met, .met),
            (.missed, .missed, .missed), (.met, .met, .met), (.met, .missed, .met),
        ]
        let start = calendar.startOfDay(for: today)
        let day = calendar.component(.day, from: start)
        return (0..<max(1, day)).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let p = pattern[back % pattern.count]
            return PerfectDayRecord(key: HabitTracker.dayKey(date, calendar: calendar),
                                    water: p.0, habit: p.1, focus: p.2)
        }
    }
}
