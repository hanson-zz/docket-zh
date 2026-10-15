import Foundation

/// 近七天报告：喝水、专注计时和习惯打卡面板底部共用的那一块。
///
/// Pure arithmetic over a value per day: each widget hands in its own log as
/// day key (`yyyyMMdd`, the same keys HabitTracker and WaterIntake write) to
/// a figure, plus a daily goal, and gets back seven days ending today, the
/// daily average, the total, how many days met the goal and the best day.
///
/// A day with nothing logged is a zero, not a gap: the average is over all
/// seven days, the way Grow and the Health app count a week, so a week with
/// two good days does not read as a good week.
public struct WeeklyReportDay: Equatable, Hashable, Sendable {
    /// `yyyyMMdd`.
    public var key: String
    public var date: Date
    /// Day of the month, 1...31.
    public var day: Int
    /// 0 for Monday through 6 for Sunday.
    public var weekday: Int
    public var value: Double
    /// That day's goal; 0 means no goal, so nothing is met.
    public var goal: Double
    public var isToday: Bool

    public var isMet: Bool { WeeklyReport.isMet(value: value, goal: goal) }

    /// "15".
    public var dayLabel: String { "\(day)" }
    /// "周三".
    public var weekdayLabel: String { WeeklyReport.weekdayNames[weekday] }
    /// "15 / 周三", the axis under a bar.
    public var axisLabel: String { "\(dayLabel) / \(weekdayLabel)" }
}

public struct WeeklyReport: Equatable, Sendable {
    /// Oldest first, today last.
    public var days: [WeeklyReportDay]
    /// The goal today, which is where the dashed line is drawn.
    public var goal: Double
    public var total: Double
    /// `total` over every day in `days`, logged or not.
    public var average: Double
    public var metDays: Int
    /// The day with the most, the later one on a tie; nil when every day is 0.
    public var best: WeeklyReportDay?

    public static let dayCount = 7
    public static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    public static func isMet(value: Double, goal: Double) -> Bool {
        goal > 0 && value >= goal
    }

    /// The last `count` days ending on `today`.
    ///
    /// - Parameters:
    ///   - values: a figure per day key; keys outside the window are ignored,
    ///     and a negative or non-finite figure counts as 0.
    ///   - goal: today's goal, and every other day's unless `goals` has one.
    ///   - goals: a goal per day key, for logs that freeze each finished day's
    ///     goal (喝水) so raising it today does not rewrite last week.
    public static func make(values: [String: Double], goal: Double, goals: [String: Double] = [:],
                            today: Date, count: Int = WeeklyReport.dayCount,
                            calendar: Calendar = HabitTracker.calendar) -> WeeklyReport {
        let start = calendar.startOfDay(for: today)
        let todayKey = HabitTracker.dayKey(start, calendar: calendar)
        let todayGoal = clean(goal)
        let days: [WeeklyReportDay] = (0..<max(1, count)).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let key = HabitTracker.dayKey(date, calendar: calendar)
            let isToday = key == todayKey
            let dayGoal = isToday ? todayGoal : clean(goals[key] ?? goal)
            return WeeklyReportDay(key: key, date: date, day: calendar.component(.day, from: date),
                                   weekday: (calendar.component(.weekday, from: date) + 5) % 7,
                                   value: clean(values[key] ?? 0), goal: dayGoal, isToday: isToday)
        }
        let total = days.reduce(0) { $0 + $1.value }
        var best: WeeklyReportDay?
        for day in days where day.value > 0 && day.value >= (best?.value ?? 0) { best = day }
        return WeeklyReport(days: days, goal: todayGoal, total: total,
                            average: days.isEmpty ? 0 : total / Double(days.count),
                            metDays: days.filter(\.isMet).count, best: best)
    }

    /// What a bar's full height stands for: the larger of the best day and
    /// the goal, so the goal line always fits and a day over goal is taller
    /// than it. Never 0, so a week of nothing does not divide by zero.
    public var scale: Double {
        max(days.map(\.value).max() ?? 0, days.map(\.goal).max() ?? 0, goal, 1)
    }

    /// 0...1, a bar's height.
    public func fraction(_ day: WeeklyReportDay) -> Double {
        min(1, max(0, day.value / scale))
    }

    /// 0...1, where the dashed goal line sits; nil when there is no goal.
    public var goalFraction: Double? {
        goal > 0 ? min(1, goal / scale) : nil
    }

    private static func clean(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

// MARK: - Words

public extension WeeklyReport {
    /// "3 小时 20 分", "45 分", "2 小时": a total of focus minutes.
    static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        guard m >= 60 else { return "\(m) 分" }
        return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
    }

    /// Up to one decimal, without a trailing ".0": "6", "5.5".
    static func figure(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}

// MARK: - Habits

public extension WeeklyReport {
    /// 习惯：每天完成了几成（0 到 100），目标 100，达标就是全勤。
    ///
    /// The share of today's habits done each day. A day before a habit was
    /// added still counts it as not done: the habits do not record when they
    /// were made, and guessing would move last week's bars when one is added.
    static func habits(_ habits: [Habit], today: Date,
                       calendar: Calendar = HabitTracker.calendar) -> WeeklyReport {
        var values: [String: Double] = [:]
        if !habits.isEmpty {
            var counts: [String: Int] = [:]
            for habit in habits { for key in habit.days { counts[key, default: 0] += 1 } }
            for (key, done) in counts { values[key] = Double(done) / Double(habits.count) * 100 }
        }
        return make(values: values, goal: habits.isEmpty ? 0 : 100, today: today, calendar: calendar)
    }

    /// Check-ins across every habit in the seven days.
    static func habitCheckIns(_ habits: [Habit], today: Date,
                              calendar: Calendar = HabitTracker.calendar) -> Int {
        let keys = Set(make(values: [:], goal: 0, today: today, calendar: calendar).days.map(\.key))
        return habits.reduce(0) { $0 + $1.days.intersection(keys).count }
    }
}

// MARK: - Water

public extension WeeklyReport {
    /// 喝水：每天计入的毫升数，过去的日子按当天冻结的目标。
    static func water(_ days: [WaterDay], goal: Int, today: Date,
                      calendar: Calendar = WaterIntake.calendar) -> WeeklyReport {
        var values: [String: Double] = [:]
        var goals: [String: Double] = [:]
        for day in days {
            values[day.key, default: 0] += Double(day.total)
            goals[day.key] = Double(day.goal)
        }
        return make(values: values, goal: Double(goal), goals: goals, today: today, calendar: calendar)
    }

    /// Drinks logged in the seven days. The log keeps single drinks for
    /// `WaterIntake.detailDays` days, which covers the whole window; a day
    /// already folded into a total has no drinks left to count.
    static func waterCups(_ days: [WaterDay], today: Date,
                          calendar: Calendar = WaterIntake.calendar) -> Int {
        let keys = Set(make(values: [:], goal: 0, today: today, calendar: calendar).days.map(\.key))
        return days.filter { keys.contains($0.key) }.reduce(0) { $0 + $1.entries.count }
    }
}
