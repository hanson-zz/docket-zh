import Foundation

// 快速待办 v3：五色标签、重复待办、键盘挪动、「今天」清空的庆祝和最近 7 天的小圆点。
//
// 标签：红橙黄绿紫五色，行首一道细色条加同色圆圈。红色就是原来的「重要」（存成
// 原来的 `f=1`，旧数据读出来就是红色，同步到系统提醒事项时照旧映射成旗标）；另外
// 四色存成 `c=`，只在码头里。红色免费，另外四色和按颜色筛选是 Pro：没解锁时这四色
// 照旧存着不改写，只是画成没有颜色（退回免费态），点了弹付费墙。
//
// 重复待办（Pro）：每天 / 每周 / 工作日。勾掉一条带重复的，按规则在「稍后」生成
// 下一次：有提醒时间的顺延提醒时间，没有的记下排到哪天（`planDay`），到了那天
// 新的一天收拾清单时升进「今天」。没解锁时规则照旧存着，勾掉不再生成。

/// 一条待办的颜色标签。
public enum TodoTag: String, CaseIterable, Sendable, Identifiable {
    case red, orange, yellow, green, purple

    public var id: String { rawValue }

    /// 存进清单里的一个字母（红色另存成 `f=1`，和旧版本的「重要」一样）。
    public var code: String {
        switch self {
        case .red: "r"
        case .orange: "o"
        case .yellow: "y"
        case .green: "g"
        case .purple: "p"
        }
    }

    public init?(code: String) {
        guard let match = Self.allCases.first(where: { $0.code == code }) else { return nil }
        self = match
    }

    /// 和效果图一致的五色（浅色、深色共用，圆圈和色条在浅色下按需压深）。
    public var hex: String {
        switch self {
        case .red: "#E5484D"
        case .orange: "#F2892B"
        case .yellow: "#E2B21C"
        case .green: "#2FA36B"
        case .purple: "#8E5BD0"
        }
    }

    /// 菜单里的名字。
    public var title: String {
        switch self {
        case .red: tr("红色（重要）")
        case .orange: tr("橙色")
        case .yellow: tr("黄色")
        case .green: tr("绿色")
        case .purple: tr("紫色")
        }
    }

    /// 只说颜色，读屏和筛选用。
    public var colorName: String {
        switch self {
        case .red: tr("红色")
        case .orange: tr("橙色")
        case .yellow: tr("黄色")
        case .green: tr("绿色")
        case .purple: tr("紫色")
        }
    }

    /// 红色免费，另外四色是 Pro。
    public var isPro: Bool { self != .red }

    /// ⌘1 到 ⌘5。
    public var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    public static func shortcut(_ number: Int) -> TodoTag? {
        guard (1...allCases.count).contains(number) else { return nil }
        return allCases[number - 1]
    }

    /// 画出来的颜色：没解锁时 Pro 四色画成没有颜色（存着的不改）。
    public static func shown(_ tag: TodoTag?, unlocked: Bool) -> TodoTag? {
        guard let tag else { return nil }
        return tag.isPro && !unlocked ? nil : tag
    }

    /// 能不能设成这个颜色：清除和红色一直可以，另外四色要解锁。
    public static func canChoose(_ tag: TodoTag?, unlocked: Bool) -> Bool {
        guard let tag else { return true }
        return !tag.isPro || unlocked
    }
}

/// 重复规则（Pro）。
public enum TodoRepeat: String, CaseIterable, Sendable, Identifiable {
    case daily = "d"
    case weekly = "w"
    case weekdays = "k"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily: tr("每天")
        case .weekly: tr("每周")
        case .weekdays: tr("工作日")
        }
    }

    /// `date` 之后的下一次（保持时刻）：每天加一天，每周加七天，工作日跳过周六周日。
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            for _ in 0..<7 where calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next.addingTimeInterval(86_400)
            }
            return next
        }
    }
}

extension QuickTodo {
    // MARK: 标签

    /// 设一条的颜色，`nil` 清除。
    public static func tagging(_ id: String, with tag: TodoTag?, in items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            guard item.id == id else { return item }
            var changed = item
            changed.tag = tag
            return changed
        })
    }

    /// 按颜色筛选（Pro）：`nil` 时原样返回。筛的是画出来的颜色，没解锁时不筛。
    public static func filtered(_ items: [TodoItem], by tag: TodoTag?, unlocked: Bool) -> [TodoItem] {
        guard let tag, unlocked else { return items }
        return items.filter { TodoTag.shown($0.tag, unlocked: unlocked) == tag }
    }

    // MARK: 重复

    /// 设一条的重复规则，`nil` 取消。
    public static func repeating(_ id: String, with rule: TodoRepeat?, in items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            guard item.id == id else { return item }
            var changed = item
            changed.repeatRule = rule
            return changed
        })
    }

    /// 勾掉一条重复待办后的下一次：文字、颜色、链接、规则照抄，放在「稍后」。
    ///
    /// 从这一条原来排的那天（提醒时间、排到哪天、放进今天的那天，都没有时是勾掉的
    /// 那天）往后按规则数，直到落在勾掉那天之后；有提醒时间的保留时刻。
    /// 没有规则或认不出日子时为 nil。
    public static func nextOccurrence(of item: TodoItem, finishedOn day: String?, id: String = TodoItem.newID(),
                                      calendar: Calendar = .current) -> TodoItem? {
        guard let rule = item.repeatRule else { return nil }
        let finished = day ?? TodoDay.key(Date(), calendar: calendar)
        guard let finishedNoon = TodoDay.date(finished, calendar: calendar) else { return nil }
        let base: Date
        if let at = item.remindAt {
            base = at
        } else if let planned = item.planDay ?? item.todaySince ?? item.addedDay,
                  let noon = TodoDay.date(planned, calendar: calendar) {
            base = noon
        } else {
            base = finishedNoon
        }
        var next = rule.next(after: base, calendar: calendar)
        var guardCount = 0
        while TodoDay.key(next, calendar: calendar) <= finished, guardCount < 400 {
            next = rule.next(after: next, calendar: calendar)
            guardCount += 1
        }
        let nextDay = TodoDay.key(next, calendar: calendar)
        return TodoItem(id: id, text: item.text, link: item.link, addedDay: finished,
                        remindAt: item.remindAt == nil ? nil : next,
                        tag: item.tag, repeatRule: rule,
                        planDay: item.remindAt == nil ? nextDay : nil, repeatOf: item.id)
    }

    // MARK: 键盘挪动

    /// ⌥↑ / ⌥↓：在自己这组里往上、往下挪一格；到了「今天」最后再往下就进「稍后」
    /// 第一条，「稍后」第一条再往上就进「今天」最后，和拖动跨组一样。
    public static func nudging(_ id: String, by step: Int, in items: [TodoItem], today: String) -> [TodoItem] {
        let list = ordered(items)
        guard step != 0, let item = list.first(where: { $0.id == id }), !item.done else { return list }
        let group = self.group(of: item)
        let rows = self.items(in: group, of: list)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return list }
        if step < 0 {
            if index > 0 {
                return moving(id, to: group, before: rows[index - 1].id, in: list, today: today)
            }
            guard group == .later else { return list }
            return moving(id, to: .today, before: nil, in: list, today: today)
        }
        if index + 1 < rows.count {
            let after = index + 2 < rows.count ? rows[index + 2].id : nil
            return moving(id, to: group, before: after, in: list, today: today)
        }
        guard group == .today else { return list }
        let later = self.items(in: .later, of: list)
        return moving(id, to: .later, before: later.first?.id, in: list, today: today)
    }

    // MARK: 「今天」清空

    /// 勾掉 `id` 正好把「今天」一组清空（「稍后」有没有都算）。由改动之前的清单判断。
    public static func clearsToday(toggling id: String, in items: [TodoItem]) -> Bool {
        let open = items.filter { !$0.done && $0.today }
        return open.count == 1 && open[0].id == id
    }

    /// 「今天」一组清空了：没有没做完的「今天」，而且今天勾掉过「今天」里的至少一条。
    public static func todayCleared(_ items: [TodoItem], today: String) -> Bool {
        !items.contains { !$0.done && $0.today }
            && items.contains { $0.done && $0.today && $0.doneDay == today }
    }

    /// 面板顶部「已完成 2 / 5」的两个数：今天勾掉的，和它加上「今天」里还没做的。
    public static func todayTally(_ items: [TodoItem], today: String) -> (done: Int, total: Int) {
        let left = items.filter { !$0.done && $0.today }.count
        let done = items.filter { $0.done && ($0.doneDay ?? today) == today }.count
        return (done, left + done)
    }
}

// MARK: - 卡片

/// 扩展栏卡片画哪种样子。
public enum TodoCardState: Equatable, Sendable {
    /// 一条都没有：歇着的小熊猫。
    case empty
    /// 「今天」没有要做的了（稍后可能还有）：小熊猫欢呼、连续天数、7 天小点。
    case cleared
    /// 进度环写还剩几件，右边今天最前两条。
    case list
}

extension QuickTodo {
    /// 卡片只读「今天」一组：今天空了而稍后有事时也写「今天清空啦」，不去拉稍后的上来。
    public static func cardState(_ items: [TodoItem]) -> TodoCardState {
        if items.isEmpty { return .empty }
        return items.contains { !$0.done && $0.today } ? .list : .cleared
    }

    /// 卡片右边的几条：「今天」里没做完的前 `limit` 条。
    public static func cardTodayRows(_ items: [TodoItem], limit: Int = 2) -> [TodoItem] {
        Array(ordered(items).filter { !$0.done && $0.today }.prefix(limit))
    }

    /// 卡片进度环：「今天」勾掉的占比，0...1。
    public static func todayFraction(_ items: [TodoItem], today: String) -> Double {
        let tally = todayTally(items, today: today)
        return tally.total == 0 ? 0 : Double(tally.done) / Double(tally.total)
    }
}

// MARK: - 最近 7 天

extension TodoStreak {
    /// 记下「今天」清空过的日子，最近 7 天的小圆点读这里。
    public static let historyKey = "clearedDays"
    /// 最多留几天。
    public static let historyLimit = 14

    /// 清空过的日子：记下的那几天，加上连续天数推出来的那一串（旧数据只有连续天数）。
    public static func clearedDays(_ config: WidgetConfig, calendar: Calendar = .current) -> Set<String> {
        var days = Set(config.strings(historyKey).filter(TodoDay.isKey))
        let streak = TodoStreak(config)
        if var day = streak.lastDay {
            for _ in 0..<min(streak.count, historyLimit) {
                days.insert(day)
                guard let before = TodoDay.previous(day, calendar: calendar) else { break }
                day = before
            }
        }
        return days
    }

    /// 记一天，只留最近 `historyLimit` 天。
    public static func recordHistory(_ day: String, in config: inout WidgetConfig) {
        guard TodoDay.isKey(day) else { return }
        var days = config.strings(historyKey).filter(TodoDay.isKey)
        guard !days.contains(day) else { return }
        days.append(day)
        days = Array(days.sorted().suffix(historyLimit))
        config.set(historyKey, .list(days.map { .string($0) }))
    }

    /// 最近 7 天（最早的在前，最后一个是今天）每天清空过没有。
    public static func week(_ config: WidgetConfig, today: String, calendar: Calendar = .current) -> [Bool] {
        let cleared = clearedDays(config, calendar: calendar)
        return lastWeek(today, calendar: calendar).map { cleared.contains($0) }
    }

    /// 最近 7 天的日子，最早的在前。
    public static func lastWeek(_ today: String, calendar: Calendar = .current) -> [String] {
        var days = [today]
        var day = today
        for _ in 0..<6 {
            guard let before = TodoDay.previous(day, calendar: calendar) else { break }
            days.insert(before, at: 0)
            day = before
        }
        return days
    }
}

extension TodoTimeText {
    /// 面板大标题下面的日子：“10月26日 周一”（英文 “Mon 10/26”）。
    public static func heroDate(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return tr("\(parts.month ?? 0)月\(parts.day ?? 0)日 \(weekday(date, calendar: calendar))")
    }
}
