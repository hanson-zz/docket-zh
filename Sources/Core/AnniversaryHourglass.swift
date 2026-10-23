import Foundation

/// 纪念日改版：沙漏样式、沙量、临近判断、面板要用的几组数。
///
/// - 单个卡片三种样式，存在 `hourglass` 键（`AnniversaryLook`）：极简线条沙漏（免费，
///   新放的卡片默认）、玻璃沙漏（Pro）、原来的撕页日历。没存这个键的老卡片按撕页读，
///   升级后长得和原来一样，不打扰老用户。玻璃沙漏没解锁时画成线条沙漏，不盖锁、
///   不改写配置，解锁或试用时自动回来（和收音机皮肤一样）。
/// - 沙漏上半的沙量是 `1 - reading.progress`：这一轮还剩多少。离下一次（正数日是下一个
///   周年）只剩 `nearDays` 天以内时沙变暖橙、沙流跳动、写「临近」；当天换成小熊猫捧场。
/// - 沙一律是自然沙色，事件色只用在名字和端盖上。
///
/// 都是纯函数，卡片和面板只管按这些数画。

/// 单个纪念日卡片的样式。
public enum AnniversaryLook: String, CaseIterable, Sendable {
    /// 极简线条沙漏：单色描边、平涂沙，免费，新放的卡片默认。
    case line
    /// 玻璃沙漏：折射高光、立柱端盖，和液态外观同一套，Pro。
    case glass
    /// 原来的撕页日历，老卡片保持这个。
    case leaf

    public static let key = "hourglass"
    /// 没存 `hourglass` 的老卡片按撕页读，和目录默认值一致。
    public static let legacy: AnniversaryLook = .leaf
    /// 新放的纪念日写进去的样式。
    public static let newWidget: AnniversaryLook = .line

    public var title: String {
        switch self {
        case .line: tr("线条沙漏")
        case .glass: tr("玻璃沙漏")
        case .leaf: tr("撕页日历")
        }
    }

    /// 只有玻璃沙漏是 Pro。
    public var isPro: Bool { self == .glass }

    /// 存着的样式，认不出的值按撕页读。
    public static func stored(_ config: WidgetConfig) -> AnniversaryLook {
        AnniversaryLook(rawValue: config.string(key, default: legacy.rawValue)) ?? legacy
    }

    /// 卡片上实际画哪种：没解锁时玻璃沙漏退回线条沙漏。
    public static func shown(config: WidgetConfig, unlocked: Bool) -> AnniversaryLook {
        let look = stored(config)
        return look.isPro && !unlocked ? .line : look
    }

    /// 画沙漏的地方（面板、多个卡片的高亮行）用哪种沙漏：撕页卡片也画线条沙漏。
    public static func hourglass(config: WidgetConfig, unlocked: Bool) -> AnniversaryLook {
        let look = shown(config: config, unlocked: unlocked)
        return look == .leaf ? .line : look
    }
}

/// 沙漏这一刻的状态。
public enum AnniversarySandMood: Equatable, Sendable {
    /// 平常：自然沙色，沙流一根静止细线。
    case calm
    /// 临近（`Anniversary.nearDays` 天以内）：沙变暖橙，沙流跳动。
    case near
    /// 就是今天：卡片换成小熊猫捧场，不画沙漏。
    case today
    /// 一次性的倒数日已经过去：沙全在下面，不再流。
    case spent
}

/// 沙漏里的沙。
public struct AnniversarySand: Equatable, Sendable {
    /// 上半剩下的比例，0...1。
    public var upper: Double
    /// 下半堆起来的比例，0...1，和 `upper` 加起来是 1。
    public var lower: Double
    public var mood: AnniversarySandMood
    /// 离下一次还有几天（正数日是下一个周年），不会再来时是 nil。
    public var daysToGo: Int?

    /// 画不画沙流：平常和临近、上面还有沙时画。
    public var flows: Bool { (mood == .calm || mood == .near) && upper > 0.005 }

    /// 沙流跳不跳：只在临近、上面还有沙、没开减少动态效果时跳。
    public func pulses(reduceMotion: Bool) -> Bool {
        mood == .near && flows && !reduceMotion
    }
}

/// 专属页的周期进度条：这一轮从哪天到哪天、已经过了几天。
public struct AnniversaryCycle: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var elapsed: Int
    public var total: Int

    public var fraction: Double { total > 0 ? min(1, max(0, Double(elapsed) / Double(total))) : 0 }
    public var percent: Int { Int((fraction * 100).rounded(.down)) }
}

/// 天、时、分三格。
public struct AnniversaryClock: Equatable, Sendable {
    public var days: Int
    public var hours: Int
    public var minutes: Int
}

/// 多个纪念日面板时间轴上的一行。
public struct AnniversaryAgendaItem: Equatable, Sendable, Identifiable {
    public var reading: AnniversaryReading
    /// 下一次到来那天（正数日是下一个周年，还没开始的正数日是那天本身）。
    public var date: Date
    /// 还有几天，今天是 0。
    public var daysLeft: Int
    /// 正数日的第几个周年，没开始或倒数日是 nil。
    public var ordinal: Int?

    public var id: String { reading.event.id }
}

extension Anniversary {
    /// 临近的阈值，固定 7 天。
    public static let nearDays = 7

    /// 单个卡片点开的面板 340 宽，多个卡片点开 328 宽。
    public static func panelWidth(layout: String) -> Double {
        layout == "multi" ? 328 : 340
    }

    /// 那一天就是今天：倒数日到了，正数日开始那天，或者每年重复的正数日的周年。
    public static func isCelebrating(_ reading: AnniversaryReading) -> Bool {
        reading.phase == .today || reading.isToday
    }

    /// 离下一次还有几天，今天是 0；不会再来时是 nil。
    ///
    /// 倒数日是下一次到来；还没开始的正数日是开始那天；已经在数的正数日只有勾了
    /// 「每年」才算下一个周年（没勾的周年那天卡片也不庆祝，就不提前说临近）。
    public static func daysToGo(_ reading: AnniversaryReading, today: Date,
                                calendar: Calendar = Anniversary.calendar) -> Int? {
        let start = calendar.startOfDay(for: today)
        switch reading.event.kind {
        case .countdown:
            return reading.next.map { days(from: start, to: $0, calendar: calendar) }
        case .countup:
            switch reading.phase {
            case .upcoming: return reading.days
            case .today: return 0
            case .past:
                guard reading.event.yearly else { return nil }
                return upcomingAnniversaries(reading.event, today: start, count: 1, calendar: calendar).first?.daysLeft
            }
        }
    }

    /// 临近：离下一次 1 到 7 天（当天算庆祝，不算临近）。
    public static func isNear(_ reading: AnniversaryReading, today: Date,
                              calendar: Calendar = Anniversary.calendar) -> Bool {
        guard !isCelebrating(reading), let left = daysToGo(reading, today: today, calendar: calendar) else {
            return false
        }
        return (1...nearDays).contains(left)
    }

    /// 沙漏里的沙：上半 = 1 - progress，下半 = progress。
    public static func sand(_ reading: AnniversaryReading, today: Date,
                            calendar: Calendar = Anniversary.calendar) -> AnniversarySand {
        let progress = min(1, max(0, reading.progress.isFinite ? reading.progress : 0))
        let left = daysToGo(reading, today: today, calendar: calendar)
        let mood: AnniversarySandMood
        if isCelebrating(reading) {
            mood = .today
        } else if reading.event.kind == .countdown, reading.phase == .past {
            mood = .spent
        } else if isNear(reading, today: today, calendar: calendar) {
            mood = .near
        } else {
            mood = .calm
        }
        if mood == .spent { return AnniversarySand(upper: 0, lower: 1, mood: mood, daysToGo: left) }
        return AnniversarySand(upper: 1 - progress, lower: progress, mood: mood, daysToGo: left)
    }

    /// 沙流上三颗跳动的沙粒在时刻 `t`（秒）的位置，0 是细腰，1 是沙堆顶。
    /// 每颗约 0.9 秒落一趟，三颗错开三分之一。
    public static func flowDots(t: Double, count: Int = 3, period: Double = 0.9) -> [Double] {
        guard count > 0, period > 0, t.isFinite else { return [] }
        let local = t.truncatingRemainder(dividingBy: 3600)
        return (0..<count).map { index in
            let phase = local / period + Double(index) / Double(count)
            let f = phase - phase.rounded(.down)
            return f < 0 ? f + 1 : f
        }
    }

    // MARK: Panel

    /// 专属页大字下面的天、时、分。
    ///
    /// 还没到的：到那天零点还有几天几时几分（71 天在 16:40 是 70 天 7 时 20 分）。
    /// 已经开始数的正数日和过去的倒数日：从那天零点起过去了几天几时几分。
    public static func clock(_ reading: AnniversaryReading, now: Date) -> AnniversaryClock {
        let target: Date
        let counting: Bool
        switch reading.phase {
        case .upcoming:
            target = reading.event.kind == .countdown ? (reading.next ?? reading.original) : reading.original
            counting = true
        case .today:
            return AnniversaryClock(days: 0, hours: 0, minutes: 0)
        case .past:
            target = reading.original
            counting = false
        }
        let seconds = counting ? target.timeIntervalSince(now) : now.timeIntervalSince(target)
        let minutes = max(0, Int((seconds / 60).rounded(.down)))
        return AnniversaryClock(days: minutes / 1440, hours: minutes / 60 % 24, minutes: minutes % 60)
    }

    /// 这一轮的起止和已经过去的天数，和 `reading.progress` 用同一种算法。
    ///
    /// 每年重复的倒数日：上一次到这一次。一次性的倒数日和还没开始的正数日：到那天之前
    /// 的 365 天。已经在数的正数日：上一个周年到下一个周年。过去了的一次性倒数日没有。
    public static func cycle(_ reading: AnniversaryReading, today: Date,
                             calendar: Calendar = Anniversary.calendar) -> AnniversaryCycle? {
        let start = calendar.startOfDay(for: today)
        let event = reading.event
        func window(to end: Date) -> AnniversaryCycle? {
            let left = days(from: start, to: end, calendar: calendar)
            if event.yearly, end > reading.original {
                let year = calendar.component(.year, from: end)
                let previous = ((year - 2)...year).reversed().lazy
                    .compactMap { occurrence(event, year: $0, calendar: calendar) }
                    .first { $0 < end }
                if let previous {
                    let total = max(1, days(from: previous, to: end, calendar: calendar))
                    return AnniversaryCycle(start: previous, end: end, elapsed: total - min(left, total), total: total)
                }
            }
            guard let begin = calendar.date(byAdding: .day, value: -365, to: end) else { return nil }
            return AnniversaryCycle(start: begin, end: end, elapsed: 365 - min(left, 365), total: 365)
        }
        switch (event.kind, reading.phase) {
        case (.countdown, .past):
            return nil
        case (.countdown, _):
            return reading.next.flatMap(window)
        case (.countup, .upcoming):
            return window(to: reading.original)
        case (.countup, .today):
            return nil
        case (.countup, .past):
            let last = lastAnniversary(event, original: reading.original, today: start, calendar: calendar)
            let year = calendar.component(.year, from: last.date)
            guard let following = (year...(year + 2)).lazy
                .compactMap({ occurrence(event, year: $0, calendar: calendar) })
                .first(where: { $0 > last.date }) else { return nil }
            let total = max(1, days(from: last.date, to: following, calendar: calendar))
            return AnniversaryCycle(start: last.date, end: following,
                                    elapsed: min(total, days(from: last.date, to: start, calendar: calendar)),
                                    total: total)
        }
    }

    /// 专属页「接下来几次」：每年重复的和正数日是接下来的几个周年（今天也算），
    /// 一次性的倒数日只有那一天，过去了就没有。
    public static func nextTimes(_ event: AnniversaryEvent, today: Date, count: Int = 3,
                                 calendar: Calendar = Anniversary.calendar) -> [AnniversaryOccurrence] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: today)
        if event.kind == .countup || event.yearly {
            var result: [AnniversaryOccurrence] = []
            // 还没到的第一次（还没开始的正数日、第一次还没到的每年倒数日）就是选的那天，
            // 算第 0 个；之后的周年从它往后数。
            if let original = date(fromKey: event.day, calendar: calendar), original >= start {
                result.append(AnniversaryOccurrence(ordinal: 0, date: original,
                                                    daysLeft: days(from: start, to: original, calendar: calendar)))
            }
            result += upcomingAnniversaries(event, today: start, count: count, calendar: calendar)
            return Array(result.prefix(count))
        }
        guard let next = nextOccurrence(event, today: start, calendar: calendar) else { return [] }
        return [AnniversaryOccurrence(ordinal: 0, date: next, daysLeft: days(from: start, to: next, calendar: calendar))]
    }

    /// 多个面板的竖向时间轴：还会来的按日子从近到远（不限一年），已经过去不会再来的
    /// 一次性倒数日放进「已经过去」，最近过去的在前。
    public static func agenda(_ events: [AnniversaryEvent], today: Date,
                              calendar: Calendar = Anniversary.calendar)
        -> (upcoming: [AnniversaryAgendaItem], past: [AnniversaryReading]) {
        let start = calendar.startOfDay(for: today)
        var upcoming: [AnniversaryAgendaItem] = []
        var past: [AnniversaryReading] = []
        for event in events {
            guard let reading = reading(event, today: start, calendar: calendar) else { continue }
            guard let date = axisDate(reading, today: start, calendar: calendar) else {
                past.append(reading)
                continue
            }
            var ordinal: Int?
            if event.kind == .countup, reading.original < start {
                ordinal = upcomingAnniversaries(event, today: start, count: 1, calendar: calendar).first?.ordinal
            }
            upcoming.append(AnniversaryAgendaItem(reading: reading, date: date,
                                                  daysLeft: days(from: start, to: date, calendar: calendar),
                                                  ordinal: ordinal))
        }
        upcoming.sort {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.reading.event.title < $1.reading.event.title
        }
        past.sort {
            $0.original != $1.original ? $0.original > $1.original : $0.event.title < $1.event.title
        }
        return (upcoming, past)
    }

    /// 多个卡片左边的胶囊：时间轴上最近的那一个，一年内没有要到的就是 nil。
    public static func lead(_ events: [AnniversaryEvent], today: Date,
                            calendar: Calendar = Anniversary.calendar) -> AnniversaryAxisPoint? {
        axisPoints(events, today: today, calendar: calendar).first
    }

    /// 1月1日。
    public static func monthDayText(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return tr("\(c.month ?? 1)月\(c.day ?? 1)日")
    }

    /// 单个卡片和面板行里名字下面那行：1月1日 周五 · 每年；农历事件写农历；
    /// 正在数的正数日写第几年。
    public static func cardLine(_ reading: AnniversaryReading, today: Date,
                                calendar: Calendar = Anniversary.calendar) -> String {
        let event = reading.event
        if event.kind == .countup, reading.phase == .past {
            return tileLine(reading, today: today, calendar: calendar)
        }
        if event.kind == .countdown, reading.phase == .past {
            return tr("\(solarText(reading.original, calendar: calendar)) · 已过")
        }
        let date = reading.kindDate
        let day = event.lunar
            ? tr("农历\(lunarShort(date, calendar: calendar))")
            : "\(monthDayText(date, calendar: calendar)) \(weekdayShort(date, calendar: calendar))"
        return event.yearly ? tr("\(day) · 每年") : day
    }

    /// 多个面板时间轴一行名字下面的字。
    ///
    /// 倒数日：2月6日 周六，农历的再写农历日子，每年重复的写每年，一次性的写年份。
    /// 正数日：第 5 个周年 · 2027年10月21日；还没开始的写哪天起。
    public static func agendaLine(_ item: AnniversaryAgendaItem,
                                  calendar: Calendar = Anniversary.calendar) -> String {
        let event = item.reading.event
        let date = item.date
        if event.kind == .countup {
            if let ordinal = item.ordinal {
                return tr("第 \(ordinal) 个周年 · \(longText(date, calendar: calendar))")
            }
            return tr("\(longText(date, calendar: calendar)) \(weekdayShort(date, calendar: calendar)) 起")
        }
        let day = "\(monthDayText(date, calendar: calendar)) \(weekdayShort(date, calendar: calendar))"
        if event.lunar { return "\(day) · " + tr("农历\(lunarShort(date, calendar: calendar))") }
        if event.yearly { return tr("\(day) · 每年") }
        return tr("\(day) · \(String(calendar.component(.year, from: date)))年")
    }

    /// 专属页「重复」一行：每年 · 公历、每年 · 农历、不重复。
    public static func repeatText(_ event: AnniversaryEvent) -> String {
        guard event.yearly else { return tr("不重复") }
        return event.lunar ? tr("每年 · 农历") : tr("每年 · 公历")
    }
}

/// 纪念日的小图标：按名字认几类常见的日子，认不出按倒数、正数给一个。
///
/// 名字里的词中英文都认，大小写不论。只是一个 SF Symbols 名字，画在卡片的时间轴和
/// 面板里，图标落在事件色的小圆上。
public enum AnniversaryIcon {
    /// 先匹配的先用：生日比纪念日具体，所以排在前面。
    static let rules: [(words: [String], symbol: String)] = [
        (["生日", "生辰", "寿", "birthday", "bday"], "birthday.cake.fill"),
        (["结婚", "婚礼", "领证", "恋爱", "在一起", "相识", "表白", "情人", "七夕", "520",
          "wedding", "marri", "love", "valentine", "dating", "together"], "heart.fill"),
        (["入职", "工作", "上班", "转正", "离职", "退休", "job", "work", "career", "retire"], "briefcase.fill"),
        (["毕业", "开学", "考试", "高考", "考研", "graduat", "exam", "school"], "graduationcap.fill"),
        (["宝宝", "出生", "满月", "baby", "born"], "figure.and.child.holdinghands"),
        (["旅行", "旅游", "出发", "航班", "trip", "travel", "flight", "vacation", "holiday"], "airplane"),
        (["春节", "过年", "除夕", "元宵", "中秋", "端午", "lunar new year", "spring festival"], "moon.stars.fill"),
        (["元旦", "新年", "跨年", "new year"], "sparkles"),
        (["国庆", "national day"], "flag.fill"),
        (["圣诞", "christmas", "xmas"], "gift.fill"),
        (["搬家", "乔迁", "新家", "moving", "new home"], "house.fill"),
        (["猫", "狗", "宠物", "puppy", "kitten"], "pawprint.fill"),
    ]

    public static let countdownFallback = "hourglass"
    public static let countupFallback = "star.fill"

    public static func symbol(for event: AnniversaryEvent) -> String {
        let title = event.title.lowercased()
        for rule in rules where rule.words.contains(where: { title.contains($0) }) {
            return rule.symbol
        }
        return event.kind == .countup ? countupFallback : countdownFallback
    }
}

/// 沙漏的轮廓：上下两个玻璃泡在细腰处相接。纯几何，卡片和面板按这些点画。
public enum HourglassGeometry {
    /// 一边的半宽：`t` 为 0 在端口，为 1 在细腰。
    public static func halfWidth(t: Double, half: Double, neck: Double) -> Double {
        let clamped = min(1, max(0, t))
        return neck + (half - neck) * pow(1 - clamped * clamped, 0.75)
    }

    /// 上半剩 `remain` 时沙面在上半泡里的位置（`t`，0 是端口，1 是细腰）。剩得越多，
    /// 沙面越靠近端口；最多到 0.05，免得沙顶到盖子。
    public static func upperSurface(remain: Double) -> Double {
        let r = min(1, max(0, remain.isFinite ? remain : 0))
        guard r > 0.005 else { return 1 }
        return 1 - min(0.95, pow(r, 0.62))
    }

    /// 下半堆了 `filled` 时沙堆边缘离底的比例（占下半泡高度），空的是 0。
    public static func lowerHeight(filled: Double) -> Double {
        let f = min(1, max(0, filled.isFinite ? filled : 0))
        guard f > 0.005 else { return 0 }
        return min(0.92, 0.12 + pow(f, 0.8) * 0.8)
    }
}
