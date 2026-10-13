import Foundation

/// 习惯打卡：几项每天要做的事，每天点一下记一次。
///
/// The habits live in the widget's own config under `habits`, which, like the
/// todo list's `items`, is the widget's contents rather than a setting, so it
/// is never a catalog default and never offered as a text field in Settings.
///
/// Each habit is one string, `id<TAB>name<TAB>days`, where `days` is a comma
/// separated list of the local calendar days it was done, written `yyyyMMdd`.
/// A string so the existing config type carries it without a new Codable
/// shape; a day key rather than a timestamp so a check-in made in one time
/// zone is still the same day after travelling, which is how a person counts.
public struct Habit: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Day keys (`yyyyMMdd`) the habit was done on.
    public var days: Set<String>

    public init(id: String = Habit.newID(), name: String, days: Set<String> = []) {
        self.id = id
        self.name = name
        self.days = days
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    var encoded: String {
        "\(id)\t\(name)\t\(days.sorted().joined(separator: ","))"
    }

    /// Tolerant like the todo list: a bare string is a habit with that name
    /// and no history, and a malformed day is dropped rather than the habit.
    init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count >= 2 {
            let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let id = String(parts[0])
            let days = parts.count == 3
                ? Set(parts[2].split(separator: ",").map(String.init).filter(HabitTracker.isDayKey))
                : []
            self.init(id: id.isEmpty ? fallbackID : id, name: name, days: days)
        } else {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            self.init(id: fallbackID, name: name)
        }
    }
}

/// One day of a habit, as the tile's dot row and the panel's heatmap draw it.
public struct HabitDay: Equatable, Hashable, Sendable {
    public var key: String
    public var date: Date
    public var day: Int
    public var done: Bool
    public var isToday: Bool
    public var isFuture: Bool
}

public enum HabitTracker {
    public static let key = "habits"
    /// A shelf of habits, not a life plan. Also what the column can stack.
    public static let maxHabits = 8
    public static let maxNameLength = 20
    /// History kept per habit. A year and a bit covers any month the panel
    /// shows and the longest streak worth counting on a shelf, and keeps the
    /// stored string from growing for ever.
    public static let keptDays = 400

    /// Gregorian, whatever calendar the Mac is set to: the day keys are
    /// Gregorian dates, and a Buddhist or Japanese year would write the same
    /// day under a different key.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // 周一开头，中国的日历这样排。
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: Day keys

    public static func dayKey(_ date: Date, calendar: Calendar = HabitTracker.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String, calendar: Calendar = HabitTracker.calendar) -> Date? {
        guard isDayKey(key), let value = Int(key) else { return nil }
        let components = DateComponents(year: value / 10_000, month: value / 100 % 100, day: value % 100)
        return calendar.date(from: components)
    }

    static func isDayKey(_ key: String) -> Bool {
        guard key.count == 8, let value = Int(key) else { return false }
        let month = value / 100 % 100
        let day = value % 100
        return (1...12).contains(month) && (1...31).contains(day)
    }

    // MARK: Reading and writing

    public static func habits(_ config: WidgetConfig) -> [Habit] {
        var seen = Set<String>()
        var result: [Habit] = []
        for (index, raw) in config.strings(key).enumerated() {
            guard var habit = Habit(decoding: raw, fallbackID: "h\(index)") else { continue }
            if seen.contains(habit.id) { habit.id = "\(habit.id)-\(index)" }
            seen.insert(habit.id)
            result.append(habit)
        }
        return Array(result.prefix(maxHabits))
    }

    /// Writes the list back, dropping history older than `keptDays` before `now`.
    public static func store(_ habits: [Habit], in config: inout WidgetConfig, now: Date = .now) {
        let calendar = Self.calendar
        let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: now).map { dayKey($0, calendar: calendar) }
        let trimmed = habits.prefix(maxHabits).map { habit -> Habit in
            guard let cutoff else { return habit }
            var kept = habit
            kept.days = habit.days.filter { $0 >= cutoff }
            return kept
        }
        config.set(key, .list(trimmed.map { .string($0.encoded) }))
    }

    public static func clean(_ name: String) -> String? {
        let oneLine = name.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return String(oneLine.prefix(maxNameLength))
    }

    public static func adding(_ name: String, to habits: [Habit], id: String = Habit.newID()) -> [Habit] {
        guard let words = clean(name), habits.count < maxHabits else { return habits }
        return habits + [Habit(id: id, name: words)]
    }

    public static func renaming(_ id: String, to name: String, in habits: [Habit]) -> [Habit] {
        guard let words = clean(name) else { return habits }
        return habits.map { $0.id == id ? Habit(id: $0.id, name: words, days: $0.days) : $0 }
    }

    public static func removing(_ id: String, from habits: [Habit]) -> [Habit] {
        habits.filter { $0.id != id }
    }

    /// Checks a day in or out. A day after `today` cannot be checked in:
    /// a habit done tomorrow has not been done.
    public static func toggling(_ id: String, day: Date, in habits: [Habit],
                                today: Date = .now, calendar: Calendar = HabitTracker.calendar) -> [Habit] {
        let key = dayKey(day, calendar: calendar)
        guard key <= dayKey(today, calendar: calendar) else { return habits }
        return habits.map { habit in
            guard habit.id == id else { return habit }
            var changed = habit
            if changed.days.contains(key) { changed.days.remove(key) } else { changed.days.insert(key) }
            return changed
        }
    }

    // MARK: Readings

    public static func isDone(_ habit: Habit, on date: Date, calendar: Calendar = HabitTracker.calendar) -> Bool {
        habit.days.contains(dayKey(date, calendar: calendar))
    }

    /// Consecutive days done, ending today. A habit not yet done today keeps
    /// the run that ended yesterday: the day is not over, so the streak is
    /// not broken yet.
    public static func streak(_ habit: Habit, today: Date, calendar: Calendar = HabitTracker.calendar) -> Int {
        var day = calendar.startOfDay(for: today)
        if !isDone(habit, on: day, calendar: calendar) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while isDone(habit, on: day, calendar: calendar), count <= keptDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The longest run anywhere in the kept history.
    public static func longestStreak(_ habit: Habit, calendar: Calendar = HabitTracker.calendar) -> Int {
        let dates = habit.days.compactMap { date(fromKey: $0, calendar: calendar) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }

    /// The last seven days, oldest first, today last: the tile's dot row.
    public static func week(_ habit: Habit, today: Date, calendar: Calendar = HabitTracker.calendar) -> [HabitDay] {
        let start = calendar.startOfDay(for: today)
        return (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            return reading(habit, date, today: start, calendar: calendar)
        }
    }

    /// The month containing `month` as weeks of seven, Monday first, with nil
    /// for the days before the 1st and after the last: the panel's heatmap.
    public static func monthGrid(_ habit: Habit, month: Date, today: Date,
                                 calendar: Calendar = HabitTracker.calendar) -> [[HabitDay?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        // 0 for Monday through 6 for Sunday.
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.startOfDay(for: today)
        var cells: [HabitDay?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            cells.append(reading(habit, date, today: start, calendar: calendar))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Days done in the month containing `month`.
    public static func doneCount(_ habit: Habit, month: Date, calendar: Calendar = HabitTracker.calendar) -> Int {
        let prefix = String(dayKey(month, calendar: calendar).prefix(6))
        return habit.days.filter { $0.hasPrefix(prefix) }.count
    }

    /// How many habits are done today.
    public static func doneToday(_ habits: [Habit], today: Date, calendar: Calendar = HabitTracker.calendar) -> Int {
        habits.filter { isDone($0, on: today, calendar: calendar) }.count
    }

    private static func reading(_ habit: Habit, _ date: Date, today: Date, calendar: Calendar) -> HabitDay {
        let key = dayKey(date, calendar: calendar)
        let todayKey = dayKey(today, calendar: calendar)
        return HabitDay(key: key, date: date, day: calendar.component(.day, from: date),
                        done: habit.days.contains(key), isToday: key == todayKey, isFuture: key > todayKey)
    }

    // MARK: Sizing

    /// Rows the shelf tile draws: three fit a 58pt card.
    public static let tileRows = 3

    /// The 76pt column stacks a name over seven dots per habit, up to four.
    public static func columnHeight(count: Int) -> Double {
        let rows = min(max(count, 1), 4)
        return Double(rows * 30 + 12)
    }

    /// The tile's caption under the habits, or its empty state.
    public static func caption(done: Int, total: Int) -> String {
        switch (done, total) {
        case (_, 0): "点按添加习惯"
        case (let d, let t) where d >= t: "今天全部完成"
        default: "今天 \(done)/\(total)"
        }
    }
}
