import Foundation

// 快速待办面板的三个分组：今天、稍后、已完成。
//
// 分组不另外存：「今天」就是 `TodoItem.today`（旧版本的星标同一个键，升级后自动算
// 进今天），做完的进「已完成」，其余是「稍后」。三组都是同一份清单按顺序筛出来的，
// 拖动排序改的就是清单本身的顺序，所以卡片、提醒、撤销看到的顺序和面板一致。
//
// 每天第一次打开时（`applyRollover`）昨天没做完的「今天」挪到最前面，提醒时间到了
// 今天（或已经过了）的从「稍后」升进「今天」，不再在顶部弹顺延横幅。

/// 面板里的一组。
public enum TodoGroup: String, CaseIterable, Sendable {
    case today, later, done

    public var title: String {
        switch self {
        case .today: tr("今天")
        // 「稍后」这个键已经是提醒卡片上的“推迟”（Snooze），分组用带说明的键。
        case .later: tr("稍后", context: "todo")
        case .done: tr("已完成")
        }
    }
}

/// 截止时间胶囊的颜色：过期红、今天橙、以后灰。
public enum TodoDueTone: String, Sendable {
    case late, today, later
}

/// 一行行尾的截止时间胶囊。
public struct TodoDueBadge: Equatable, Sendable {
    public var text: String
    public var tone: TodoDueTone

    public init(text: String, tone: TodoDueTone) {
        self.text = text
        self.tone = tone
    }
}

/// 面板顶部一行：今天还剩几件、已完成几件，以及细进度条的比例。
public struct TodoProgress: Equatable, Sendable {
    public var left: Int
    public var done: Int

    public init(left: Int, done: Int) {
        self.left = max(0, left)
        self.done = max(0, done)
    }

    public var total: Int { left + done }

    /// 0...1，一件都没有时是 0。
    public var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    /// “今天还剩 3 件 · 已完成 5”。
    public var line: String {
        tr("今天还剩 \(left) 件 · 已完成 \(done)")
    }
}

extension QuickTodo {
    /// 这一条在哪一组。
    public static func group(of item: TodoItem) -> TodoGroup {
        if item.done { return .done }
        return item.today ? .today : .later
    }

    /// 某一组的条目，保持清单里的顺序。
    public static func items(in group: TodoGroup, of items: [TodoItem]) -> [TodoItem] {
        ordered(items).filter { self.group(of: $0) == group }
    }

    public static func progress(_ items: [TodoItem]) -> TodoProgress {
        let list = ordered(items)
        return TodoProgress(left: list.filter { group(of: $0) == .today }.count,
                            done: list.filter(\.done).count)
    }

    /// 昨天（或更早）放进「今天」还没做完的：截止胶囊标红。
    public static func isCarried(_ item: TodoItem, today: String) -> Bool {
        guard item.today, !item.done else { return false }
        let since = item.todaySince ?? item.addedDay ?? today
        return since < today
    }

    // MARK: 拖动

    /// 把一条拖到某一组、某一条前面（`before` 为 nil 时放在这一组最后）。
    ///
    /// 拖进「今天」就是放进今天（记下今天，替代原来的星标）；拖回「稍后」清掉。
    /// 「已完成」不接受拖进来，原样返回。拖到自己前面也原样返回。
    public static func moving(_ id: String, to group: TodoGroup, before target: String?,
                              in items: [TodoItem], today: String) -> [TodoItem] {
        let list = ordered(items)
        guard group != .done, var item = list.first(where: { $0.id == id }), !item.done,
              target != id else { return list }
        switch group {
        case .today:
            if !item.today { item.todaySince = today }
            item.today = true
        case .later:
            item.today = false
            item.todaySince = nil
        case .done:
            return list
        }
        var rest = list.filter { $0.id != id }
        let index: Int
        if let target, let at = rest.firstIndex(where: { $0.id == target }), !rest[at].done,
           self.group(of: rest[at]) == group {
            index = at
        } else if let last = rest.lastIndex(where: { self.group(of: $0) == group }) {
            index = last + 1
        } else if group == .today {
            // 今天还空着：放在所有没做完的最前面。
            index = 0
        } else {
            index = rest.firstIndex(where: \.done) ?? rest.count
        }
        rest.insert(item, at: index)
        return ordered(rest)
    }

    /// 标为重要，或者取消。
    public static func togglingImportant(_ id: String, in items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            guard item.id == id else { return item }
            var changed = item
            changed.important.toggle()
            return changed
        })
    }

    // MARK: 新的一天

    /// 新的一天收拾「今天」：昨天没做完的（以及提醒时间已经过了、从「稍后」升上来的）
    /// 挪到清单最前面，顺序不变；提醒时间到了今天的从「稍后」升进「今天」。
    ///
    /// 旧版本标了星没有 `p=` 的，按记下那天算，昨天以前记下的就是顺下来的。
    public static func planningToday(_ items: [TodoItem], today: String,
                                     calendar: Calendar = .current) -> [TodoItem] {
        var carried: [TodoItem] = []
        var rest: [TodoItem] = []
        for var item in ordered(items) {
            guard !item.done else { rest.append(item); continue }
            if item.today {
                if (item.todaySince ?? item.addedDay ?? today) < today {
                    if item.todaySince == nil { item.todaySince = item.addedDay }
                    carried.append(item)
                } else {
                    if item.todaySince == nil { item.todaySince = today }
                    rest.append(item)
                }
                continue
            }
            if let at = item.remindAt {
                let day = TodoDay.key(at, calendar: calendar)
                if day < today {
                    item.today = true
                    item.todaySince = day
                    carried.append(item)
                    continue
                }
                if day == today {
                    item.today = true
                    item.todaySince = today
                }
            }
            rest.append(item)
        }
        return ordered(carried + rest)
    }

    // MARK: 截止时间胶囊

    /// 行尾胶囊上的字和颜色。有提醒时间时按提醒时间：过了红、今天橙、以后灰；
    /// 没有提醒时间但是昨天顺下来的，写“昨天”（更早写日期）标红。都没有时为 nil。
    public static func dueBadge(_ item: TodoItem, now: Date, calendar: Calendar = .current) -> TodoDueBadge? {
        guard !item.done else { return nil }
        let today = TodoDay.key(now, calendar: calendar)
        if let at = item.remindAt {
            let tone: TodoDueTone
            if at <= now {
                tone = .late
            } else if TodoDay.key(at, calendar: calendar) == today {
                tone = .today
            } else {
                tone = .later
            }
            return TodoDueBadge(text: TodoTimeText.due(at, now: now, calendar: calendar), tone: tone)
        }
        if isCarried(item, today: today), let since = item.todaySince ?? item.addedDay {
            return TodoDueBadge(text: TodoTimeText.day(since, today: today, calendar: calendar), tone: .late)
        }
        return nil
    }
}
