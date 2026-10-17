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
///
/// 图标、颜色、每日目标次数、单位和当天未完成的次数，作为 `days` 列表最后一项
/// 写成 `@icon=…;color=…;goal=…;unit=…;counts=yyyyMMdd:n+yyyyMMdd:n`。放在日期列表里
/// 而不是新开一列，是因为旧版本读日期时会把认不出的项丢掉，降级后打卡记录仍然完整。
/// 什么都没设置的习惯写出来和旧格式一模一样。
public struct Habit: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Day keys (`yyyyMMdd`) the habit was done on, that is its daily goal was met.
    public var days: Set<String>
    /// SF Symbol 名称，nil 时用 `Habit.defaultIcon`。
    public var icon: String?
    /// nil 时用小组件自己的强调色。
    public var color: PaletteColor?
    /// 每天要做几次才算完成，1 就是原来的勾选。
    public var goal: Int
    /// 计数的单位，比如“杯”，nil 时显示“次”。
    public var unit: String?
    /// 还没达到目标的日子做了几次。达到目标的那天只记在 `days` 里。
    public var counts: [String: Int]

    public static let defaultIcon = "checkmark.seal.fill"
    public static let defaultUnit = tr("次")

    public init(id: String = Habit.newID(), name: String, days: Set<String> = [],
                icon: String? = nil, color: PaletteColor? = nil, goal: Int = 1,
                unit: String? = nil, counts: [String: Int] = [:]) {
        self.id = id
        self.name = name
        self.days = days
        self.icon = icon
        self.color = color
        self.goal = HabitTracker.clampGoal(goal)
        self.unit = unit
        self.counts = counts
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    public var iconName: String { icon ?? Self.defaultIcon }
    public var unitName: String { unit ?? Self.defaultUnit }

    /// 只有设置过图标、颜色、目标、单位或有未完成次数时才写的那一项。
    var meta: String? {
        var parts: [String] = []
        if let icon { parts.append("icon=\(icon)") }
        if let color { parts.append("color=\(color.rawValue)") }
        if goal != 1 { parts.append("goal=\(goal)") }
        if let unit { parts.append("unit=\(unit)") }
        let partial = counts.filter { $0.value > 0 && !days.contains($0.key) }
        if !partial.isEmpty {
            parts.append("counts=" + partial.keys.sorted().map { "\($0):\(partial[$0]!)" }.joined(separator: "+"))
        }
        return parts.isEmpty ? nil : "@" + parts.joined(separator: ";")
    }

    var encoded: String {
        let list = days.sorted() + (meta.map { [$0] } ?? [])
        return "\(id)\t\(name)\t\(list.joined(separator: ","))"
    }

    /// Tolerant like the todo list: a bare string is a habit with that name
    /// and no history, and a malformed day is dropped rather than the habit.
    init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count >= 2 {
            let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let id = String(parts[0])
            let items = parts.count == 3 ? parts[2].split(separator: ",").map(String.init) : []
            let days = Set(items.filter(HabitTracker.isDayKey))
            self.init(id: id.isEmpty ? fallbackID : id, name: name, days: days)
            if let meta = items.last(where: { $0.hasPrefix("@") }) { apply(meta: meta) }
        } else {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            self.init(id: fallbackID, name: name)
        }
    }

    /// 认不出的键和值都忽略，习惯本身照常读出。
    private mutating func apply(meta: String) {
        for pair in meta.dropFirst().split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "icon": icon = HabitTracker.cleanIcon(kv[1])
            case "color": color = PaletteColor(rawValue: kv[1])
            case "goal": if let value = Int(kv[1]) { goal = HabitTracker.clampGoal(value) }
            case "unit": unit = HabitTracker.cleanUnit(kv[1])
            case "counts":
                for entry in kv[1].split(separator: "+") {
                    let dc = entry.split(separator: ":").map(String.init)
                    guard dc.count == 2, HabitTracker.isDayKey(dc[0]), let n = Int(dc[1]), n > 0 else { continue }
                    counts[dc[0]] = n
                }
            default: continue
            }
        }
        // 目标改小以后旧的未完成次数可能已经够了。
        let target = goal
        for (key, n) in counts where n >= target {
            days.insert(key)
        }
        let done = days
        counts = counts.filter { !done.contains($0.key) && $0.value < target }
    }
}

/// 新建习惯时一点即加的模板。
public struct HabitTemplate: Equatable, Sendable, Identifiable {
    public var name: String
    public var icon: String
    public var color: PaletteColor
    public var goal: Int
    public var unit: String?

    public var id: String { name }

    public init(name: String, icon: String, color: PaletteColor, goal: Int = 1, unit: String? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
        self.goal = goal
        self.unit = unit
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
            kept.counts = habit.counts.filter { $0.key >= cutoff }
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
        return habits.map { habit in
            guard habit.id == id else { return habit }
            var changed = habit
            changed.name = words
            return changed
        }
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
            changed.counts[key] = nil
            return changed
        }
    }

    /// 打卡按钮的一下：目标是 1 次时和 `toggling` 一样；目标多次时加一次，
    /// 加满算完成，已经完成时再点一下清零（和取消勾选一样）。
    public static func tapping(_ id: String, day: Date, in habits: [Habit],
                               today: Date = .now, calendar: Calendar = HabitTracker.calendar) -> [Habit] {
        let key = dayKey(day, calendar: calendar)
        guard key <= dayKey(today, calendar: calendar) else { return habits }
        return habits.map { habit in
            guard habit.id == id else { return habit }
            var changed = habit
            if changed.days.contains(key) {
                changed.days.remove(key)
                changed.counts[key] = nil
            } else {
                let next = (changed.counts[key] ?? 0) + 1
                if next >= changed.goal {
                    changed.days.insert(key)
                    changed.counts[key] = nil
                } else {
                    changed.counts[key] = next
                }
            }
            return changed
        }
    }

    /// 编辑弹层的“完成”：名称、图标、颜色、目标和单位一起改，打卡记录不动。
    /// 名称为空时保留原名。目标改小后，已经够数的未完成日子算作完成；
    /// 目标改大不会取消已经完成的日子。
    public static func updating(_ id: String, name: String, icon: String?, color: PaletteColor?,
                                goal: Int, unit: String?, in habits: [Habit]) -> [Habit] {
        habits.map { habit in
            guard habit.id == id else { return habit }
            var changed = habit
            if let words = clean(name) { changed.name = words }
            changed.icon = icon.flatMap(cleanIcon)
            changed.color = color
            changed.goal = clampGoal(goal)
            changed.unit = unit.flatMap(cleanUnit)
            let goal = changed.goal
            for (key, n) in changed.counts where n >= goal { changed.days.insert(key) }
            let done = changed.days
            changed.counts = changed.counts.filter { !done.contains($0.key) && $0.value < goal }
            return changed
        }
    }

    /// 新建一个带图标、颜色和目标的习惯。满 `maxHabits` 个或名称为空时不变。
    public static func adding(_ name: String, icon: String?, color: PaletteColor?, goal: Int, unit: String?,
                              to habits: [Habit], id: String = Habit.newID()) -> [Habit] {
        guard let words = clean(name), habits.count < maxHabits else { return habits }
        return habits + [Habit(id: id, name: words, icon: icon.flatMap(cleanIcon), color: color,
                               goal: goal, unit: unit.flatMap(cleanUnit))]
    }

    public static func adding(_ template: HabitTemplate, to habits: [Habit], id: String = Habit.newID()) -> [Habit] {
        adding(template.name, icon: template.icon, color: template.color, goal: template.goal,
               unit: template.unit, to: habits, id: id)
    }

    /// 上移（负数）或下移（正数），到头了就停在头上。
    public static func moving(_ id: String, by offset: Int, in habits: [Habit]) -> [Habit] {
        guard let from = habits.firstIndex(where: { $0.id == id }) else { return habits }
        let to = min(max(from + offset, 0), habits.count - 1)
        guard to != from else { return habits }
        var result = habits
        let habit = result.remove(at: from)
        result.insert(habit, at: to)
        return result
    }

    /// 拖到另一张卡片上：放到那张卡片的位置。
    public static func moving(_ id: String, to targetID: String, in habits: [Habit]) -> [Habit] {
        guard let from = habits.firstIndex(where: { $0.id == id }),
              let to = habits.firstIndex(where: { $0.id == targetID }), from != to else { return habits }
        return moving(id, by: to - from, in: habits)
    }

    // MARK: Goals, icons and colours

    public static let maxGoal = 99
    public static let maxUnitLength = 4

    public static func clampGoal(_ goal: Int) -> Int { min(max(goal, 1), maxGoal) }

    /// SF Symbol 名称只有小写字母、数字和点。
    public static func cleanIcon(_ icon: String) -> String? {
        let trimmed = icon.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 60,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") })
        else { return nil }
        return trimmed
    }

    /// 单位去掉存档里用作分隔的符号，最多 4 个字，空的就用默认的“次”。
    public static func cleanUnit(_ unit: String) -> String? {
        let banned: Set<Character> = [";", "=", ",", "+", "@", ":", "\t", "\n", "\r"]
        let kept = String(unit.filter { !banned.contains($0) }).trimmingCharacters(in: .whitespaces)
        guard !kept.isEmpty, kept != Habit.defaultUnit else { return nil }
        return String(kept.prefix(maxUnitLength))
    }

    /// 编辑弹层里可选的图标。
    public static let icons: [String] = [
        "checkmark.seal.fill", "sunrise.fill", "book.fill", "figure.run",
        "figure.mind.and.body", "drop.fill", "figure.flexibility", "square.and.pencil",
        "moon.zzz.fill", "dumbbell.fill", "figure.walk", "bicycle",
        "heart.fill", "brain.head.profile", "pills.fill", "fork.knife",
        "cup.and.saucer.fill", "bed.double.fill", "music.note", "paintbrush.fill",
        "graduationcap.fill", "leaf.fill", "phone.down.fill", "sparkles",
    ]

    /// 编辑弹层里可选的 8 种颜色。
    public static let colors: [PaletteColor] = PaletteColor.picker

    public static func colorName(_ color: PaletteColor) -> String {
        switch color {
        case .orange: tr("橙色")
        case .yellow: tr("黄色")
        case .pink: tr("粉色")
        case .purple: tr("紫色")
        case .blue: tr("蓝色")
        case .green: tr("绿色")
        case .graphite: tr("灰色")
        case .indigo: tr("靛蓝")
        case .red: tr("红色")
        case .teal: tr("青色")
        }
    }

    public static let templates: [HabitTemplate] = [
        HabitTemplate(name: tr("早起"), icon: "sunrise.fill", color: .orange),
        HabitTemplate(name: tr("阅读"), icon: "book.fill", color: .indigo),
        HabitTemplate(name: tr("运动"), icon: "figure.run", color: .red),
        HabitTemplate(name: tr("冥想"), icon: "figure.mind.and.body", color: .purple),
        HabitTemplate(name: tr("喝水"), icon: "drop.fill", color: .blue, goal: 8, unit: tr("杯")),
        HabitTemplate(name: tr("拉伸"), icon: "figure.flexibility", color: .green),
        HabitTemplate(name: tr("写日记"), icon: "square.and.pencil", color: .pink),
        HabitTemplate(name: tr("不熬夜"), icon: "moon.zzz.fill", color: .teal),
    ]

    /// 卡片底部的目标，比如“每天 1 次”“每天 8 杯”。
    public static func goalText(_ habit: Habit) -> String {
        tr("每天 \(habit.goal) \(habit.unitName)")
    }

    // MARK: Readings

    public static func isDone(_ habit: Habit, on date: Date, calendar: Calendar = HabitTracker.calendar) -> Bool {
        habit.days.contains(dayKey(date, calendar: calendar))
    }

    /// 那天做了几次：完成的日子算满目标。
    public static func count(_ habit: Habit, on date: Date, calendar: Calendar = HabitTracker.calendar) -> Int {
        let key = dayKey(date, calendar: calendar)
        return habit.days.contains(key) ? habit.goal : min(habit.counts[key] ?? 0, habit.goal)
    }

    /// 那天完成了多少，0 到 1。
    public static func progress(_ habit: Habit, on date: Date, calendar: Calendar = HabitTracker.calendar) -> Double {
        Double(count(habit, on: date, calendar: calendar)) / Double(max(habit.goal, 1))
    }

    /// 卡片上的今日状态：“已完成”“未完成”或“3/8 杯”。
    public static func todayText(_ habit: Habit, today: Date, calendar: Calendar = HabitTracker.calendar) -> String {
        if isDone(habit, on: today, calendar: calendar) { return tr("已完成") }
        if habit.goal == 1 { return tr("未完成") }
        return "\(count(habit, on: today, calendar: calendar))/\(habit.goal) \(habit.unitName)"
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
        return max(76, Double(rows * 30 + 12))
    }

    /// The tile's caption under the habits, or its empty state.
    public static func caption(done: Int, total: Int) -> String {
        switch (done, total) {
        case (_, 0): tr("点按添加习惯")
        case (let d, let t) where d >= t: tr("今天全部完成")
        default: tr("今天 \(done)/\(total)")
        }
    }
}
