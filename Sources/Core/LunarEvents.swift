import Foundation

/// 农历面板里记的生日和纪念日：名字、农历月日、要不要闰月、提前几天提醒。
///
/// 只存农历的月和日，每年换算成公历：
/// - 闰月：记的是闰月，那年有这个闰月就按闰月过，没有就按同名的普通月过（民间多数
///   这样做）。记的是普通月，就只按普通月过。
/// - 小月：记的是三十，那个月只有 29 天就按廿九过，面板上写一句。
///
/// 存在卡片配置的 `events` 键，一条一个字符串，名字放最后（名字里可以有竖线）：
/// `id|种类|月|日|闰|提前|分钟|名字`。不在设置页里列，只在面板里加、改、删。
public struct LunarEvent: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case birthday = "b"
        case anniversary = "a"
        case other = "o"

        public var title: String {
            switch self {
            case .birthday: tr("生日")
            case .anniversary: tr("纪念日")
            case .other: tr("其他")
            }
        }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// 农历月，1 到 12。
    public var month: Int
    /// 农历日，1 到 30。
    public var day: Int
    public var isLeap: Bool
    /// 提前几天提醒：0 是只在当天，-1 是不提醒。
    public var lead: Int
    /// 提醒时间，当天零点起的分钟数。
    public var minute: Int

    public init(id: String = UUID().uuidString, name: String, kind: Kind = .birthday,
                month: Int, day: Int, isLeap: Bool = false,
                lead: Int = LunarEvents.defaultLead, minute: Int = LunarEvents.defaultMinute) {
        self.id = id
        self.name = name
        self.kind = kind
        self.month = min(max(month, 1), 12)
        self.day = min(max(day, 1), 30)
        self.isLeap = isLeap
        self.lead = LunarEvents.leadChoices.contains(lead) ? lead : LunarEvents.defaultLead
        self.minute = min(max(minute, 0), 24 * 60 - 1)
    }

    var encoded: String {
        [id, kind.rawValue, "\(month)", "\(day)", isLeap ? "1" : "0", "\(lead)", "\(minute)", name]
            .joined(separator: "|")
    }

    init?(encoded text: String) {
        let parts = text.split(separator: "|", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8, !parts[0].isEmpty,
              let month = Int(parts[2]), (1...12).contains(month),
              let day = Int(parts[3]), (1...30).contains(day),
              let lead = Int(parts[5]), let minute = Int(parts[6]),
              let name = LunarEvents.clean(parts[7]) else { return nil }
        self.init(id: parts[0], name: name, kind: Kind(rawValue: parts[1]) ?? .other,
                  month: month, day: day, isLeap: parts[4] == "1", lead: lead, minute: minute)
    }

    /// 农历十月初八、农历闰六月初十
    public var lunarText: String {
        tr("农历\(ChineseCalendar.LunarDate.monthTitle(month, leap: isLeap))\(ChineseCalendar.LunarDate.dayTitle(day))")
    }
}

public enum LunarEvents {
    public static let key = "events"
    public static let limit = 30
    public static let nameLimit = 20
    /// 提前几天：当天、1 天、3 天、7 天，-1 不提醒。
    public static let leadChoices = [0, 1, 3, 7, -1]
    public static let defaultLead = 3
    /// 早上 9 点。
    public static let defaultMinute = 9 * 60

    // MARK: 读写

    public static func events(_ config: WidgetConfig) -> [LunarEvent] {
        var seen = Set<String>()
        return config.strings(key).compactMap(LunarEvent.init(encoded:))
            .filter { seen.insert($0.id).inserted }
            .prefix(limit).map { $0 }
    }

    public static func store(_ events: [LunarEvent], in config: inout WidgetConfig) {
        let list = events.prefix(limit).map { WidgetConfig.Value.string($0.encoded) }
        config.set(key, list.isEmpty ? nil : .list(list))
    }

    /// 改的就地换掉，新的加在最后；放满了新的加不进去。
    public static func saving(_ event: LunarEvent, in list: [LunarEvent]) -> [LunarEvent] {
        var result = list
        if let index = result.firstIndex(where: { $0.id == event.id }) {
            result[index] = event
        } else if result.count < limit {
            result.append(event)
        }
        return result
    }

    public static func removing(_ id: String, from list: [LunarEvent]) -> [LunarEvent] {
        list.filter { $0.id != id }
    }

    /// 去掉首尾空白，换行换成空格，最多 20 个字；空的是 nil。
    public static func clean(_ name: String) -> String? {
        let flat = name.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(nameLimit))
    }

    // MARK: 换算

    public struct Occurrence: Equatable, Sendable {
        /// 那天零点（中国时间）。
        public var date: Date
        /// 实际过的那个农历日（小月的三十变成廿九）。
        public var day: Int
        /// 记的是闰月、那年有这个闰月，按闰月过的。
        public var isLeap: Bool
        /// 记的是三十，那个月只有 29 天，按廿九过。
        public var shortMonth: Bool
        /// 记的是闰月，那年没有这个闰月，按普通月过。
        public var leapFallback: Bool
    }

    /// 某个农历年某月的初一。闰月不存在时 nil（Foundation 会给一个别的月份，要读回来核对）。
    static func monthStart(era: Int, year: Int, month: Int, leap: Bool) -> Date? {
        let lunar = ChineseCalendar.lunarCalendar
        var parts = DateComponents()
        parts.era = era
        parts.year = year
        parts.month = month
        parts.day = 1
        parts.isLeapMonth = leap
        guard let found = lunar.date(from: parts) else { return nil }
        let back = lunar.dateComponents([.era, .year, .month, .day], from: found)
        guard back.era == era, back.year == year, back.month == month, back.day == 1,
              (back.isLeapMonth ?? false) == leap else { return nil }
        return found
    }

    /// 在某个农历年里，这个农历月日落在公历哪天。
    static func occurrence(month: Int, day: Int, leap: Bool, era: Int, year: Int) -> Occurrence? {
        let lunar = ChineseCalendar.lunarCalendar
        var usedLeap = false
        var start: Date?
        if leap, let found = monthStart(era: era, year: year, month: month, leap: true) {
            start = found
            usedLeap = true
        }
        if start == nil { start = monthStart(era: era, year: year, month: month, leap: false) }
        guard let first = start,
              let length = lunar.range(of: .day, in: .month, for: first)?.count else { return nil }
        let actual = min(day, length)
        guard let found = lunar.date(byAdding: .day, value: actual - 1, to: first) else { return nil }
        return Occurrence(date: ChineseCalendar.gregorian.startOfDay(for: found), day: actual,
                          isLeap: usedLeap, shortMonth: actual < day, leapFallback: leap && !usedLeap)
    }

    /// 从今天起（今天也算）接下来的几次。
    public static func occurrences(month: Int, day: Int, leap: Bool, from now: Date,
                                   count: Int = 2) -> [Occurrence] {
        let calendar = ChineseCalendar.gregorian
        let lunar = ChineseCalendar.lunarCalendar
        let today = calendar.startOfDay(for: now)
        // 农历年 353 到 385 天，隔 200 天取一个点，四个点一定盖住今年和后面两年。
        var years: [(era: Int, year: Int)] = []
        for step in 0..<4 {
            guard let anchor = calendar.date(byAdding: .day, value: step * 200, to: today) else { continue }
            let parts = lunar.dateComponents([.era, .year], from: anchor)
            guard let era = parts.era, let year = parts.year else { continue }
            if !years.contains(where: { $0.era == era && $0.year == year }) { years.append((era, year)) }
        }
        let found = years.compactMap { occurrence(month: month, day: day, leap: leap, era: $0.era, year: $0.year) }
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
        return Array(found.prefix(max(0, count)))
    }

    public static func next(_ event: LunarEvent, from now: Date) -> Occurrence? {
        occurrences(month: event.month, day: event.day, leap: event.isLeap, from: now, count: 1).first
    }

    public struct Row: Equatable, Sendable {
        public var event: LunarEvent
        public var next: Occurrence
        public var days: Int
    }

    /// 面板列表：按还有几天排，近的在前；同一天按名字。
    public static func rows(_ events: [LunarEvent], now: Date) -> [Row] {
        events.compactMap { event in
            next(event, from: now).map { Row(event: event, next: $0, days: ChineseCalendar.days(from: now, to: $0.date)) }
        }
        .sorted { $0.days != $1.days ? $0.days < $1.days : $0.event.name < $1.event.name }
    }

    /// 今天过的那几条，卡片上小熊猫送祝福用。
    public static func today(_ events: [LunarEvent], now: Date) -> [LunarEvent] {
        rows(events, now: now).filter { $0.days == 0 }.map(\.event)
    }

    // MARK: 文字

    /// 11月16日 周一
    public static func dateText(_ date: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = max(0, min(calendar.component(.weekday, from: date) - 1, 6))
        return tr("\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 周\(trKey(names[index]))")
    }

    /// 列表第二行：农历十月初八 · 11月16日 周一
    public static func subtitle(_ row: Row) -> String {
        tr("\(row.event.lunarText) · \(dateText(row.next.date))")
    }

    /// 换算时做了变通才有的一句：「今年十月只有 29 天，按廿九过」「今年没有闰六月，按六月过」。
    public static func note(_ event: LunarEvent, _ occurrence: Occurrence) -> String? {
        let plain = ChineseCalendar.LunarDate.monthTitle(event.month, leap: false)
        let shown = ChineseCalendar.LunarDate.monthTitle(event.month, leap: occurrence.isLeap)
        if occurrence.leapFallback && occurrence.shortMonth {
            return tr("这一年没有闰\(plain)，按\(plain)过；\(plain)只有 29 天，按廿九过")
        }
        if occurrence.leapFallback { return tr("这一年没有闰\(plain)，按\(plain)过") }
        if occurrence.shortMonth { return tr("这一年\(shown)只有 29 天，按廿九过") }
        return nil
    }

    /// 提醒说明：「提前 3 天 09:00 提醒，当天再提醒一次」。
    public static func reminderText(_ event: LunarEvent) -> String {
        let time = timeText(event.minute)
        switch event.lead {
        case -1: return tr("不提醒")
        case 0: return tr("当天 \(time) 提醒")
        default: return tr("提前 \(event.lead) 天 \(time) 提醒，当天再提醒一次")
        }
    }

    /// 09:00
    public static func timeText(_ minute: Int) -> String {
        let hour = minute / 60, rest = minute % 60
        return "\(hour < 10 ? "0" : "")\(hour):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// 提醒时间可选：早 6 点到晚 10 点，每半小时。
    public static let minuteChoices = Array(stride(from: 6 * 60, through: 22 * 60, by: 30))

    // MARK: 提醒

    public struct Reminder: Equatable, Sendable {
        /// `lead` 或 `day`，和事件 id 拼成通知的标识。
        public var slot: String
        public var fire: Date
        public var title: String
        public var body: String
    }

    /// 下一次的提前提醒和当天提醒，已经过了的不要。
    public static func reminders(_ event: LunarEvent, now: Date) -> [Reminder] {
        guard event.lead >= 0, let occurrence = next(event, from: now) else { return [] }
        let calendar = ChineseCalendar.gregorian
        let hour = event.minute / 60, minute = event.minute % 60
        func at(_ day: Date) -> Date? { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) }
        let lunar = event.lunarText
        var result: [Reminder] = []
        if event.lead > 0,
           let day = calendar.date(byAdding: .day, value: -event.lead, to: occurrence.date),
           let fire = at(day), fire > now {
            result.append(Reminder(slot: "lead", fire: fire,
                                   title: tr("\(event.lead) 天后是\(event.name)"),
                                   body: tr("\(lunar)，\(dateText(occurrence.date))")))
        }
        if let fire = at(occurrence.date), fire > now {
            result.append(Reminder(slot: "day", fire: fire, title: tr("今天是\(event.name)"),
                                   body: tr("\(lunar)，\(greeting(event.kind))")))
        }
        return result
    }

    /// 生日快乐 / 纪念日快乐 / 别忘了
    public static func greeting(_ kind: LunarEvent.Kind) -> String {
        switch kind {
        case .birthday: tr("生日快乐")
        case .anniversary: tr("纪念日快乐")
        case .other: tr("别忘了")
        }
    }
}

extension ChineseCalendar.LunarDate {
    /// 十月、闰六月、冬月
    public static func monthTitle(_ month: Int, leap: Bool) -> String {
        (leap ? "闰" : "") + monthNames[max(0, min(month - 1, 11))] + "月"
    }

    /// 初八、廿九、三十
    public static func dayTitle(_ day: Int) -> String {
        Self(cycleYear: 1, month: 1, day: day, isLeapMonth: false).dayName
    }
}
