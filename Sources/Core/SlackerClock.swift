import Foundation

/// 摸鱼时钟：工作日倒数下班，非工作日祝周末快乐，下面四个小格是发薪、周五、
/// 下一个节日和今天赚了多少。
///
/// 全部是纯函数，时间、日历和节假日安排都由调用方传进来，测试可以把时钟
/// 拨到任意一秒。卡片和面板只负责画。
///
/// 规则（也写在 README 里）：
/// - 工作日 = 设置里勾选的星期几；打开“按法定节假日”时，法定放假日不上班，
///   调休上班日要上班（安排来自 `HolidaySchedule`，和“农历与假期”同一份）。
/// - 工作时间是 [开始, 结束)，结束必须晚于开始，否则按 09:00 到 18:00。
/// - 上班前 2 小时内显示“距离上班 HH:MM”，更早显示“还没上班”；
///   下班后 2 小时内显示“下班啦”，之后显示“休息时间”。
/// - 非工作日：周六周日“周末快乐”，其他星期几“休息日快乐”，
///   法定节日窗口里显示“国庆快乐”“春节快乐”，清明和端午是“安康”。
public enum SlackerClock {

    // MARK: Keys

    public static let workdaysKey = "workdays"
    public static let startKey = "start"
    public static let endKey = "end"
    public static let paydayKey = "payday"
    public static let incomeKey = "income"
    /// 金额后面的货币符号。新放的按地区写（`RegionalDefaults`），老卡片没有这个键，照旧是 ¥。
    public static let currencyKey = "currency"
    public static let itemsKey = "more"
    public static let fontKey = "font"
    public static let tintKey = "tint"
    public static let holidaysKey = "holidays"
    public static let lookKey = "look"
    /// 只在面板里改，不出现在设置的通用控件里。
    public static let backgroundKey = "background"
    public static let backgroundImageKey = "backgroundImage"
    public static let textColorKey = "textColor"

    // MARK: Defaults

    public static let defaultStart = 9 * 60
    public static let defaultEnd = 18 * 60
    public static let defaultPayday = 15
    public static let defaultIncome = 100.0
    public static let incomeRange = 0.0...100_000.0
    public static let incomeStep = 10.0
    public static let paydayRange = 1...31
    /// 周一到周五，按 ISO 写法 1 是周一、7 是周日。
    public static let weekdays: [Int] = [1, 2, 3, 4, 5]

    /// 三种状态各自的底色：上班橙（小熊猫主题色）、下班绿、周末蓝。
    public static let workHex = "#E8743B"
    public static let restHex = "#6FAE47"
    public static let weekendHex = "#3D8FD6"
    /// 背景的默认颜色就是小熊猫橙。
    public static let defaultBackgroundHex = workHex
    public static let defaultTextHex = "#FFFFFF"

    /// 背景预设色，第一个是默认的小熊猫橙。
    public static let backgroundSwatches: [String] = [
        "#E8743B", "#6FAE47", "#3D8FD6", "#F2B33D", "#D9534F", "#8E6CC7",
        "#4A3B34", "#2F4858", "#1C1C1E", "#F4EFE6",
    ]

    /// 字体颜色预设。
    public static let textSwatches: [String] = [
        "#FFFFFF", "#1C1C1E", "#FFE08A", "#FFD1DC", "#BDE6FF", "#C8F0C0", "#5A3A22",
    ]

    /// 设置里的星期选项，标题和存进配置的值。
    public static let weekdayChoices: [(title: String, value: String)] = [
        (tr("周一"), "1"), (tr("周二"), "2"), (tr("周三"), "3"), (tr("周四"), "4"),
        (tr("周五"), "5"), (tr("周六"), "6"), (tr("周日"), "7"),
    ]

    /// 卡片上的几种字体。
    public enum FontChoice: String, CaseIterable, Sendable {
        case system, rounded, mono, serif

        public var title: String {
            switch self {
            case .system: tr("系统")
            case .rounded: tr("圆体")
            case .mono: tr("等宽")
            case .serif: tr("宋体")
            }
        }
    }

    /// “显示更多”的四个小格，顺序就是卡片上的顺序。
    public enum Item: String, CaseIterable, Sendable, Identifiable {
        case payday, friday, holiday, earned

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .payday: tr("发薪日")
            case .friday: tr("距离周五")
            case .holiday: tr("下一个节日")
            case .earned: tr("今天收入")
            }
        }
    }

    public static let maxItems = 4

    /// 卡片外观：小熊猫插画（默认）或液态。液态在插画后面加一层水，
    /// 水位是今天的工作进度，越接近下班越满，下班那一分钟水面闪金光，
    /// 不上班的日子水满且静止。小熊猫和文字都还在。
    public enum Look: String, CaseIterable, Sendable {
        case illustrated, liquid

        public var title: String {
            switch self {
            case .illustrated: tr("小熊猫")
            case .liquid: tr("液态")
            }
        }
    }

    /// 没有这个键的旧卡片和新加的卡片都是小熊猫插画。
    public static func look(_ config: WidgetConfig) -> Look {
        Look(rawValue: config.string(lookKey, default: Look.illustrated.rawValue)) ?? .illustrated
    }

    // MARK: Settings

    /// 一个摸鱼时钟的设置，从配置里读出来，缺的项用默认值。
    public struct Settings: Equatable, Sendable {
        /// ISO 星期：1 是周一，7 是周日。
        public var workdays: Set<Int>
        /// 一天里的分钟数。
        public var start: Int
        public var end: Int
        public var payday: Int
        public var income: Double
        public var items: [Item]
        public var followsHolidays: Bool
        public var currencySymbol: String

        public init(workdays: Set<Int> = Set(SlackerClock.weekdays),
                    start: Int = SlackerClock.defaultStart, end: Int = SlackerClock.defaultEnd,
                    payday: Int = SlackerClock.defaultPayday, income: Double = SlackerClock.defaultIncome,
                    items: [Item] = Item.allCases, followsHolidays: Bool = true,
                    currencySymbol: String = "¥") {
            self.workdays = workdays
            let window = SlackerClock.window(start: start, end: end)
            self.start = window.start
            self.end = window.end
            self.payday = min(max(payday, 1), 31)
            self.income = income.isFinite ? min(max(income, SlackerClock.incomeRange.lowerBound),
                                                SlackerClock.incomeRange.upperBound) : SlackerClock.defaultIncome
            self.items = SlackerClock.items(items.map(\.rawValue))
            self.followsHolidays = followsHolidays
            let symbol = currencySymbol.trimmingCharacters(in: .whitespaces)
            self.currencySymbol = symbol.isEmpty ? "¥" : String(symbol.prefix(4))
        }

        public init(config: WidgetConfig) {
            let days = Set(config.strings(SlackerClock.workdaysKey,
                                          default: SlackerClock.weekdays.map(String.init)).compactMap(Int.init)
                .filter { (1...7).contains($0) })
            self.init(workdays: days,
                      start: PostureSchedule.minutes(config.string(SlackerClock.startKey, default: "09:00")) ?? -1,
                      end: PostureSchedule.minutes(config.string(SlackerClock.endKey, default: "18:00")) ?? -1,
                      payday: Int(config.double(SlackerClock.paydayKey, default: Double(SlackerClock.defaultPayday))),
                      income: config.double(SlackerClock.incomeKey, default: SlackerClock.defaultIncome),
                      items: SlackerClock.items(config.strings(SlackerClock.itemsKey,
                                                               default: Item.allCases.map(\.rawValue))),
                      followsHolidays: config.bool(SlackerClock.holidaysKey, default: true),
                      currencySymbol: config.string(SlackerClock.currencyKey, default: "¥"))
        }

        /// 一天上班多少秒。
        public var workSeconds: Double { Double(end - start) * 60 }
    }

    /// 结束必须晚于开始；不合格（含跨午夜）时退回 09:00 到 18:00。
    public static func window(start: Int, end: Int) -> (start: Int, end: Int) {
        let valid = (0..<1440).contains(start) && (1...1440).contains(end) && end > start
        return valid ? (start, end) : (defaultStart, defaultEnd)
    }

    /// 结束时间是否晚于开始，面板用来拦住不合格的输入。
    public static func isValidWindow(start: Int, end: Int) -> Bool {
        (0..<1440).contains(start) && (1...1440).contains(end) && end > start
    }

    /// 认得的小格按固定顺序排好，去重，最多 4 个。
    public static func items(_ raw: [String]) -> [Item] {
        // 按设置里拖好的先后（`OrderedChecklist`），不再固定按目录顺序。
        let ordered = OrderedChecklist.ordered(raw, all: Item.allCases.map(\.rawValue))
        return Array(ordered.compactMap(Item.init(rawValue:)).prefix(maxItems))
    }

    // MARK: Calendar

    /// 公历，本机时区，周一开头：工作时间按这台 Mac 的钟走。
    /// 法定节假日按北京时间的日期认（`HolidaySchedule`），在国内两者一致。
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        return calendar
    }

    /// ISO 星期：1 是周一，7 是周日。
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    /// 这一天上不上班。
    public static func isWorkday(_ date: Date, settings: Settings, calendar: Calendar,
                                 known: [Int: [HolidayDay]]) -> Bool {
        if settings.followsHolidays {
            switch HolidaySchedule.kind(of: date, known: known) {
            case .holiday: return false
            case .makeupWorkday: return true
            case .weekend, .workday: break
            }
        }
        return settings.workdays.contains(isoWeekday(date, calendar: calendar))
    }

    // MARK: Phase

    public enum Phase: Equatable, Sendable {
        /// 工作日、上班前，还有多少秒上班。
        case beforeWork(secondsLeft: Int)
        /// 工作日、上班中，还有多少秒下班。
        case working(secondsLeft: Int)
        /// 工作日、下班后，已经下班多少秒。
        case afterWork(secondsSince: Int)
        /// 不上班的一天；`greeting` 是标题。
        case dayOff(greeting: String)

        public var art: Art {
            switch self {
            case .working: .work
            case .beforeWork, .afterWork: .rest
            case .dayOff: .weekend
            }
        }
    }

    /// 三张小熊猫图。
    public enum Art: String, CaseIterable, Sendable {
        case work, rest, weekend

        /// Resources/Slacker 里的文件名（不含扩展名）。
        public var imageName: String { "slacker-panda-\(rawValue)-512" }

        /// 随状态变色时的底色。
        public var hex: String {
            switch self {
            case .work: SlackerClock.workHex
            case .rest: SlackerClock.restHex
            case .weekend: SlackerClock.weekendHex
            }
        }
    }

    /// 上班前多久开始倒数，下班后多久还算“下班啦”。
    public static let leadSeconds = 2 * 3600
    public static let justOffSeconds = 2 * 3600

    public static func phase(now: Date, settings: Settings, calendar: Calendar = SlackerClock.calendar,
                             known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Phase {
        guard isWorkday(now, settings: settings, calendar: calendar, known: known) else {
            return .dayOff(greeting: greeting(now, settings: settings, calendar: calendar, known: known))
        }
        let midnight = calendar.startOfDay(for: now)
        let second = Int(now.timeIntervalSince(midnight).rounded(.down))
        let start = settings.start * 60, end = settings.end * 60
        if second < start { return .beforeWork(secondsLeft: start - second) }
        if second < end { return .working(secondsLeft: end - second) }
        return .afterWork(secondsSince: second - end)
    }

    /// 标题。
    public static func title(_ phase: Phase) -> String {
        switch phase {
        case .working(let left):
            return tr("距离下班 \(clock(seconds: left))")
        case .beforeWork(let left):
            return left <= leadSeconds ? tr("距离上班 \(clockMinutes(seconds: left))") : tr("还没上班")
        case .afterWork(let since):
            return since < justOffSeconds ? tr("下班啦") : tr("休息时间")
        case .dayOff(let greeting):
            return greeting
        }
    }

    /// 窄的侧边栏放不下一整行，拆成上下两行：“距离下班”和“02:35:18”。
    public static func titleLines(_ phase: Phase) -> (top: String, bottom: String?) {
        switch phase {
        case .working(let left):
            return (tr("距离下班"), clock(seconds: left))
        case .beforeWork(let left) where left <= leadSeconds:
            return (tr("距离上班"), clockMinutes(seconds: left))
        default:
            return (title(phase), nil)
        }
    }

    /// 02:35:18。
    public static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
    }

    /// 01:05，向上取整到分钟，还差 10 秒时显示 00:01 而不是 00:00。
    public static func clockMinutes(seconds: Int) -> String {
        let minutes = (max(0, seconds) + 59) / 60
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: Holidays

    /// 法定节日的祝福窗口：元旦、春节、清明、劳动节、端午、中秋、国庆。
    /// 春节、清明、端午、中秋、国庆、元旦沿用竹篮节日徽章的窗口。
    public static let legalFestivals: [(name: String, window: FestivalWindow)] = {
        var list: [(String, FestivalWindow)] = []
        for badge in [PerfectBadge.festNewYear, .festSpring, .festQingming, .festDragonBoat,
                      .festMidAutumn, .festNational] {
            if let window = badge.festivalWindow { list.append((badge.title, window)) }
        }
        list.insert((tr("劳动节"), FestivalWindow(.gregorian, from: .init(5, 1), to: .init(5, 5))), at: 3)
        return list
    }()

    /// “国庆快乐”“清明安康”。
    public static func greeting(festival name: String) -> String {
        let short = HolidaySchedule.shortName(name)
        return ["清明", "端午"].contains(short) ? tr("\(trKey(short))安康") : tr("\(trKey(short))快乐")
    }

    /// 不上班那天的标题。
    static func greeting(_ date: Date, settings: Settings, calendar: Calendar,
                         known: [Int: [HolidayDay]]) -> String {
        if settings.followsHolidays, case .holiday(let name) = HolidaySchedule.kind(of: date, known: known) {
            return greeting(festival: name)
        }
        if let festival = legalFestivals.first(where: { $0.window.contains(date, base: calendar) }) {
            return greeting(festival: festival.name)
        }
        let weekday = isoWeekday(date, calendar: calendar)
        return weekday >= 6 ? tr("周末快乐") : tr("休息日快乐")
    }

    /// 下一个节日，和竹篮的节日限定徽章是同一份名单、同一套窗口。
    public struct NextFestival: Equatable, Sendable {
        public var name: String
        /// 0 表示今天就在节日窗口里。
        public var days: Int
    }

    /// 小格上的节日名：“重阳节”“国庆节”“春节”“七夕”“世界水日”。
    public static func festivalName(_ badge: PerfectBadge) -> String {
        switch badge {
        case .festLantern, .festQingming, .festDragonBoat, .festMidAutumn, .festNational, .festDoubleNinth:
            tr("\(badge.title)节")
        default:
            badge.title
        }
    }

    public static func nextFestival(after now: Date, calendar: Calendar = SlackerClock.calendar) -> NextFestival? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        var best: NextFestival?
        for badge in PerfectBadge.allCases {
            guard let window = badge.festivalWindow else { continue }
            for y in (year - 1)...(year + 1) {
                guard let occurrence = window.occurrence(inYear: y, base: calendar) else { continue }
                let start = calendar.startOfDay(for: occurrence.start)
                let end = calendar.startOfDay(for: occurrence.end)
                let days: Int
                if start <= today, today <= end {
                    days = 0
                } else if start > today {
                    days = calendar.dateComponents([.day], from: today, to: start).day ?? Int.max
                } else {
                    continue
                }
                if days < (best?.days ?? Int.max) {
                    best = NextFestival(name: festivalName(badge), days: days)
                }
            }
        }
        return best
    }

    // MARK: Payday and Friday

    /// 离发薪还有几天，0 是今天。月份没有那一天（比如 31 号遇上 4 月）时取月末。
    public static func daysUntilPayday(_ payday: Int, now: Date, calendar: Calendar = SlackerClock.calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let thisMonth = paydayDate(payday, monthOf: today, calendar: calendar)
        if let thisMonth, thisMonth >= today {
            return calendar.dateComponents([.day], from: today, to: thisMonth).day ?? 0
        }
        guard let nextMonthDay = calendar.date(byAdding: .month, value: 1, to: firstOfMonth(today, calendar: calendar)),
              let next = paydayDate(payday, monthOf: nextMonthDay, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: today, to: next).day ?? 0
    }

    /// 某个月的发薪日（零点）。
    public static func paydayDate(_ payday: Int, monthOf date: Date, calendar: Calendar) -> Date? {
        let first = firstOfMonth(date, calendar: calendar)
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        let day = min(max(payday, 1), length)
        return calendar.date(byAdding: .day, value: day - 1, to: first)
    }

    static func firstOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// 离周五还有几天，周五当天是 0，周六是 6。
    public static func daysUntilFriday(_ now: Date, calendar: Calendar = SlackerClock.calendar) -> Int {
        (5 - isoWeekday(now, calendar: calendar) + 7) % 7
    }

    /// 离下一个上班日还有几天（从明天找起，最多找 60 天，找不到是 nil）。
    public static func daysUntilWork(_ now: Date, settings: Settings, calendar: Calendar = SlackerClock.calendar,
                                     known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Int? {
        let today = calendar.startOfDay(for: now)
        for offset in 1...60 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if isWorkday(day, settings: settings, calendar: calendar, known: known) { return offset }
        }
        return nil
    }

    // MARK: Money

    /// 今天赚了多少：工作时间内按已工作的比例，上班前 0，下班后满额，不上班的日子 0。
    public static func earnedToday(phase: Phase, settings: Settings) -> Double {
        switch phase {
        case .beforeWork, .dayOff: return 0
        case .afterWork: return settings.income
        case .working(let left):
            let total = settings.workSeconds
            guard total > 0 else { return 0 }
            let done = min(max(total - Double(left), 0), total)
            return settings.income * done / total
        }
    }

    /// 本月已赚：日收入 x 本月 1 号到今天（含）已经过去的工作日数。
    /// 今天是工作日时只有下班后才算进去，周末和节假日今天本来就不算。
    public static func earnedThisMonth(now: Date, settings: Settings, calendar: Calendar = SlackerClock.calendar,
                                       known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Double {
        Double(workdaysPassedThisMonth(now: now, settings: settings, calendar: calendar, known: known)) * settings.income
    }

    public static func workdaysPassedThisMonth(now: Date, settings: Settings, calendar: Calendar = SlackerClock.calendar,
                                               known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Int {
        let today = calendar.startOfDay(for: now)
        var day = firstOfMonth(today, calendar: calendar)
        var count = 0
        while day < today {
            if isWorkday(day, settings: settings, calendar: calendar, known: known) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if case .afterWork = phase(now: now, settings: settings, calendar: calendar, known: known) { count += 1 }
        return count
    }

    /// 68.50；保留两位小数。
    public static func money(_ value: Double) -> String {
        String(format: "%.2f", max(0, value))
    }

    /// 本月已赚：整数时不带小数（1800），否则两位小数。
    public static func monthMoney(_ value: Double) -> String {
        let v = max(0, value)
        return v == v.rounded() && v < 1e9 ? String(Int(v)) : String(format: "%.2f", v)
    }

    // MARK: Cells

    /// 一个小格：上面一行小字，下面一行数字和单位。
    public struct Cell: Equatable, Sendable, Identifiable {
        public var item: Item
        public var label: String
        public var value: String
        public var unit: String

        public var id: String { item.rawValue }

        public init(item: Item, label: String, value: String, unit: String) {
            self.item = item
            self.label = label
            self.value = value
            self.unit = unit
        }
    }

    /// 卡片和面板读到的全部内容，一次算好。
    public struct Reading: Equatable, Sendable {
        public var phase: Phase
        public var title: String
        public var cells: [Cell]

        public var art: Art { phase.art }
    }

    public static func reading(now: Date, settings: Settings, calendar: Calendar = SlackerClock.calendar,
                               known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Reading {
        let phase = Self.phase(now: now, settings: settings, calendar: calendar, known: known)
        let cells = settings.items.map { item in
            cell(item, now: now, phase: phase, settings: settings, calendar: calendar, known: known)
        }
        return Reading(phase: phase, title: title(phase), cells: cells)
    }

    public static func cell(_ item: Item, now: Date, phase: Phase, settings: Settings,
                            calendar: Calendar = SlackerClock.calendar,
                            known: [Int: [HolidayDay]] = HolidaySchedule.bundled) -> Cell {
        switch item {
        case .payday:
            let days = daysUntilPayday(settings.payday, now: now, calendar: calendar)
            return days == 0 ? Cell(item: item, label: tr("今天"), value: tr("发薪"), unit: "")
                             : Cell(item: item, label: tr("发薪"), value: "\(days)", unit: tr("天"))
        case .friday:
            if case .dayOff = phase {
                let days = daysUntilWork(now, settings: settings, calendar: calendar, known: known)
                return Cell(item: item, label: tr("上班"), value: days.map(String.init) ?? "--", unit: tr("天"))
            }
            let days = daysUntilFriday(now, calendar: calendar)
            return days == 0 ? Cell(item: item, label: tr("周五"), value: tr("就是"), unit: tr("今天"))
                             : Cell(item: item, label: tr("周五"), value: "\(days)", unit: tr("天"))
        case .holiday:
            guard let next = nextFestival(after: now, calendar: calendar) else {
                return Cell(item: item, label: tr("节日"), value: "--", unit: "")
            }
            return next.days == 0 ? Cell(item: item, label: next.name, value: tr("就是"), unit: tr("今天"))
                                  : Cell(item: item, label: next.name, value: "\(next.days)", unit: tr("天"))
        case .earned:
            if case .dayOff = phase {
                let month = earnedThisMonth(now: now, settings: settings, calendar: calendar, known: known)
                return Cell(item: item, label: tr("本月已赚"), value: monthMoney(month), unit: settings.currencySymbol)
            }
            return Cell(item: item, label: tr("今天赚了"), value: money(earnedToday(phase: phase, settings: settings)),
                        unit: settings.currencySymbol)
        }
    }

    // MARK: Liquid

    /// 液态的水位 0...1：上班前空，上班中按已工作的比例，下班后满，
    /// 不上班的日子也是满的（休息满格）。
    public static func waterLevel(_ phase: Phase, settings: Settings) -> Double {
        switch phase {
        case .beforeWork: return 0
        case .afterWork, .dayOff: return 1
        case .working(let left):
            let total = settings.workSeconds
            guard total > 0 else { return 0 }
            return min(max((total - Double(left)) / total, 0), 1)
        }
    }

    /// 下班后多少秒内水面闪金光。
    public static let goldenSeconds = 60

    /// 刚下班的这一分钟。
    public static func isGolden(_ phase: Phase) -> Bool {
        if case .afterWork(let since) = phase { return since < goldenSeconds }
        return false
    }

    /// 液态的帧率，nil 表示一张静止的图：减少动态效果、卡片看不见、
    /// 或者不上班的日子（水面静止）都不动；闪金光时 30 帧，平时 10 帧的慢波纹。
    public static func liquidFPS(_ phase: Phase, visible: Bool, reduceMotion: Bool) -> Double? {
        guard visible, !reduceMotion else { return nil }
        if case .dayOff = phase { return nil }
        return isGolden(phase) ? 30 : 10
    }

    // MARK: Look

    /// 卡片底色：随状态变色时用三种状态色，否则用设置的背景色。
    public static func backgroundHex(_ config: WidgetConfig, art: Art) -> String {
        if config.bool(tintKey, default: true) { return art.hex }
        let hex = config.string(backgroundKey, default: defaultBackgroundHex)
        return ColorCode(hex: hex) == nil ? defaultBackgroundHex : hex
    }

    public static func textHex(_ config: WidgetConfig) -> String {
        let hex = config.string(textColorKey, default: defaultTextHex)
        return ColorCode(hex: hex) == nil ? defaultTextHex : hex
    }

    public static func font(_ config: WidgetConfig) -> FontChoice {
        FontChoice(rawValue: config.string(fontKey, default: FontChoice.system.rawValue)) ?? .system
    }

    // MARK: Size

    /// 底部扩展栏上的宽度：标题或小格（取宽的那个），加右边的小熊猫。
    public static func tileWidth(count: Int) -> Double {
        let n = max(0, min(count, maxItems))
        let cells = Double(n) * cellWidth + Double(max(0, n - 1)) * cellSpacing
        return max(titleWidth, cells) + pandaWidth + 26
    }

    public static let cellWidth = 46.0
    public static let cellSpacing = 4.0
    public static let titleWidth = 152.0
    public static let pandaWidth = 60.0

    /// 侧边栏里竖着排：小熊猫、标题两行，下面一格一行。
    public static func columnHeight(count: Int) -> Double {
        let rows = max(0, min(count, maxItems))
        return 96 + Double(rows) * columnCellPitch
    }

    public static let columnCellPitch = 28.0

    /// 用户背景图（只在不随状态变色、并且选过图片时用）。
    public static func backgroundImagePath(_ config: WidgetConfig) -> String? {
        guard !config.bool(tintKey, default: true) else { return nil }
        let path = config.string(backgroundImageKey, default: "")
        return path.isEmpty ? nil : path
    }
}
