import Foundation

/// 喝水：今天喝了多少，离目标还差多少，小熊猫跟着“装满”。
///
/// Everything the widget remembers lives in its own config, like the habit
/// tracker's check-ins: `days` is the log (the widget's contents, so never a
/// catalog default and never a text field in Settings), and the options
/// (`goal`, `cupSize`, `remindEvery`, `start`, `end`, `unit`) sit beside it.
/// The panel also keeps `customFactor` (how much a 自定义 drink counts) and
/// the inputs of the personal goal (`weight`, `sex`, `age` and the rest, see
/// WaterGoal), none of which is a Settings row; `goal` is only the goal set
/// by hand.
///
/// One string per day: `yyyyMMdd|goal|entries`.
///
/// - `goal` is that day's goal in millilitres, frozen once the day is over so
///   raising the goal today never rewrites whether last week was met.
/// - `entries` is a comma separated list of drinks, each `HHMM` + a one letter
///   drink code + the amount poured in millilitres, with `@NN` (percent) only
///   when the hydration factor is not the drink's own, e.g. `0930w250`,
///   `1415c200`, `1600x300@70`.
/// - Days older than `detailDays` are folded into `=total`, the effective
///   millilitres of that day: the chart, the calendar and the streak only
///   need the total, and a hundred and twenty days of single sips would make
///   every write rewrite a long string for nothing.
///
/// A day key rather than a timestamp, as in HabitTracker: a glass drunk in
/// one time zone stays on the day it was drunk after travelling.
public enum DrinkType: String, CaseIterable, Sendable, Hashable, Identifiable {
    case water = "w"
    case tea = "t"
    case coffee = "c"
    case milk = "m"
    case juice = "j"
    case soda = "s"
    case custom = "x"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: "水"
        case .tea: "茶"
        case .coffee: "咖啡"
        case .milk: "牛奶"
        case .juice: "果汁"
        case .soda: "汽水"
        case .custom: "自定义"
        }
    }

    /// How much of what is poured counts toward the day. Rough, friendly
    /// numbers in the spirit of hydration apps, not a medical table.
    public var factor: Double {
        switch self {
        case .water: 1.0
        case .tea: 0.9
        case .coffee: 0.8
        case .milk: 0.9
        case .juice: 0.8
        case .soda: 0.6
        case .custom: 1.0
        }
    }

    public var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .tea: "leaf.fill"
        case .coffee: "cup.and.saucer.fill"
        case .milk: "mug.fill"
        case .juice: "takeoutbag.and.cup.and.straw.fill"
        case .soda: "bubbles.and.sparkles.fill"
        case .custom: "slider.horizontal.3"
        }
    }
}

/// One drink.
public struct WaterEntry: Equatable, Hashable, Sendable {
    /// Minutes after local midnight, 0...1439.
    public var minute: Int
    public var type: DrinkType
    /// Millilitres poured.
    public var amount: Int
    /// The share that counts, 0.1...1.5.
    public var factor: Double

    public init(minute: Int, type: DrinkType, amount: Int, factor: Double? = nil) {
        self.minute = min(1439, max(0, minute))
        self.type = type
        self.amount = max(0, amount)
        self.factor = WaterIntake.clampFactor(factor ?? type.factor)
    }

    /// Millilitres that count toward the goal.
    public var effective: Int { Int((Double(amount) * factor).rounded()) }

    public var clock: String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    var encoded: String {
        var text = String(format: "%02d%02d", minute / 60, minute % 60) + type.rawValue + "\(amount)"
        let percent = Int((factor * 100).rounded())
        if percent != Int((type.factor * 100).rounded()) { text += "@\(percent)" }
        return text
    }

    /// Nil for anything malformed, so one bad token loses one drink, not a day.
    init?(decoding raw: Substring) {
        guard raw.count >= 6 else { return nil }
        let chars = Array(raw)
        guard let hh = Int(String(chars[0..<2])), let mm = Int(String(chars[2..<4])),
              (0...23).contains(hh), (0...59).contains(mm),
              let type = DrinkType(rawValue: String(chars[4])) else { return nil }
        let rest = String(chars[5...])
        let parts = rest.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard let amount = Int(parts[0]), amount > 0 else { return nil }
        var factor: Double?
        if parts.count == 2 {
            guard let percent = Int(parts[1]) else { return nil }
            factor = Double(percent) / 100
        }
        self.init(minute: hh * 60 + mm, type: type, amount: amount, factor: factor)
    }
}

/// One day of the log.
public struct WaterDay: Equatable, Sendable {
    /// `yyyyMMdd`.
    public var key: String
    public var goal: Int
    public var entries: [WaterEntry]
    /// The effective total of a day whose single drinks were folded away.
    public var summary: Int?

    public init(key: String, goal: Int, entries: [WaterEntry] = [], summary: Int? = nil) {
        self.key = key
        self.goal = goal
        self.entries = entries
        self.summary = summary
    }

    /// Effective millilitres.
    public var total: Int { summary ?? entries.reduce(0) { $0 + $1.effective } }
    public var isMet: Bool { goal > 0 && total >= goal }

    var encoded: String {
        let body = summary.map { "=\($0)" } ?? entries.map(\.encoded).joined(separator: ",")
        return "\(key)|\(goal)|\(body)"
    }

    init?(decoding raw: String) {
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, HabitTracker.isDayKey(String(parts[0])),
              let goal = Int(parts[1]) else { return nil }
        let body = parts[2]
        if body.hasPrefix("=") {
            guard let total = Int(body.dropFirst()) else { return nil }
            self.init(key: String(parts[0]), goal: goal, summary: max(0, total))
        } else {
            let entries = body.split(separator: ",").compactMap(WaterEntry.init(decoding:))
            self.init(key: String(parts[0]), goal: goal, entries: entries.sorted { $0.minute < $1.minute })
        }
    }
}

/// One day as the chart and the calendar draw it.
public struct WaterDayReading: Equatable, Hashable, Sendable {
    public var key: String
    public var date: Date
    public var day: Int
    public var total: Int
    public var goal: Int
    public var isToday: Bool
    public var isFuture: Bool
    public var isMet: Bool { goal > 0 && total >= goal }
    /// 0...1, for a bar's height.
    public var fraction: Double { WaterIntake.progress(total: total, goal: goal) }
}

public enum WaterIntake {
    public static let key = "days"
    public static let defaultGoal = 2000
    public static let goalRange = 500...6000
    public static let defaultCup = 250
    public static let cupRange = 50...1000
    /// About four months: enough for the month calendar and any streak a
    /// shelf will show, and a bound on the stored string.
    public static let keptDays = 120
    /// Days whose single drinks are kept; older days keep their total only.
    public static let detailDays = 7
    /// A day is a shelf of glasses, not a spreadsheet.
    public static let maxEntriesPerDay = 60
    /// 体重 x 35 毫升, the old suggestion; kept to recognise a goal it set.
    public static let millilitresPerKilogram = 35
    public static let quickAmounts = [100, 250, 500]
    /// 15, 20, 180 and 240 came with the old 喝水提醒, whose interval was
    /// any number of minutes; see `migratingHydration`.
    public static let reminderChoices = [0, 15, 20, 30, 45, 60, 90, 120, 180, 240]
    public static let defaultReminder = 60
    public static let millilitresPerOunce = 29.5735

    public static var calendar: Calendar { HabitTracker.calendar }

    // MARK: Options

    /// Today's goal: the one set by hand, or the personal recommendation
    /// (see WaterGoal). `now` matters because today's exercise and 发烧或腹泻
    /// count only on the day they were set.
    public static func goal(_ config: WidgetConfig, now: Date = .now,
                            calendar: Calendar = WaterIntake.calendar) -> Int {
        WaterGoal.result(config, now: now, calendar: calendar).goal
    }

    public static func clampGoal(_ value: Int) -> Int {
        min(goalRange.upperBound, max(goalRange.lowerBound, value))
    }

    public static func cupSize(_ config: WidgetConfig) -> Int {
        min(cupRange.upperBound, max(cupRange.lowerBound, config.int("cupSize", default: defaultCup)))
    }

    public static func clampFactor(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1.5, max(0.1, (value * 100).rounded() / 100))
    }

    public static func customFactor(_ config: WidgetConfig) -> Double {
        clampFactor(config.double("customFactor", default: 1))
    }

    public static func usesOunces(_ config: WidgetConfig) -> Bool {
        config.string("unit", default: "ml") == "oz"
    }

    /// Minutes between reminders, 0 for off. Anything not on the menu is off
    /// rather than a guess.
    public static func reminderMinutes(_ config: WidgetConfig) -> Int {
        let value = Int(config.string("remindEvery", default: "\(defaultReminder)")) ?? 0
        return reminderChoices.contains(value) ? value : 0
    }

    // MARK: The old 喝水提醒

    /// The raw kind the old 喝水提醒 widget was saved under. Kept only so a
    /// saved shelf still decodes; see `WidgetInstance.init(from:)`.
    public static let legacyHydrationKind = "hydration"

    /// The old widget's config as 喝水's.
    ///
    /// It stored two things: `duration`, seconds between drinks (45 minutes
    /// by default), and `lastDrink`, the moment of the last tap. The interval
    /// becomes `remindEvery`, the nearest choice on the menu that is not off.
    /// `lastDrink` is dropped: it has no amount, so it cannot become a glass
    /// in the log without inventing one. Every other key (where the tile sits,
    /// when it shows) is kept, and anything 喝水 needs that is missing is
    /// filled from the catalog's defaults when the tile is drawn.
    public static func migratingHydration(_ old: WidgetConfig) -> WidgetConfig {
        var config = old
        let seconds = old.double("duration", default: 2700)
        config.set("duration", nil)
        config.set("lastDrink", nil)
        if config["remindEvery"] == nil {
            config.set("remindEvery", .string("\(nearestReminder(seconds: seconds))"))
        }
        return config
    }

    /// The menu's interval closest to `seconds`, never 0 (off): the old widget
    /// had no off, so a shelf that had one keeps being reminded.
    public static func nearestReminder(seconds: Double) -> Int {
        let minutes = seconds.isFinite ? seconds / 60 : Double(defaultReminder)
        let choices = reminderChoices.filter { $0 > 0 }
        return choices.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? defaultReminder
    }

    // MARK: Reading and writing

    public static func days(_ config: WidgetConfig) -> [WaterDay] {
        var byKey: [String: WaterDay] = [:]
        for raw in config.strings(key) {
            guard let day = WaterDay(decoding: raw) else { continue }
            // A duplicate key (two shelves merged by hand) adds up rather
            // than one silently winning.
            if var existing = byKey[day.key] {
                if existing.summary == nil, day.summary == nil {
                    existing.entries = (existing.entries + day.entries).sorted { $0.minute < $1.minute }
                } else {
                    existing.summary = existing.total + day.total
                    existing.entries = []
                }
                byKey[day.key] = existing
            } else {
                byKey[day.key] = day
            }
        }
        return byKey.values.sorted { $0.key < $1.key }
    }

    /// Writes the log back: days older than `keptDays` before `now` are
    /// dropped, days older than `detailDays` are folded into their total, and
    /// empty days that are not today are left out.
    public static func store(_ days: [WaterDay], in config: inout WidgetConfig, now: Date = .now,
                             calendar: Calendar = WaterIntake.calendar) {
        config.set(key, .list(compacted(days, now: now, calendar: calendar).map { .string($0.encoded) }))
    }

    public static func compacted(_ days: [WaterDay], now: Date,
                                 calendar: Calendar = WaterIntake.calendar) -> [WaterDay] {
        let today = HabitTracker.dayKey(now, calendar: calendar)
        let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: now)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        let foldBefore = calendar.date(byAdding: .day, value: -detailDays, to: now)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        return days.sorted { $0.key < $1.key }.compactMap { day in
            guard day.key > cutoff else { return nil }
            guard day.key == today || day.total > 0 else { return nil }
            var kept = day
            if day.key < foldBefore, day.summary == nil {
                kept.summary = day.total
                kept.entries = []
            }
            return kept
        }
    }

    /// Today's record, or an empty one carrying the current goal.
    public static func today(_ days: [WaterDay], goal: Int, now: Date,
                             calendar: Calendar = WaterIntake.calendar) -> WaterDay {
        let key = HabitTracker.dayKey(now, calendar: calendar)
        guard var day = days.first(where: { $0.key == key }) else { return WaterDay(key: key, goal: goal) }
        // Today follows the setting; only finished days are frozen.
        day.goal = goal
        return day
    }

    public static func today(_ config: WidgetConfig, now: Date = .now,
                             calendar: Calendar = WaterIntake.calendar) -> WaterDay {
        today(days(config), goal: goal(config, now: now, calendar: calendar), now: now, calendar: calendar)
    }

    /// Replaces today's record in the log, adding it if it is new.
    static func replacingToday(_ day: WaterDay, in days: [WaterDay]) -> [WaterDay] {
        var result = days.filter { $0.key != day.key }
        result.append(day)
        return result.sorted { $0.key < $1.key }
    }

    /// Logs a drink at `now`.
    public static func logging(_ type: DrinkType, amount: Int, factor: Double? = nil,
                               in days: [WaterDay], goal: Int, now: Date,
                               calendar: Calendar = WaterIntake.calendar) -> [WaterDay] {
        guard amount > 0 else { return days }
        var day = today(days, goal: goal, now: now, calendar: calendar)
        guard day.summary == nil, day.entries.count < maxEntriesPerDay else { return days }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let entry = WaterEntry(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), type: type,
                               amount: min(amount, 5000), factor: factor)
        day.entries.append(entry)
        day.entries.sort { $0.minute < $1.minute }
        return replacingToday(day, in: days)
    }

    /// Removes today's drink at `index` (in time order).
    public static func removing(at index: Int, in days: [WaterDay], goal: Int, now: Date,
                                calendar: Calendar = WaterIntake.calendar) -> [WaterDay] {
        var day = today(days, goal: goal, now: now, calendar: calendar)
        guard day.entries.indices.contains(index) else { return days }
        day.entries.remove(at: index)
        return replacingToday(day, in: days)
    }

    /// Takes back the drink logged last today: the latest by time, and of two
    /// at the same minute the one written last.
    public static func undoingLast(in days: [WaterDay], goal: Int, now: Date,
                                   calendar: Calendar = WaterIntake.calendar) -> [WaterDay] {
        let day = today(days, goal: goal, now: now, calendar: calendar)
        guard !day.entries.isEmpty else { return days }
        return removing(at: day.entries.count - 1, in: days, goal: goal, now: now, calendar: calendar)
    }

    /// The goal changed: today's record follows, finished days do not.
    public static func settingGoal(_ goal: Int, in days: [WaterDay], now: Date,
                                   calendar: Calendar = WaterIntake.calendar) -> [WaterDay] {
        let key = HabitTracker.dayKey(now, calendar: calendar)
        return days.map { day in
            guard day.key == key else { return day }
            var changed = day
            changed.goal = clampGoal(goal)
            return changed
        }
    }

    // MARK: Readings

    /// 0...1 toward the goal.
    public static func progress(total: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, Double(total) / Double(goal)))
    }

    public static func isMet(total: Int, goal: Int) -> Bool { goal > 0 && total >= goal }

    /// Whether the display condition 今天未达标时显示 holds.
    public static func belowGoal(_ config: WidgetConfig, now: Date = .now) -> Bool {
        !today(config, now: now).isMet
    }

    /// When the latest drink went in, across the whole log.
    public static func lastDrink(_ days: [WaterDay], calendar: Calendar = WaterIntake.calendar) -> Date? {
        for day in days.sorted(by: { $0.key > $1.key }) {
            guard let last = day.entries.max(by: { $0.minute < $1.minute }),
                  let start = HabitTracker.date(fromKey: day.key, calendar: calendar) else { continue }
            return calendar.date(byAdding: .minute, value: last.minute, to: start)
        }
        return nil
    }

    /// Consecutive days the goal was met, ending today. Today not met yet
    /// keeps the run that ended yesterday: the day is not over.
    public static func streak(_ days: [WaterDay], goal: Int, today: Date,
                              calendar: Calendar = WaterIntake.calendar) -> Int {
        var met = Set(days.filter(\.isMet).map(\.key))
        let todayKey = HabitTracker.dayKey(today, calendar: calendar)
        // Today is judged against the current goal, like everything else today.
        let current = Self.today(days, goal: goal, now: today, calendar: calendar)
        if current.isMet { met.insert(todayKey) } else { met.remove(todayKey) }

        var day = calendar.startOfDay(for: today)
        if !met.contains(todayKey) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while met.contains(HabitTracker.dayKey(day, calendar: calendar)), count <= keptDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Days in a row before today that missed their goal, counted back from
    /// yesterday and never past the first day anything was logged (a new
    /// widget has not missed the days before it existed). 0 once today's
    /// goal is met.
    public static func missedDays(_ days: [WaterDay], goal: Int, today: Date,
                                  calendar: Calendar = WaterIntake.calendar) -> Int {
        if Self.today(days, goal: goal, now: today, calendar: calendar).isMet { return 0 }
        guard let first = days.map(\.key).min() else { return 0 }
        let byKey = Dictionary(days.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var count = 0
        var day = calendar.startOfDay(for: today)
        while count <= keptDays {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            let key = HabitTracker.dayKey(day, calendar: calendar)
            guard key >= first else { break }
            if byKey[key]?.isMet == true { break }
            count += 1
        }
        return count
    }

    /// The last `count` days, oldest first and today last: the panel's bars.
    public static func lastDays(_ days: [WaterDay], goal: Int, today: Date, count: Int = 7,
                                calendar: Calendar = WaterIntake.calendar) -> [WaterDayReading] {
        let start = calendar.startOfDay(for: today)
        return (0..<max(1, count)).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            return reading(days, date, goal: goal, today: start, calendar: calendar)
        }
    }

    /// The month containing `month` as weeks of seven, Monday first, nil
    /// outside the month: the panel's calendar dots.
    public static func monthGrid(_ days: [WaterDay], goal: Int, month: Date, today: Date,
                                 calendar: Calendar = WaterIntake.calendar) -> [[WaterDayReading?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.startOfDay(for: today)
        var cells: [WaterDayReading?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            cells.append(reading(days, date, goal: goal, today: start, calendar: calendar))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Days the goal was met in the month containing `month`.
    public static func metCount(_ days: [WaterDay], goal: Int, month: Date, today: Date,
                                calendar: Calendar = WaterIntake.calendar) -> Int {
        monthGrid(days, goal: goal, month: month, today: today, calendar: calendar)
            .flatMap { $0 }.compactMap { $0 }.filter { !$0.isFuture && $0.isMet }.count
    }

    private static func reading(_ days: [WaterDay], _ date: Date, goal: Int, today: Date,
                                calendar: Calendar) -> WaterDayReading {
        let key = HabitTracker.dayKey(date, calendar: calendar)
        let todayKey = HabitTracker.dayKey(today, calendar: calendar)
        let stored = days.first { $0.key == key }
        let dayGoal = key == todayKey ? goal : (stored?.goal ?? goal)
        return WaterDayReading(key: key, date: date, day: calendar.component(.day, from: date),
                               total: stored?.total ?? 0, goal: dayGoal,
                               isToday: key == todayKey, isFuture: key > todayKey)
    }

    // MARK: Goal suggestion

    /// The old suggestion: 体重 x 35 毫升, to the nearest 50 and inside the
    /// goal range. Nil for a weight no adult has. The goal now comes from
    /// WaterGoal; this only tells whether an old saved goal was the old
    /// suggestion (see `WaterGoal.manualGoal`).
    public static func suggestedGoal(weightKilograms: Double) -> Int? {
        guard weightKilograms.isFinite, (20...250).contains(weightKilograms) else { return nil }
        let raw = weightKilograms * Double(millilitresPerKilogram)
        return clampGoal(Int((raw / 50).rounded()) * 50)
    }

    // MARK: Words

    public static func unitLabel(ounces: Bool) -> String { ounces ? "盎司" : "毫升" }

    /// The figure alone: "1200", or "40.6" in ounces.
    public static func figure(_ millilitres: Int, ounces: Bool) -> String {
        guard ounces else { return "\(millilitres)" }
        let value = Double(millilitres) / millilitresPerOunce
        return value >= 100 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    /// "250 毫升".
    public static func amount(_ millilitres: Int, ounces: Bool) -> String {
        "\(figure(millilitres, ounces: ounces)) \(unitLabel(ounces: ounces))"
    }

    /// "1200 / 2000 毫升".
    public static func tally(total: Int, goal: Int, ounces: Bool) -> String {
        "\(figure(total, ounces: ounces)) / \(figure(goal, ounces: ounces)) \(unitLabel(ounces: ounces))"
    }

    /// What is left, or that the day is done.
    public static func remainingLine(total: Int, goal: Int, ounces: Bool) -> String {
        guard !isMet(total: total, goal: goal) else { return "今天达标啦" }
        return "还差 \(amount(goal - total, ounces: ounces))"
    }

    public static func percent(total: Int, goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        return Int((Double(total) / Double(goal) * 100).rounded(.down))
    }
}

/// When the next "该喝水了" goes out.
///
/// Only inside the active hours, never once today's goal is met, and never
/// sooner than `interval` after the last drink: the first reminder of a day is
/// at the start of the window (or an interval after a drink taken before it),
/// an ignored one repeats every interval, and one that would land after the
/// end of the window moves to the start of tomorrow's.
public struct WaterReminder: Equatable, Sendable {
    /// Minutes between reminders; 0 is off.
    public var every: Int
    /// Minutes after midnight.
    public var start: Int
    public var end: Int

    public init(every: Int, start: Int, end: Int) {
        self.every = max(0, every)
        self.start = min(1439, max(0, start))
        self.end = min(1440, max(0, end))
    }

    public init(config: WidgetConfig) {
        self.init(every: WaterIntake.reminderMinutes(config),
                  start: PostureSchedule.minutes(config.string("start", default: "09:00")) ?? 9 * 60,
                  end: PostureSchedule.minutes(config.string("end", default: "21:00")) ?? 21 * 60)
    }

    /// The window on the day starting at `dayStart`. An end not after the
    /// start (or a malformed one) means the whole day.
    func window(_ dayStart: Date) -> (start: Date, end: Date) {
        if end > start {
            return (dayStart.addingTimeInterval(TimeInterval(start * 60)),
                    dayStart.addingTimeInterval(TimeInterval(end * 60)))
        }
        return (dayStart, dayStart.addingTimeInterval(86_400))
    }

    public func isActive(_ date: Date, calendar: Calendar = WaterIntake.calendar) -> Bool {
        let w = window(calendar.startOfDay(for: date))
        return date >= w.start && date <= w.end
    }

    /// Strictly after `now`, or nil when reminders are off.
    public func next(now: Date, lastDrink: Date?, todayTotal: Int, goal: Int,
                     calendar: Calendar = WaterIntake.calendar) -> Date? {
        guard every > 0 else { return nil }
        let interval = TimeInterval(every * 60)
        let dayStart = calendar.startOfDay(for: now)
        if !WaterIntake.isMet(total: todayTotal, goal: goal) {
            let w = window(dayStart)
            var candidate = w.start
            if let lastDrink, lastDrink >= dayStart {
                candidate = max(candidate, lastDrink.addingTimeInterval(interval))
            }
            if candidate <= now {
                let missed = (now.timeIntervalSince(candidate) / interval).rounded(.down) + 1
                candidate = candidate.addingTimeInterval(missed * interval)
            }
            if candidate <= w.end { return candidate }
        }
        // Tomorrow starts with nothing drunk.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return window(calendar.startOfDay(for: tomorrow)).start
    }

    /// Where the reminder stands, for the panel: the old 喝水提醒's readout
    /// (when the next drink is due, and how long it has been overdue), on
    /// 喝水's schedule.
    public enum Due: Equatable, Sendable {
        /// Reminders are off.
        case off
        /// Today's goal is met; the next one is tomorrow's first, at this time.
        case met(Date)
        /// Due at this time.
        case upcoming(Date)
        /// Due for this many seconds, inside the hours with the goal unmet.
        case overdue(TimeInterval)
    }

    /// The same rule as `next`, except that a due time already passed is
    /// reported as overdue rather than rolled forward to the next repeat.
    public func due(now: Date, lastDrink: Date?, todayTotal: Int, goal: Int,
                    calendar: Calendar = WaterIntake.calendar) -> Due {
        guard every > 0 else { return .off }
        if WaterIntake.isMet(total: todayTotal, goal: goal) {
            guard let next = next(now: now, lastDrink: lastDrink, todayTotal: todayTotal, goal: goal,
                                  calendar: calendar) else { return .off }
            return .met(next)
        }
        let dayStart = calendar.startOfDay(for: now)
        let w = window(dayStart)
        if now >= w.start, now <= w.end {
            var dueAt = w.start
            if let lastDrink, lastDrink >= dayStart {
                dueAt = max(dueAt, lastDrink.addingTimeInterval(TimeInterval(every * 60)))
            }
            if dueAt <= now { return .overdue(now.timeIntervalSince(dueAt)) }
            if dueAt <= w.end { return .upcoming(dueAt) }
        }
        guard let next = next(now: now, lastDrink: lastDrink, todayTotal: todayTotal, goal: goal,
                              calendar: calendar) else { return .off }
        return .upcoming(next)
    }

    /// A next reminder picked by hand in the panel, kept as `nextAt`
    /// (seconds since 1970). It holds while it is still ahead, reminders are
    /// on and today's goal is not met; a drink clears it, and once it has
    /// passed the usual schedule takes over again.
    public static let overrideKey = "nextAt"

    public static func override(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = WaterIntake.calendar) -> Date? {
        let stamp = config.double(overrideKey)
        guard stamp > 0, WaterIntake.reminderMinutes(config) > 0 else { return nil }
        let at = Date(timeIntervalSince1970: stamp)
        guard at > now else { return nil }
        let today = WaterIntake.today(WaterIntake.days(config), goal: WaterIntake.goal(config, now: now, calendar: calendar),
                                      now: now, calendar: calendar)
        return WaterIntake.isMet(total: today.total, goal: today.goal) ? nil : at
    }

    /// The time a hand-picked reminder lands on: `minutes` after midnight
    /// today, or tomorrow when that has already gone by.
    public static func pickedTime(minutes: Int, now: Date,
                                  calendar: Calendar = WaterIntake.calendar) -> Date {
        let today = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minutes * 60))
        return today > now ? today : today.addingTimeInterval(86_400)
    }

    public static func due(_ config: WidgetConfig, now: Date,
                           calendar: Calendar = WaterIntake.calendar) -> Due {
        if let picked = override(config, now: now, calendar: calendar) { return .upcoming(picked) }
        let days = WaterIntake.days(config)
        let today = WaterIntake.today(days, goal: WaterIntake.goal(config, now: now, calendar: calendar), now: now, calendar: calendar)
        return WaterReminder(config: config).due(now: now, lastDrink: WaterIntake.lastDrink(days, calendar: calendar),
                                                  todayTotal: today.total, goal: today.goal, calendar: calendar)
    }

    public static func next(_ config: WidgetConfig, now: Date,
                            calendar: Calendar = WaterIntake.calendar) -> Date? {
        if let picked = override(config, now: now, calendar: calendar) { return picked }
        let days = WaterIntake.days(config)
        let today = WaterIntake.today(days, goal: WaterIntake.goal(config, now: now, calendar: calendar), now: now, calendar: calendar)
        return WaterReminder(config: config).next(now: now, lastDrink: WaterIntake.lastDrink(days, calendar: calendar),
                                                   todayTotal: today.total, goal: today.goal, calendar: calendar)
    }

    /// The red panda's lines, picked by the moment so two reminders in a row
    /// rarely say the same thing.
    public static func message(at date: Date, total: Int, goal: Int, ounces: Bool = false)
        -> (title: String, body: String) {
        let left = WaterIntake.amount(max(0, goal - total), ounces: ounces)
        let lines: [(String, String)] = [
            ("小熊猫举起了水杯", "咕嘟咕嘟，陪我喝一口吧！今天还差 \(left)。"),
            ("小熊猫有点渴了", "尾巴都蔫了，喝杯水让我们一起满血复活。还差 \(left)。"),
            ("该喝水啦", "小熊猫已经把杯子推到你面前了，还差 \(left) 就装满啦。"),
            ("小熊猫敲了敲屏幕", "别光顾着忙，抿一口水再继续。今天还差 \(left)。"),
            ("补水时间到", "小熊猫说：喝水的人运气不会太差。还差 \(left)。"),
        ]
        let index = Int(date.timeIntervalSince1970 / 60) % lines.count
        let pick = lines[(index + lines.count) % lines.count]
        return (pick.0, pick.1)
    }
}

/// Sizes, beside the logic so the catalog stays free of SwiftUI.
public extension WaterIntake {
    /// 液态和圆环一样宽：都没有角色。
    static func tileWidth(layout: String) -> Double {
        layout == "ring" || layout == LiquidMotion.layout ? 184 : 200
    }

    static func columnHeight(layout: String) -> Double {
        layout == "ring" || layout == LiquidMotion.layout ? 112 : 120
    }
}

// MARK: - Characters

/// Who fills up on the tile. The red panda is the app icon's own and has one
/// picture for every mood; the others have four, `water-<id>-<mood>.png`.
public enum WaterCharacter: String, CaseIterable, Sendable, Identifiable {
    case redPanda = "panda"
    case shiba
    case cat
    case penguin
    case otter
    case octopus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .redPanda: "小熊猫"
        case .shiba: "柴犬"
        case .cat: "橘猫"
        case .penguin: "企鹅"
        case .otter: "水獭"
        case .octopus: "章鱼"
        }
    }

    /// Whether it has a picture per mood.
    public var hasMoods: Bool { self != .redPanda }

    /// Pro 专属: every character but the red panda, unlocked from the
    /// sponsor window like the supporter clock faces.
    public var isSupporterOnly: Bool { self != .redPanda }

    /// The bundled picture's name for a mood, without the extension.
    public func imageName(_ mood: WaterMood) -> String {
        hasMoods ? "water-\(rawValue)-\(mood.rawValue)" : "WaterPanda"
    }

    /// Width over height of the box the character is drawn in: its widest
    /// picture, so changing mood never moves the text beside it.
    public var aspect: Double {
        switch self {
        case .redPanda: 360.0 / 281.0
        default: 0.95
        }
    }

    public static func from(_ config: WidgetConfig) -> WaterCharacter {
        WaterCharacter(rawValue: config.string("character", default: WaterCharacter.redPanda.rawValue)) ?? .redPanda
    }

    /// What is drawn: a supporter-only character falls back to the red panda
    /// while it is locked, as a supporter clock face falls back to flip
    /// cards, so a config copied from another Mac still shows someone.
    public static func shown(_ config: WidgetConfig, unlocked: Bool) -> WaterCharacter {
        let chosen = from(config)
        return chosen.isSupporterOnly && !unlocked ? .redPanda : chosen
    }
}

/// What the character is doing.
public enum WaterMood: String, CaseIterable, Sendable {
    /// Sitting there.
    case idle
    /// Eyes closed: outside the reminder hours, or nothing drunk for a long while.
    case rest
    /// Holding a cup, for a moment after a drink is logged.
    case drink
    /// Arms up with confetti: today's goal is met.
    case cheer

    /// How long the cup stays up after a drink.
    public static let drinkSeconds: TimeInterval = 3
    /// How long without a drink before it dozes off inside the hours.
    public static let dozeAfter: TimeInterval = 3 * 3600

    /// Drinking beats everything for its few seconds, then a met goal, then
    /// rest, then idle.
    ///
    /// `loggedAt` is when the last drink was written (a timestamp, since the
    /// log itself only keeps minutes); `lastDrink` is the latest drink in the
    /// log. The window is the reminder hours, whether or not reminders are on.
    public static func at(_ now: Date, loggedAt: Date?, lastDrink: Date?, met: Bool,
                          window: WaterReminder, calendar: Calendar = WaterIntake.calendar) -> WaterMood {
        if let loggedAt, now >= loggedAt, now.timeIntervalSince(loggedAt) < drinkSeconds { return .drink }
        if met { return .cheer }
        guard window.isActive(now, calendar: calendar) else { return .rest }
        let dayStart = calendar.startOfDay(for: now)
        let opened = window.window(dayStart).start
        let since = max(lastDrink ?? opened, opened)
        return now.timeIntervalSince(since) >= dozeAfter ? .rest : .idle
    }

    public static func at(_ now: Date, config: WidgetConfig, calendar: Calendar = WaterIntake.calendar) -> WaterMood {
        let days = WaterIntake.days(config)
        let today = WaterIntake.today(days, goal: WaterIntake.goal(config, now: now, calendar: calendar), now: now, calendar: calendar)
        let logged = config.double("loggedAt")
        return at(now, loggedAt: logged > 0 ? Date(timeIntervalSince1970: logged) : nil,
                  lastDrink: WaterIntake.lastDrink(days, calendar: calendar), met: today.isMet,
                  window: WaterReminder(config: config), calendar: calendar)
    }
}
