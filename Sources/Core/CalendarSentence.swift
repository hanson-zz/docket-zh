import Foundation

/// 日历面板底下「写一句」：把「明天下午 3 点开会」这样一句中文拆成标题和时间。
///
/// 认得的说法：
/// - 哪天：今天、明天、后天、大后天、今晚、明晚、今早、明早；周X / 星期X / 礼拜X（这周的，
///   已经过去就是下周的；说「这周」「本周」就固定这周）、下周X、下下周X；10月25日 / 10月25号。
/// - 时段：凌晨、早上、早晨、上午、中午、下午、傍晚、晚上、夜里。
/// - 几点：3点、3 点、三点、15:30、3点半、3点一刻、3点三刻、3点15、3点15分、十点十分；
///   X点到Y点、X点至Y点、X-Y点、3点半到5点。
/// - 全天。
///
/// 规则：只有日子没有钟点是全天日程；只有钟点没有日子是今天；没说上午下午时 1 到 6 点按下午算
/// （「3点开会」几乎都是下午 3 点）；只说时段不说几点按时段的常用钟点（上午 9 点、下午 2 点……）；
/// 没说结束时间按 `defaultMinutes`。认出来的字从句子里去掉，剩下的是标题，空了叫「新日程」。
public struct CalendarSentence: Equatable, Sendable {
    public var title: String
    public var slot: CalendarPlanner.Slot
    /// 认出了日期、时段或钟点。没认出时只有标题，`slot` 是今天的默认时间。
    public var understood: Bool

    public init(title: String, slot: CalendarPlanner.Slot, understood: Bool) {
        self.title = title
        self.slot = slot
        self.understood = understood
    }

    /// 一句话拆成日程；空白一句返回 nil。
    public static func parse(_ text: String, now: Date, defaultMinutes: Int = 60,
                             calendar: Calendar = WeekAgenda.calendar) -> CalendarSentence? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)

        var day: Date?
        var period: Period?
        var understood = false
        var allDay = false

        // 全天
        if let range = rest.range(of: "全天") {
            rest.replaceSubrange(range, with: " ")
            allDay = true
            understood = true
        }

        // 10月25日 / 10月25号
        if let m = first(datePattern, in: rest) {
            let month = number(m.group("month", in: rest)) ?? 0
            let date = number(m.group("day", in: rest)) ?? 0
            let year = calendar.component(.year, from: now)
            if var found = calendar.date(from: DateComponents(year: year, month: month, day: date)),
               calendar.component(.month, from: found) == month {
                if found < today, let next = calendar.date(byAdding: .year, value: 1, to: found) { found = next }
                day = found
                understood = true
            }
            rest = m.removing(from: rest)
        }

        // 今天、明天、今晚……
        if day == nil, let m = first(relativePattern, in: rest) {
            let word = m.group("word", in: rest) ?? ""
            let offsets: [String: Int] = ["今天": 0, "今晚": 0, "今早": 0, "明天": 1, "明晚": 1, "明早": 1,
                                          "后天": 2, "大后天": 3]
            day = calendar.date(byAdding: .day, value: offsets[word] ?? 0, to: today)
            if word.hasSuffix("晚") { period = .evening }
            if word.hasSuffix("早") { period = .morning }
            understood = true
            rest = m.removing(from: rest)
        }

        // 周X / 下周X / 这周X
        if day == nil, let m = first(weekPattern, in: rest) {
            let prefix = m.group("prefix", in: rest) ?? ""
            let name = m.group("weekday", in: rest) ?? ""
            if let index = weekdayIndex(name) {
                let monday = WeekAgenda.weekStart(now, calendar: calendar)
                var offset = index
                switch prefix {
                case "下": offset += 7
                case "下下": offset += 14
                default: break
                }
                if var found = calendar.date(byAdding: .day, value: offset, to: monday) {
                    if prefix.isEmpty, found < today, let next = calendar.date(byAdding: .day, value: 7, to: found) {
                        found = next
                    }
                    day = found
                    understood = true
                }
            }
            rest = m.removing(from: rest)
        }

        // 几点（可带时段，可是一段）
        var start: (hour: Int, minute: Int)?
        var end: (hour: Int, minute: Int)?
        if let m = first(rangePattern, in: rest),
           m.group("bare1", in: rest) == nil || m.group("h2", in: rest) != nil {
            let p1 = Period(m.group("p1", in: rest)) ?? period
            let p2 = Period(m.group("p2", in: rest))
            if let h1 = number(m.group("h1", in: rest)) {
                let minute1 = minutes(m, 1, in: rest)
                start = (hour(h1, p1), minute1)
                if let h2 = number(m.group("h2", in: rest)) {
                    var endHour = hour(h2, p2 ?? p1)
                    let minute2 = minutes(m, 2, in: rest)
                    if let s = start, endHour * 60 + minute2 <= s.hour * 60 + s.minute, endHour < 12 {
                        endHour += 12
                    }
                    end = (endHour, minute2)
                }
                if p1 != nil { period = p1 }
                understood = true
                allDay = false
            }
            rest = m.removing(from: rest)
        }

        // 只说时段
        if start == nil, let m = first(periodPattern, in: rest) {
            period = Period(m.group("p", in: rest))
            rest = m.removing(from: rest)
        }
        if start == nil, let period, !allDay {
            start = (period.defaultHour, 0)
            understood = true
        }

        let title = clean(rest)
        let base = day ?? today
        let slot: CalendarPlanner.Slot
        if let start, !allDay {
            let from = base.addingTimeInterval(Double(start.hour * 3_600 + start.minute * 60))
            var to = from.addingTimeInterval(Double(max(1, defaultMinutes)) * 60)
            if let end {
                let candidate = base.addingTimeInterval(Double(end.hour * 3_600 + end.minute * 60))
                if candidate > from { to = candidate }
            }
            slot = CalendarPlanner.Slot(start: from, end: to)
        } else if day != nil || allDay {
            slot = CalendarPlanner.slot(.allDay, start: base, calendar: calendar)
        } else {
            let from = CalendarPlanner.defaultStart(day: today, now: now, calendar: calendar)
            slot = CalendarPlanner.Slot(start: from, end: from.addingTimeInterval(Double(max(1, defaultMinutes)) * 60))
        }
        return CalendarSentence(title: title.isEmpty ? tr("新日程") : title, slot: slot, understood: understood)
    }

    // MARK: 时段

    enum Period: Equatable {
        case dawn, morning, forenoon, noon, afternoon, dusk, evening

        init?(_ word: String?) {
            switch word {
            case "凌晨": self = .dawn
            case "早上", "早晨": self = .morning
            case "上午": self = .forenoon
            case "中午": self = .noon
            case "下午": self = .afternoon
            case "傍晚": self = .dusk
            case "晚上", "夜里": self = .evening
            default: return nil
            }
        }

        /// 只说时段不说几点时的钟点。
        var defaultHour: Int {
            switch self {
            case .dawn: 6
            case .morning: 8
            case .forenoon: 9
            case .noon: 12
            case .afternoon: 14
            case .dusk: 18
            case .evening: 19
            }
        }
    }

    /// 12 小时说法换成 24 小时。13 点以上原样；24 点以上夹到 23。
    static func hour(_ value: Int, _ period: Period?) -> Int {
        let h = min(max(value, 0), 24)
        if h >= 13 { return min(h, 23) }
        switch period {
        case .dawn: return h == 12 ? 0 : h
        case .morning, .forenoon: return h
        case .noon: return h <= 3 ? h + 12 : h
        case .afternoon, .dusk: return h < 12 ? h + 12 : h
        case .evening: return h < 12 ? h + 12 : 23
        case nil: return (1...6).contains(h) ? h + 12 : h
        }
    }

    // MARK: 数字

    /// 阿拉伯数字或「三」「十二」「二十五」「两」。
    static func number(_ text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let chars = Array(text)
        if let ten = chars.firstIndex(of: "十") {
            let high = ten == 0 ? 1 : (digits[chars[0]] ?? 1)
            let low = ten + 1 < chars.count ? (digits[chars[ten + 1]] ?? 0) : 0
            return high * 10 + low
        }
        guard chars.count == 1, let value = digits[chars[0]] else { return nil }
        return value
    }

    private static func minutes(_ m: Match, _ index: Int, in text: String) -> Int {
        if m.group("half\(index)", in: text) != nil { return 30 }
        if m.group("quarter\(index)", in: text) != nil { return 15 }
        if m.group("three\(index)", in: text) != nil { return 45 }
        // 15:30 的分钟在 m1，「3点15」的在 m1x。
        let written = m.group("m\(index)", in: text) ?? m.group("m\(index)x", in: text)
        return min(59, number(written) ?? 0)
    }

    private static func weekdayIndex(_ name: String) -> Int? {
        switch name {
        case "一", "1": 0
        case "二", "2": 1
        case "三", "3": 2
        case "四", "4": 3
        case "五", "5": 4
        case "六", "6": 5
        case "日", "天", "7": 6
        default: nil
        }
    }

    // MARK: 标题

    /// 去掉认完时间剩下的连接词和标点。
    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。.、；;：:！!？?的在-~"))
        value = value.trimmingCharacters(in: edges)
        // 「提醒我开会」「记得开会」
        for lead in ["提醒我", "记得"] where value.hasPrefix(lead) && value.count > lead.count {
            value = String(value.dropFirst(lead.count)).trimmingCharacters(in: edges)
        }
        return value
    }

    // MARK: 正则

    private static let num = "\\d{1,2}|[零〇一二两三四五六七八九十]{1,3}"
    private static let periods = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里"
    private static let joiner = "\\s*(?:到|至|-|~|～)\\s*"

    /// 一个钟点：3点、3 点半、15:30、十点十分、15时。第一个钟点后面紧跟「到 / 至 / -」时
    /// 可以不写「点」（「3-5点」），这时 bare1 有值，后面必须真的接上第二个钟点。
    private static func time(_ i: Int) -> String {
        let minute = "(?<m\(i)x>\\d{1,2}|[零〇一二三四五六七八九十]{1,3})(?![\\d零〇一二两三四五六七八九十])(?!\\s*[号楼层个人天位])"
        let tail = i == 1 ? "|(?<bare1>(?=\(joiner)))" : ""
        return "(?<h\(i)>\(num))\\s*(?:[:：]\\s*(?<m\(i)>\\d{2})|点钟?\\s*(?:(?<half\(i)>半)|(?<quarter\(i)>一刻)|(?<three\(i)>三刻)|\(minute)\\s*分?)?|时\(tail))"
    }

    private static let datePattern = regex("(?<month>\\d{1,2}|[一二三四五六七八九十]{1,3})\\s*月\\s*(?<day>\\d{1,2}|[一二三四五六七八九十]{1,3})\\s*[日号]")
    private static let relativePattern = regex("(?<word>大后天|后天|明天|今天|今晚|明晚|今早|明早)")
    private static let weekPattern = regex("(?<prefix>下下|下|这|本)?个?(?:周|星期|礼拜)(?<weekday>[一二三四五六日天1-7])")
    private static let rangePattern = regex("(?:(?<p1>\(periods))\\s*)?\(time(1))(?:\(joiner)(?:(?<p2>\(periods))\\s*)?\(time(2)))?")
    private static let periodPattern = regex("(?<p>\(periods))")

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private struct Match {
        var result: NSTextCheckingResult

        func group(_ name: String, in text: String) -> String? {
            let range = result.range(withName: name)
            guard range.location != NSNotFound, let r = Range(range, in: text) else { return nil }
            return String(text[r])
        }

        func removing(from text: String) -> String {
            guard let r = Range(result.range, in: text) else { return text }
            var copy = text
            copy.replaceSubrange(r, with: " ")
            return copy
        }
    }

    private static func first(_ regex: NSRegularExpression?, in text: String) -> Match? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range).map(Match.init)
    }
}
