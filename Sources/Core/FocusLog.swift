import Foundation

/// 专注记录：每天专注了多少分钟，给专注计时面板的“近七天”用。
///
/// The timer itself (`TimerState`) only knows the session in progress, so a
/// finished focus session is noticed from outside, the way the pet's treat
/// is (`VirtualPet.finishedFocus`), and its length is added to the day the
/// session ended on.
///
/// Stored as a list of strings, one per day, `yyyyMMdd|minutes`, the same day
/// keys HabitTracker and WaterIntake write: a session finished in one time
/// zone stays on the day it was finished after travelling. Kept outside the
/// widget's config because the timer is one timer for the whole app, so two
/// timer tiles must not keep two logs.
public enum FocusLog {
    /// 每日目标默认 50 分钟。
    public static let defaultGoal = 50
    public static let goalRange = 5...600
    public static let goalStep = 5
    /// About four months, like 喝水's log.
    public static let keptDays = 120
    /// A day cannot hold more focus than it has minutes.
    public static let maxMinutesPerDay = 24 * 60

    // MARK: Reading and writing

    /// Minutes per day key. Malformed lines are skipped, and a key written
    /// twice (two Macs' logs merged by hand) adds up.
    public static func minutes(_ lines: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for line in lines {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2, HabitTracker.isDayKey(String(parts[0])),
                  let value = Int(parts[1]), value > 0 else { continue }
            result[String(parts[0]), default: 0] += value
        }
        return result.mapValues { min(maxMinutesPerDay, $0) }
    }

    /// The log written back, oldest first, dropping days older than
    /// `keptDays` before `now` and days with nothing.
    public static func lines(_ minutes: [String: Int], now: Date,
                             calendar: Calendar = HabitTracker.calendar) -> [String] {
        let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: now)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        return minutes.keys.sorted().compactMap { key in
            guard key > cutoff, let value = minutes[key], value > 0 else { return nil }
            return "\(key)|\(min(maxMinutesPerDay, value))"
        }
    }

    /// Adds a finished session of `seconds` to the day `endedAt` falls on.
    /// Rounded to the nearest minute; under half a minute adds nothing.
    public static func adding(seconds: TimeInterval, endedAt: Date, to lines: [String],
                              calendar: Calendar = HabitTracker.calendar) -> [String] {
        let added = addedMinutes(seconds: seconds)
        guard added > 0 else { return lines }
        var log = minutes(lines)
        let key = HabitTracker.dayKey(endedAt, calendar: calendar)
        log[key] = min(maxMinutesPerDay, log[key, default: 0] + added)
        return Self.lines(log, now: endedAt, calendar: calendar)
    }

    /// The whole minutes a finished session of `seconds` adds: rounded to
    /// the nearest minute, 0 for under half a minute or nonsense.
    public static func addedMinutes(seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(0, Int((seconds / 60).rounded()))
    }

    // MARK: Lifetime total

    /// Every minute ever focused, for the 小熊猫的竹篮 badges (专注累计 10 / 100
    /// 小时). The daily log forgets after `keptDays`, so the total is kept
    /// beside it under its own key and only ever grows.
    ///
    /// A total never written (the log predates it) starts from what the log
    /// still holds, and a total somehow below the log (defaults restored
    /// from another Mac) is raised to it: never fewer hours than the days
    /// on record add up to.
    public static func lifetimeMinutes(stored: Int, lines: [String]) -> Int {
        max(max(0, stored), minutes(lines).values.reduce(0, +))
    }

    /// The total after a finished session of `seconds`, with `lines` the log
    /// as it was before the session was added.
    public static func addingTotal(seconds: TimeInterval, stored: Int, lines: [String]) -> Int {
        lifetimeMinutes(stored: stored, lines: lines) + addedMinutes(seconds: seconds)
    }

    /// 夜猫子徽章：一轮专注在晚上 23 点到凌晨 3 点 59 分之间结束。
    public static func isLateNight(_ endedAt: Date, calendar: Calendar = HabitTracker.calendar) -> Bool {
        let hour = calendar.component(.hour, from: endedAt)
        return hour >= 23 || hour < 4
    }

    /// The length of the focus session that `VirtualPet.finishedFocus` says
    /// has just ended: the pinned duration, or the focus length when none
    /// was pinned.
    public static func sessionSeconds(_ timer: TimerState) -> TimeInterval {
        timer.duration ?? Double(timer.work * 60)
    }

    public static func clampGoal(_ value: Int) -> Int {
        min(goalRange.upperBound, max(goalRange.lowerBound, value))
    }

    /// A stored goal of 0 (never set) reads as the default.
    public static func goal(stored: Int) -> Int {
        stored > 0 ? clampGoal(stored) : defaultGoal
    }

    // MARK: Report

    public static func report(_ lines: [String], goal: Int, today: Date,
                              calendar: Calendar = HabitTracker.calendar) -> WeeklyReport {
        WeeklyReport.make(values: minutes(lines).mapValues(Double.init), goal: Double(goal),
                          today: today, calendar: calendar)
    }
}
