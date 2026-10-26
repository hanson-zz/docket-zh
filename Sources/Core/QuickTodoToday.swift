import Foundation

/// 快速待办的“一天”：按本机日历的年月日写成 `yyyy-MM-dd`。
///
/// 字符串而不是 `Date`：存进小组件自己的配置里不用新的 Codable 形状，两天
/// 比先后直接比字符串就行（同样的位数、同样的顺序）。
public enum TodoDay {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 是不是一个写得对的日子。
    public static func isKey(_ text: String) -> Bool {
        components(text) != nil
    }

    private static func components(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    /// 这一天的中午，换算日期时避开夏令时的零点。
    public static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        guard var parts = components(text) else { return nil }
        parts.hour = 12
        return calendar.date(from: parts)
    }

    /// 前一天，写不对时为 nil。
    public static func previous(_ text: String, calendar: Calendar = .current) -> String? {
        guard let noon = date(text, calendar: calendar),
              let before = calendar.date(byAdding: .day, value: -1, to: noon) else { return nil }
        return key(before, calendar: calendar)
    }
}

/// 卡片上画哪几条：「今天」分组里有东西时就是它们，没有就是前几条未完成的。
public struct TodoCardRows: Equatable, Sendable {
    public var rows: [TodoItem]
    /// 是不是「今天」分组里的那几条。
    public var focused: Bool
    /// 右上角的“x/3”：标过的里做完了几条、一共标了几条。没标时是全部的。
    public var done: Int
    public var total: Int
    /// 卡片上放不下、还没做完的条数。
    public var hidden: Int
}

extension QuickTodo {
    /// 卡片上最多画几行。「今天」分组本身不限条数（旧版本的“今天三件事”最多 3 条，
    /// 改版后取消了上限）。
    public static let maxToday = 3

    /// 「今天」分组里的那几条：没做完的在前，各自保持清单里的顺序。
    public static func todayItems(_ items: [TodoItem]) -> [TodoItem] {
        ordered(items).filter(\.today)
    }

    /// 放进「今天」或拿回「稍后」。放进来时记下今天（`day`），拿出去时清掉。
    public static func togglingToday(_ id: String, in items: [TodoItem], day: String? = nil) -> [TodoItem] {
        guard items.contains(where: { $0.id == id }) else { return ordered(items) }
        return ordered(items.map { other in
            guard other.id == id else { return other }
            var changed = other
            changed.today.toggle()
            changed.todaySince = changed.today ? (day ?? changed.addedDay) : nil
            return changed
        })
    }

    /// 卡片上的几行。
    ///
    /// 「今天」分组里有东西时只画它们，做完的也留着打勾划线，右上角是做完几条 / 一共
    /// 几条；今天一条都没有时画前 `limit` 条没做完的，右上角是全部的完成数。
    public static func cardRows(_ items: [TodoItem], limit: Int = maxToday) -> TodoCardRows {
        let list = ordered(items)
        let unfinished = open(list)
        let marked = todayItems(list)
        if !marked.isEmpty {
            let rows = Array(marked.prefix(limit))
            let hidden = unfinished.filter { !$0.today }.count
            return TodoCardRows(rows: rows, focused: true,
                                done: marked.filter(\.done).count, total: marked.count, hidden: hidden)
        }
        let rows = Array(unfinished.prefix(limit))
        return TodoCardRows(rows: rows, focused: false,
                            done: list.count - unfinished.count, total: list.count,
                            hidden: max(0, unfinished.count - rows.count))
    }
}

// MARK: - 当天清

extension QuickTodo {
    /// 上一次按“新的一天”收拾清单是哪天。
    public static let dayKey = "day"

    /// 第二天收拾清单：昨天以前做完的从清单里拿掉（`applyRollover` 把它们挪进
    /// 收起区），没记日子的老条目记成今天。
    ///
    /// 没做完的留着：`applyRollover` 接着用 `planningToday` 把昨天没做完的「今天」
    /// 挪到最前面（改版后不再问顺延还是放弃）。旧版本写下
    /// 的条目没有日子，一律当作今天记下、今天做完，升级当天不会被当成“昨天的”。
    public static func rollingOver(_ items: [TodoItem], today: String) -> [TodoItem] {
        ordered(items).compactMap { item in
            var item = item
            if item.done {
                let finished = item.doneDay ?? today
                guard finished >= today else { return nil }
                item.doneDay = finished
            } else if item.addedDay == nil {
                item.addedDay = today
            }
            return item
        }
    }

    /// 是否该收拾了：今天还没收拾过。
    public static func needsRollover(_ config: WidgetConfig, today: String) -> Bool {
        config.string(dayKey) != today
    }

    /// 收拾一遍并记下今天。今天已经收拾过时什么也不改。
    ///
    /// 昨天以前做完的挪进收起区（见 `QuickTodoArchive.swift`），在那里留 7 天，
    /// 过期的这时一并清掉。
    public static func applyRollover(in config: inout WidgetConfig, today: String,
                                     calendar: Calendar = .current) {
        guard needsRollover(config, today: today) else { return }
        let current = items(config)
        let moved = archiving(current, today: today)
        let kept = prunedArchive(moved + archive(config), today: today, calendar: calendar)
        storeArchive(kept, in: &config)
        store(planningToday(rollingOver(current, today: today), today: today, calendar: calendar), in: &config)
        config.set(dayKey, .string(today))
    }

    /// 昨天（或更早）记下、还没做完的。
    public static func leftover(_ items: [TodoItem], today: String) -> [TodoItem] {
        open(ordered(items)).filter { ($0.addedDay ?? today) < today }
    }

    /// 顺延到今天：这些条目改记成今天的，“今天三件事”的标记照留。
    public static func carryingOver(_ items: [TodoItem], today: String) -> [TodoItem] {
        let late = Set(leftover(items, today: today).map(\.id))
        return ordered(items.map { item in
            guard late.contains(item.id) else { return item }
            var moved = item
            moved.addedDay = today
            return moved
        })
    }

    /// 放弃：把昨天没做完的删掉。
    public static func droppingLeftover(_ items: [TodoItem], today: String) -> [TodoItem] {
        let late = Set(leftover(items, today: today).map(\.id))
        return ordered(items.filter { !late.contains($0.id) })
    }

    /// 今天清空了：一条没剩，而且今天确实勾掉过至少一条。
    public static func isClearedToday(_ items: [TodoItem], today: String) -> Bool {
        !items.isEmpty && open(items).isEmpty && items.contains { $0.doneDay == today }
    }
}

// MARK: - 连续清空天数

/// 连续几天把快速待办清空。只记最后清空的那天和到那天为止连了几天。
public struct TodoStreak: Equatable, Sendable {
    public var lastDay: String?
    public var count: Int

    public init(lastDay: String? = nil, count: Int = 0) {
        self.lastDay = lastDay
        self.count = max(0, count)
    }

    public static let dayKey = "streakDay"
    public static let countKey = "streakCount"

    public init(_ config: WidgetConfig) {
        let day = config.string(Self.dayKey)
        self.init(lastDay: TodoDay.isKey(day) ? day : nil, count: config.int(Self.countKey))
    }

    public func store(in config: inout WidgetConfig) {
        config.set(Self.dayKey, lastDay.map { .string($0) })
        config.set(Self.countKey, .number(Double(count)))
    }

    /// 记下 `day` 清空了：同一天记两次不重复算，接着前一天就加一，断过就从一开始。
    public func recording(_ day: String, calendar: Calendar = .current) -> TodoStreak {
        guard TodoDay.isKey(day) else { return self }
        if lastDay == day { return self }
        if let lastDay, lastDay > day { return self }
        if let lastDay, TodoDay.previous(day, calendar: calendar) == lastDay {
            return TodoStreak(lastDay: day, count: count + 1)
        }
        return TodoStreak(lastDay: day, count: 1)
    }

    /// 今天看到的连续天数：最后清空的是今天或昨天时还连着，再早就断了。
    public func current(today: String, calendar: Calendar = .current) -> Int {
        guard let lastDay, count > 0 else { return 0 }
        if lastDay == today || lastDay == TodoDay.previous(today, calendar: calendar) { return count }
        return 0
    }
}

extension QuickTodo {
    /// 「今天」一组清空时记一笔连续清空，也记进最近 7 天的小圆点。
    public static func recordCleared(in config: inout WidgetConfig, today: String,
                                     calendar: Calendar = .current) {
        TodoStreak(config).recording(today, calendar: calendar).store(in: &config)
        TodoStreak.recordHistory(today, in: &config)
    }

    public static func streak(_ config: WidgetConfig, today: String, calendar: Calendar = .current) -> Int {
        TodoStreak(config).current(today: today, calendar: calendar)
    }
}

// MARK: - 拖进来记

/// 拖到卡片上的一样东西变成的一条待办。
public struct TodoDrop: Equatable, Sendable {
    public var text: String
    public var link: String?

    public init(text: String, link: String? = nil) {
        self.text = text
        self.link = link
    }

    /// 一个链接或文件：文字是文件名，或者网址去掉 `https://` 和 `www.` 之后的样子。
    public static func url(_ url: URL) -> TodoDrop? {
        if url.isFileURL {
            let name = url.lastPathComponent
            guard !name.isEmpty, let words = QuickTodo.clean(name) else { return nil }
            return TodoDrop(text: words, link: url.absoluteString)
        }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        var shown = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path
        if path.count > 1 { shown += path }
        if shown.hasSuffix("/") { shown.removeLast() }
        guard let words = QuickTodo.clean(shown) else { return nil }
        return TodoDrop(text: words, link: url.absoluteString)
    }

    /// 一段文字：整段就是一个网址时当链接记，否则就是一句待办。
    public static func text(_ raw: String) -> TodoDrop? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
           let drop = Self.url(url) {
            return drop
        }
        guard let words = QuickTodo.clean(trimmed) else { return nil }
        return TodoDrop(text: words)
    }
}
