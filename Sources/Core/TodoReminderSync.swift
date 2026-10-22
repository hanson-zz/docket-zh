import Foundation

// 快速待办和系统“提醒事项”双向同步（Pro）：面板底部开关，选一个提醒事项列表。
//
// 每条记着对面那一条的标识（`TodoItem.externalID`）和上次两边一致时的指纹
// （`syncMark`）。同步时拿两边现在的指纹和它比，就知道是哪边改过：
// - 只有提醒事项改过：照提醒事项改快速待办（标题、完成、提醒时间、重要）。
// - 快速待办改过（或者两边都改过）：快速待办为准，写回提醒事项。
// - 提醒事项那边没了：上次同步过的（在 `known` 里），快速待办这边没改过就跟着删，
//   改过就当新的重新建；没同步过的（换了列表）只解开关联。
// - 快速待办这边没了：上次同步过的提醒事项跟着删；已经完成的留着，只是不再关联
//   （做完 7 天后从“已收起”里清掉的，不去删提醒事项里的完成记录）。
// - 提醒事项里新出现、还没完成的：在快速待办里新建一条。
//
// 这里只算该做什么，读写 EventKit 在 Services 里（TodoReminderSyncService）。

/// 提醒事项那边的一条，读出来时已经换成快速待办的说法。
public struct TodoRemoteReminder: Equatable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    /// 到期时间。只有日期没有钟点的，按那天 9:00 算（快速待办总带钟点）。
    public var due: Date?
    /// 优先级是“高”。
    public var important: Bool

    public init(id: String, title: String, done: Bool = false, due: Date? = nil, important: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
        self.due = due.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded(.down) * 60) }
        self.important = important
    }
}

/// 一次同步算出来的结果。
public struct TodoSyncPlan: Equatable, Sendable {
    /// 同步后的快速待办（改过、新建、删掉的都已经算进去）。
    public var items: [TodoItem]
    /// 要在提醒事项里新建的（快速待办里的 id）。建好后用 `QuickTodo.linking` 记下标识。
    public var create: [String]
    /// 要写回提醒事项的：提醒事项标识和快速待办里的那一条。
    public var update: [TodoSyncWrite]
    /// 要从提醒事项里删掉的标识。
    public var delete: [String]
    /// 同步后关联着的提醒事项标识，存起来下次分辨“对面删了”还是“没同步过”。
    public var known: [String]

    public init(items: [TodoItem], create: [String] = [], update: [TodoSyncWrite] = [],
                delete: [String] = [], known: [String] = []) {
        self.items = items
        self.create = create
        self.update = update
        self.delete = delete
        self.known = known
    }

    /// 只改了快速待办自己（或什么都没改），不用碰提醒事项。
    public var touchesRemote: Bool { !create.isEmpty || !update.isEmpty || !delete.isEmpty }
}

public struct TodoSyncWrite: Equatable, Sendable {
    public var remoteID: String
    public var item: TodoItem

    public init(remoteID: String, item: TodoItem) {
        self.remoteID = remoteID
        self.item = item
    }
}

public enum TodoReminderSync {
    /// 开关存在小组件自己的配置里（面板底部，不在设置页）。
    public static let enabledKey = "syncReminders"
    /// 选的提醒事项列表（`calendarIdentifier`），没选时用系统默认列表。
    public static let listKey = "syncList"
    /// 上次同步后关联着的提醒事项标识。
    public static let knownKey = "syncKnown"
    /// 提醒事项里已完成的读多少天以内的（够覆盖“已收起”的 7 天）。
    public static let completedWindowDays = 8

    public static func isEnabled(_ config: WidgetConfig) -> Bool {
        config.bool(enabledKey, default: false)
    }

    /// 真的在同步：开关开着，并且解锁了 Pro。没解锁时开关照旧存着，只是不跑。
    public static func isActive(_ config: WidgetConfig, unlocked: Bool) -> Bool {
        isEnabled(config) && ProLicenseGate.canSyncTodoReminders(unlocked: unlocked)
    }

    public static func known(_ config: WidgetConfig) -> [String] {
        config.strings(knownKey)
    }

    public static func storeKnown(_ ids: [String], in config: inout WidgetConfig) {
        config.set(knownKey, ids.isEmpty ? nil : .list(ids.map { .string($0) }))
    }

    // MARK: 指纹

    /// 标题、完成、提醒时间（到分钟）、重要拼起来的指纹。FNV-1a，进程之间稳定。
    public static func fingerprint(title: String, done: Bool, due: Date?, important: Bool) -> String {
        let minutes = due.map { String(Int(($0.timeIntervalSince1970 / 60).rounded(.down))) } ?? "-"
        let raw = "\(title)\u{1F}\(done ? 1 : 0)\u{1F}\(minutes)\u{1F}\(important ? 1 : 0)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    public static func fingerprint(_ item: TodoItem) -> String {
        fingerprint(title: item.text, done: item.done, due: item.remindAt, important: item.important)
    }

    public static func fingerprint(_ remote: TodoRemoteReminder) -> String {
        fingerprint(title: QuickTodo.clean(remote.title) ?? remote.title, done: remote.done,
                    due: remote.due, important: remote.important)
    }

    // MARK: 算

    /// - Parameters:
    ///   - items: 快速待办现在的清单。
    ///   - archive: “已收起”里的（只用来认出它们关联的提醒事项还在用，不改它们）。
    ///   - remote: 选中列表里没完成的，加上最近 `completedWindowDays` 天完成的。
    ///   - known: 上次同步后关联着的提醒事项标识。
    ///   - today: 今天（`TodoDay.key`），新建、完成时记日子用。
    public static func plan(items: [TodoItem], archive: [TodoItem], remote: [TodoRemoteReminder],
                            known: [String], today: String, newID: () -> String = TodoItem.newID) -> TodoSyncPlan {
        let knownSet = Set(known)
        var remoteByID: [String: TodoRemoteReminder] = [:]
        for reminder in remote where remoteByID[reminder.id] == nil { remoteByID[reminder.id] = reminder }

        var result: [TodoItem] = []
        var create: [String] = []
        var update: [TodoSyncWrite] = []
        var linked = Set(archive.compactMap(\.externalID))

        for var item in QuickTodo.ordered(items) {
            guard let external = item.externalID else {
                if !item.done { create.append(item.id) }
                result.append(item)
                continue
            }
            let local = fingerprint(item)
            guard let reminder = remoteByID[external] else {
                if knownSet.contains(external) {
                    // 提醒事项那边删了（或挪去了别的列表）。
                    if item.done {
                        item.externalID = nil
                        item.syncMark = nil
                        result.append(item)
                    } else if item.syncMark == local {
                        // 快速待办这边没改过：跟着删。
                        continue
                    } else {
                        item.externalID = nil
                        item.syncMark = nil
                        create.append(item.id)
                        result.append(item)
                    }
                } else {
                    // 没同步过这个标识（换了列表）：解开，没做完的在新列表里建。
                    item.externalID = nil
                    item.syncMark = nil
                    if !item.done { create.append(item.id) }
                    result.append(item)
                }
                continue
            }
            linked.insert(external)
            let other = fingerprint(reminder)
            if local == other {
                item.syncMark = local
            } else if item.syncMark == local {
                // 只有提醒事项改过：照着改。
                item = applying(reminder, to: item, today: today)
                item.syncMark = fingerprint(item)
            } else {
                update.append(TodoSyncWrite(remoteID: external, item: item))
                item.syncMark = local
            }
            result.append(item)
        }

        var delete: [String] = []
        let present = Set(result.compactMap(\.externalID)).union(linked)
        for reminder in remote where !present.contains(reminder.id) {
            if knownSet.contains(reminder.id) {
                // 快速待办这边删了：没完成的跟着删，完成的留在提醒事项里。
                if !reminder.done { delete.append(reminder.id) }
                continue
            }
            guard !reminder.done, let words = QuickTodo.clean(reminder.title),
                  result.count < QuickTodo.maxItems else { continue }
            let dueDay = reminder.due.map { TodoDay.key($0) }
            let isToday = dueDay.map { $0 <= today } ?? false
            var item = TodoItem(id: newID(), text: words, today: isToday, addedDay: today,
                                remindAt: reminder.due, todaySince: isToday ? today : nil,
                                important: reminder.important, externalID: reminder.id)
            item.syncMark = fingerprint(item)
            result.append(item)
            linked.insert(reminder.id)
        }

        let keep = Set(result.compactMap(\.externalID)).union(linked).subtracting(delete)
        return TodoSyncPlan(items: QuickTodo.ordered(result), create: create, update: update,
                            delete: delete, known: keep.sorted())
    }

    /// 照提醒事项改一条：标题、完成（记今天）、提醒时间、重要。分组跟着提醒时间走：
    /// 改到今天或更早就进「今天」。
    static func applying(_ reminder: TodoRemoteReminder, to item: TodoItem, today: String) -> TodoItem {
        var changed = item
        if let words = QuickTodo.clean(reminder.title) { changed.text = words }
        if reminder.done != item.done {
            changed.done = reminder.done
            changed.doneDay = reminder.done ? today : nil
        }
        if reminder.due != item.remindAt {
            changed.remindAt = reminder.due
            if let due = reminder.due, TodoDay.key(due) <= today, !changed.today {
                changed.today = true
                changed.todaySince = today
            }
        }
        changed.important = reminder.important
        return changed
    }
}

extension QuickTodo {
    /// 在提醒事项里建好以后，记下对面的标识和这时的指纹。
    public static func linking(_ id: String, to external: String, in items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            guard item.id == id else { return item }
            var linked = item
            linked.externalID = external
            linked.syncMark = TodoReminderSync.fingerprint(item)
            return linked
        })
    }

    /// 换列表或关掉后重新开始：清掉所有关联。
    public static func unlinkingAll(_ items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            var plain = item
            plain.externalID = nil
            plain.syncMark = nil
            return plain
        })
    }
}
