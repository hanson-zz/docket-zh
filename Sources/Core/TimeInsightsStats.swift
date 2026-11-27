import Foundation

// MARK: - 时间洞察 · 统计
//
// 主面板和「完整统计」窗口要的数：分类固定色、24 小时堆叠柱、较昨日变化、占比、
// 周和月的按天汇总与排行、历史按日列表。全部从真实的 `ActivitySession` 算，
// 没有数据就是空，不补示例数字。纯逻辑，测试直接编译。

// MARK: 分类颜色

public extension TimeInsightsCategory {
    /// 图表、图例、标签统一用的分类固定色。不用大面积蓝色：开发是沉静的蓝，
    /// 其余各自一色，未分类是中性灰。
    var colorHex: String {
        switch self {
        case .development: "#4A8EF1"
        case .design: "#A18CE6"
        case .learning: "#51B7DB"
        case .communication: "#48B99A"
        case .entertainment: "#E46BA2"
        case .other: "#F2B84D"
        case .uncategorized: "#A5ACB9"
        }
    }
}

/// 一个分类一共多久。
public struct TimeInsightsCategoryUsage: Equatable, Sendable, Identifiable {
    public var category: TimeInsightsCategory
    public var active: TimeInterval
    public var id: String { category.rawValue }

    public init(category: TimeInsightsCategory, active: TimeInterval) {
        self.category = category
        self.active = active
    }
}

public extension TimeInsightsDay {
    /// 有数据的分类，从多到少；一样多时按分类本身的顺序。
    var categoryRanking: [TimeInsightsCategoryUsage] {
        TimeInsightsStats.ranking(categories)
    }
}

// MARK: 24 小时堆叠柱

/// 柱状图里的一小段：某个小时里某个分类（或某个 App）占了多少。
public struct TimeInsightsHourSlice: Equatable, Sendable, Identifiable {
    public var hour: Int
    /// 分类的 rawValue，或 App 的 bundle ID，或「其他应用」的 `TimeInsightsChart.restKey`。
    public var key: String
    public var label: String
    public var seconds: TimeInterval
    public var colorHex: String
    /// 同一根柱子里从下往上的顺序。
    public var order: Int
    public var id: String { "\(hour)-\(key)" }

    public init(hour: Int, key: String, label: String, seconds: TimeInterval, colorHex: String, order: Int) {
        self.hour = hour
        self.key = key
        self.label = label
        self.seconds = seconds
        self.colorHex = colorHex
        self.order = order
    }
}

/// 图例里的一项。
public struct TimeInsightsLegendItem: Equatable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var colorHex: String
    public var seconds: TimeInterval
    public var id: String { key }

    public init(key: String, label: String, colorHex: String, seconds: TimeInterval) {
        self.key = key
        self.label = label
        self.colorHex = colorHex
        self.seconds = seconds
    }
}

public enum TimeInsightsChart {
    public enum Mode: String, CaseIterable, Sendable {
        case category
        case app
    }

    /// 按应用堆叠时单独画几个 App，其余并成「其他应用」。
    public static let appSeries = 5
    public static let restKey = "__rest__"
    /// 按应用堆叠时 App 的颜色（按排名取），和分类色区分开，也不用大面积蓝。
    public static let appPalette = ["#4A7BD8", "#3FAE6A", "#E2A23C", "#8E6FD8", "#E0679A"]
    public static let restColor = "#A9AFBB"

    /// 按分类堆叠：每个小时每个有数据的分类一段，分类按固定顺序从下往上。
    public static func byCategory(_ day: TimeInsightsDay) -> [TimeInsightsHourSlice] {
        var out: [TimeInsightsHourSlice] = []
        for hour in 0..<24 {
            for (order, category) in TimeInsightsCategory.allCases.enumerated() {
                let seconds = day.hourCategories[category]?[hour] ?? 0
                guard seconds > 0 else { continue }
                out.append(TimeInsightsHourSlice(hour: hour, key: category.rawValue, label: category.title,
                                                 seconds: seconds, colorHex: category.colorHex, order: order))
            }
        }
        return out
    }

    /// 按应用堆叠：当天前 `appSeries` 个 App 各一色，其余并成一段「其他应用」。
    public static func byApp(_ day: TimeInsightsDay, restLabel: String) -> [TimeInsightsHourSlice] {
        let top = Array(day.apps.prefix(appSeries))
        let topIDs = Set(top.map(\.bundleID))
        var out: [TimeInsightsHourSlice] = []
        for hour in 0..<24 {
            for (order, usage) in top.enumerated() {
                let seconds = day.hourApps[usage.bundleID]?[hour] ?? 0
                guard seconds > 0 else { continue }
                out.append(TimeInsightsHourSlice(hour: hour, key: usage.bundleID, label: usage.appName,
                                                 seconds: seconds, colorHex: appPalette[order % appPalette.count],
                                                 order: order))
            }
            let rest = day.hourApps.filter { !topIDs.contains($0.key) }.reduce(0) { $0 + $1.value[hour] }
            if rest > 0 {
                out.append(TimeInsightsHourSlice(hour: hour, key: restKey, label: restLabel, seconds: rest,
                                                 colorHex: restColor, order: top.count))
            }
        }
        return out
    }

    /// 图例：有数据的分类（或 App），各自一共多久，从多到少。
    public static func legend(_ slices: [TimeInsightsHourSlice]) -> [TimeInsightsLegendItem] {
        var items: [String: TimeInsightsLegendItem] = [:]
        var order: [String: Int] = [:]
        for slice in slices {
            var item = items[slice.key] ?? TimeInsightsLegendItem(key: slice.key, label: slice.label,
                                                                  colorHex: slice.colorHex, seconds: 0)
            item.seconds += slice.seconds
            items[slice.key] = item
            order[slice.key] = slice.order
        }
        return items.values.sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds : (order[$0.key] ?? 0) < (order[$1.key] ?? 0)
        }
    }

    /// 纵轴上限（分钟）：最高那根柱子向上取到 15 的倍数，最少 15，最多 60。
    public static func axisMinutes(_ slices: [TimeInsightsHourSlice]) -> Int {
        var perHour = Array(repeating: 0.0, count: 24)
        for slice in slices where (0..<24).contains(slice.hour) { perHour[slice.hour] += slice.seconds }
        let peak = (perHour.max() ?? 0) / 60
        let step = 15.0
        return Int(min(60, max(step, (peak / step).rounded(.up) * step)))
    }
}

// MARK: 应用活动片段（Pro 小范围钻取）

public enum TimeInsightsActivityDetail {
    /// 所有应用先统一去重、再裁切所选周期，最后筛选指定 App。
    /// 和主统计使用相同的去重口径，避免应用图表比总览多算重叠片段。
    public static func matchingSessions(_ sessions: [ActivitySession], bundleID: String,
                                        interval: DateInterval) -> [ActivitySession] {
        guard !TimeInsightsDefaults.alwaysSkipped.contains(bundleID) else { return [] }
        let clean = TimeInsightsMath.normalized(
            sessions.filter { !TimeInsightsDefaults.alwaysSkipped.contains($0.bundleID) }
        )
        return TimeInsightsMath.clipped(clean, to: interval)
            .filter { $0.bundleID == bundleID }
    }

    /// 最近 `limit` 个有效活跃片段（不含无操作的前台停留）。默认不读取
    /// 窗口标题、域名，且在返回界面前清空这些敏感字段。
    public static func recentSessions(_ sessions: [ActivitySession], bundleID: String,
                                      interval: DateInterval, limit: Int = 8,
                                      includeTitles: Bool = false) -> [ActivitySession] {
        guard limit > 0 else { return [] }
        return matchingSessions(sessions, bundleID: bundleID, interval: interval)
            .filter { $0.source.isActive }
            .sorted { $0.start != $1.start ? $0.start > $1.start : $0.id > $1.id }
            .prefix(limit)
            .map { segment in
                var safe = segment
                // 旧数据库里可能含未脱敏内容：展示之前再次过滤。
                safe.windowTitle = includeTitles && TimeInsightsTitlePrivacy.allows(bundleID: segment.bundleID)
                    ? TimeInsightsTitlePrivacy.sanitize(segment.windowTitle) : nil
                safe.domain = nil
                return safe
            }
    }
}

// MARK: 较昨日、占比

public enum TimeInsightsStats {
    /// 较昨日的变化比例（0.12 是多了 12%）。昨天没有任何有效活跃（没装、没放卡片、
    /// 暂停了一整天）时 nil，界面上就不写较昨日，不拿 0 去比。
    public static func change(today: TimeInterval, yesterday: TimeInsightsDay?) -> Double? {
        guard let yesterday, yesterday.active >= 60 else { return nil }
        return (today - yesterday.active) / yesterday.active
    }

    /// 「+12%」「-5%」「持平」。
    public static func changeText(_ change: Double) -> String {
        let percent = Int((change * 100).rounded())
        if percent == 0 { return tr("持平") }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    /// `part` 占 `total` 的百分比（四舍五入的整数）；`total` 为 0 时是 0。
    public static func percent(_ part: TimeInterval, of total: TimeInterval) -> Int {
        guard total > 0 else { return 0 }
        return Int((max(0, part) / total * 100).rounded())
    }

    /// 分类按时长从多到少排，没有时长的不列。
    public static func ranking(_ categories: [TimeInsightsCategory: TimeInterval]) -> [TimeInsightsCategoryUsage] {
        let order = Dictionary(uniqueKeysWithValues: TimeInsightsCategory.allCases.enumerated().map { pair in (pair.element, pair.offset) })
        return categories
            .filter { $0.value > 0 }
            .map { TimeInsightsCategoryUsage(category: $0.key, active: $0.value) }
            .sorted { $0.active != $1.active ? $0.active > $1.active
                : (order[$0.category] ?? 0) < (order[$1.category] ?? 0) }
    }
}

// MARK: 周、月、历史

/// 一段时间（一周、一个月、最近几天）按天的汇总和排行。
public struct TimeInsightsPeriod: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case week
        case month
    }

    /// 一天的合计。
    public struct DayTotal: Equatable, Sendable, Identifiable {
        public var date: Date
        public var active: TimeInterval
        public var foreground: TimeInterval
        public var work: TimeInterval
        public var other: TimeInterval
        public var uncategorized: TimeInterval
        public var categories: [TimeInsightsCategory: TimeInterval]
        public var topApp: TimeInsightsAppUsage?
        public var id: Date { date }

        public var hasData: Bool { foreground > 0 }
    }

    public var interval: DateInterval
    /// 每天一项，从早到晚，没有数据的日子也在（合计是 0）。
    public var days: [DayTotal]
    public var apps: [TimeInsightsAppUsage]
    public var categories: [TimeInsightsCategoryUsage]
    public var active: TimeInterval
    public var work: TimeInterval
    public var uncategorized: TimeInterval

    /// 有记录的天数。
    public var activeDays: Int { days.filter { $0.active > 0 }.count }

    /// 有记录的那些天平均每天多久。
    public var averagePerActiveDay: TimeInterval {
        activeDays > 0 ? active / Double(activeDays) : 0
    }

    public var isEmpty: Bool { active <= 0 }

    /// 一周从星期一开始；月是日历月。
    public static func interval(_ kind: Kind, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        switch kind {
        case .week:
            if let week = cal.dateInterval(of: .weekOfYear, for: date) { return week }
        case .month:
            if let month = cal.dateInterval(of: .month, for: date) { return month }
        }
        return TimeInsightsMath.dayInterval(date, calendar: calendar)
    }

    /// 前一个或后一个周期里的某一天（`step` 为 -1 或 1）。
    public static func shift(_ date: Date, kind: Kind, by step: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = kind == .week ? .weekOfYear : .month
        return calendar.date(byAdding: component, value: step, to: date) ?? date
    }

    /// 截止到 `last` 那天（含）往前 `count` 天的区间，历史列表用。
    public static func recent(days count: Int, endingOn last: Date, calendar: Calendar = .current) -> DateInterval {
        let end = TimeInsightsMath.dayInterval(last, calendar: calendar).end
        let start = calendar.date(byAdding: .day, value: -max(1, count), to: end) ?? end.addingTimeInterval(-86_400)
        return DateInterval(start: calendar.startOfDay(for: start), end: end)
    }

    public static func make(_ sessions: [ActivitySession], interval: DateInterval,
                            calendar: Calendar = .current) -> TimeInsightsPeriod {
        var days: [DayTotal] = []
        var apps: [String: TimeInsightsAppUsage] = [:]
        var categories: [TimeInsightsCategory: TimeInterval] = [:]
        var active: TimeInterval = 0, work: TimeInterval = 0, uncategorized: TimeInterval = 0
        // 先按区间裁一遍，后面每天只看和这一天有重叠的。
        let relevant = sessions.filter { $0.end > interval.start && $0.start < interval.end }
        var cursor = calendar.startOfDay(for: interval.start)
        var guardCount = 0
        while cursor < interval.end, guardCount < 400 {
            guardCount += 1
            let dayRange = TimeInsightsMath.dayInterval(cursor, calendar: calendar)
            let todays = relevant.filter { $0.end > dayRange.start && $0.start < dayRange.end }
            let day = TimeInsightsDay.make(todays, day: cursor, calendar: calendar)
            days.append(DayTotal(date: dayRange.start, active: day.active, foreground: day.foreground,
                                 work: day.work, other: day.other, uncategorized: day.uncategorized,
                                 categories: day.categories, topApp: day.apps.first))
            active += day.active
            work += day.work
            uncategorized += day.uncategorized
            for (category, seconds) in day.categories { categories[category, default: 0] += seconds }
            for usage in day.apps {
                var total = apps[usage.bundleID]
                    ?? TimeInsightsAppUsage(bundleID: usage.bundleID, appName: usage.appName,
                                            category: usage.category, active: 0)
                total.active += usage.active
                total.segments += usage.segments
                total.appName = usage.appName
                total.category = usage.category
                apps[usage.bundleID] = total
            }
            cursor = dayRange.end
        }
        let ranked = apps.values.sorted {
            $0.active != $1.active ? $0.active > $1.active : $0.appName < $1.appName
        }
        return TimeInsightsPeriod(interval: interval, days: days, apps: ranked,
                                  categories: TimeInsightsStats.ranking(categories),
                                  active: active, work: work, uncategorized: uncategorized)
    }
}

// MARK: 面板宽度

public enum TimeInsightsLayout {
    /// Dock 展开面板用 440pt 紧凑布局；极窄屏退到 340pt，指标转为纵排。
    /// 24 小时柱状图留给独立的完整统计窗口，不让 Dock 面板过宽。
    public static let wideWidth: CGFloat = 440
    public static let narrowWidth: CGFloat = 340

    /// 屏幕可见区域宽 `screenWidth` 时面板多宽：两边各留 40 才使用标准版。
    public static func panelWidth(screenWidth: CGFloat?) -> CGFloat {
        guard let screenWidth else { return wideWidth }
        return screenWidth >= wideWidth + 80 ? wideWidth : narrowWidth
    }

    /// 内容区宽 380pt 及以上时主数字与辅助指标并排，否则纵排。
    public static func isWide(contentWidth: CGFloat) -> Bool { contentWidth >= 380 }
}

// MARK: 完整导出（Pro）

public extension TimeInsightsCSV {
    /// 完整导出（Pro）的列：基础列加窗口标题和域名。
    static let fullHeader = "start,end,duration_seconds,bundle_id,app_name,category,source,window_title,domain"

    static func makeFull(_ sessions: [ActivitySession]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [fullHeader]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            lines.append([
                formatter.string(from: s.start),
                formatter.string(from: s.end),
                String(Int(s.duration.rounded())),
                escape(s.bundleID),
                escape(s.appName),
                s.classification.rawValue,
                s.source.rawValue,
                escape(s.windowTitle ?? ""),
                escape(s.domain ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
