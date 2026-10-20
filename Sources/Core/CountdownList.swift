import Foundation

/// 一个计时器：名字、时长、在跑时的结束时刻或暂停时还剩的秒数。
///
/// 第一个（`CountdownList.mainID`）就是原来卡片上的那个倒计时，仍然存在
/// `duration`、`deadline`、`paused`、`name` 四个键里，卡片的三个预设、面板的大环
/// 和到点弹出的卡片都照旧读它；旧配置因此不用改写，打开就是列表的第一项。
/// 其余同时在跑的存在 `timers` 里，见 `CountdownList`。
public struct CountdownTimer: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 这一轮（也是上一轮）的时长，秒。
    public var duration: TimeInterval
    /// 正在跑时的结束时刻（epoch）。到点后不清掉，表示“时间到，还没人点停”。
    public var deadline: TimeInterval?
    /// 暂停时还剩的秒数；有它就是暂停，`deadline` 同时为空。
    public var paused: TimeInterval?

    public init(id: String, name: String = "", duration: TimeInterval,
                deadline: TimeInterval? = nil, paused: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.duration = max(0, duration)
        self.deadline = deadline
        self.paused = paused
    }

    public var isMain: Bool { id == CountdownList.mainID }

    /// 没起名字时叫“倒计时”。
    public var title: String { name.isEmpty ? tr("倒计时") : name }

    /// `timers` 里的一行：`id|时长|结束时刻|暂停剩余|名字`，没有的留空；名字放最后，
    /// 里面有“|”也不会读错。
    var line: String {
        func number(_ value: TimeInterval?) -> String { value.map { String(Int($0.rounded())) } ?? "" }
        return "\(id)|\(Int(duration.rounded()))|\(number(deadline))|\(number(paused))|\(name)"
    }

    init?(line: String) {
        let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, !parts[0].isEmpty, parts[0] != CountdownList.mainID,
              let duration = Double(parts[1]), duration > 0 else { return nil }
        self.init(id: parts[0], name: parts.count > 4 ? parts[4] : "", duration: duration,
                  deadline: Double(parts[2]), paused: Double(parts[3]))
    }
}

/// 日期倒计时：到某一天还有几天（生日、发布日），可以每年重复。
public struct CountdownDate: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 那一天，`yyyyMMdd`。每年重复的只看月和日。
    public var day: String
    public var yearly: Bool

    public init(id: String, name: String, day: String, yearly: Bool = false) {
        self.id = id
        self.name = name
        self.day = day
        self.yearly = yearly
    }

    /// 没起名字时叫“日期倒计时”。
    public var title: String { name.isEmpty ? tr("日期倒计时") : name }

    /// `dates` 里的一行：`id|yyyyMMdd|1|名字`（1 每年重复、0 只一次）。
    var line: String { "\(id)|\(day)|\(yearly ? "1" : "0")|\(name)" }

    init?(line: String) {
        let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, !parts[0].isEmpty, CountdownList.parts(parts[1]) != nil else { return nil }
        self.init(id: parts[0], name: parts.count > 3 ? parts[3] : "", day: parts[1], yearly: parts[2] == "1")
    }
}

/// 倒计时卡片上的多个计时器和日期倒计时。
///
/// 配置里的键：
/// - 第一个计时器在原来的 `duration`、`deadline`、`paused`、`name` 里（见 `CountdownRun`）。
/// - `timers`：其余计时器，每个一行 `id|时长|结束时刻|暂停剩余|名字`。
/// - `dates`：日期倒计时，每个一行 `id|yyyyMMdd|1|名字`。
///
/// 没有 `timers`、`dates` 的旧卡片就是只有第一个计时器、没有日期，照旧能用。
public enum CountdownList {
    public static let mainID = "main"
    public static let timersKey = "timers"
    public static let datesKey = "dates"
    /// 一张卡片最多同时放几个计时器（含第一个）。
    public static let maxTimers = 8
    /// 最多几个日期倒计时。
    public static let maxDates = 12
    /// 新计时器默认的时长（分钟）。
    public static let newTimerMinutes = 10

    // MARK: 计时器

    /// 第一个计时器，读原来的四个键。
    public static func main(_ config: WidgetConfig) -> CountdownTimer {
        CountdownTimer(id: mainID, name: config.string("name"),
                       duration: max(0, config.double("duration", default: 300)),
                       deadline: config["deadline"] != nil ? config.double("deadline") : nil,
                       paused: config["paused"] != nil ? config.double("paused") : nil)
    }

    /// 第一个之外的计时器，按存的先后，重复的 id 只留第一个。
    public static func extras(_ config: WidgetConfig) -> [CountdownTimer] {
        var seen: Set<String> = []
        var result: [CountdownTimer] = []
        for line in config.strings(timersKey) {
            guard let timer = CountdownTimer(line: line), seen.insert(timer.id).inserted else { continue }
            result.append(timer)
            if result.count == maxTimers - 1 { break }
        }
        return result
    }

    /// 全部计时器：第一个在最前。
    public static func timers(_ config: WidgetConfig) -> [CountdownTimer] {
        [main(config)] + extras(config)
    }

    /// 按 id 找；空字符串或 `main` 是第一个。
    public static func timer(_ id: String, in config: WidgetConfig) -> CountdownTimer? {
        if id.isEmpty || id == mainID { return main(config) }
        return extras(config).first { $0.id == id }
    }

    /// 写回一个计时器：第一个写回原来的四个键，其余的替换或加到 `timers` 末尾（满了不加）。
    public static func store(_ timer: CountdownTimer, in config: inout WidgetConfig) {
        if timer.isMain {
            config.set("duration", .number(timer.duration))
            config.set("deadline", timer.deadline.map { .number($0) })
            config.set("paused", timer.paused.map { .number($0) })
            config.set("name", .string(timer.name))
            return
        }
        var list = extras(config)
        if let index = list.firstIndex(where: { $0.id == timer.id }) {
            list[index] = timer
        } else {
            guard list.count < maxTimers - 1 else { return }
            list.append(timer)
        }
        storeExtras(list, in: &config)
    }

    /// 删掉一个计时器。第一个不能删，只回到没开始。
    public static func remove(_ id: String, in config: inout WidgetConfig) {
        if id.isEmpty || id == mainID {
            store(stopping(Self.main(config)), in: &config)
            return
        }
        storeExtras(extras(config).filter { $0.id != id }, in: &config)
    }

    /// 改一个计时器：找到就改完写回，找不到不动。
    public static func update(_ id: String, in config: inout WidgetConfig,
                              _ change: (inout CountdownTimer) -> Void) {
        guard var found = Self.timer(id, in: config) else { return }
        change(&found)
        store(found, in: &config)
    }

    /// 加一个新计时器并马上开始。满了返回 nil。
    @discardableResult
    public static func adding(name: String, duration: TimeInterval, to config: inout WidgetConfig,
                              now: Date) -> CountdownTimer? {
        let list = extras(config)
        guard list.count < maxTimers - 1, duration > 0 else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let timer = starting(CountdownTimer(id: newTimerID(existing: list), name: trimmed, duration: duration),
                             duration: duration, now: now)
        store(timer, in: &config)
        return timer
    }

    public static func canAddTimer(_ config: WidgetConfig) -> Bool {
        extras(config).count < maxTimers - 1
    }

    static func storeExtras(_ list: [CountdownTimer], in config: inout WidgetConfig) {
        let kept = Array(list.prefix(maxTimers - 1))
        config.set(timersKey, kept.isEmpty ? nil : .list(kept.map { .string($0.line) }))
    }

    static func newTimerID(existing: [CountdownTimer]) -> String {
        let used = Set(existing.map(\.id))
        var n = existing.count + 1
        while used.contains("t\(n)") { n += 1 }
        return "t\(n)"
    }

    // MARK: 计时器的动作（只改值，不写配置）

    public static func phase(_ timer: CountdownTimer, now: Date) -> CountdownRun.Phase {
        let total = max(1, timer.duration)
        if let paused = timer.paused {
            let left = max(0, min(paused, total))
            return .paused(left: left, fraction: 1 - left / total)
        }
        guard let deadline = timer.deadline else { return .idle }
        let left = deadline - now.timeIntervalSince1970
        if left <= 0 { return .ringing(since: -left) }
        let clamped = min(left, total)
        return .running(left: clamped, fraction: min(1, max(0, 1 - clamped / total)))
    }

    /// 从现在起计 `duration` 秒（也记成这个计时器的时长）。
    public static func starting(_ timer: CountdownTimer, duration: TimeInterval, now: Date) -> CountdownTimer {
        var result = timer
        let length = duration > 0 ? duration : timer.duration
        result.duration = length
        result.paused = nil
        result.deadline = now.timeIntervalSince1970 + length
        return result
    }

    /// 暂停：存下还剩多少。不在跑时不动。
    public static func pausing(_ timer: CountdownTimer, now: Date) -> CountdownTimer {
        guard case .running(let left, _) = phase(timer, now: now) else { return timer }
        var result = timer
        result.paused = left
        result.deadline = nil
        return result
    }

    /// 继续：从剩下的接着数。不在暂停时不动。
    public static func resuming(_ timer: CountdownTimer, now: Date) -> CountdownTimer {
        guard case .paused(let left, _) = phase(timer, now: now) else { return timer }
        var result = timer
        result.paused = nil
        result.deadline = now.timeIntervalSince1970 + left
        return result
    }

    /// 停：回到没开始，时长留着下次用。
    public static func stopping(_ timer: CountdownTimer) -> CountdownTimer {
        var result = timer
        result.paused = nil
        result.deadline = nil
        return result
    }

    /// 加时间：跑着的往后推，暂停的加剩下的，已经到点的从现在起再计这么久；没开始时不动。
    public static func adding(_ seconds: TimeInterval, to timer: CountdownTimer, now: Date) -> CountdownTimer {
        guard seconds > 0 else { return timer }
        var result = timer
        switch phase(timer, now: now) {
        case .idle:
            return timer
        case .running(let left, _):
            result.duration = timer.duration + seconds
            result.deadline = now.timeIntervalSince1970 + left + seconds
        case .paused(let left, _):
            result.duration = timer.duration + seconds
            result.paused = left + seconds
        case .ringing:
            result.duration = seconds
            result.paused = nil
            result.deadline = now.timeIntervalSince1970 + seconds
        }
        return result
    }

    // MARK: 卡片显示哪一个

    public enum Focus: Equatable, Sendable {
        /// 有计时器在响、在跑或暂停：显示这一个。
        case timer(CountdownTimer)
        /// 计时器都没开始，有日期倒计时：卡片头上写最近的那个日期，下面仍是预设。
        case date(CountdownDate, days: Int)
        /// 什么都没有：原来的样子，名字和三个预设。
        case idle
    }

    /// 卡片显示最近的一个：先是在响的（最近开始响的），再是最快到点的在跑的，
    /// 再是剩得最少的暂停的；计时器都没开始时是最近的日期倒计时。
    public static func focus(_ config: WidgetConfig, now: Date, calendar: Calendar = .current) -> Focus {
        let all = timers(config).map { (timer: $0, phase: phase($0, now: now)) }
        let ringing = all.compactMap { entry -> (CountdownTimer, TimeInterval)? in
            if case .ringing(let since) = entry.phase { return (entry.timer, since) }
            return nil
        }
        if let first = ringing.min(by: { ($0.1, $0.0.id) < ($1.1, $1.0.id) }) { return .timer(first.0) }
        let running = all.compactMap { entry -> (CountdownTimer, TimeInterval)? in
            if case .running(let left, _) = entry.phase { return (entry.timer, left) }
            return nil
        }
        if let first = running.min(by: { ($0.1, $0.0.id) < ($1.1, $1.0.id) }) { return .timer(first.0) }
        let paused = all.compactMap { entry -> (CountdownTimer, TimeInterval)? in
            if case .paused(let left, _) = entry.phase { return (entry.timer, left) }
            return nil
        }
        if let first = paused.min(by: { ($0.1, $0.0.id) < ($1.1, $1.0.id) }) { return .timer(first.0) }
        if let nearest = nearestDate(config, now: now, calendar: calendar) {
            return .date(nearest.date, days: nearest.days)
        }
        return .idle
    }

    /// 正在跑的计时器有几个（卡片上写“另有 2 个”）。
    public static func activeCount(_ config: WidgetConfig, now: Date) -> Int {
        timers(config).filter { phase($0, now: now) != .idle }.count
    }

    // MARK: 日期倒计时

    /// 全部日期倒计时，按离今天的天数排：还没到的从近到远，已经过了的（不重复的）排最后。
    public static func dates(_ config: WidgetConfig, now: Date, calendar: Calendar = .current) -> [CountdownDate] {
        storedDates(config).sorted { a, b in
            let da = daysLeft(a, now: now, calendar: calendar), db = daysLeft(b, now: now, calendar: calendar)
            let ka = da >= 0 ? (0, da) : (1, -da), kb = db >= 0 ? (0, db) : (1, -db)
            return (ka.0, ka.1, a.id) < (kb.0, kb.1, b.id)
        }
    }

    /// 按存的先后读，重复的 id 只留第一个。
    public static func storedDates(_ config: WidgetConfig) -> [CountdownDate] {
        var seen: Set<String> = []
        var result: [CountdownDate] = []
        for line in config.strings(datesKey) {
            guard let item = CountdownDate(line: line), seen.insert(item.id).inserted else { continue }
            result.append(item)
            if result.count == maxDates { break }
        }
        return result
    }

    public static func storeDates(_ list: [CountdownDate], in config: inout WidgetConfig) {
        let kept = Array(list.prefix(maxDates))
        config.set(datesKey, kept.isEmpty ? nil : .list(kept.map { .string($0.line) }))
    }

    /// 加一个日期倒计时。满了返回 nil。
    @discardableResult
    public static func addingDate(name: String, on date: Date, yearly: Bool, to config: inout WidgetConfig,
                                  calendar: Calendar = .current) -> CountdownDate? {
        var list = storedDates(config)
        guard list.count < maxDates else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let item = CountdownDate(id: newDateID(existing: list), name: trimmed,
                                 day: dayKey(date, calendar: calendar), yearly: yearly)
        list.append(item)
        storeDates(list, in: &config)
        return item
    }

    public static func removeDate(_ id: String, in config: inout WidgetConfig) {
        storeDates(storedDates(config).filter { $0.id != id }, in: &config)
    }

    public static func canAddDate(_ config: WidgetConfig) -> Bool {
        storedDates(config).count < maxDates
    }

    static func newDateID(existing: [CountdownDate]) -> String {
        let used = Set(existing.map(\.id))
        var n = existing.count + 1
        while used.contains("d\(n)") { n += 1 }
        return "d\(n)"
    }

    /// 下一次是哪一天（那天的零点）。每年重复的：今年这天还没过（含今天）就是今年，
    /// 过了是明年；2 月 29 日在平年算 2 月 28 日。不重复的就是那一天。
    public static func nextDay(_ item: CountdownDate, now: Date, calendar: Calendar = .current) -> Date? {
        guard let ymd = parts(item.day) else { return nil }
        let (year, month, day) = ymd
        guard item.yearly else { return makeDay(year, month, day, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: now)
        for candidate in [thisYear, thisYear + 1] {
            guard let date = makeDay(candidate, month, day, calendar: calendar) else { continue }
            if date >= today { return date }
        }
        return nil
    }

    /// 离那天还有几天：今天是 0，明天是 1；不重复的已经过了是负数。
    public static func daysLeft(_ item: CountdownDate, now: Date, calendar: Calendar = .current) -> Int {
        guard let target = nextDay(item, now: now, calendar: calendar) else { return 0 }
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// 最近的一个还没过的日期倒计时（今天的也算）。都过了时是 nil。
    public static func nearestDate(_ config: WidgetConfig, now: Date,
                                   calendar: Calendar = .current) -> (date: CountdownDate, days: Int)? {
        storedDates(config)
            .map { (date: $0, days: daysLeft($0, now: now, calendar: calendar)) }
            .filter { $0.days >= 0 }
            .min { ($0.days, $0.date.id) < ($1.days, $1.date.id) }
    }

    /// “今天”“明天”“还有 66 天”“已过 3 天”。
    public static func daysText(_ days: Int) -> String {
        if days == 0 { return tr("就是今天") }
        if days == 1 { return tr("明天") }
        if days > 0 { return tr("还有 \(days) 天") }
        return tr("已过 \(-days) 天")
    }

    /// 卡片上的短写法：“66 天”“今天”“明天”。
    public static func daysShort(_ days: Int) -> String {
        if days == 0 { return tr("今天") }
        if days == 1 { return tr("明天") }
        if days > 0 { return tr("\(days) 天") }
        return tr("已过 \(-days) 天")
    }

    /// 日期那行：每年重复的“每年 12月25日”，不重复的“2027年1月1日”。
    public static func dateText(_ item: CountdownDate) -> String {
        guard let ymd = parts(item.day) else { return "" }
        let (year, month, day) = ymd
        return item.yearly ? tr("每年 \(month)月\(day)日") : tr("\(String(year))年\(month)月\(day)日")
    }

    /// 编辑时 DatePicker 用的日期。
    public static func date(of item: CountdownDate, calendar: Calendar = .current) -> Date? {
        guard let ymd = parts(item.day) else { return nil }
        return makeDay(ymd.0, ymd.1, ymd.2, calendar: calendar)
    }

    // MARK: 内部

    static func parts(_ key: String) -> (Int, Int, Int)? {
        guard key.count == 8, key.allSatisfy(\.isNumber), let value = Int(key) else { return nil }
        let (year, month, day) = (value / 10000, value / 100 % 100, value % 100)
        guard (1...12).contains(month), (1...31).contains(day), year > 0 else { return nil }
        return (year, month, day)
    }

    static func makeDay(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, range.upperBound - 1)))
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}
