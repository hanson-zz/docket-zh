import Foundation

/// 闹钟管“今天某个时刻”：一张卡片放多个闹钟，下一个最醒目。
///
/// 存在小组件自己的配置里：
/// - `alarms`：每个闹钟一行 `id|HH:mm|1|名字`（1 开、0 关）。名字放最后，里面有“|”也不会读错。
/// - `handled`：今天已经处理过（关掉或稍后）的响铃，`id@yyyyMMdd`，只留今天的。
/// - `snoozes`：稍后再响的，`id|epoch`。
///
/// 旧卡片只有一个闹钟，存在 `time`、`name`、`enabled` 三个键里。没有 `alarms`
/// 这个键时按旧键读成一个闹钟；第一次在新面板或卡片上改动时写成列表，旧键不再读。
public struct AlarmItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// 午夜后的分钟数。
    public var minutes: Int
    public var name: String
    public var enabled: Bool

    public init(id: String, minutes: Int, name: String, enabled: Bool = true) {
        self.id = id
        self.minutes = min(23 * 60 + 59, max(0, minutes))
        self.name = name
        self.enabled = enabled
    }

    public var time: String { PostureSchedule.clock(minutes) }

    /// 没起名字时叫“闹钟”。
    public var title: String { name.isEmpty ? tr("闹钟") : name }

    var line: String { "\(id)|\(time)|\(enabled ? "1" : "0")|\(name)" }

    init?(line: String) {
        let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, !parts[0].isEmpty, let minutes = PostureSchedule.minutes(parts[1]) else { return nil }
        self.init(id: parts[0], minutes: minutes, name: parts.count > 3 ? parts[3] : "", enabled: parts[2] != "0")
    }
}

public enum AlarmBook {
    public static let alarmsKey = "alarms"
    public static let handledKey = "handled"
    public static let snoozesKey = "snoozes"
    public static let soundKey = "sound"
    /// 稍后再响隔几分钟。
    public static let snoozeMinutes = 10
    /// 一次响铃最多响多久，没人管就自己停（秒）。
    public static let ringWindow: TimeInterval = 10 * 60
    /// 提示音只在前两分钟里每 4 秒响一下，之后卡片仍显示“正在响”，不再出声。
    public static let chimeSeconds = 120
    public static let chimeEvery = 4
    /// 一张卡片最多放几个闹钟。
    public static let maxAlarms = 12

    // MARK: 读写

    /// 卡片上的闹钟，按时间排好。旧卡片按 `time`、`name`、`enabled` 读成一个。
    public static func items(_ config: WidgetConfig) -> [AlarmItem] {
        if config[alarmsKey] != nil {
            return sorted(config.strings(alarmsKey).compactMap { AlarmItem(line: $0) })
        }
        let minutes = PostureSchedule.minutes(config.string("time", default: "14:30")) ?? 14 * 60 + 30
        return [AlarmItem(id: "a", minutes: minutes, name: config.string("name"),
                          enabled: config.bool("enabled", default: true))]
    }

    /// 是否还是旧的单个闹钟（设置里的“时间”“名称”只对它有意义）。
    public static func isLegacy(_ config: WidgetConfig) -> Bool { config[alarmsKey] == nil }

    public static func sorted(_ items: [AlarmItem]) -> [AlarmItem] {
        items.sorted { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
    }

    /// 把列表写回配置；旧的三个键清掉，免得两份对不上。
    public static func store(_ items: [AlarmItem], in config: inout WidgetConfig) {
        config.set(alarmsKey, .list(sorted(items).prefix(maxAlarms).map { .string($0.line) }))
        config.set("time", nil)
        config.set("name", nil)
        config.set("enabled", nil)
    }

    /// 新闹钟的 id：不和已有的重复就行。
    public static func newID(existing: [AlarmItem]) -> String {
        let used = Set(existing.map(\.id))
        var n = existing.count + 1
        while used.contains("a\(n)") { n += 1 }
        return "a\(n)"
    }

    // MARK: 下一个

    /// 今天的这个时刻；已经过了就是明天的。
    public static func nextOccurrence(_ item: AlarmItem, after now: Date, calendar: Calendar = .current) -> Date {
        let today = at(item.minutes, on: now, calendar: calendar)
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 什么时候响：开着的闹钟的下一次，稍后再响的算稍后的时刻。
    public static func nextRing(_ item: AlarmItem, config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> Date {
        let regular = nextOccurrence(item, after: now, calendar: calendar)
        if let snooze = snoozes(config)[item.id], snooze > now, snooze < regular { return snooze }
        return regular
    }

    /// 排好的接下来要响的：开着的按下一次响铃的先后。卡片第一行是第一个。
    public static func upcoming(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> [(item: AlarmItem, at: Date)] {
        items(config).filter(\.enabled)
            .map { (item: $0, at: nextRing($0, config: config, now: now, calendar: calendar)) }
            .sorted { ($0.at, $0.item.id) < ($1.at, $1.item.id) }
    }

    /// 卡片上最醒目的那个：下一个开着的；全关了时是时间上最近的一个（显示已关闭）。
    public static func headline(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> AlarmItem? {
        if let first = upcoming(config, now: now, calendar: calendar).first { return first.item }
        return items(config).min {
            (nextOccurrence($0, after: now, calendar: calendar), $0.id)
                < (nextOccurrence($1, after: now, calendar: calendar), $1.id)
        }
    }

    // MARK: 响铃

    /// 正在响的闹钟和它从什么时候开始响。到点后 10 分钟内、今天还没处理过；
    /// 稍后再响的到了稍后的时刻再响一次。
    public static func ringing(_ config: WidgetConfig, now: Date,
                               calendar: Calendar = .current) -> (item: AlarmItem, since: Date)? {
        let handled = Set(handledToday(config, now: now, calendar: calendar))
        let snoozed = snoozes(config)
        var best: (item: AlarmItem, since: Date)?
        for item in items(config) where item.enabled {
            var start: Date?
            let today = at(item.minutes, on: now, calendar: calendar)
            if today <= now, now.timeIntervalSince(today) < ringWindow,
               !handled.contains(handleKey(item.id, day: now, calendar: calendar)) {
                start = today
            }
            if let snooze = snoozed[item.id], snooze <= now, now.timeIntervalSince(snooze) < ringWindow {
                start = max(start ?? snooze, snooze)
            }
            if let start, best == nil || start > best!.since { best = (item, start) }
        }
        return best
    }

    /// 关掉：今天这次记成已处理，稍后再响的也一并取消。
    public static func dismiss(_ id: String, in config: inout WidgetConfig, now: Date,
                               calendar: Calendar = .current) {
        markHandled(id, in: &config, now: now, calendar: calendar)
        var snoozed = snoozes(config)
        snoozed[id] = nil
        storeSnoozes(snoozed, in: &config)
    }

    /// 稍后 10 分钟：这次记成已处理，10 分钟后再响。
    public static func snooze(_ id: String, in config: inout WidgetConfig, now: Date,
                              calendar: Calendar = .current) {
        markHandled(id, in: &config, now: now, calendar: calendar)
        var snoozed = snoozes(config)
        snoozed[id] = now.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        storeSnoozes(snoozed, in: &config)
    }

    /// 开或关某个闹钟。关掉时它的稍后再响也取消。
    public static func setEnabled(_ id: String, _ on: Bool, in config: inout WidgetConfig) {
        var list = items(config)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].enabled = on
        store(list, in: &config)
        if !on {
            var snoozed = snoozes(config)
            snoozed[id] = nil
            storeSnoozes(snoozed, in: &config)
        }
    }

    /// 响铃开始后的第几段：每 4 秒一段，段数一变就响一下；两分钟后是 nil，不再出声。
    public static func chimeBucket(since: TimeInterval) -> Int? {
        guard since >= 0, since <= TimeInterval(chimeSeconds) else { return nil }
        return Int(since) / chimeEvery
    }

    // MARK: 文字

    /// “14:30”，24 小时制。稍后再响的时刻不在整点上，也照样写出来。
    public static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return PostureSchedule.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// “还有 2 小时”“还有 1 小时 20 分”“还有 35 分钟”“不到 1 分钟”。
    public static func untilText(_ date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return tr("不到 1 分钟") }
        if minutes < 60 { return tr("还有 \(minutes) 分钟") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("还有 \(h) 小时") : tr("还有 \(h) 小时 \(m) 分")
    }

    /// 卡片第三行：“接着 18:00 取快递 · 21:30 吃药”，排在第一个后面的开着的闹钟。
    public static func laterLine(_ config: WidgetConfig, now: Date, limit: Int = 3,
                                 calendar: Calendar = .current) -> String? {
        let rest = upcoming(config, now: now, calendar: calendar).dropFirst().prefix(limit)
        guard !rest.isEmpty else { return nil }
        let joined = rest.map { "\($0.item.time) \($0.item.title)" }.joined(separator: " · ")
        return tr("接着 \(joined)")
    }

    // MARK: 内部

    static func at(_ minutes: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    static func handleKey(_ id: String, day: Date, calendar: Calendar) -> String {
        "\(id)@\(dayKey(day, calendar: calendar))"
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func handledToday(_ config: WidgetConfig, now: Date, calendar: Calendar) -> [String] {
        let suffix = "@\(dayKey(now, calendar: calendar))"
        return config.strings(handledKey).filter { $0.hasSuffix(suffix) }
    }

    static func markHandled(_ id: String, in config: inout WidgetConfig, now: Date, calendar: Calendar) {
        var today = handledToday(config, now: now, calendar: calendar)
        let key = handleKey(id, day: now, calendar: calendar)
        if !today.contains(key) { today.append(key) }
        config.set(handledKey, .list(today.map { .string($0) }))
    }

    public static func snoozes(_ config: WidgetConfig) -> [String: Date] {
        var result: [String: Date] = [:]
        for line in config.strings(snoozesKey) {
            let parts = line.split(separator: "|")
            guard parts.count == 2, let epoch = Double(parts[1]) else { continue }
            result[String(parts[0])] = Date(timeIntervalSince1970: epoch)
        }
        return result
    }

    static func storeSnoozes(_ snoozes: [String: Date], in config: inout WidgetConfig) {
        let lines = snoozes.keys.sorted().compactMap { id in
            snoozes[id].map { "\(id)|\(Int($0.timeIntervalSince1970))" }
        }
        config.set(snoozesKey, .list(lines.map { .string($0) }))
    }
}
