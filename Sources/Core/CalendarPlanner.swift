import Foundation

/// 日历面板（日历和一周日程两种小组件共用）：一周条的小圆点、今天时间轴的范围和空档、
/// 「接下来」、快速新建的时间预设和冲突提示、点开日程后拖两端改时间。
///
/// 纯逻辑，界面把 `EKEvent` 拍平成 `WeekEntry` 后交给这里，测试不需要日历数据库。
public enum CalendarPlanner {
    /// 时间轴默认画 9 点到 18 点，日程更早更晚时整点往外扩（和效果图一样）。
    public static let defaultHours = 9...18
    /// 空档至少这么长才显示「专注一下」。
    public static let minimumGap: TimeInterval = 30 * 60
    /// 拖两端改时间按 15 分钟吸附，日程最短也是 15 分钟。
    public static let step: TimeInterval = 15 * 60

    // MARK: 一周条

    /// 一天下面画几个圆点：一个日程一个点，最多 3 个。
    public static func dots(_ count: Int) -> Int { min(max(count, 0), 3) }

    /// 某一天的日程：盖住这一天的都算，定时的按开始时间在前，全天的在后。
    public static func entries(on day: Date, _ all: [WeekEntry], includeAllDay: Bool = true,
                               calendar: Calendar = WeekAgenda.calendar) -> [WeekEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let on = all.filter { entry in
            guard includeAllDay || !entry.isAllDay else { return false }
            let last = max(entry.end, entry.start.addingTimeInterval(1))
            return entry.start < end && last > start
        }
        let order: (WeekEntry, WeekEntry) -> Bool = { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
        return on.filter { !$0.isAllDay }.sorted(by: order) + on.filter(\.isAllDay).sorted(by: order)
    }

    /// 头上那行：「10 月 · 今天 4 个日程」「10 月 · 周四 2 个日程」「10 月 · 今天没有日程」。
    public static func headline(day: Date, now: Date, count: Int, calendar: Calendar = WeekAgenda.calendar) -> String {
        let month = calendar.component(.month, from: day)
        let name = dayLabel(day, now: now, calendar: calendar)
        return count > 0 ? tr("\(month) 月 · \(name) \(count) 个日程") : tr("\(month) 月 · \(name)没有日程")
    }

    /// 「今天」「明天」「后天」「昨天」，一周以内「周四」，再远「11月3日」。
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar = WeekAgenda.calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case 0: return tr("今天")
        case 1: return tr("明天")
        case 2: return tr("后天")
        case -1: return tr("昨天")
        default:
            if (3...6).contains(offset) {
                let index = (calendar.component(.weekday, from: day) + 5) % 7
                return tr("周\(WeekAgenda.weekdayNames[index])")
            }
            let parts = calendar.dateComponents([.month, .day], from: day)
            return tr("\(parts.month ?? 0)月\(parts.day ?? 0)日")
        }
    }

    // MARK: 时间轴

    /// 轴的范围（整点）：盖住 9 到 18 点和这一天每个定时日程；看的是今天时再盖住现在。
    public static func hourRange(_ entries: [WeekEntry], day: Date, now: Date,
                                 calendar: Calendar = WeekAgenda.calendar) -> ClosedRange<Int> {
        let spans = entries.map { CalendarSpan(id: $0.id, start: $0.start, end: $0.end, isAllDay: $0.isAllDay) }
        let range = DayTimeline.hourRange(spans, day: day, calendar: calendar, defaults: defaultHours)
        guard calendar.isDate(now, inSameDayAs: day) else { return range }
        let hour = calendar.component(.hour, from: now)
        return min(range.lowerBound, hour)...max(range.upperBound, min(24, hour + 1))
    }

    /// 时间轴上一块的位置，单位是小时（相对轴的起点），界面乘上每小时的高度。
    public static func offset(_ date: Date, hours: ClosedRange<Int>, day: Date,
                              calendar: Calendar = WeekAgenda.calendar) -> Double {
        let start = calendar.startOfDay(for: day)
        let value = date.timeIntervalSince(start) / 3_600 - Double(hours.lowerBound)
        return min(max(value, 0), Double(hours.upperBound - hours.lowerBound))
    }

    /// 今天时间轴上还没过去的空档：轴的范围里没有定时日程、至少 30 分钟的一段。
    /// 起点从现在（往后取整到 5 分钟）算起；看的不是今天时没有空档（专注只能现在开始）。
    public static func gaps(_ entries: [WeekEntry], day: Date, hours: ClosedRange<Int>, now: Date,
                            minimum: TimeInterval = CalendarPlanner.minimumGap,
                            calendar: Calendar = WeekAgenda.calendar) -> [DateInterval] {
        guard calendar.isDate(now, inSameDayAs: day) else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        let windowStart = dayStart.addingTimeInterval(Double(hours.lowerBound) * 3_600)
        let windowEnd = dayStart.addingTimeInterval(Double(hours.upperBound) * 3_600)
        var cursor = max(windowStart, roundUp(now, to: 5 * 60, calendar: calendar))
        guard cursor < windowEnd else { return [] }
        let busy = entries.filter { !$0.isAllDay && $0.end > windowStart && $0.start < windowEnd }
            .sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for event in busy {
            if event.start > cursor, event.start.timeIntervalSince(cursor) >= minimum {
                result.append(DateInterval(start: cursor, end: event.start))
            }
            cursor = max(cursor, event.end)
            if cursor >= windowEnd { return result }
        }
        if windowEnd.timeIntervalSince(cursor) >= minimum {
            result.append(DateInterval(start: cursor, end: windowEnd))
        }
        return result
    }

    /// 「空档 2 小时」「空档 45 分钟」。
    public static func gapTitle(_ gap: DateInterval) -> String {
        tr("空档 \(CalendarDay.duration(minutes: Int((gap.duration / 60).rounded(.down))))")
    }

    /// 「12:00 至 14:00」。
    public static func rangeText(_ start: Date, _ end: Date, calendar: Calendar = WeekAgenda.calendar) -> String {
        tr("\(CalendarDay.clock(start, calendar: calendar)) 至 \(CalendarDay.clock(end, calendar: calendar))")
    }

    /// 在空档里专注多久：专注计时设的时长，但不超过空档剩下的时间，至少 5 分钟。
    public static func focusMinutes(_ gap: DateInterval, now: Date, preferred: Int) -> Int {
        let left = Int((gap.end.timeIntervalSince(max(now, gap.start)) / 60).rounded(.down))
        return max(5, min(max(1, preferred), left))
    }

    // MARK: 接下来

    public struct Upcoming: Identifiable, Hashable, Sendable {
        public var entry: WeekEntry
        /// 「明天」「周四」「11月3日」。
        public var day: String
        /// 「09:30」或「全天」。
        public var time: String
        public var id: String { entry.id }
    }

    /// 今天以后最先开始的几个日程（从明天零点起），按开始时间。
    public static func upcoming(_ entries: [WeekEntry], now: Date, limit: Int = 3,
                                calendar: Calendar = WeekAgenda.calendar) -> [Upcoming] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        return entries.filter { $0.start >= tomorrow }
            .sorted { $0.start == $1.start ? ($0.isAllDay != $1.isAllDay ? $0.isAllDay : $0.title < $1.title)
                                           : $0.start < $1.start }
            .prefix(max(0, limit))
            .map { entry in
                Upcoming(entry: entry, day: dayLabel(entry.start, now: now, calendar: calendar),
                         time: entry.isAllDay ? tr("全天") : CalendarDay.clock(entry.start, calendar: calendar))
            }
    }

    // MARK: 快速新建

    /// 新建时的四个时间预设。
    public enum Length: String, CaseIterable, Sendable {
        case half, hour, twoHours, allDay

        public var minutes: Int? {
            switch self {
            case .half: 30
            case .hour: 60
            case .twoHours: 120
            case .allDay: nil
            }
        }

        public var title: String {
            switch self {
            case .half: tr("30 分钟")
            case .hour: tr("1 小时")
            case .twoHours: tr("2 小时")
            case .allDay: tr("全天")
            }
        }
    }

    /// 新日程的时间。全天时 `start` 是那天零点，`end` 是第二天零点（EventKit 的写法）。
    public struct Slot: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var isAllDay: Bool

        public init(start: Date, end: Date, isAllDay: Bool = false) {
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    /// 新建默认从哪开始：看的是今天就从下一个整半点，别的日子从上午 9 点。
    /// 今天已经过了 23:30 时也是 23:30，不跨到明天。
    public static func defaultStart(day: Date, now: Date, calendar: Calendar = WeekAgenda.calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        guard calendar.isDate(now, inSameDayAs: day) else { return start.addingTimeInterval(9 * 3_600) }
        let next = roundUp(now.addingTimeInterval(1), to: 30 * 60, calendar: calendar)
        return min(next, start.addingTimeInterval(23.5 * 3_600))
    }

    /// 按预设定出时间：时长从 `start` 往后算；全天取 `start` 那一天。
    public static func slot(_ length: Length, start: Date, calendar: Calendar = WeekAgenda.calendar) -> Slot {
        guard let minutes = length.minutes else {
            let day = calendar.startOfDay(for: start)
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return Slot(start: day, end: next, isAllDay: true)
        }
        return Slot(start: start, end: start.addingTimeInterval(Double(minutes) * 60))
    }

    /// 时间正好是哪个预设，用来点亮那颗按钮；都不是时为 nil。
    public static func length(of slot: Slot) -> Length? {
        if slot.isAllDay { return .allDay }
        let minutes = Int((slot.end.timeIntervalSince(slot.start) / 60).rounded())
        return Length.allCases.first { $0.minutes == minutes }
    }

    /// 和这段时间重叠的定时日程（首尾相接不算）。全天的不算冲突，`excluding` 是正在改的那个。
    public static func conflicts(_ slot: Slot, in entries: [WeekEntry], excluding: String? = nil) -> [WeekEntry] {
        guard !slot.isAllDay else { return [] }
        return entries.filter { entry in
            !entry.isAllDay && entry.id != excluding && entry.start < slot.end && entry.end > slot.start
        }.sorted { $0.start < $1.start }
    }

    /// 冲突提示一行：`clash` 为 true 时界面标红点。
    /// 冲突：「和「需求会」冲突」「和「需求会」等 2 个日程冲突」；
    /// 不冲突：说离得最近的那个「和「需求会」不冲突」，当天没别的就「这段时间没有别的日程」。
    public static func conflictLine(_ slot: Slot, in entries: [WeekEntry], excluding: String? = nil,
                                    calendar: Calendar = WeekAgenda.calendar) -> (text: String, clash: Bool) {
        if slot.isAllDay { return (tr("全天日程不占时间"), false) }
        let hits = conflicts(slot, in: entries, excluding: excluding)
        if let first = hits.first {
            return hits.count == 1 ? (tr("和「\(first.title)」冲突"), true)
                                   : (tr("和「\(first.title)」等 \(hits.count) 个日程冲突"), true)
        }
        let sameDay = entries.filter {
            !$0.isAllDay && $0.id != excluding && calendar.isDate($0.start, inSameDayAs: slot.start)
        }
        func distance(_ entry: WeekEntry) -> TimeInterval {
            entry.end <= slot.start ? slot.start.timeIntervalSince(entry.end) : entry.start.timeIntervalSince(slot.end)
        }
        guard let near = sameDay.min(by: { distance($0) == distance($1) ? $0.start < $1.start : distance($0) < distance($1) })
        else { return (tr("这段时间没有别的日程"), false) }
        return (tr("和「\(near.title)」不冲突"), false)
    }

    // MARK: 拖两端改时间

    public enum Edge: Sendable { case start, end }

    /// 拖一端到 `to`：吸附到 15 分钟，至少留 15 分钟，不跨出这一天（终点最晚到第二天零点）。
    public static func drag(start: Date, end: Date, edge: Edge, to target: Date,
                            calendar: Calendar = WeekAgenda.calendar) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: start)
        let dayEnd = dayStart.addingTimeInterval(24 * 3_600)
        let snapped = round(target, to: step, calendar: calendar)
        switch edge {
        case .start:
            let value = min(max(snapped, dayStart), end.addingTimeInterval(-step))
            return (value, end)
        case .end:
            let value = max(min(snapped, dayEnd), start.addingTimeInterval(step))
            return (start, value)
        }
    }

    /// 点开日程后那条小时间轴的范围：从开始前一个整点起，至少 3 小时，盖住结束后一个整点。
    public static func editHours(start: Date, end: Date, calendar: Calendar = WeekAgenda.calendar) -> ClosedRange<Int> {
        let dayStart = calendar.startOfDay(for: start)
        let from = start.timeIntervalSince(dayStart) / 3_600
        let to = min(24, end.timeIntervalSince(dayStart) / 3_600)
        var low = max(0, Int(from.rounded(.down)) - 1)
        var high = max(low + 3, Int(to.rounded(.up)) + 1)
        if high > 24 {
            high = 24
            low = max(0, min(low, high - 3))
        }
        return low...high
    }

    // MARK: Helpers

    /// 往后取整到 `step`，按本地零点算。
    static func roundUp(_ date: Date, to step: TimeInterval, calendar: Calendar = WeekAgenda.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return day.addingTimeInterval((date.timeIntervalSince(day) / step).rounded(.up) * step)
    }

    /// 吸附到 `step`。按本地零点算，避免时区偏移不是整刻钟时吸到奇怪的位置。
    static func round(_ date: Date, to step: TimeInterval, calendar: Calendar = WeekAgenda.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let value = date.timeIntervalSince(day)
        return day.addingTimeInterval((value / step).rounded() * step)
    }
}
