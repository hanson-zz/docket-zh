import Foundation

/// 时钟展开面板跟着卡片外观走：像素卡片开点阵屏面板，液晶卡片开数码管面板，
/// 其余各有一套。卡片的画法（`ClockFace`）在这里换成面板的样子。
///
/// 几套面板共用同一组信息（今天进度、世界时钟、农历节气、第几周、下一个日程
/// 或闹钟），只换头部和视觉语言；这些信息的算法都在 `ClockPanelData`。
public enum ClockPanelKind: String, CaseIterable, Sendable {
    case pixel, lcd, classic, analog, flip, words, neon, nixie

    /// 卡片画哪种，面板就开哪种。传进来的是卡片实际画的画法
    /// （`ClockStyles.face(_:unlocked:)`），Pro 样式没解锁时卡片画成翻页，
    /// 面板也跟着开翻页，卡片和面板对得上。
    public static func of(_ face: ClockFace) -> ClockPanelKind {
        switch face {
        case .pixel: .pixel
        case .lcd: .lcd
        case .standard, .bigDigits: .classic
        case .analog, .secondsRing: .analog
        case .flip, .foldFlip, .bigFlipCards: .flip
        case .words: .words
        case .neon: .neon
        case .nixie: .nixie
        }
    }
}

/// 时钟面板上的信息，纯计算，不碰界面和系统服务，方便测试。
public enum ClockPanelData {

    // MARK: 世界时钟城市

    /// 面板里世界时钟的三座城市，存成 "时区|名字" 的列表。
    public static let citiesKey = "clockCities"
    public static let cityCount = 3

    /// 没选过时：伦敦、纽约、东京。
    public static var defaultCities: [WorldCity] {
        [WorldCity(name: tr("伦敦"), zone: "Europe/London"),
         WorldCity(name: tr("纽约"), zone: "America/New_York"),
         WorldCity(name: tr("东京"), zone: "Asia/Tokyo")]
    }

    /// 面板上的三座城市。存的值认不出（时区不存在、格式不对）的那一格用默认。
    public static func cities(_ config: WidgetConfig) -> [WorldCity] {
        let stored = config.strings(citiesKey)
        let fallback = defaultCities
        return (0..<cityCount).map { slot in
            guard slot < stored.count, let city = decode(stored[slot]) else { return fallback[slot] }
            return city
        }
    }

    /// 把第 `slot` 格换成 `city`，其余格原样（没存过的写成默认）。
    public static func set(_ city: WorldCity, at slot: Int, in config: inout WidgetConfig) {
        guard (0..<cityCount).contains(slot) else { return }
        var list = cities(config)
        list[slot] = city
        config.set(citiesKey, .list(list.map { .string(encode($0)) }))
    }

    static func encode(_ city: WorldCity) -> String { "\(city.zone)|\(city.name)" }

    static func decode(_ raw: String) -> WorldCity? {
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard let zone = parts.first, TimeZone(identifier: zone) != nil else { return nil }
        let name = parts.count > 1 && !parts[1].isEmpty ? parts[1] : WorldCities.displayName(zone: zone)
        return WorldCity(name: name, zone: zone)
    }

    // MARK: 今天进度

    public struct DayProgress: Equatable, Sendable {
        /// 0...1，今天过去了多少。
        public var fraction: Double
        /// 卡片上的整数百分比，向下取整。
        public var percent: Int
        /// 离今天结束还有多少分钟，向下取整。
        public var remainingMinutes: Int
    }

    public static func day(_ now: Date, calendar: Calendar = .current) -> DayProgress {
        let fraction = TimeProgress.fraction(.day, now: now, calendar: calendar)
        let end = TimeProgress.interval(.day, now: now, calendar: calendar)?.end ?? now
        let remaining = max(0, Int(end.timeIntervalSince(now) / 60))
        return DayProgress(fraction: fraction, percent: TimeProgress.percent(fraction), remainingMinutes: remaining)
    }

    /// 进度条分 `count` 格时已经走满的格数；当前格是这个下标（走满了没有当前格）。
    public static func filledCells(_ fraction: Double, of count: Int) -> Int {
        guard count > 0, fraction.isFinite else { return 0 }
        return min(count, max(0, Int(fraction * Double(count))))
    }

    /// “14 时 02 分”。
    public static func hoursMinutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let rest = m % 60
        return tr("\(m / 60) 时 \(rest < 10 ? "0\(rest)" : "\(rest)") 分")
    }

    /// “还剩 14 时 02 分”。
    public static func remainingText(_ progress: DayProgress) -> String {
        tr("还剩 \(hoursMinutes(progress.remainingMinutes))")
    }

    // MARK: 世界时钟

    public struct CityTime: Equatable, Sendable {
        public var name: String
        public var zone: String
        /// 当地 24 小时制的时和分。
        public var hour: Int
        public var minute: Int
        /// 当地 06:00 到 18:00 算白天（按钟点，不按日出）。
        public var isDay: Bool
        /// 当地日期比此处早一天是 -1，晚一天是 1。
        public var dayOffset: Int
        /// 当地比此处快多少秒（慢是负数）。
        public var offsetSeconds: Int

        /// “02:57”，两位小时，面板上三列宽度一样。
        public var clock: String {
            (hour < 10 ? "0\(hour)" : "\(hour)") + ":" + (minute < 10 ? "0\(minute)" : "\(minute)")
        }
    }

    public static func cityTime(_ city: WorldCity, now: Date, here: TimeZone = .current) -> CityTime {
        let zone = TimeZone(identifier: city.zone) ?? here
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let c = there.dateComponents([.hour, .minute], from: now)
        let hour = c.hour ?? 0
        return CityTime(name: city.name, zone: city.zone, hour: hour, minute: c.minute ?? 0,
                        isDay: isDaytime(hour: hour), dayOffset: dayOffset(now, zone: zone, here: here),
                        offsetSeconds: zone.secondsFromGMT(for: now) - here.secondsFromGMT(for: now))
    }

    public static func isDaytime(hour: Int) -> Bool { (6..<18).contains(hour) }

    /// 同一刻在两地是不是同一天。
    public static func dayOffset(_ now: Date, zone: TimeZone, here: TimeZone) -> Int {
        func ymd(_ z: TimeZone) -> DateComponents {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = z
            return calendar.dateComponents([.year, .month, .day], from: now)
        }
        let a = ymd(zone), b = ymd(here)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let da = utc.date(from: a), let db = utc.date(from: b) else { return 0 }
        return utc.dateComponents([.day], from: db, to: da).day ?? 0
    }

    /// 时差：“+1”“−7”“+5:30”，用排版减号；相同是 “0”。
    public static func offsetText(_ seconds: Int) -> String {
        guard seconds != 0 else { return "0" }
        let sign = seconds < 0 ? "\u{2212}" : "+"
        let minutes = abs(seconds) / 60
        let rest = minutes % 60
        guard rest != 0 else { return "\(sign)\(minutes / 60)" }
        return "\(sign)\(minutes / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// 城市时间下面那行：“−7 时”，不是同一天时 “昨天 −12”，时差为零是 “同此处”。
    public static func relativeLine(_ city: CityTime) -> String {
        let offset = offsetText(city.offsetSeconds)
        switch city.dayOffset {
        case ..<0: return tr("昨天 \(offset)")
        case 1...: return tr("明天 \(offset)")
        default: return city.offsetSeconds == 0 ? tr("同此处") : tr("\(offset) 时")
        }
    }

    // MARK: 农历、节气

    public struct Lunar: Equatable, Sendable {
        /// “九月十一”。
        public var date: String
        /// “霜降 3 天后”，节气当天是 “今天霜降”。
        public var term: String?
    }

    public static func lunar(_ now: Date) -> Lunar {
        let date = ChineseCalendar.lunar(now).short
        guard let next = ChineseCalendar.nextTerm(after: now) else { return Lunar(date: date, term: nil) }
        let days = ChineseCalendar.days(from: now, to: next.day)
        let name = trKey(next.name)
        return Lunar(date: date, term: days <= 0 ? tr("今天\(name)") : tr("\(name) \(days) 天后"))
    }

    // MARK: 第几周、第几天

    public static func week(_ now: Date, calendar: Calendar = .current) -> (week: Int, dayOfYear: Int) {
        (calendar.component(.weekOfYear, from: now), calendar.ordinality(of: .day, in: .year, for: now) ?? 1)
    }

    // MARK: 下一个日程、闹钟

    public struct Upcoming: Equatable, Sendable {
        public var at: Date
        public var title: String

        public init(at: Date, title: String) {
            self.at = at
            self.title = title
        }
    }

    /// 码头上所有闹钟卡片里，最先要响的一个。没有开着的闹钟是 nil。
    public static func nextAlarm(_ configs: [WidgetConfig], now: Date,
                                 calendar: Calendar = .current) -> Upcoming? {
        configs.compactMap { AlarmBook.upcoming($0, now: now, calendar: calendar).first }
            .min { $0.at < $1.at }
            .map { Upcoming(at: $0.at, title: $0.item.title) }
    }

    /// 接下来 `within` 秒内最先开始的非全天日程。已经开始的不算。
    public static func nextEvent(_ events: [(start: Date, title: String, allDay: Bool)], now: Date,
                                 within: TimeInterval = 24 * 3600) -> Upcoming? {
        events.filter { !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= within }
            .min { ($0.start, $0.title) < ($1.start, $1.title) }
            .map { Upcoming(at: $0.start, title: $0.title.isEmpty ? tr("日程") : $0.title) }
    }

    /// 不是今天时，标题前面的 “明天”（再往后写几月几日）。
    public static func dayWord(_ date: Date, now: Date, calendar: Calendar = .current) -> String? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return nil
        case 1: return tr("明天")
        default:
            let c = calendar.dateComponents([.month, .day], from: date)
            return tr("\(c.month ?? 1)月\(c.day ?? 1)日")
        }
    }

    /// “4 时后”“35 分后”“马上”。
    public static func untilShort(_ date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 1 { return tr("马上") }
        if minutes < 60 { return tr("\(minutes) 分后") }
        return tr("\(minutes / 60) 时后")
    }

    /// 24 小时制 “07:30”。
    public static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        AlarmBook.clockText(date, calendar: calendar)
    }

    // MARK: 日出日落

    /// 昼长 “11 时 04 分”。
    public static func daylightText(rise: Date, set: Date) -> String {
        hoursMinutes(Int(set.timeIntervalSince(rise) / 60))
    }
}
