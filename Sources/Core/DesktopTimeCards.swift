import Foundation

// MARK: - 桌面卡片 · 时间组
//
// 时钟、世界时钟、秒表、专注计时、倒计时、闹钟、时间进度、一周日程、农历、纪念日、日历
// 钉在桌面时的专属布局（视图在 Sources/Widgets/DesktopCards/DesktopCardsTime.swift）。
// 小号一个核心数字或状态加最多一个操作；中号核心加几条次要信息或一排操作；大号核心加
// 列表 / 月历 / 操作区，完整不截断、不滚动。这里放纯判断：哪些种类有专属布局、每档列几条、
// 挑哪几条。数据和扩展栏是同一份配置，这里只读不存。

public enum DesktopTimeCards {
    /// 有专属布局的种类：小 / 中 / 大三档都有，小号总能放下。
    public static let kinds: Set<WidgetKind> = [
        .clock, .world, .stopwatch, .timer, .countdown, .alarm,
        .progress, .week, .lunar, .anniversary, .calendar,
    ]

    /// 每档的列表部分最多列几条（核心那一块不算）。按卡片高度排好，多了会截断或要滚动。
    public static func rows(_ kind: WidgetKind, _ size: DesktopPinSize) -> Int {
        switch (kind, size) {
        case (.world, .small): 1
        case (.world, .medium): 3
        case (.world, .large): 5
        case (.stopwatch, .medium): 3
        case (.stopwatch, .large): 5
        case (.countdown, .large): 3
        case (.alarm, .medium): 2
        case (.alarm, .large): 3
        case (.anniversary, .medium): 3
        case (.anniversary, .large): 3
        case (.calendar, .small): 1
        case (.calendar, .medium): 3
        case (.calendar, .large): 2
        case (.week, .large): 3
        default: 0
        }
    }

    // MARK: 世界时钟

    /// 卡片上列哪几个城市，顺序和面板一样。小号只放一个：第一个不在本地时区的（看别处
    /// 几点才是世界时钟的意思），都在本地时就第一个。
    public static func worldCities(_ cities: [WorldCity], size: DesktopPinSize,
                                   here: TimeZone = .current) -> [WorldCity] {
        let limit = rows(.world, size)
        guard size == .small else { return Array(cities.prefix(limit)) }
        let away = cities.first { city in
            guard let zone = city.timeZone else { return false }
            return zone.identifier != here.identifier
        }
        return (away ?? cities.first).map { [$0] } ?? []
    }

    /// 格子里放不下「比北京晚 12 小时」时的短写法：「+1 小时」「−12 小时」「+5 小时 30 分」，
    /// 一样时是「时间相同」。负号用 U+2212，和数字一样粗。
    public static func shortOffset(_ seconds: Int) -> String {
        guard seconds != 0 else { return tr("时间相同") }
        return (seconds > 0 ? "+" : "\u{2212}") + WorldClockText.duration(seconds)
    }

    // MARK: 秒表

    /// 计次表最近几圈，新的在上；最快、最慢的标记沿用 `StopwatchLaps.rows`（算的是全部圈）。
    public static func lapRows(_ laps: [TimeInterval], limit: Int) -> [StopwatchLaps.Row] {
        Array(StopwatchLaps.rows(laps).prefix(max(0, limit)))
    }

    // MARK: 闹钟

    public struct AlarmRow: Equatable, Sendable {
        public var item: AlarmItem
        /// 下一次响铃；关着或已经响过的一次性闹钟是 nil。
        public var at: Date?

        public var live: Bool { at != nil }
    }

    /// 核心那个（`AlarmBook.headline`）下面的列表：开着的按下一次响铃先后，关着的排在后面
    /// （按一天里的时刻），都不含核心那个。
    public static func alarmRows(_ config: WidgetConfig, now: Date, limit: Int,
                                 excluding headline: String?, calendar: Calendar = .current) -> [AlarmRow] {
        let upcoming = AlarmBook.upcoming(config, now: now, calendar: calendar)
        let liveIDs = Set(upcoming.map(\.item.id))
        let on = upcoming.map { AlarmRow(item: $0.item, at: $0.at) }
        let off = AlarmBook.items(config)
            .filter { !liveIDs.contains($0.id) }
            .sorted { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
            .map { AlarmRow(item: $0, at: nil) }
        return Array((on + off).filter { $0.item.id != headline }.prefix(max(0, limit)))
    }

    // MARK: 纪念日

    /// 核心那个之外的纪念日，按卡片的列表顺序（今天的、最近要到的、正数日、过去的）。
    public static func otherReadings(_ readings: [AnniversaryReading], featured: String?,
                                     limit: Int) -> [AnniversaryReading] {
        Array(readings.filter { $0.event.id != featured }.prefix(max(0, limit)))
    }

    // MARK: 日历和一周日程

    /// 今天接下来的日程：没结束的定时日程按开始时间（正在开的也算），全天的放在后面。
    /// `includeAllDay` 跟着小组件自己的「显示全天日程」。
    public static func upcoming(_ entries: [WeekEntry], now: Date, limit: Int,
                                includeAllDay: Bool = true) -> [WeekEntry] {
        let timed = entries.filter { !$0.isAllDay && $0.end > now }
            .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
        let allDay = includeAllDay
            ? entries.filter(\.isAllDay).sorted { ($0.title, $0.id) < ($1.title, $1.id) }
            : []
        return Array((timed + allDay).prefix(max(0, limit)))
    }

    /// 正在进行的那个（开始了还没结束的定时日程），日历卡片上标「进行中」。
    public static func isOngoing(_ entry: WeekEntry, now: Date) -> Bool {
        !entry.isAllDay && entry.start <= now && entry.end > now
    }

    /// 月历上哪几天有日程（当天零点）。跨天的日程每一天都算。
    public static func busyDays(_ entries: [WeekEntry], calendar: Calendar = WeekAgenda.calendar) -> Set<Date> {
        var days = Set<Date>()
        for entry in entries {
            var day = calendar.startOfDay(for: entry.start)
            // 结束在零点的不算那一天（全天日程的结束是第二天零点）。
            let last = entry.end > entry.start ? entry.end.addingTimeInterval(-1) : entry.start
            var guardCount = 0
            while day <= last, guardCount < 62 {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
        }
        return days
    }

    // MARK: 时间进度

    /// 点周期名换下一个：日 → 周 → 月 → 年 → 日，和扩展栏卡片一样。
    public static func nextPeriod(_ period: TimeProgress.Period) -> TimeProgress.Period {
        let all = TimeProgress.Period.allCases
        let index = all.firstIndex(of: period) ?? 0
        return all[(index + 1) % all.count]
    }

    // MARK: 倒计时

    public enum CountdownRow: Equatable, Sendable {
        case timer(CountdownTimer)
        case date(CountdownDate, days: Int)

        public var id: String {
            switch self {
            case .timer(let timer): "t-\(timer.id)"
            case .date(let date, _): "d-\(date.id)"
            }
        }
    }

    /// 大号核心下面的列表：卡片上显示的那个计时器之外，在跑、暂停、在响的计时器在前，
    /// 然后是日期倒计时（近的在前），没开始的其他计时器最后。
    public static func countdownRows(_ config: WidgetConfig, now: Date, shown: String?, limit: Int,
                                     calendar: Calendar = .current) -> [CountdownRow] {
        let timers = CountdownList.timers(config).filter { $0.id != shown }
        let active = timers.filter { CountdownList.phase($0, now: now) != .idle }
        let idle = timers.filter { CountdownList.phase($0, now: now) == .idle }
        let dates = CountdownList.dates(config, now: now, calendar: calendar).map {
            CountdownRow.date($0, days: CountdownList.daysLeft($0, now: now, calendar: calendar))
        }
        let rows = active.map(CountdownRow.timer) + dates + idle.map(CountdownRow.timer)
        return Array(rows.prefix(max(0, limit)))
    }

    // MARK: 农历

    /// 某月的月历要几行（周一开头）。
    public static func monthRows(year: Int, month: Int) -> Int {
        let calendar = ChineseCalendar.gregorian
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return 5 }
        let cells = LunarCard.leadingBlanks(year: year, month: month) + days
        return (cells + 6) / 7
    }

    // MARK: 专注计时

    /// 还剩多少：暂停优先于结束时刻；两个都没有时是没开始，停在整段时长上。
    public static func focusRemaining(_ state: TimerState, now: Date) -> (left: TimeInterval, total: TimeInterval) {
        let total = max(1, state.duration ?? Double(state.minutes * 60))
        if let paused = state.paused { return (max(0, min(paused, total)), total) }
        guard let deadline = state.deadline else { return (total, total) }
        return (max(0, min(deadline.timeIntervalSince(now), total)), total)
    }

    /// 桌面卡片上开始 / 暂停一下之后的状态，和扩展栏卡片的按钮一样：跑着就暂停（存下还剩
    /// 多少），停着就从屏幕上的数接着走，已经到 0 的重新开始一整段。开始时把长度钉住。
    public static func focusToggled(_ state: TimerState, now: Date) -> TimerState {
        var next = state
        let (left, total) = focusRemaining(state, now: now)
        if state.deadline != nil, left > 0 {
            next.paused = left
            next.deadline = nil
        } else {
            next.duration = total
            next.deadline = now.addingTimeInterval(left > 0 ? left : total)
            next.paused = nil
            if state.phase == .focus {
                next.recentTasks = FocusDay.remembering(state.task, in: state.recentTasks)
            }
        }
        return next
    }

    /// 重置：连钉住的长度一起清掉，用设置里现在的时长。
    public static func focusReset(_ state: TimerState) -> TimerState {
        var next = state
        next.deadline = nil
        next.paused = nil
        next.duration = nil
        return next
    }
}
