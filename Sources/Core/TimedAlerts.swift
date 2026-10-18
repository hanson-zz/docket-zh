import Foundation

// 到点提醒的后台调度：倒计时、闹钟、快速待办和提醒事项不再靠扩展栏上的卡片
// 每秒刷新才发现到点，而是由应用里的一个计时器从启动起一直看着，扩展栏隐藏、
// 卡片在别的布局或文件夹里也照样到点、照样弹出卡片。
//
// 这里只放纯逻辑（从布局里找出所有小组件、这一秒里谁刚到点、还在不在响、
// 要不要为了准时挡住系统的省电节流），计时器和弹出在 Services/TimedAlertDriver.swift。

// MARK: - 布局里的小组件

/// 布局里的小组件可能放在文件夹里，也可能在当前没用的布局里。
public enum DockItemTree {
    /// 一串项目里所有的小组件，文件夹里的也算，按出现的先后。
    public static func widgets(in items: [DockItem]) -> [WidgetInstance] {
        items.flatMap { item -> [WidgetInstance] in
            switch item {
            case .widget(let widget): [widget]
            case .group(let group): widgets(in: group.items)
            default: []
            }
        }
    }

    /// 找一个小组件，文件夹里的也找。
    public static func widget(_ id: UUID, in items: [DockItem]) -> WidgetInstance? {
        for item in items {
            switch item {
            case .widget(let widget) where widget.id == id: return widget
            case .group(let group): if let found = widget(id, in: group.items) { return found }
            default: continue
            }
        }
        return nil
    }

    /// 把同一个 id 的小组件换成新的一份，文件夹里的也换。没找到时为 nil。
    public static func replacing(_ instance: WidgetInstance, in items: [DockItem]) -> [DockItem]? {
        var result = items
        for index in result.indices {
            switch result[index] {
            case .widget(let widget) where widget.id == instance.id:
                result[index] = .widget(instance)
                return result
            case .group(var group):
                if let inner = replacing(instance, in: group.items) {
                    group.items = inner
                    result[index] = .group(group)
                    return result
                }
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - 这一秒里谁到点了

public enum TimedAlertScan {
    /// 倒计时在 (`after`, `now`] 里到点时是它的结束时刻。两次检查隔得太久（合盖
    /// 睡眠）不算，和提醒音效一样不补弹。
    public static func countdownRang(_ config: WidgetConfig, after: Date, upTo now: Date) -> Date? {
        guard fresh(after: after, now: now), config["paused"] == nil, config["deadline"] != nil else { return nil }
        let deadline = Date(timeIntervalSince1970: config.double("deadline"))
        return deadline > after && deadline <= now ? deadline : nil
    }

    /// 倒计时还停在“时间到”、而且还是 `due` 那一次（没人点停、没再开一轮）。
    public static func countdownStillRinging(_ config: WidgetConfig, due: Date, now: Date) -> Bool {
        guard case .ringing = CountdownRun.phase(config, now: now) else { return false }
        return abs(config.double("deadline") - due.timeIntervalSince1970) < 1
    }

    /// 闹钟在 (`after`, `now`] 里开始响（到点或稍后再响到了）时是它和开始的时刻。
    public static func alarmRang(_ config: WidgetConfig, after: Date, upTo now: Date,
                                 calendar: Calendar = .current) -> (item: AlarmItem, since: Date)? {
        guard fresh(after: after, now: now),
              let ringing = AlarmBook.ringing(config, now: now, calendar: calendar),
              ringing.since > after, ringing.since <= now else { return nil }
        return ringing
    }

    /// 这个闹钟还在响、而且还是从 `since` 开始的那一次（没关、没稍后、没关掉开关）。
    public static func alarmStillRinging(_ config: WidgetConfig, id: String, since: Date, now: Date,
                                         calendar: Calendar = .current) -> Bool {
        guard let ringing = AlarmBook.ringing(config, now: now, calendar: calendar) else { return false }
        return ringing.item.id == id && abs(ringing.since.timeIntervalSince(since)) < 1
    }

    /// 这次响铃是不是稍后再响的那一次。
    public static func alarmIsSnoozed(_ config: WidgetConfig, id: String, since: Date) -> Bool {
        guard let snooze = AlarmBook.snoozes(config)[id] else { return false }
        return abs(snooze.timeIntervalSince(since)) < 1
    }

    /// 倒计时到点后第几声（每 4 秒一声，30 秒后不再响），没在响时为 nil。
    public static func countdownChime(_ config: WidgetConfig, now: Date) -> (key: String, bucket: Int)? {
        guard case .ringing(let since) = CountdownRun.phase(config, now: now),
              let bucket = CountdownRun.chimeBucket(since: since) else { return nil }
        return ("\(Int(config.double("deadline")))", bucket)
    }

    /// 闹钟响铃后第几声（每 4 秒一声，两分钟后不再出声），没在响时为 nil。
    public static func alarmChime(_ config: WidgetConfig, now: Date,
                                  calendar: Calendar = .current) -> (key: String, bucket: Int)? {
        guard let ringing = AlarmBook.ringing(config, now: now, calendar: calendar),
              let bucket = AlarmBook.chimeBucket(since: now.timeIntervalSince(ringing.since)) else { return nil }
        return ("\(ringing.item.id)@\(Int(ringing.since.timeIntervalSince1970))", bucket)
    }

    /// 倒计时「再来一次」：同样的时长从现在重新计。
    public static func restartingCountdown(_ config: inout WidgetConfig, duration: TimeInterval, now: Date) {
        let length = duration > 0 ? duration : CountdownRun.duration(config)
        config.set("duration", .number(length))
        config.set("paused", nil)
        config.set("deadline", .number(now.timeIntervalSince1970 + length))
    }

    /// 倒计时「关闭」：回到没开始，三个预设回来（和点卡片停一样）。
    public static func stoppingCountdown(_ config: inout WidgetConfig) {
        config.set("paused", nil)
        config.set("deadline", nil)
    }

    static func fresh(after: Date, now: Date) -> Bool {
        let gap = now.timeIntervalSince(after)
        return gap > 0 && gap <= ReminderSoundDecision.maxGap
    }
}

// MARK: - 准时

/// 码头是只有菜单栏图标的应用，扩展栏隐藏时系统可能把它的计时器推迟好几秒
/// （App Nap）。快到点和正在响的时候请系统别推迟，其余时间照常省电。
public enum TimedAlertWake {
    /// 提前多久开始要准时。
    public static let lead: TimeInterval = 90

    /// 下一个要到点的时刻在 `lead` 秒以内，或者有东西正在响，就要准时。
    public static func needsPrecision(next: Date?, ringing: Bool, now: Date) -> Bool {
        if ringing { return true }
        guard let next else { return false }
        let left = next.timeIntervalSince(now)
        return left >= -1 && left <= lead
    }

    /// 几个候选里最早的、还没过的那个。
    public static func soonest(_ dates: [Date], after now: Date) -> Date? {
        dates.filter { $0 > now }.min()
    }

    /// 倒计时下一个到点的时刻：正在跑时是结束时刻，暂停、没开始、已经到点都没有。
    public static func countdownNext(_ config: WidgetConfig, now: Date) -> Date? {
        guard case .running = CountdownRun.phase(config, now: now) else { return nil }
        return Date(timeIntervalSince1970: config.double("deadline"))
    }
}

// MARK: - 提醒事项读哪些列表

public enum ReminderScanScope {
    /// 扩展栏上（任一布局里）提醒事项卡片各自筛选的列表名。有一张没筛（空）就是
    /// 全部列表，为 nil；一张卡片都没有时是空集合，什么都不读。
    public static func lists(filters: [String]) -> Set<String>? {
        let trimmed = filters.map { $0.trimmingCharacters(in: .whitespaces) }
        if trimmed.contains(where: \.isEmpty) { return nil }
        return Set(trimmed)
    }
}

// MARK: - 日程悬停详情

/// 日历时间线和一周日程悬停时浮出来的那张小卡片上的一条日程。
public struct EventPeekItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// 日历的名字。
    public var calendar: String
    /// 日历的颜色 `#RRGGBB`，空时用小组件的强调色。
    public var colorHex: String
    /// 地点；只是一条会议链接时为空。
    public var location: String
    public var link: MeetingLink?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendar: String = "", colorHex: String = "", location: String = "", link: MeetingLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.colorHex = colorHex
        self.location = location
        self.link = link
    }
}

/// 浮出卡片的内容：可选的一行标题（一周日程写那天），下面几条日程。
public struct EventPeek: Equatable, Sendable {
    public var heading: String
    public var subheading: String
    public var items: [EventPeekItem]
    /// 放不下的还有几条。
    public var more: Int

    public init(heading: String = "", subheading: String = "", items: [EventPeekItem], more: Int = 0) {
        self.heading = heading
        self.subheading = subheading
        self.items = items
        self.more = more
    }

    /// 一周日程一天最多列几条，其余写“还有 N 个”。
    public static let dayLimit = 5

    /// 一周日程里一天的浮出内容。
    public static func day(heading: String, subheading: String, entries: [EventPeekItem]) -> EventPeek {
        let shown = Array(entries.prefix(dayLimit))
        return EventPeek(heading: heading, subheading: subheading, items: shown, more: entries.count - shown.count)
    }
}

public enum EventPeekText {
    /// 时间那行：“14:00-15:00 · 还有 25 分钟”，全天的写“全天”，开完的写“已结束”。
    public static func timeLine(_ item: EventPeekItem, now: Date, calendar: Calendar = .current) -> String {
        if item.isAllDay { return tr("全天") }
        let range = CalendarDay.range(item.start, item.end, calendar: calendar)
        guard calendar.isDate(item.start, inSameDayAs: now) else { return range }
        if item.end <= now { return "\(range) · \(tr("已结束"))" }
        return "\(range) · \(CalendarDay.countdown(start: item.start, end: item.end, now: now))"
    }

    /// 地点那行：有地点写地点，没有时写会议来源（腾讯会议、飞书会议），都没有时为空。
    public static func placeLine(_ item: EventPeekItem) -> String {
        if !item.location.isEmpty { return item.location }
        return item.link?.provider.title ?? ""
    }

    /// 有会议链接、还没开完的才给「加入」按钮。
    public static func showsJoin(_ item: EventPeekItem, now: Date) -> Bool {
        item.link != nil && !item.isAllDay && item.end > now
    }

    /// “还有 2 个”。
    public static func moreLine(_ count: Int) -> String {
        tr("还有 \(count) 个")
    }
}

/// 浮出卡片摆在哪：卡片朝扩展栏外侧那一边，横向对着指的那一块。
public enum EventPeekLayout {
    /// 卡片宽。
    public static let width: CGFloat = 260
    /// 和卡片的距离。
    public static let gap: CGFloat = 8

    /// 指向的那一点（屏幕坐标，y 向上）：底部扩展栏是卡片上沿、横向在指的那一块
    /// 中间；顶部是下沿；左右两边是外侧的边、纵向居中。
    public static func anchor(edge: DockPosition, tile: CGRect, focusX: CGFloat?) -> CGPoint {
        let x = min(max(focusX ?? tile.midX, tile.minX), tile.maxX)
        switch edge {
        case .bottom: return CGPoint(x: x, y: tile.maxY)
        case .top: return CGPoint(x: x, y: tile.minY)
        case .left: return CGPoint(x: tile.maxX, y: tile.midY)
        case .right: return CGPoint(x: tile.minX, y: tile.midY)
        }
    }

    /// 卡片的位置，夹在屏幕可见范围里（左右上下各留 4pt）。
    public static func frame(edge: DockPosition, tile: CGRect, focusX: CGFloat?, size: CGSize,
                             visible: CGRect) -> CGRect {
        let origin = Geometry.popupOrigin(edge: edge, anchor: anchor(edge: edge, tile: tile, focusX: focusX),
                                          size: size, gap: gap)
        let x = min(max(origin.x, visible.minX + 4), max(visible.minX + 4, visible.maxX - size.width - 4))
        let y = min(max(origin.y, visible.minY + 4), max(visible.minY + 4, visible.maxY - size.height - 4))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
