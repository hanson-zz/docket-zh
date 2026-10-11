import Foundation

/// The arithmetic behind the stand-up reminder, kept free of any UI so it can
/// be tested.
///
/// The widget stores the interval (`duration`), the active hours (`start` and
/// `end`, as "HH:mm"), when the last break was logged (`lastBreak`), and a
/// count of breaks for one day (`breakDay` as "yyyy-MM-dd" and `breakCount`).
public struct PostureSchedule: Equatable, Sendable {
    /// Seconds between reminders, never below five minutes.
    public var interval: TimeInterval
    /// Minutes after midnight.
    public var start: Int
    public var end: Int

    public static let minimumInterval: TimeInterval = 300

    public init(interval: TimeInterval, start: Int, end: Int) {
        self.interval = max(Self.minimumInterval, interval)
        self.start = start
        self.end = end
    }

    public init(config: WidgetConfig) {
        self.init(interval: config.double("duration", default: 1800),
                  start: Self.minutes(config.string("start", default: "09:00")) ?? 9 * 60,
                  end: Self.minutes(config.string("end", default: "18:00")) ?? 18 * 60)
    }

    /// "9:30" or "09:30" to 570. Nil for anything else.
    public static func minutes(_ text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespaces)
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Whether a moment falls inside the active hours. A window whose end is
    /// before its start runs overnight; one whose ends meet is all day.
    public func isActive(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return true }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }

    /// When the current stretch of sitting started: the last break, or the
    /// start of today's active hours if no break has been logged since.
    public func anchor(lastBreak: Date?, now: Date, calendar: Calendar = .current) -> Date {
        let windowStart = currentWindowStart(now, calendar: calendar)
        guard let lastBreak, lastBreak > windowStart else { return windowStart }
        return lastBreak
    }

    /// When the next break is due. May be in the past, which means overdue.
    public func due(lastBreak: Date?, now: Date, calendar: Calendar = .current) -> Date {
        anchor(lastBreak: lastBreak, now: now, calendar: calendar).addingTimeInterval(interval)
    }

    /// The next moment a notification should go out, strictly after `now`.
    ///
    /// An ignored reminder repeats every interval rather than going quiet,
    /// and a reminder that would land outside the active hours waits for the
    /// next window instead.
    public func nextReminder(lastBreak: Date?, now: Date, calendar: Calendar = .current) -> Date {
        var candidate = due(lastBreak: lastBreak, now: now, calendar: calendar)
        if candidate <= now {
            let missed = (now.timeIntervalSince(candidate) / interval).rounded(.down) + 1
            candidate = candidate.addingTimeInterval(missed * interval)
        }
        if isActive(candidate, calendar: calendar) { return candidate }
        // Outside the window: first reminder of the next one.
        let next = nextWindowStart(after: candidate, calendar: calendar)
        return next.addingTimeInterval(interval)
    }

    /// Seconds left until a break is due, floored at zero.
    public func remaining(lastBreak: Date?, now: Date, calendar: Calendar = .current) -> TimeInterval {
        max(0, due(lastBreak: lastBreak, now: now, calendar: calendar).timeIntervalSince(now))
    }

    /// 0...1 through the current interval, for the tile's ring.
    public func progress(lastBreak: Date?, now: Date, calendar: Calendar = .current) -> Double {
        let left = remaining(lastBreak: lastBreak, now: now, calendar: calendar)
        return min(1, max(0, 1 - left / interval))
    }

    // MARK: Windows

    private func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The start of the active window `date` is in, or of the most recent one.
    func currentWindowStart(_ date: Date, calendar: Calendar) -> Date {
        let day = startOfDay(date, calendar: calendar)
        let todayStart = day.addingTimeInterval(TimeInterval(start * 60))
        if date >= todayStart { return todayStart }
        return calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
    }

    func nextWindowStart(after date: Date, calendar: Calendar) -> Date {
        let day = startOfDay(date, calendar: calendar)
        let todayStart = day.addingTimeInterval(TimeInterval(start * 60))
        if todayStart > date { return todayStart }
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
    }
}

/// How many breaks were taken today. One day is kept, not a log.
public enum PostureTally {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Today's count: whatever is stored, if it was stored today.
    public static func today(storedDay: String, count: Int, now: Date,
                             calendar: Calendar = .current) -> Int {
        storedDay == dayKey(now, calendar: calendar) ? max(0, count) : 0
    }

    /// The day and count after logging a break now.
    public static func logging(storedDay: String, count: Int, now: Date,
                               calendar: Calendar = .current) -> (day: String, count: Int) {
        (dayKey(now, calendar: calendar),
         today(storedDay: storedDay, count: count, now: now, calendar: calendar) + 1)
    }
}
