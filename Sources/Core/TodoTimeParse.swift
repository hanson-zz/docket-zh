import Foundation

// 快速待办输入框里的自然语言时间：「明天 9 点交稿」记成“交稿”，明天 9:00 提醒。
//
// 认中文和英文：今天、明天、后天、大后天、今晚、明早，周X / 星期X / 礼拜X、下周X，
// 10/23、10月23日，X点、X点半、X点一刻、X点20(分)、9:30、上午 / 中午 / 下午 / 傍晚 /
// 晚上；today、tonight、tomorrow、friday、next friday、on fri、9am、3:30 pm、at 9。
// 只认一段连在一起的（日期、时段、时刻之间可以有空格），认出的片段在输入框里标橙，
// 下面一行预览“明天 10/23 周五 09:00 提醒”。
//
// 几条约定：
// - 只说了日期没说几点：今天的只放进「今天」不设提醒；别的日子 9:00 提醒；说了时段
//   用时段的钟点（上午 9、中午 12、下午 15、傍晚 18、晚上 20，和“今晚 20:00”一致）。
// - 只说了几点、没说上午下午：今天还没到的那个（7 点在 16:10 说是今晚 19:00），都过了
//   就是明天；带了日期的 1 到 6 点当下午（“明天 3 点开会”是 15:00，和日历「写一句」
//   一样），7 点以后照原样。
// - 光写周X：最近的那个，今天就是今天（时刻已经过了就是下周）；下周X 是下一周（周一
//   起算）的那一天。10/23 早于今天就是明年。
// - 汉字数字的钟点（“一点”“两点”）容易是“快一点”这种话，只在前面有日期或时段、
//   或者后面跟着“钟 / 半 / 分”时才算。
// - 去掉片段以后没剩字（只输入了“明天”）就不认，整句照原样记。

public struct TodoTimeParse: Equatable, Sendable {
    /// 去掉时间片段后的待办文字。
    public var title: String
    /// 时间片段在原文里的位置，UTF-16 偏移（输入框按这个标橙）。
    public var start: Int
    public var length: Int
    /// 认出的那一段原文。
    public var fragment: String
    /// 提醒时间。只说了“今天”没说几点时为 nil，只放进「今天」。
    public var remindAt: Date?
    /// 放进「今天」分组：提醒在今天（或已经过了），或者只说了“今天”。
    public var today: Bool

    public init(title: String, start: Int, length: Int, fragment: String, remindAt: Date?, today: Bool) {
        self.title = title
        self.start = start
        self.length = length
        self.fragment = fragment
        self.remindAt = remindAt
        self.today = today
    }

    /// 输入框下面那一行：“明天 10/23 周五 09:00 提醒”，只放进今天时“放进今天”。
    public func preview(now: Date, calendar: Calendar = .current) -> String {
        guard let remindAt else { return tr("放进今天") }
        return TodoTimeText.preview(remindAt, now: now, calendar: calendar)
    }

    // MARK: 认

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> TodoTimeParse? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let whole = NSRange(location: 0, length: ns.length)
        var best: Candidate?
        for (regex, order) in Pattern.all {
            for match in regex.matches(in: text, range: whole) {
                guard let found = Candidate(match: match, order: order, in: ns) else { continue }
                if let current = best {
                    if found.range.location < current.range.location
                        || (found.range.location == current.range.location && found.range.length > current.range.length) {
                        best = found
                    }
                } else {
                    best = found
                }
            }
        }
        guard let pick = best, let resolution = pick.resolve(now: now, calendar: calendar) else { return nil }
        let resolved: Date?
        switch resolution {
        case .todayOnly: resolved = nil
        case .at(let date): resolved = date
        }
        let before = ns.substring(to: pick.range.location)
        let after = ns.substring(from: pick.range.location + pick.range.length)
        let title = joined(before, after)
        guard !title.isEmpty else { return nil }
        let todayKey = TodoDay.key(now, calendar: calendar)
        let isToday = resolved.map { TodoDay.key($0, calendar: calendar) <= todayKey } ?? true
        return TodoTimeParse(title: title, start: pick.range.location, length: pick.range.length,
                             fragment: ns.substring(with: pick.range), remindAt: resolved, today: isToday)
    }

    /// 片段两边的字接起来：两边都是英文字母或数字时中间留一个空格，中文直接接上。
    static func joined(_ before: String, _ after: String) -> String {
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "，,。、；;：:！!？?"))
        let left = before.trimmingCharacters(in: edges)
        let right = after.trimmingCharacters(in: edges)
        guard !left.isEmpty, !right.isEmpty else { return left + right }
        let needsSpace = (left.unicodeScalars.last.map(isLatin) ?? false)
            && (right.unicodeScalars.first.map(isLatin) ?? false)
        return needsSpace ? left + " " + right : left + right
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "," || scalar == ".")
    }
}

// MARK: - 正则

private enum Pattern {
    static let cnNum = "(?:\\d{1,2}|[零一二两三四五六七八九十]{1,3})"

    static let enDays = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
    static let enShort = "mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun"

    static let date = "大后天|后天|明天|明日|今天|今日|今晚|明晚|明早|今早"
        + "|(?:下下|下个|下|这个|这|本)?(?:周|星期|礼拜)[一二三四五六日天1-7]"
        + "|\\d{1,2}月\\d{1,2}[日号](?!\\d)"
        + "|\\d{1,2}/\\d{1,2}(?![\\d/])"
        + "|(?:on\\s+)?(?:today|tonight|tomorrow|tmrw|tmr)(?![a-z])"
        + "|(?:(?:on|next|this)\\s+)?(?:\(enDays))(?![a-z])"
        + "|(?:on|next|this)\\s+(?:\(enShort))(?![a-z])"

    static let period = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜晚"
        + "|(?:in\\s+the\\s+)?(?:morning|afternoon|evening)(?![a-z])|noon(?![a-z])|night(?![a-z])"

    static let enTime = "(?:at\\s+)?\\d{1,2}(?:[:：]\\d{2})?\\s*(?:a\\.m\\.|p\\.m\\.|am|pm)(?![a-z])"
        + "|at\\s+\\d{1,2}(?:[:：]\\d{2})?(?![\\d:：])"
    static let time = enTime
        + "|\\d{1,2}[:：]\\d{2}(?!\\d)"
        + "|\(cnNum)\\s*点(?:钟)?(?:\\s*(?:半|一刻|三刻|\\d{1,2}(?!\\d)(?!\\s*[号楼层个人天位])\\s*分?))?"

    /// 日期、时段、时刻，按这个顺序，至少有日期或时刻。
    static let forward = "(?<![a-z0-9])(?:(\(date))\\s*)?(?:(\(period))\\s*)?(\(time))?"
    /// 英文常见的“9am tomorrow”“3pm on friday”：时刻在前、日期在后。
    static let backward = "(?<![a-z0-9])(\(enTime))\\s+(\(date))"

    enum Order { case forward, backward }

    static let all: [(NSRegularExpression, Order)] = [
        (try! NSRegularExpression(pattern: forward, options: [.caseInsensitive]), .forward),
        (try! NSRegularExpression(pattern: backward, options: [.caseInsensitive]), .backward),
    ]
}

// MARK: - 一个候选片段

private struct Candidate {
    var range: NSRange
    var date: String?
    var period: String?
    var time: String?

    init?(match: NSTextCheckingResult, order: Pattern.Order, in text: NSString) {
        func group(_ index: Int) -> String? {
            let r = match.range(at: index)
            guard r.location != NSNotFound, r.length > 0 else { return nil }
            return text.substring(with: r)
        }
        switch order {
        case .forward:
            date = group(1)
            period = group(2)
            time = group(3)
        case .backward:
            time = group(1)
            date = group(2)
            period = nil
        }
        guard date != nil || time != nil else { return nil }
        // 片段末尾的空格不算进去。
        var r = match.range
        while r.length > 0 {
            let last = text.character(at: r.location + r.length - 1)
            guard let scalar = Unicode.Scalar(last), CharacterSet.whitespaces.contains(scalar) else { break }
            r.length -= 1
        }
        guard r.length > 0 else { return nil }
        range = r
        // 只有汉字数字钟点、没有日期时段、后面也没“钟 / 半 / 分”：多半是“快一点”。
        if date == nil, period == nil, let time, Clock.isBareChineseNumeral(time) { return nil }
    }

    /// 认出来落在哪：只放进今天，或者某个时刻。
    enum Resolution { case todayOnly, at(Date) }

    /// 落不下来（2/30 这种）时为 nil。
    func resolve(now: Date, calendar: Calendar) -> Resolution? {
        let start = calendar.startOfDay(for: now)
        let day = date.map { DayWord(lowercased: $0.lowercased()) }
        if let day, day.kind == .invalid { return nil }
        var periodKind = period.map { PeriodWord(lowercased: $0.lowercased()) }
        if periodKind == nil, let implied = day?.impliedPeriod { periodKind = implied }
        let clock = time.flatMap { Clock(lowercased: $0.lowercased()) }
        if time != nil, clock == nil { return nil }

        let offsetDay: Date
        if let day {
            guard let found = day.date(from: start, calendar: calendar) else { return nil }
            offsetDay = found
        } else {
            offsetDay = start
        }
        let isWeekday = day?.kind == .weekday
        let onToday = calendar.isDate(offsetDay, inSameDayAs: start)

        // 只有日期。
        guard let clock else {
            if let periodKind {
                return at(offsetDay, hour: periodKind.defaultHour, minute: 0, calendar: calendar).map(Resolution.at)
            }
            if day != nil, onToday { return .todayOnly }
            return at(offsetDay, hour: 9, minute: 0, calendar: calendar).map(Resolution.at)
        }

        if let hour = clock.hour(period: periodKind) {
            guard var result = at(offsetDay, hour: hour, minute: clock.minute, calendar: calendar) else { return nil }
            if day == nil || isWeekday, result <= now, onToday {
                result = calendar.date(byAdding: .day, value: isWeekday ? 7 : 1, to: result) ?? result
            }
            return .at(result)
        }

        // 没说上午下午。
        let h = clock.rawHour
        if day == nil {
            var candidates = [h]
            if h < 12 { candidates.append(h + 12) }
            for hour in candidates {
                if let result = at(start, hour: hour, minute: clock.minute, calendar: calendar), result > now {
                    return .at(result)
                }
            }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return at(tomorrow, hour: (1...6).contains(h) ? h + 12 : h, minute: clock.minute,
                      calendar: calendar).map(Resolution.at)
        }
        let hour = (1...6).contains(h) ? h + 12 : h
        guard var result = at(offsetDay, hour: hour, minute: clock.minute, calendar: calendar) else { return nil }
        if isWeekday, result <= now, onToday {
            result = calendar.date(byAdding: .day, value: 7, to: result) ?? result
        }
        return .at(result)
    }

    private func at(_ day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

// MARK: - 日期

private struct DayWord {
    enum Kind { case relative, weekday, monthDay, invalid }

    var kind: Kind
    var offset = 0
    /// 1 是周一，7 是周日。
    var weekday = 0
    /// 下周X 是 1，下下周X 是 2。
    var weeksAhead = 0
    var month = 0
    var day = 0
    var impliedPeriod: PeriodWord?

    init(lowercased raw: String) {
        // “on friday”的 on 不算；中间几个空格都当一个。
        let text = raw.split(whereSeparator: \.isWhitespace).filter { $0 != "on" }.joined(separator: " ")
        switch text {
        case "今天", "今日", "today": kind = .relative; offset = 0
        case "今晚", "tonight": kind = .relative; offset = 0; impliedPeriod = .evening
        case "今早": kind = .relative; offset = 0; impliedPeriod = .morning
        case "明天", "明日", "tomorrow", "tmr", "tmrw": kind = .relative; offset = 1
        case "明晚": kind = .relative; offset = 1; impliedPeriod = .evening
        case "明早": kind = .relative; offset = 1; impliedPeriod = .morning
        case "后天": kind = .relative; offset = 2
        case "大后天": kind = .relative; offset = 3
        default:
            if let found = DayWord.monthDay(text) {
                kind = .monthDay
                month = found.month
                day = found.day
            } else if let found = DayWord.weekday(text) {
                kind = .weekday
                weekday = found.weekday
                weeksAhead = found.ahead
            } else {
                kind = .invalid
            }
        }
    }

    private static func monthDay(_ text: String) -> (month: Int, day: Int)? {
        var digits = text
        for mark in ["月", "日", "号"] { digits = digits.replacingOccurrences(of: mark, with: "/") }
        let parts = digits.split(separator: "/").map(String.init)
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (month: month, day: day)
    }

    private static let chineseWeekdays: [Character: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7,
        "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
    ]

    private static let englishWeekdays: [String: Int] = [
        "monday": 1, "mon": 1, "tuesday": 2, "tues": 2, "tue": 2, "wednesday": 3, "wed": 3,
        "thursday": 4, "thurs": 4, "thur": 4, "thu": 4, "friday": 5, "fri": 5,
        "saturday": 6, "sat": 6, "sunday": 7, "sun": 7,
    ]

    private static func weekday(_ text: String) -> (weekday: Int, ahead: Int)? {
        if let last = text.last, let weekday = chineseWeekdays[last],
           text.contains("周") || text.contains("星期") || text.contains("礼拜") {
            let ahead = text.hasPrefix("下下") ? 2 : (text.hasPrefix("下") ? 1 : 0)
            return (weekday: weekday, ahead: ahead)
        }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.last, let weekday = englishWeekdays[name] else { return nil }
        return (weekday: weekday, ahead: words.first == "next" ? 1 : 0)
    }

    /// 落在哪一天（零点）。
    func date(from start: Date, calendar: Calendar) -> Date? {
        switch kind {
        case .relative:
            return calendar.date(byAdding: .day, value: offset, to: start)
        case .weekday:
            // Calendar 的 weekday 是周日 1 到周六 7，换成周一 1 到周日 7。
            let system = calendar.component(.weekday, from: start)
            let iso = (system + 5) % 7 + 1
            let days: Int
            if weeksAhead > 0 {
                days = (7 - iso) + weekday + (weeksAhead - 1) * 7
            } else {
                days = (weekday - iso + 7) % 7
            }
            return calendar.date(byAdding: .day, value: days, to: start)
        case .monthDay:
            let year = calendar.component(.year, from: start)
            for candidate in [year, year + 1] {
                var parts = DateComponents()
                parts.year = candidate
                parts.month = month
                parts.day = day
                guard let date = calendar.date(from: parts),
                      calendar.component(.month, from: date) == month,
                      calendar.component(.day, from: date) == day else { return nil }
                if date >= start { return date }
            }
            return nil
        case .invalid:
            return nil
        }
    }
}

// MARK: - 时段

private enum PeriodWord: Equatable {
    case dawn, morning, noon, afternoon, dusk, evening

    init(lowercased raw: String) {
        let text = raw.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? raw
        switch text {
        case "凌晨": self = .dawn
        case "早上", "早晨", "上午", "morning": self = .morning
        case "中午", "noon": self = .noon
        case "下午", "afternoon": self = .afternoon
        case "傍晚": self = .dusk
        default: self = .evening
        }
    }

    /// 只说了时段没说几点时的钟点。
    var defaultHour: Int {
        switch self {
        case .dawn: 6
        case .morning: 9
        case .noon: 12
        case .afternoon: 15
        case .dusk: 18
        case .evening: 20
        }
    }
}

// MARK: - 时刻

private struct Clock {
    var rawHour: Int
    var minute: Int
    /// 写了 am / pm：true 是 pm。
    var pm: Bool?

    init?(lowercased raw: String) {
        var text = raw.replacingOccurrences(of: "：", with: ":")
        if text.hasPrefix("at ") || text.hasPrefix("at\t") { text = String(text.dropFirst(3)) }
        text = text.trimmingCharacters(in: .whitespaces)
        for (mark, isPM) in [("a.m.", false), ("p.m.", true), ("am", false), ("pm", true)] where text.hasSuffix(mark) {
            pm = isPM
            text = String(text.dropLast(mark.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if let dot = text.firstIndex(of: "点") {
            guard let hour = Clock.number(String(text[..<dot]).trimmingCharacters(in: .whitespaces)) else { return nil }
            var rest = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("钟") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
            rest = rest.replacingOccurrences(of: "分", with: "").trimmingCharacters(in: .whitespaces)
            let minute: Int
            switch rest {
            case "": minute = 0
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default:
                guard let value = Int(rest) else { return nil }
                minute = value
            }
            rawHour = hour
            self.minute = minute
        } else {
            let parts = text.split(separator: ":").map(String.init)
            guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
            rawHour = hour
            minute = parts.count == 2 ? (Int(parts[1]) ?? -1) : 0
        }
        guard (0...24).contains(rawHour), (0...59).contains(minute) else { return nil }
        if rawHour == 24 { rawHour = 0 }
        if pm != nil, !(1...12).contains(rawHour) { return nil }
    }

    /// 有 am / pm 或时段时能定下来的钟点；都没有时为 nil（交给调用方猜）。
    func hour(period: PeriodWord?) -> Int? {
        if let pm {
            if pm { return rawHour < 12 ? rawHour + 12 : 12 }
            return rawHour == 12 ? 0 : rawHour
        }
        if rawHour >= 13 || rawHour == 0 { return rawHour }
        guard let period else { return nil }
        switch period {
        case .afternoon, .dusk, .evening:
            return rawHour < 12 ? rawHour + 12 : rawHour
        case .noon:
            return rawHour <= 2 ? rawHour + 12 : rawHour
        case .dawn:
            return rawHour == 12 ? 0 : rawHour
        case .morning:
            return rawHour
        }
    }

    /// “一点”“两点”“十点”：汉字数字，后面没有“钟 / 半 / 分 / 刻”。
    static func isBareChineseNumeral(_ text: String) -> Bool {
        guard let dot = text.firstIndex(of: "点") else { return false }
        let head = text[..<dot].trimmingCharacters(in: .whitespaces)
        guard let first = head.first, !first.isASCII else { return false }
        let tail = text[text.index(after: dot)...]
        return tail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static let digits: [Character: Int] = [
        "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    /// “9”“十”“十二”“二十三”。
    static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        guard !text.isEmpty else { return nil }
        if let ten = text.firstIndex(of: "十") {
            let left = text[..<ten]
            let right = text[text.index(after: ten)...]
            let tens: Int? = left.isEmpty ? 1 : (left.count == 1 ? digits[left.first!] : nil)
            let ones: Int? = right.isEmpty ? 0 : (right.count == 1 ? digits[right.first!] : nil)
            guard let tens, let ones else { return nil }
            return tens * 10 + ones
        }
        guard text.count == 1, let value = digits[text.first!] else { return nil }
        return value
    }
}

// MARK: - 时间的写法

/// 待办里时间的几种写法：预览、截止胶囊、“昨天”。
public enum TodoTimeText {
    /// 周一到周日的短名（英文 Mon 到 Sun）。
    public static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: tr("周日")
        case 2: tr("周一")
        case 3: tr("周二")
        case 4: tr("周三")
        case 5: tr("周四")
        case 6: tr("周五")
        default: tr("周六")
        }
    }

    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    /// “明天 10/23 周五 09:00 提醒”：今天、明天、后天写在前面，再远就从日期写起。
    public static func preview(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        switch ReminderTiming.dayOffset(date, from: now, calendar: calendar) {
        case 0: parts.append(tr("今天"))
        case 1: parts.append(tr("明天"))
        case 2: parts.append(tr("后天"))
        default: break
        }
        parts.append(monthDay(date, calendar: calendar))
        parts.append(weekday(date, calendar: calendar))
        parts.append(ReminderPopupText.clock(date, calendar: calendar))
        let when = parts.joined(separator: " ")
        return tr("\(when) 提醒")
    }

    /// 截止时间胶囊：“昨天 18:00”“17:30”“明天 09:00”“周五 10:00”“10/27 09:00”。
    public static func due(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = ReminderPopupText.clock(date, calendar: calendar)
        let days = ReminderTiming.dayOffset(date, from: now, calendar: calendar)
        switch days {
        case -1: return tr("昨天 \(clock)")
        case 0: return clock
        case 1: return tr("明天 \(clock)")
        case 2...6: return "\(weekday(date, calendar: calendar)) \(clock)"
        default: return "\(monthDay(date, calendar: calendar)) \(clock)"
        }
    }

    /// 顺下来的那天：“昨天”，更早写“10/20”。
    public static func day(_ key: String, today: String, calendar: Calendar = .current) -> String {
        if TodoDay.previous(today, calendar: calendar) == key { return tr("昨天") }
        guard let date = TodoDay.date(key, calendar: calendar) else { return key }
        return monthDay(date, calendar: calendar)
    }
}
