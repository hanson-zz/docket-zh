import Foundation

// 快速待办的“已完成”收起区。
//
// 第二天收拾清单时，昨天以前做完的不再直接删掉，而是挪进单独的 `archive` 列表：
// 面板底部“已收起”可以展开看、可以恢复成没做完的、也可以单条删掉。做完那天起
// 保留 7 天（做完的第二天收起，第 8 天收拾时清掉），满 100 条时最早做完的先清。
//
// 单独一个键而不是在原列表里加标记：卡片、计数、“今天三件事”、提醒到点、顺延
// 这些读的都是 `items`，收起的条目根本不在里面，就不会被误算进去。

extension QuickTodo {
    /// 收起区存在小组件配置里的键，每条和 `items` 一样的写法。
    public static let archiveKey = "archive"
    /// 做完以后在收起区留几天。
    public static let archiveDays = 7

    /// 收起区里的条目，最近做完的在前。
    public static func archive(_ config: WidgetConfig) -> [TodoItem] {
        var seen = Set<String>()
        var result: [TodoItem] = []
        for (index, raw) in config.strings(archiveKey).enumerated() {
            guard var item = TodoItem(decoding: raw, fallbackID: "z\(index)") else { continue }
            if seen.contains(item.id) { item.id = "\(item.id)-\(index)" }
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    public static func storeArchive(_ archive: [TodoItem], in config: inout WidgetConfig) {
        config.set(archiveKey, archive.isEmpty ? nil : .list(archive.map { .string($0.encoded) }))
    }

    /// 收拾时要挪进收起区的：昨天以前做完的（`rollingOver` 从清单里拿掉的那些）。
    /// 收起的不再是“今天三件事”，提醒时间也清掉，恢复时不会弹一张过时的卡片。
    public static func archiving(_ items: [TodoItem], today: String) -> [TodoItem] {
        items.compactMap { item in
            guard item.done, let finished = item.doneDay, finished < today else { return nil }
            var kept = item
            kept.today = false
            kept.remindAt = nil
            return kept
        }
    }

    /// 只留做完不满 `archiveDays` 天的，最近做完的在前，最多 `maxItems` 条。
    public static func prunedArchive(_ archive: [TodoItem], today: String,
                                     calendar: Calendar = .current) -> [TodoItem] {
        let cutoff = archiveCutoff(today: today, calendar: calendar)
        let kept = archive.filter { item in
            guard let day = item.doneDay else { return false }
            return cutoff.map { day >= $0 } ?? true
        }
        // 稳定排序：同一天做完的保持原来的先后。
        let sorted = kept.enumerated().sorted { lhs, rhs in
            let a = lhs.element.doneDay ?? "", b = rhs.element.doneDay ?? ""
            return a == b ? lhs.offset < rhs.offset : a > b
        }.map(\.element)
        return Array(sorted.prefix(maxItems))
    }

    /// 收起区最早还留着哪一天做完的：今天往前 `archiveDays` 天。
    public static func archiveCutoff(today: String, calendar: Calendar = .current) -> String? {
        guard let noon = TodoDay.date(today, calendar: calendar),
              let start = calendar.date(byAdding: .day, value: -archiveDays, to: noon) else { return nil }
        return TodoDay.key(start, calendar: calendar)
    }

    /// 恢复一条：从收起区拿出来，放回清单末尾当作今天没做完的。清单满了不动。
    public static func restoring(_ id: String, items: [TodoItem], archive: [TodoItem],
                                 today: String) -> (items: [TodoItem], archive: [TodoItem]) {
        guard let item = archive.first(where: { $0.id == id }), items.count < maxItems else {
            return (ordered(items), archive)
        }
        var back = item
        back.done = false
        back.doneDay = nil
        back.addedDay = today
        // 收起区里的 id 可能和清单里新记的撞上，撞了换一个。
        if items.contains(where: { $0.id == back.id }) { back.id = TodoItem.newID() }
        let current = ordered(items)
        return (open(current) + [back] + current.filter(\.done), archive.filter { $0.id != id })
    }

    /// 从收起区删掉一条。
    public static func removingArchived(_ id: String, from archive: [TodoItem]) -> [TodoItem] {
        archive.filter { $0.id != id }
    }

    /// 收起区一行右边的日子：“昨天”，更早的写“10/16”。
    public static func archivedDayLabel(_ item: TodoItem, today: String, calendar: Calendar = .current) -> String {
        guard let day = item.doneDay, let date = TodoDay.date(day, calendar: calendar) else { return "" }
        if TodoDay.previous(today, calendar: calendar) == day { return tr("昨天") }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
}

// MARK: - 快捷键小框记到哪一个

extension QuickTodo {
    /// 全局快捷键小框记到哪一个快速待办：扩展栏上从头数第一个；顶层没有时，
    /// 再按顺序找分组里的（分组里还能套分组，一层层往里找）。顶层优先，是因为
    /// 摆在外面的那个一眼看得到，记进去马上能看见。
    public static func captureTarget(in items: [DockItem]) -> WidgetInstance? {
        if let top = items.lazy.compactMap(\.widget).first(where: { $0.kind == .todo }) { return top }
        for item in items {
            if case .group(let group) = item, let found = captureTarget(in: group.items) { return found }
        }
        return nil
    }
}

extension ShelfItems {
    /// 换掉一个小组件（按 id），放在分组里的（分组里再套分组也算）一样找得到。
    /// 找不到时是 nil。小组件自己写设置（`WidgetWriter`）走这里，分组里的快速
    /// 待办、股票这些写下的东西才不会丢。
    public static func replacingWidget(_ instance: WidgetInstance, in items: [DockItem]) -> [DockItem]? {
        var result = items
        for index in result.indices {
            switch result[index] {
            case .widget(let widget) where widget.id == instance.id:
                result[index] = .widget(instance)
                return result
            case .group(var group):
                if let inner = replacingWidget(instance, in: group.items) {
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
