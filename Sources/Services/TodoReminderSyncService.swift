import AppKit
import EventKit
import Foundation

/// 快速待办和系统“提醒事项”双向同步（Pro）：读写 EventKit，算法在 Core 的
/// `TodoReminderSync`。
///
/// - 只有一个实例，同一时刻只跑一轮（`running`），跑的时候又来了改动就记一笔，
///   这一轮跑完紧接着再跑一轮，不会两轮同时写同一个列表。
/// - 去抖：快速待办这边改了（`TodoLog` 里每次写清单之后）和系统提醒事项改了
///   （`.EKEventStoreChanged`，包括别的设备经 iCloud 同步过来的）都只是排一次，
///   停 0.8 秒没有新改动才真的跑。自己写回去也会发一次通知，下一轮两边一致，
///   什么也不写就停了。
/// - 只有一张快速待办卡片同步：清单里第一张打开了开关的。两张都同步同一个列表时
///   会把对方建的条目当成新的再导一遍，所以别的卡片的开关存着但不跑，面板里说明。
/// - 这里从不在启动时请求权限：没给权限就什么也不做，开关打开那一下才问
///   （`enable`）。没解锁 Pro 时开关照旧存着、不跑（`TodoReminderSync.isActive`）。
/// - 读不到列表（列表被删了、提醒事项读取失败）时这一轮不动，免得把那边当成
///   全删了、跟着把快速待办删光。
/// - 只写到期日期和时刻，不加提醒事项自己的闹钟：到点由码头弹卡片，免得同一件事
///   系统再弹一次通知。
@MainActor @Observable
final class TodoReminderSyncService {
    static let shared = TodoReminderSyncService()

    enum Problem: Equatable {
        /// 没给提醒事项权限，或者在系统设置里关掉了。
        case denied
        /// 选的列表找不到了（被删了或换了账户）。
        case missingList
        case failed(String)
    }

    /// 最近一轮没同步成的原因，面板底部显示；成功一轮就清掉。
    private(set) var problem: Problem?
    /// 最近一次同步完成的时刻。
    private(set) var lastSynced: Date?

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false

    static let debounce: Duration = .milliseconds(800)

    private init() {}

    /// 启动时接上：看着系统提醒事项的改动，并先排一轮（没有打开同步的卡片就什么也不做）。
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { TodoReminderSyncService.shared.schedule() }
        }
        schedule()
    }

    /// 每个布局里的每个小组件，和到点提醒用的是同一份。
    private var widgets: [WidgetInstance] { TimedAlertDriver.shared.widgets() }

    /// 负责同步的那一张：第一张打开了开关的快速待办。
    func owner() -> WidgetInstance? {
        widgets.first { $0.kind == .todo && TodoReminderSync.isEnabled($0.config) }
    }

    /// 快速待办这边写过清单：这张卡片在同步时排一轮。
    func localChanged(_ id: UUID) {
        guard let owner = owner(), owner.id == id,
              TodoReminderSync.isActive(owner.config, unlocked: ProAccess.isUnlocked) else { return }
        schedule()
    }

    /// 排一轮：0.8 秒内再来就重新计时。
    func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await TodoReminderSyncService.shared.run()
        }
    }

    private func run() async {
        if running {
            again = true
            return
        }
        running = true
        repeat {
            again = false
            await syncOnce()
        } while again
        running = false
    }

    // MARK: 开关和列表

    /// 打开开关：先要权限（只在这里问），记下用哪个列表，再排一轮。没给权限返回 false。
    func enable(_ instance: WidgetInstance) async -> Bool {
        var status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try? await EKEventStore().requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
            ReminderSync.store.reset()
        }
        guard status == .fullAccess else {
            problem = .denied
            return false
        }
        let saved = WidgetWriter.current(instance.id) ?? instance
        let chosen = saved.config.string(TodoReminderSync.listKey)
        let list = chosen.isEmpty ? Self.defaultList()?.calendarIdentifier : chosen
        problem = nil
        WidgetWriter.write(saved) { config in
            config.set(TodoReminderSync.enabledKey, .bool(true))
            if let list { config.set(TodoReminderSync.listKey, .string(list)) }
        }
        schedule()
        return true
    }

    /// 关掉：关联和标识都留着，再打开时接着对上，不会重复建。
    func disable(_ instance: WidgetInstance) {
        let saved = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(saved) { $0.set(TodoReminderSync.enabledKey, .bool(false)) }
        problem = nil
    }

    /// 换列表：清掉所有关联重新开始，没做完的在新列表里建一遍，原来列表里的不动。
    func choose(list id: String, for instance: WidgetInstance) {
        let saved = WidgetWriter.current(instance.id) ?? instance
        guard saved.config.string(TodoReminderSync.listKey) != id else { return }
        WidgetWriter.write(saved) { config in
            config.set(TodoReminderSync.listKey, .string(id))
            QuickTodo.store(QuickTodo.unlinkingAll(QuickTodo.items(config)), in: &config)
            QuickTodo.storeArchive(QuickTodo.unlinkingAll(QuickTodo.archive(config)), in: &config)
            TodoReminderSync.storeKnown([], in: &config)
        }
        problem = nil
        schedule()
    }

    /// 能写的列表（标识和名字），面板里的列表菜单用。没权限时是空的。
    func lists() -> [(id: String, title: String)] {
        guard ReminderSync.canWrite else { return [] }
        return ReminderSync.writableLists().map { (id: $0.calendarIdentifier, title: $0.title) }
    }

    /// 现在选的列表名字，找不到时为 nil。
    func listTitle(_ config: WidgetConfig) -> String? {
        let id = config.string(TodoReminderSync.listKey)
        guard ReminderSync.canWrite else { return nil }
        if id.isEmpty { return Self.defaultList()?.title }
        return ReminderSync.store.calendar(withIdentifier: id)?.title
    }

    private static func defaultList() -> EKCalendar? {
        ReminderSync.store.defaultCalendarForNewReminders() ?? ReminderSync.writableLists().first
    }

    // MARK: 一轮

    private func syncOnce() async {
        guard let owner = owner(), TodoReminderSync.isActive(owner.config, unlocked: ProAccess.isUnlocked) else {
            return
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            problem = .denied
            return
        }
        let store = ReminderSync.store
        var listID = owner.config.string(TodoReminderSync.listKey)
        if listID.isEmpty, let fallback = Self.defaultList() {
            // 旧数据或者打开时还没有列表：记下现在的默认列表，以后不再跟着默认列表变。
            listID = fallback.calendarIdentifier
            WidgetWriter.write(owner) { $0.set(TodoReminderSync.listKey, .string(listID)) }
        }
        guard let list = store.calendar(withIdentifier: listID), list.allowsContentModifications else {
            problem = .missingList
            return
        }
        let now = Date()
        let since = Calendar.current.date(byAdding: .day, value: -TodoReminderSync.completedWindowDays, to: now) ?? now
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        let finished = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: now,
                                                            calendars: [list])
        guard let unfinished = await Self.fetch(store, open), let completed = await Self.fetch(store, finished) else {
            problem = .failed(tr("读不到提醒事项"))
            return
        }

        // 从这里到写回都在主线程上一口气做完，中间没有 await，用户的改动插不进来。
        guard let current = WidgetWriter.current(owner.id),
              TodoReminderSync.isActive(current.config, unlocked: ProAccess.isUnlocked),
              current.config.string(TodoReminderSync.listKey) == listID else { return }
        let before = QuickTodo.items(current.config)
        let plan = TodoReminderSync.plan(items: before, archive: QuickTodo.archive(current.config),
                                         remote: unfinished + completed,
                                         known: TodoReminderSync.known(current.config),
                                         today: TodoDay.key(now))
        var items = plan.items
        var known = Set(plan.known)
        var failure: String?

        for write in plan.update {
            guard let reminder = store.calendarItem(withIdentifier: write.remoteID) as? EKReminder else { continue }
            Self.fill(reminder, from: write.item)
            if let error = Self.save(reminder, in: store) { failure = error }
        }
        for id in plan.delete {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            do {
                try store.remove(reminder, commit: true)
            } catch {
                failure = error.localizedDescription
            }
        }
        for id in plan.create {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            Self.fill(reminder, from: item)
            if let error = Self.save(reminder, in: store) {
                failure = error
                continue
            }
            items = QuickTodo.linking(id, to: reminder.calendarItemIdentifier, in: items)
            known.insert(reminder.calendarItemIdentifier)
        }

        if items != before || known != Set(TodoReminderSync.known(current.config)) {
            WidgetWriter.write(current) { config in
                QuickTodo.store(items, in: &config)
                TodoReminderSync.storeKnown(known.sorted(), in: &config)
            }
        }
        problem = failure.map(Problem.failed)
        lastSynced = now
    }

    /// 读一批提醒事项，在回调里就换成值（EKReminder 是活对象，不能带过线程）。
    /// 读取失败时为 nil，这一轮就不动。
    private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate) async -> [TodoRemoteReminder]? {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found.map { $0.map(TodoReminderSyncService.remote) })
            }
        }
    }

    /// 提醒事项的一条换成快速待办的说法：只有日期的按那天 9:00，优先级“高”算重要。
    nonisolated static func remote(_ reminder: EKReminder) -> TodoRemoteReminder {
        var due: Date?
        if let parsed = ReminderTiming.due(from: reminder.dueDateComponents) {
            due = parsed.hasTime
                ? parsed.date
                : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: parsed.date)
        }
        return TodoRemoteReminder(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                  done: reminder.isCompleted, due: due,
                                  important: (1...4).contains(reminder.priority))
    }

    /// 快速待办的一条写进提醒事项：标题、完成、到期时刻、重要，拖进来的链接也带上。
    private static func fill(_ reminder: EKReminder, from item: TodoItem) {
        reminder.title = item.text
        if reminder.isCompleted != item.done { reminder.isCompleted = item.done }
        if let at = item.remindAt {
            reminder.dueDateComponents = ReminderTiming.components(ReminderDue(date: at, hasTime: true))
        } else {
            reminder.dueDateComponents = nil
            reminder.startDateComponents = nil
        }
        if item.important {
            reminder.priority = ReminderPriority.high.rawValue
        } else if (1...4).contains(reminder.priority) {
            // 只拿掉“高”，原来设的中、低优先级不动。
            reminder.priority = ReminderPriority.none.rawValue
        }
        if reminder.url == nil, let url = item.url { reminder.url = url }
    }

    /// 存一条，失败时返回原因并丢掉没写进去的改动。
    private static func save(_ reminder: EKReminder, in store: EKEventStore) -> String? {
        do {
            try store.save(reminder, commit: true)
            return nil
        } catch {
            store.reset()
            return error.localizedDescription
        }
    }

    /// 系统设置 ▸ 隐私与安全性 ▸ 提醒事项。
    static func openPrivacySettings() {
        TodoReminderExport.openPrivacySettings()
    }
}
