import Foundation

// 程序坞「日历」动态图标的纯逻辑：今天哪几场算数、下一场是哪场、液位多高、什么颜色、
// 胶囊里写什么、什么时候转一圈、多久重画一次。不碰 EventKit 和 SwiftUI，全部能在测试里跑。

/// 今天的一场日程，只带图标和悬停列表用得到的几样：不带备注、地点、参与人。
public struct LiveCalendarEvent: Identifiable, Equatable, Sendable {
    /// 事件 id 加这一次的开始时刻：重复日程的每一次各算一场。
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// 日历颜色 `#RRGGBB`，读不到时是空串。
    public var colorHex: String
    /// 自己已拒绝，或日程已取消：不算数。
    public var declined: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                colorHex: String = "", declined: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.declined = declined
    }
}

/// 液位和颜色的几个阶段，按离开始还有多久分。
public enum LiveCalendarPhase: Equatable, Sendable {
    /// 还没进提前量：液面满着，胶囊写开始时刻。
    case waiting
    /// 进了提前量，剩余多于 5 分钟：冷色，倒计时。
    case counting
    /// 剩 5 分钟以内：暖橙，倒计时。
    case warm
    /// 不到 1 分钟：暖橙，「即将开始」。
    case imminent
    /// 已经开始，还在停留的那一分钟里：暖橙，液面见底，「进行中」。
    case inProgress

    /// 暖橙阶段。
    public var isWarm: Bool {
        switch self {
        case .warm, .imminent, .inProgress: return true
        case .waiting, .counting: return false
        }
    }
}

/// 胶囊里的字，长短三档：放得下就用长的，放不下换短的，字号不缩。
public struct LiveCalendarLabel: Equatable, Sendable {
    public var full: String
    public var compact: String
    public var minimal: String

    public init(full: String, compact: String, minimal: String) {
        self.full = full
        self.compact = compact
        self.minimal = minimal
    }

    /// 从长到短，给 ViewThatFits 依次试。
    public var candidates: [String] {
        var out: [String] = []
        for text in [full, compact, minimal] where !out.contains(text) { out.append(text) }
        return out
    }
}

/// 换场时转不转：同一场不转，第一次出现和变成没日程都不转，两次转圈至少隔 `minimumGap`，
/// 日程库一阵连着变（iCloud 同步）时只转第一下，后面直接换。
public struct LiveCalendarFlip: Equatable, Sendable {
    public static let minimumGap: TimeInterval = 10

    public private(set) var shownID: String?
    public private(set) var lastTurn: Date?

    public init() {}

    /// 记下新的下一场，返回这次该不该整圈旋转。
    public mutating func update(to id: String?, at now: Date) -> Bool {
        defer { shownID = id }
        guard let previous = shownID, let id, previous != id else { return false }
        if let lastTurn, now.timeIntervalSince(lastTurn) < Self.minimumGap { return false }
        lastTurn = now
        return true
    }
}

public enum LiveCalendar {
    /// 系统日历 App。
    public static let bundleID = "com.apple.iCal"
    /// 提前量（分钟）的设置键，默认 30。
    public static let leadKey = "liveIcons.calendarLead"
    public static let defaultLeadMinutes = 30
    public static let leadChoices = [10, 15, 30, 45, 60]
    /// 剩这么多秒以内变暖橙。
    public static let warmWindow: TimeInterval = 5 * 60
    /// 剩这么多秒以内写「即将开始」。
    public static let imminentWindow: TimeInterval = 60
    /// 开始后「进行中」停留多久再换下一场。
    public static let inProgressHold: TimeInterval = 60
    /// 悬停列表最多几条。
    public static let agendaLimit = 4
    /// 整圈旋转的时长和换内容的时刻（转到 180° 倒立时）。
    public static let turnDuration: TimeInterval = 0.9
    public static let emphasisDuration: TimeInterval = 0.14

    /// 设置里存的提前量：没存过或不在可选项里时用默认。
    public static func leadMinutes(stored: Int?) -> Int {
        guard let stored, leadChoices.contains(stored) else { return defaultLeadMinutes }
        return stored
    }

    /// 今天算数的日程：开始在今天、不是全天、没拒绝没取消，按开始时刻排，同时开始按标题再按 id。
    public static func today(_ events: [LiveCalendarEvent], now: Date, calendar: Calendar) -> [LiveCalendarEvent] {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events
            .filter { !$0.isAllDay && !$0.declined && $0.start >= dayStart && $0.start < dayEnd }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if a.title != b.title { return a.title < b.title }
                return a.id < b.id
            }
    }

    /// 图标正在倒数的那一场：今天第一场还没开始、或开始不到 `inProgressHold` 的。没有就是 nil，
    /// 图标保持系统原样。
    public static func target(_ events: [LiveCalendarEvent], now: Date, calendar: Calendar) -> LiveCalendarEvent? {
        today(events, now: now, calendar: calendar).first { now < $0.start.addingTimeInterval(inProgressHold) }
    }

    /// 悬停列表：今天还没结束的（含正在开的），最多 `limit` 条。
    public static func agenda(_ events: [LiveCalendarEvent], now: Date, calendar: Calendar,
                              limit: Int = agendaLimit) -> [LiveCalendarEvent] {
        Array(today(events, now: now, calendar: calendar).filter { $0.end > now || $0.start > now }.prefix(max(0, limit)))
    }

    /// 阶段，按剩余秒数和提前量（秒）分。
    public static func phase(start: Date, now: Date, lead: TimeInterval) -> LiveCalendarPhase {
        let r = start.timeIntervalSince(now)
        if r <= 0 { return .inProgress }
        if r <= imminentWindow { return .imminent }
        if r <= warmWindow { return .warm }
        if r <= max(lead, warmWindow) { return .counting }
        return .waiting
    }

    /// 液面高度比例 0...1：剩余 / 提前量，进提前量之前是满的，开始后见底。
    public static func level(start: Date, now: Date, lead: TimeInterval) -> Double {
        let r = start.timeIntervalSince(now)
        guard r > 0, lead > 0, r.isFinite else { return 0 }
        return min(1, r / lead)
    }

    /// 剩几分钟（向上取整）：24 分 1 秒显示 25 分，正好 5 分显示 5 分。
    public static func minutesLeft(start: Date, now: Date) -> Int {
        let r = start.timeIntervalSince(now)
        guard r > 0, r.isFinite else { return 0 }
        return Int((r / 60).rounded(.up))
    }

    /// 24 小时制「9:05」「14:00」。
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 胶囊里的字。
    public static func label(start: Date, now: Date, lead: TimeInterval, calendar: Calendar) -> LiveCalendarLabel {
        switch phase(start: start, now: now, lead: lead) {
        case .waiting:
            let time = clock(start, calendar: calendar)
            return LiveCalendarLabel(full: time, compact: time, minimal: time)
        case .counting, .warm:
            let m = minutesLeft(start: start, now: now)
            return LiveCalendarLabel(full: tr("\(m) 分"), compact: tr("\(m)分"), minimal: "\(m)")
        case .imminent:
            return LiveCalendarLabel(full: tr("即将开始"), compact: tr("即将"), minimal: tr("即将"))
        case .inProgress:
            return LiveCalendarLabel(full: tr("进行中"), compact: tr("现在"), minimal: tr("现在"))
        }
    }

    /// 页眉的星期：「周五」，英文界面「FRI」。周日是 weekday 1。
    public static func weekday(_ date: Date, calendar: Calendar, english: Bool) -> String {
        let zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let en = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        let i = min(6, max(0, calendar.component(.weekday, from: date) - 1))
        return english ? en[i] : zh[i]
    }

    /// 几号。
    public static func dayNumber(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.day, from: date))"
    }

    /// 离下一次该重画还有几秒：倒计时的分钟数变、阶段变、液面降 1 像素，取最早的；
    /// 不超过 60 秒（日期翻页、日程变化也要跟上），不少于 1 秒。
    /// 低电量模式只在分钟数和阶段变时重画，不追 1 像素。
    public static func nextTick(start: Date?, now: Date, lead: TimeInterval, pixelHeight: Double,
                                lowPower: Bool) -> TimeInterval {
        let ceiling: TimeInterval = 60
        guard let start else { return ceiling }
        let r = start.timeIntervalSince(now)
        guard r.isFinite else { return ceiling }
        var delay = ceiling
        if r <= 0 {
            // 「进行中」停留到期就换下一场。
            delay = min(delay, r + inProgressHold)
        } else {
            // 分钟数在 r 落到下一个 60 的整数倍时变（阶段边界 60 秒、5 分钟、提前量也都在整分上）。
            let frac = r.truncatingRemainder(dividingBy: 60)
            delay = min(delay, frac > 0.001 ? frac : 60)
            if r > lead {
                delay = min(delay, r - lead)
            } else if !lowPower, pixelHeight > 0, lead > 0 {
                delay = min(delay, lead / pixelHeight)
            }
        }
        // 稍微越过边界一点，醒来时读数已经变了。
        return min(ceiling, max(1, delay + 0.05))
    }
}
