import Foundation

/// 闹钟哪几天响。
public enum AlarmRepeat: Hashable, Sendable {
    /// 一周里的这几天，1 是周一，7 是周日；七天都在就是每天。空的当每天。
    case weekdays(Set<Int>)
    /// 只在这一天响一次，`yyyyMMdd`。
    case once(String)

    public static let daily = AlarmRepeat.weekdays(Set(1...7))
    public static let workdays = AlarmRepeat.weekdays([1, 2, 3, 4, 5])
    public static let weekend = AlarmRepeat.weekdays([6, 7])

    /// 一周里哪几天（只响一次的是空的）。
    public var days: Set<Int> {
        if case .weekdays(let days) = self { return days.isEmpty ? Set(1...7) : days }
        return []
    }

    public var isOnce: Bool {
        if case .once = self { return true }
        return false
    }

    public var isDaily: Bool { days.count == 7 }

    /// 存进 `repeats` 的写法：“12345”或“once:20261020”。
    var code: String {
        switch self {
        case .weekdays: days.sorted().map { String($0) }.joined()
        case .once(let day): "once:\(day)"
        }
    }

    init(code: String) {
        if code.hasPrefix("once:") {
            let day = String(code.dropFirst(5))
            if day.count == 8, day.allSatisfy(\.isNumber) {
                self = .once(day)
                return
            }
            self = .daily
            return
        }
        let days = Set(code.compactMap { Int(String($0)) }.filter { (1...7).contains($0) })
        self = .weekdays(days.isEmpty ? Set(1...7) : days)
    }
}

/// 闹钟管“今天某个时刻”：一张卡片放多个闹钟，下一个最醒目。
///
/// 存在小组件自己的配置里：
/// - `alarms`：每个闹钟一行 `id|HH:mm|1|名字`（1 开、0 关）。名字放最后，里面有“|”也不会读错。
/// - `handled`：今天已经处理过（关掉或稍后）的响铃，`id@yyyyMMdd`，只留今天的。
/// - `snoozes`：稍后再响的，`id|epoch`。
/// - `repeats`：不是每天响的闹钟，`id|12345`（周一是 1，周日是 7）或 `id|once:yyyyMMdd`
///   （只响一次）。没写的就是每天，旧配置没有这个键，照样每天响。
///
/// 旧卡片只有一个闹钟，存在 `time`、`name`、`enabled` 三个键里。没有 `alarms`
/// 这个键时按旧键读成一个闹钟；第一次在新面板或卡片上改动时写成列表，旧键不再读。
public struct AlarmItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// 午夜后的分钟数。
    public var minutes: Int
    public var name: String
    public var enabled: Bool
    /// 哪几天响，默认每天。
    public var repeats: AlarmRepeat

    public init(id: String, minutes: Int, name: String, enabled: Bool = true, repeats: AlarmRepeat = .daily) {
        self.id = id
        self.minutes = min(23 * 60 + 59, max(0, minutes))
        self.name = name
        self.enabled = enabled
        if case .weekdays(let days) = repeats, days.isEmpty {
            self.repeats = .daily
        } else {
            self.repeats = repeats
        }
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
    public static let repeatsKey = "repeats"
    public static let soundKey = "sound"
    /// 稍后再响隔几分钟：和 iPhone 的闹钟一样是 9 分钟，卡片、面板和到点弹出的
    /// 卡片都用这一个数。
    public static let snoozeMinutes = 9
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
            let repeats = repeatMap(config)
            return sorted(config.strings(alarmsKey).compactMap { line in
                guard var item = AlarmItem(line: line) else { return nil }
                if let rule = repeats[item.id] { item.repeats = rule }
                return item
            })
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
        let kept = Array(sorted(items).prefix(maxAlarms))
        config.set(alarmsKey, .list(kept.map { .string($0.line) }))
        let rules = kept.filter { !$0.repeats.isDaily }.map { "\($0.id)|\($0.repeats.code)" }
        config.set(repeatsKey, rules.isEmpty ? nil : .list(rules.map { .string($0) }))
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

    /// 下一次响的时刻：每天的是今天的这个时刻，过了就是明天的；只在某几天响的
    /// 往后找到第一个对的日子；只响一次的就是那一天，已经过了也返回那一刻
    /// （用 `isLive` 判断它还会不会响）。
    public static func nextOccurrence(_ item: AlarmItem, after now: Date, calendar: Calendar = .current) -> Date {
        if case .once(let key) = item.repeats {
            return onceDate(key, minutes: item.minutes, calendar: calendar) ?? at(item.minutes, on: now, calendar: calendar)
        }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard rings(item.repeats, on: day, calendar: calendar) else { continue }
            let candidate = at(item.minutes, on: day, calendar: calendar)
            if candidate > now { return candidate }
        }
        let today = at(item.minutes, on: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 什么时候响：开着的闹钟的下一次，稍后再响的算稍后的时刻。
    public static func nextRing(_ item: AlarmItem, config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> Date {
        let regular = nextOccurrence(item, after: now, calendar: calendar)
        if let snooze = snoozes(config)[item.id], snooze > now, snooze < regular || regular <= now { return snooze }
        return regular
    }

    /// 开着、而且后面还会响：只响一次的过了那一刻（也没有稍后再响）就不算了。
    public static func isLive(_ item: AlarmItem, config: WidgetConfig, now: Date,
                              calendar: Calendar = .current) -> Bool {
        item.enabled && nextRing(item, config: config, now: now, calendar: calendar) > now
    }

    /// 排好的接下来要响的：开着的按下一次响铃的先后。卡片第一行是第一个。
    public static func upcoming(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> [(item: AlarmItem, at: Date)] {
        items(config).filter(\.enabled)
            .map { (item: $0, at: nextRing($0, config: config, now: now, calendar: calendar)) }
            .filter { $0.at > now }
            .sorted { ($0.at, $0.item.id) < ($1.at, $1.item.id) }
    }

    /// 卡片上最醒目的那个：下一个开着的；全关了时是时间上最近的一个（显示已关闭），
    /// 已经响过的一次性闹钟排在最后。
    public static func headline(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> AlarmItem? {
        if let first = upcoming(config, now: now, calendar: calendar).first { return first.item }
        let all = items(config)
        let pending = all.filter { nextOccurrence($0, after: now, calendar: calendar) > now }
        return (pending.isEmpty ? all : pending).min {
            (nextOccurrence($0, after: now, calendar: calendar), $0.id)
                < (nextOccurrence($1, after: now, calendar: calendar), $1.id)
        }
    }

    /// 这条规则在这一天响不响。
    public static func rings(_ rule: AlarmRepeat, on day: Date, calendar: Calendar = .current) -> Bool {
        switch rule {
        case .weekdays: rule.days.contains(isoWeekday(day, calendar: calendar))
        case .once(let key): key == dayKey(day, calendar: calendar)
        }
    }

    /// 今天会响的开着的闹钟（时间轴上的点）：午夜后的分钟数，按先后。
    /// 稍后再响落在今天的也算一个点。
    public static func today(_ config: WidgetConfig, now: Date,
                             calendar: Calendar = .current) -> [(item: AlarmItem, minutes: Int)] {
        var marks: [(item: AlarmItem, minutes: Int)] = []
        for item in items(config) where item.enabled && rings(item.repeats, on: now, calendar: calendar) {
            marks.append((item, item.minutes))
        }
        let snoozed = snoozes(config)
        for item in items(config) where item.enabled {
            guard let snooze = snoozed[item.id], calendar.isDate(snooze, inSameDayAs: now) else { continue }
            let parts = calendar.dateComponents([.hour, .minute], from: snooze)
            marks.append((item, (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
        }
        return marks.sorted { ($0.minutes, $0.item.id) < ($1.minutes, $1.item.id) }
    }

    /// 快速加一个只响一次的闹钟：从现在起 `minutes` 分钟后，往上取整到分钟。
    /// 返回午夜后的分钟数和那一天（过了午夜就是明天）。
    public static func quickOnce(after minutes: Int, now: Date,
                                 calendar: Calendar = .current) -> (minutes: Int, repeats: AlarmRepeat) {
        let raw = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let second = calendar.component(.second, from: raw)
        let target = second == 0 ? raw : raw.addingTimeInterval(TimeInterval(60 - second))
        let parts = calendar.dateComponents([.hour, .minute], from: target)
        return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0), .once(dayKey(target, calendar: calendar)))
    }

    /// 新建或重新打开一个只响一次的闹钟时用哪一天：这个时刻今天还没过就是今天，过了是明天。
    public static func onceDay(for minutes: Int, now: Date, calendar: Calendar = .current) -> AlarmRepeat {
        let today = at(minutes, on: now, calendar: calendar)
        let day = today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        return .once(dayKey(day, calendar: calendar))
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
            if rings(item.repeats, on: now, calendar: calendar), today <= now, now.timeIntervalSince(today) < ringWindow,
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

    /// 关掉：今天这次记成已处理，稍后再响的也一并取消。只响一次的闹钟顺手关掉开关。
    public static func dismiss(_ id: String, in config: inout WidgetConfig, now: Date,
                               calendar: Calendar = .current) {
        markHandled(id, in: &config, now: now, calendar: calendar)
        var snoozed = snoozes(config)
        snoozed[id] = nil
        storeSnoozes(snoozed, in: &config)
        var list = items(config)
        if let index = list.firstIndex(where: { $0.id == id }), list[index].repeats.isOnce, list[index].enabled {
            list[index].enabled = false
            store(list, in: &config)
        }
    }

    /// 稍后 9 分钟：这次记成已处理，9 分钟后再响。
    public static func snooze(_ id: String, in config: inout WidgetConfig, now: Date,
                              calendar: Calendar = .current) {
        markHandled(id, in: &config, now: now, calendar: calendar)
        var snoozed = snoozes(config)
        snoozed[id] = now.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        storeSnoozes(snoozed, in: &config)
    }

    /// 开或关某个闹钟。关掉时它的稍后再响也取消；重新打开一个已经过了的
    /// 只响一次的闹钟时，改到下一次这个时刻（今天没过就是今天，过了是明天）。
    public static func setEnabled(_ id: String, _ on: Bool, in config: inout WidgetConfig,
                                  now: Date = .now, calendar: Calendar = .current) {
        var list = items(config)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].enabled = on
        if on, list[index].repeats.isOnce,
           nextOccurrence(list[index], after: now, calendar: calendar) <= now {
            list[index].repeats = onceDay(for: list[index].minutes, now: now, calendar: calendar)
        }
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

    /// 几小时几分钟后响：“2 小时 7 分钟后响”“35 分钟后响”“不到 1 分钟后响”。
    public static func ringsInText(_ date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return tr("不到 1 分钟后响") }
        if minutes < 60 { return tr("\(minutes) 分钟后响") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("\(h) 小时后响") : tr("\(h) 小时 \(m) 分钟后响")
    }

    /// 重复规则的说明：“每天”“工作日”“周末”“周一、三、五”，只响一次的是
    /// “仅今天”“仅明天”“仅 10月22日”，过了是“已响过”。
    public static func repeatText(_ rule: AlarmRepeat, minutes: Int = 0, now: Date,
                                  calendar: Calendar = .current) -> String {
        switch rule {
        case .once(let key):
            guard let date = onceDate(key, minutes: minutes, calendar: calendar) else { return tr("仅一次") }
            if date <= now { return tr("已响过") }
            if calendar.isDate(date, inSameDayAs: now) { return tr("仅今天") }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(date, inSameDayAs: tomorrow) { return tr("仅明天") }
            let parts = calendar.dateComponents([.month, .day], from: date)
            return tr("仅 \(parts.month ?? 0)月\(parts.day ?? 0)日")
        case .weekdays:
            let days = rule.days
            if days.count == 7 { return tr("每天") }
            if days == [1, 2, 3, 4, 5] { return tr("工作日") }
            if days == [6, 7] { return tr("周末") }
            return days.sorted().map { weekdayName($0) }.joined(separator: tr("、"))
        }
    }

    /// 一周七天的单字：“一”…“日”（重复日选择用）。
    public static func weekdayShort(_ iso: Int) -> String {
        switch iso {
        case 1: tr("一")
        case 2: tr("二")
        case 3: tr("三")
        case 4: tr("四")
        case 5: tr("五")
        case 6: tr("六")
        default: tr("日")
        }
    }

    /// 一周七天的名字：“周一”…“周日”。
    public static func weekdayName(_ iso: Int) -> String {
        switch iso {
        case 1: tr("周一")
        case 2: tr("周二")
        case 3: tr("周三")
        case 4: tr("周四")
        case 5: tr("周五")
        case 6: tr("周六")
        default: tr("周日")
        }
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

    /// 周一是 1，周日是 7。
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func onceDate(_ key: String, minutes: Int, calendar: Calendar) -> Date? {
        guard key.count == 8, let value = Int(key) else { return nil }
        let parts = DateComponents(year: value / 10000, month: value / 100 % 100, day: value % 100,
                                   hour: minutes / 60, minute: minutes % 60)
        return calendar.date(from: parts)
    }

    static func repeatMap(_ config: WidgetConfig) -> [String: AlarmRepeat] {
        var result: [String: AlarmRepeat] = [:]
        for line in config.strings(repeatsKey) {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            result[parts[0]] = AlarmRepeat(code: parts[1])
        }
        return result
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
