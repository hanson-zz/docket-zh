import Foundation

/// 纪念日：倒数日和正数日，可按公历或农历每年重复。
///
/// The events live in the widget's own config under `events`, which, like the
/// todo list's `items` and the habits, is the widget's contents rather than a
/// setting, so it is never a catalog default and never offered as a text
/// field in Settings. Which event the single card shows is kept under
/// `pinned` the same way, and chosen in the panel.
///
/// Each event is one string, `id<TAB>title<TAB>yyyyMMdd<TAB>flags<TAB>colour`.
/// The date is always the Gregorian day the user picked; a lunar event keeps
/// that day too and repeats on the lunar month and day it falls on, so there
/// is only one date to store and the lunar text is always derived from it.
/// `flags` is a few letters: `u` counts up (正数日) instead of down, `y`
/// repeats every year, `l` repeats by the lunar calendar. `colour` is a
/// `PaletteColor` raw value or empty for the widget's own colour.
public struct AnniversaryEvent: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        /// 倒数日：还有几天。
        case countdown
        /// 正数日：已经几天，比如在一起、入职。
        case countup

        public var title: String {
            switch self {
            case .countdown: "倒数日"
            case .countup: "正数日"
            }
        }
    }

    public var id: String
    public var title: String
    /// Day key (`yyyyMMdd`) of the Gregorian day picked.
    public var day: String
    public var kind: Kind
    public var yearly: Bool
    public var lunar: Bool
    public var color: PaletteColor?

    public init(id: String = AnniversaryEvent.newID(), title: String, day: String,
                kind: Kind = .countdown, yearly: Bool = false, lunar: Bool = false,
                color: PaletteColor? = nil) {
        self.id = id
        self.title = title
        self.day = day
        self.kind = kind
        self.yearly = yearly
        self.lunar = lunar
        self.color = color
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    var flags: String {
        (kind == .countup ? "u" : "") + (yearly ? "y" : "") + (lunar ? "l" : "")
    }

    var encoded: String {
        "\(id)\t\(title)\t\(day)\t\(flags)\t\(color?.rawValue ?? "")"
    }

    /// Tolerant like the habits: an unknown colour is dropped rather than the
    /// event, but an event without a readable date says nothing and goes.
    init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let day = parts[2].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, Anniversary.isDayKey(day) else { return nil }
        let flags = parts.count > 3 ? parts[3] : ""
        let color = parts.count > 4 ? PaletteColor(rawValue: parts[4]) : nil
        self.init(id: parts[0].isEmpty ? fallbackID : parts[0],
                  title: String(title.prefix(Anniversary.maxTitleLength)), day: day,
                  kind: flags.contains("u") ? .countup : .countdown,
                  yearly: flags.contains("y"), lunar: flags.contains("l"), color: color)
    }
}

/// Where an event stands today, as every card and the panel say it.
public struct AnniversaryReading: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Still to come: 还有 N 天.
        case upcoming
        /// 就是今天.
        case today
        /// Gone by, or counting up from: 已经 N 天.
        case past
    }

    public var event: AnniversaryEvent
    /// The day the event was set for.
    public var original: Date
    /// The next time it comes round, today included. For a one-off event
    /// that has passed, nil.
    public var next: Date?
    public var phase: Phase
    /// The number on the card, never negative.
    public var days: Int
    /// Counting up, the whole years since the day and the days since the last
    /// anniversary: 3 年 | 357 天.
    public var years: Int
    public var remainder: Int
    /// 0...1 for the small ring: how far through the year towards the next
    /// occurrence, or since the last anniversary when counting up.
    public var progress: Double
    /// The day itself comes round today: the event's day, or a yearly
    /// anniversary of it.
    public var isToday: Bool
    /// Where the timeline puts it: the next occurrence of anything still to
    /// come or repeating, otherwise the day it happened.
    public var timelineDate: Date

    /// 还有, 已经, 就是今天.
    public var word: String {
        switch phase {
        case .upcoming: "还有"
        case .today: "就是今天"
        case .past: "已经"
        }
    }

    /// 还有 116 天, 已经 1453 天, 就是今天.
    public var sentence: String {
        phase == .today ? word : "\(word) \(days) 天"
    }

    /// Counting up, the anniversary that comes round today: 3 周年.
    public var anniversaryNote: String? {
        guard isToday, phase == .past, event.kind == .countup, years > 0 else { return nil }
        return "\(years) 周年"
    }

    public var isFuture: Bool { phase == .upcoming }
}

public enum Anniversary {
    public static let key = "events"
    public static let pinnedKey = "pinned"
    /// A shelf of dates that matter, not a calendar.
    public static let maxEvents = 12
    public static let maxTitleLength = 20
    /// "近 N 天内有纪念日时显示".
    public static let soonDays = 7

    /// Gregorian in the Mac's own time zone: a day is counted the way the
    /// person at the Mac counts it.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// The Chinese calendar in the same zone as `calendar`.
    static func lunarCalendar(for calendar: Calendar) -> Calendar {
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = calendar.timeZone
        return lunar
    }

    // MARK: Day keys

    public static func dayKey(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String, calendar: Calendar = Anniversary.calendar) -> Date? {
        guard isDayKey(key), let value = Int(key) else { return nil }
        let year = value / 10_000, month = value / 100 % 100, day = value % 100
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func isDayKey(_ key: String) -> Bool {
        guard key.count == 8, let value = Int(key) else { return false }
        let month = value / 100 % 100
        let day = value % 100
        return value / 10_000 >= 1 && (1...12).contains(month) && (1...31).contains(day)
    }

    /// Whole local days from one date to another, negative into the past.
    public static func days(from: Date, to: Date, calendar: Calendar = Anniversary.calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }

    // MARK: Reading and writing

    public static func events(_ config: WidgetConfig) -> [AnniversaryEvent] {
        var seen = Set<String>()
        var result: [AnniversaryEvent] = []
        for (index, raw) in config.strings(key).enumerated() {
            guard var event = AnniversaryEvent(decoding: raw, fallbackID: "e\(index)") else { continue }
            if seen.contains(event.id) { event.id = "\(event.id)-\(index)" }
            seen.insert(event.id)
            result.append(event)
        }
        return Array(result.prefix(maxEvents))
    }

    public static func store(_ events: [AnniversaryEvent], in config: inout WidgetConfig) {
        config.set(key, .list(events.prefix(maxEvents).map { .string($0.encoded) }))
        let pinned = config.string(pinnedKey)
        if !pinned.isEmpty, !events.contains(where: { $0.id == pinned }) {
            config.set(pinnedKey, nil)
        }
    }

    public static func pinnedID(_ config: WidgetConfig) -> String? {
        let id = config.string(pinnedKey)
        return id.isEmpty ? nil : id
    }

    public static func pin(_ id: String?, in config: inout WidgetConfig) {
        config.set(pinnedKey, id.map { WidgetConfig.Value.string($0) })
    }

    public static func clean(_ title: String) -> String? {
        let oneLine = title.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return String(oneLine.prefix(maxTitleLength))
    }

    /// Adds a new event or replaces the one with the same id. Nothing changes
    /// for an empty title, a bad date, or a thirteenth event.
    public static func saving(_ event: AnniversaryEvent, in events: [AnniversaryEvent]) -> [AnniversaryEvent] {
        guard let title = clean(event.title), isDayKey(event.day) else { return events }
        var cleaned = event
        cleaned.title = title
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            var changed = events
            changed[index] = cleaned
            return changed
        }
        guard events.count < maxEvents else { return events }
        return events + [cleaned]
    }

    public static func removing(_ id: String, from events: [AnniversaryEvent]) -> [AnniversaryEvent] {
        events.filter { $0.id != id }
    }

    // MARK: Occurrences

    /// The day an event falls on in the year that starts in Gregorian `year`.
    ///
    /// Solar: the same month and day, with 29 February kept on the 28th in a
    /// year without it. Lunar: the same lunar month and day in the lunar year
    /// that begins in `year` (so a 腊月 date lands in the January after),
    /// always in the ordinary month even when the day picked was in a leap
    /// one, and on the 29th in a month that has no 30th.
    public static func occurrence(_ event: AnniversaryEvent, year: Int,
                                  calendar: Calendar = Anniversary.calendar) -> Date? {
        guard let original = date(fromKey: event.day, calendar: calendar) else { return nil }
        if event.lunar {
            let parts = lunarParts(original, calendar: calendar)
            return lunarDay(month: parts.month, day: parts.day, lunarYearStartingIn: year, calendar: calendar)
        }
        let month = calendar.component(.month, from: original)
        let day = calendar.component(.day, from: original)
        return solarDay(year: year, month: month, day: day, calendar: calendar)
    }

    static func solarDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        return calendar.date(byAdding: .day, value: min(day, length) - 1, to: calendar.startOfDay(for: first))
    }

    /// The Gregorian day of lunar `month`/`day` in the lunar year that begins
    /// in Gregorian `year`, in the ordinary (non-leap) month.
    public static func lunarDay(month: Int, day: Int, lunarYearStartingIn year: Int,
                                calendar: Calendar = Anniversary.calendar) -> Date? {
        let lunar = lunarCalendar(for: calendar)
        // Lunar new year falls between Jan 21 and Feb 20, so mid-March is
        // always in the lunar year that started this Gregorian year.
        guard let anchor = calendar.date(from: DateComponents(year: year, month: 3, day: 15, hour: 12)) else {
            return nil
        }
        var parts = lunar.dateComponents([.era, .year], from: anchor)
        parts.month = month
        parts.day = 1
        parts.hour = 12
        parts.isLeapMonth = false
        guard let first = lunar.date(from: parts),
              let length = lunar.range(of: .day, in: .month, for: first)?.count,
              let found = lunar.date(byAdding: .day, value: min(day, length) - 1, to: first) else { return nil }
        return calendar.startOfDay(for: found)
    }

    /// The lunar month and day a Gregorian day falls on.
    public static func lunarParts(_ date: Date, calendar: Calendar = Anniversary.calendar)
        -> (month: Int, day: Int, isLeap: Bool) {
        let lunar = lunarCalendar(for: calendar)
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: date)) ?? date
        let parts = lunar.dateComponents([.month, .day], from: noon)
        return (parts.month ?? 1, parts.day ?? 1, parts.isLeapMonth ?? false)
    }

    /// The Gregorian day that is lunar `month`/`day` in the lunar year
    /// `reference` falls in, for the panel's lunar pickers.
    public static func solarDate(lunarMonth month: Int, day: Int, inLunarYearOf reference: Date,
                                 calendar: Calendar = Anniversary.calendar) -> Date? {
        let lunar = lunarCalendar(for: calendar)
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: reference)) ?? reference
        var parts = lunar.dateComponents([.era, .year], from: noon)
        parts.month = month
        parts.day = 1
        parts.hour = 12
        parts.isLeapMonth = false
        guard let first = lunar.date(from: parts),
              let length = lunar.range(of: .day, in: .month, for: first)?.count,
              let found = lunar.date(byAdding: .day, value: min(day, length) - 1, to: first) else { return nil }
        return calendar.startOfDay(for: found)
    }

    /// The next time an event comes round, `today` included. A one-off event
    /// has one day; a yearly one starts from the day picked, so a yearly
    /// event set in the future first counts down to that day.
    public static func nextOccurrence(_ event: AnniversaryEvent, today: Date,
                                      calendar: Calendar = Anniversary.calendar) -> Date? {
        guard let original = date(fromKey: event.day, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: today)
        if original >= start { return original }
        guard event.yearly else { return nil }
        let year = calendar.component(.year, from: start)
        for candidate in (year - 1)...(year + 1) {
            if let day = occurrence(event, year: candidate, calendar: calendar), day >= start, day > original {
                return day
            }
        }
        return nil
    }

    /// The last anniversary on or before `today`, after the day itself, or
    /// the day itself when none has come round yet.
    static func lastAnniversary(_ event: AnniversaryEvent, original: Date, today: Date,
                                calendar: Calendar) -> (date: Date, count: Int) {
        let start = calendar.startOfDay(for: today)
        guard original < start else { return (original, 0) }
        let first = calendar.component(.year, from: original)
        let last = calendar.component(.year, from: start)
        var latest = original
        var count = 0
        for year in (first - 1)...(last + 1) where year - first < 400 {
            guard let day = occurrence(event, year: year, calendar: calendar),
                  day > original, day <= start else { continue }
            count += 1
            if day > latest { latest = day }
        }
        return (latest, count)
    }

    // MARK: Readings

    public static func reading(_ event: AnniversaryEvent, today: Date,
                               calendar: Calendar = Anniversary.calendar) -> AnniversaryReading? {
        guard let original = date(fromKey: event.day, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: today)
        let next = nextOccurrence(event, today: start, calendar: calendar)
        let isToday = next.map { calendar.isDate($0, inSameDayAs: start) } ?? false
        let toOriginal = days(from: start, to: original, calendar: calendar)

        let phase: AnniversaryReading.Phase
        let count: Int
        let progress: Double
        var years = 0
        var remainder = 0

        switch event.kind {
        case .countdown:
            if let next {
                count = days(from: start, to: next, calendar: calendar)
                phase = count == 0 ? .today : .upcoming
                progress = countdownProgress(event, next: next, today: start, calendar: calendar)
            } else {
                count = -toOriginal
                phase = .past
                progress = 1
            }
        case .countup:
            if toOriginal > 0 {
                count = toOriginal
                phase = .upcoming
                progress = countdownProgress(event, next: original, today: start, calendar: calendar)
            } else if toOriginal == 0 {
                count = 0
                phase = .today
                progress = 0
            } else {
                count = -toOriginal
                phase = .past
                let last = lastAnniversary(event, original: original, today: start, calendar: calendar)
                years = last.count
                remainder = days(from: last.date, to: start, calendar: calendar)
                let year = calendar.component(.year, from: last.date)
                let following = (year...(year + 2)).lazy
                    .compactMap { occurrence(event, year: $0, calendar: calendar) }
                    .first { $0 > last.date }
                if let following {
                    let span = max(1, days(from: last.date, to: following, calendar: calendar))
                    progress = Double(remainder) / Double(span)
                } else {
                    progress = 0
                }
            }
        }

        // Counting up sits on the day it counts from, however often it
        // comes round: that day is what the event is about.
        let timelineDate = event.kind == .countdown ? (next ?? original) : original

        return AnniversaryReading(event: event, original: original, next: next, phase: phase,
                                  days: max(0, count), years: years, remainder: remainder,
                                  progress: min(1, max(0, progress)), isToday: isToday,
                                  timelineDate: timelineDate)
    }

    /// How far through the wait for `next` today is: from the occurrence a
    /// year before for a repeating event, otherwise out of a year.
    static func countdownProgress(_ event: AnniversaryEvent, next: Date, today: Date,
                                  calendar: Calendar) -> Double {
        let left = days(from: today, to: next, calendar: calendar)
        if event.yearly, let original = date(fromKey: event.day, calendar: calendar), next > original {
            let year = calendar.component(.year, from: next)
            let previous = ((year - 2)...year).reversed().lazy
                .compactMap { occurrence(event, year: $0, calendar: calendar) }
                .first { $0 < next }
            if let previous {
                let span = max(1, days(from: previous, to: next, calendar: calendar))
                return 1 - Double(min(left, span)) / Double(span)
            }
        }
        return 1 - Double(min(left, 365)) / 365
    }

    /// Readings in the order the cards list them: today first, then what is
    /// coming soonest, then what is counting up, then countdowns that have
    /// run out, each nearest first.
    public static func readings(_ events: [AnniversaryEvent], today: Date,
                                calendar: Calendar = Anniversary.calendar) -> [AnniversaryReading] {
        events.compactMap { reading($0, today: today, calendar: calendar) }.sorted(by: listOrder)
    }

    static func listOrder(_ a: AnniversaryReading, _ b: AnniversaryReading) -> Bool {
        func rank(_ r: AnniversaryReading) -> Int {
            if r.isToday { return 0 }
            guard r.phase == .past else { return 1 }
            return r.event.kind == .countup ? 2 : 3
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        if a.days != b.days { return a.days < b.days }
        return a.event.title < b.event.title
    }

    /// What the single card shows: the pinned event, otherwise the first in
    /// list order, which is the nearest one still to come.
    public static func featured(_ events: [AnniversaryEvent], pinned: String?, today: Date,
                                calendar: Calendar = Anniversary.calendar) -> AnniversaryReading? {
        if let pinned, let event = events.first(where: { $0.id == pinned }),
           let found = reading(event, today: today, calendar: calendar) {
            return found
        }
        return readings(events, today: today, calendar: calendar).first
    }

    /// The panel's timeline, latest at the top like the design: what is
    /// still to come above the line marking today, and what has passed (or
    /// is being counted up from) below it.
    public static func timeline(_ events: [AnniversaryEvent], today: Date,
                                calendar: Calendar = Anniversary.calendar)
        -> (future: [AnniversaryReading], past: [AnniversaryReading]) {
        let all = events.compactMap { reading($0, today: today, calendar: calendar) }
        let start = calendar.startOfDay(for: today)
        let sorted = all.sorted {
            $0.timelineDate != $1.timelineDate ? $0.timelineDate > $1.timelineDate : $0.event.title < $1.event.title
        }
        return (sorted.filter { $0.timelineDate >= start }, sorted.filter { $0.timelineDate < start })
    }

    /// Days until the event next comes round, or nil when it never will.
    public static func daysUntilNext(_ event: AnniversaryEvent, today: Date,
                                     calendar: Calendar = Anniversary.calendar) -> Int? {
        nextOccurrence(event, today: today, calendar: calendar).map { days(from: today, to: $0, calendar: calendar) }
    }

    /// Whether anything comes round within `soonDays`, today included.
    public static func hasSoon(_ config: WidgetConfig, today: Date = .now, within: Int = Anniversary.soonDays,
                               calendar: Calendar = Anniversary.calendar) -> Bool {
        events(config).contains { (daysUntilNext($0, today: today, calendar: calendar) ?? .max) <= within }
    }

    // MARK: Text

    static let lunarMonthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    static let lunarDigits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)

    /// 正月, 闰六月, 腊月.
    public static func lunarMonthName(_ month: Int, leap: Bool = false) -> String {
        (leap ? "闰" : "") + lunarMonthNames[max(0, min(month - 1, 11))] + "月"
    }

    /// 初一, 十五, 廿一, 三十.
    public static func lunarDayName(_ day: Int) -> String {
        switch day {
        case 10: "初十"
        case 20: "二十"
        case 30: "三十"
        case 1...9: "初" + lunarDigits[day - 1]
        case 11...19: "十" + lunarDigits[day - 11]
        case 21...29: "廿" + lunarDigits[day - 21]
        default: "\(day)"
        }
    }

    /// 正月初一, without the year.
    public static func lunarShort(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let parts = lunarParts(date, calendar: calendar)
        return lunarMonthName(parts.month, leap: parts.isLeap) + lunarDayName(parts.day)
    }

    /// 丁未年正月初一.
    public static func lunarText(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let lunar = lunarCalendar(for: calendar)
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: date)) ?? date
        let cycle = max((lunar.dateComponents([.year], from: noon).year ?? 1) - 1, 0)
        return stems[cycle % 10] + branches[cycle % 12] + "年" + lunarShort(date, calendar: calendar)
    }

    /// 2022-10-21.
    public static func solarText(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The line under an event's name: the lunar date of the day it next
    /// falls on for a lunar event, otherwise the date and whether it repeats.
    public static func subtitle(_ reading: AnniversaryReading, calendar: Calendar = Anniversary.calendar) -> String {
        let event = reading.event
        let shown = event.kind == .countup && reading.phase == .past ? reading.original : reading.timelineDate
        if event.lunar {
            let text = lunarText(shown, calendar: calendar)
            return event.yearly ? "\(text) · 每年" : text
        }
        let text = solarText(shown, calendar: calendar)
        return event.yearly ? "\(text) · 每年" : text
    }

    // MARK: Sizing

    /// Events the multi card shows side by side.
    public static let multiCount = 3

    public static func tileWidth(layout: String, count: Int) -> Double {
        guard layout == "multi" else { return 172 }
        // Nothing yet reads as the full card: the library draws three samples.
        let shown = count == 0 ? multiCount : min(max(count, 2), multiCount)
        return shown == 2 ? 148 : 196
    }

    /// The column stacks one event, or up to three for the multi layout.
    public static func columnHeight(layout: String, count: Int) -> Double {
        guard layout == "multi" else { return 84 }
        let rows = count == 0 ? multiCount : min(count, multiCount)
        return max(84, Double(rows * 38 + 10))
    }
}
