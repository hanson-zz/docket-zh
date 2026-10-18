import AppKit
import EventKit
import Foundation

/// 倒计时、闹钟、快速待办和提醒事项的到点：从启动起每秒看一次，不再靠扩展栏
/// 上的卡片刷新才发现。
///
/// 原来这几种都是卡片每秒重画时顺手比一下“上一秒到这一秒之间有没有到点”，所以
/// 扩展栏自动隐藏、卡片放在文件夹里或别的布局里时既不响也不弹。现在由这一个
/// 计时器看着每个布局里的这几种小组件：
///
/// - 倒计时、闹钟：到点那一秒弹出卡片（「再来一次 / 关闭」「稍后 9 分钟 / 关闭」），
///   提示音也在这里响（倒计时 30 秒内、闹钟两分钟内每 4 秒一声，卡片设置里关了
///   提示音就不响）。卡片上点了停、关掉或稍后，弹出的那张跟着收起。
/// - 快速待办：读每张待办卡片存着的提醒时间。
/// - 提醒事项：从 EventKit 读今天到期、带具体时刻的提醒（列表跟各张提醒事项卡片的
///   筛选走，没有提醒事项卡片就不读），每 5 分钟、日子变了和系统提醒事项有改动时
///   重读一次。只读不问：没给权限就什么也不做，权限由面板去要。
///
/// 弹不弹由设置 ▸ 扩展栏 ▸ 音效 ▸ 到点弹出卡片的开关决定；关着的提醒事项和待办
/// 照旧只响一声。合盖睡眠醒来晚了太久的不补弹、不补响（`ReminderSoundDecision.maxGap`）。
/// 快到点和正在响时请系统别把计时器往后推（App Nap），见 `TimedAlertWake`。
@MainActor
final class TimedAlertDriver {
    static let shared = TimedAlertDriver()

    /// 每个布局里的每个小组件。DocketApp 接上。
    var widgets: @MainActor () -> [WidgetInstance] = { [] }

    private var timer: Timer?
    private var last = Date.now
    /// 每个计时器上一次响到第几声。
    private var chimed: [String: Int] = [:]
    private var activity: NSObjectProtocol?

    // 提醒事项
    private var reminders: [ScannedReminder] = []
    private var reminderWidget: UUID?
    private var fetchedAt: Date?
    private var fetchedDay: Date?
    private var fetchedScope: Set<String>?? = .none
    private var fetching = false
    private var storeObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard timer == nil else { return }
        last = .now
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { TimedAlertDriver.shared.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                                               queue: .main) { _ in
            MainActor.assumeIsolated { TimedAlertDriver.shared.fetchedAt = nil }
        }
    }

    func tick(now: Date = .now) {
        let old = last
        last = now
        let all = widgets()
        var upcoming: [Date] = []
        var ringing = false

        for widget in all {
            switch widget.kind {
            case .countdown:
                countdown(widget, after: old, now: now, upcoming: &upcoming, ringing: &ringing)
            case .alarm:
                alarm(widget, after: old, now: now, upcoming: &upcoming, ringing: &ringing)
            case .todo:
                todo(widget, all: all, after: old, now: now, upcoming: &upcoming)
            default:
                continue
            }
        }
        withdrawStale(all, now: now)
        remindersTick(all, after: old, now: now, upcoming: &upcoming)
        keepPrecise(TimedAlertWake.needsPrecision(next: TimedAlertWake.soonest(upcoming, after: now),
                                                  ringing: ringing, now: now))
    }

    // MARK: 倒计时

    private func countdown(_ widget: WidgetInstance, after old: Date, now: Date,
                           upcoming: inout [Date], ringing: inout Bool) {
        let config = widget.config
        if let next = TimedAlertWake.countdownNext(config, now: now) { upcoming.append(next) }
        if let due = TimedAlertScan.countdownRang(config, after: old, upTo: now),
           ReminderPopupCenter.shared.shows(.countdown) {
            let name = config.string("name")
            let alert = ReminderAlert(kind: .countdown, itemID: widget.id.uuidString, widgetID: widget.id,
                                      title: ReminderPopupText.countdownTitle(name: name), due: due,
                                      timer: TimerPopupInfo(duration: CountdownRun.duration(config),
                                                            sound: config.bool(CountdownRun.soundKey, default: true)))
            ReminderPopupCenter.shared.post([alert], now: now)
        }
        if let chime = TimedAlertScan.countdownChime(config, now: now) {
            ringing = true
            ring("c:\(widget.id):\(chime.key)", bucket: chime.bucket, kind: .countdown,
                 sound: config.bool(CountdownRun.soundKey, default: true))
        }
    }

    // MARK: 闹钟

    private func alarm(_ widget: WidgetInstance, after old: Date, now: Date,
                       upcoming: inout [Date], ringing: inout Bool) {
        let config = widget.config
        if let next = AlarmBook.upcoming(config, now: now).first?.at { upcoming.append(next) }
        if let rang = TimedAlertScan.alarmRang(config, after: old, upTo: now),
           ReminderPopupCenter.shared.shows(.alarm) {
            let info = TimerPopupInfo(alarmID: rang.item.id, clock: rang.item.time,
                                      snoozed: TimedAlertScan.alarmIsSnoozed(config, id: rang.item.id, since: rang.since),
                                      sound: config.bool(AlarmBook.soundKey, default: true))
            let alert = ReminderAlert(kind: .alarm, itemID: "\(widget.id.uuidString)#\(rang.item.id)",
                                      widgetID: widget.id, title: rang.item.title, due: rang.since, timer: info)
            ReminderPopupCenter.shared.post([alert], now: now)
        }
        if let chime = TimedAlertScan.alarmChime(config, now: now) {
            ringing = true
            ring("a:\(widget.id):\(chime.key)", bucket: chime.bucket, kind: .alarm,
                 sound: config.bool(AlarmBook.soundKey, default: true))
        }
    }

    /// 段数变了就响一声。卡片设置里关了提示音时只记下段数，不出声。
    private func ring(_ key: String, bucket: Int, kind: TimerChime.Kind, sound: Bool) {
        guard chimed[key] != bucket else { return }
        chimed[key] = bucket
        if chimed.count > 64 { chimed = [key: bucket] }
        if sound { TimerChime.play(kind) }
    }

    /// 卡片上点了停、关掉、稍后，或者关掉了那个闹钟：弹出的那张跟着收起。
    private func withdrawStale(_ all: [WidgetInstance], now: Date) {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var gone: Set<String> = []
        for alert in ReminderPopupCenter.shared.pending where alert.kind.isTimer {
            guard let id = alert.widgetID, let widget = byID[id] else {
                gone.insert(alert.id)
                continue
            }
            let still: Bool
            if alert.kind == .countdown {
                still = TimedAlertScan.countdownStillRinging(widget.config, due: alert.due, now: now)
            } else {
                still = TimedAlertScan.alarmStillRinging(widget.config, id: alert.timer?.alarmID ?? "",
                                                         since: alert.due, now: now)
            }
            if !still { gone.insert(alert.id) }
        }
        if !gone.isEmpty { ReminderPopupCenter.shared.withdraw(gone) }
    }

    // MARK: 快速待办

    private func todo(_ widget: WidgetInstance, all: [WidgetInstance], after old: Date, now: Date,
                      upcoming: inout [Date]) {
        let items = QuickTodo.items(widget.config)
        upcoming += QuickTodo.open(items).compactMap(\.remindAt)
        let due = QuickTodo.dueReminders(items, after: old, upTo: now)
        guard !due.isEmpty else { return }
        guard ReminderPopupCenter.shared.shows(.todo) else {
            ReminderSoundPlayer.shared.play(.todo, now: now)
            return
        }
        ReminderPopupCenter.shared.post(due.compactMap { ReminderPopupAlerts.todo($0, in: items, widget: widget.id) },
                                        now: now)
    }

    // MARK: 提醒事项

    private struct ScannedReminder: Sendable {
        var id: String
        var title: String
        var due: ReminderDue
        var list: String
        var highPriority: Bool
    }

    private func remindersTick(_ all: [WidgetInstance], after old: Date, now: Date, upcoming: inout [Date]) {
        let tiles = all.filter { $0.kind == .reminders }
        guard !tiles.isEmpty, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            reminders = []
            reminderWidget = nil
            return
        }
        reminderWidget = tiles.first?.id
        let scope = ReminderScanScope.lists(filters: tiles.map { $0.config.string("list") })
        let day = Calendar.current.startOfDay(for: now)
        if fetchedAt == nil || now.timeIntervalSince(fetchedAt ?? now) >= 300 || fetchedDay != day
            || fetchedScope != .some(scope) {
            fetchReminders(scope: scope, day: day, now: now)
        }
        upcoming += reminders.filter(\.due.hasTime).map(\.due.date)

        let due = ReminderSoundDecision.newlyDue(reminders.map { (id: $0.id, due: $0.due) }, after: old, upTo: now)
        guard !due.isEmpty else { return }
        guard ReminderPopupCenter.shared.shows(.reminders) else {
            ReminderSoundPlayer.shared.play(.reminders, now: now)
            return
        }
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let alerts = due.compactMap { id -> ReminderAlert? in
            guard let item = byID[id] else { return nil }
            return ReminderAlert(kind: .reminders, itemID: item.id, widgetID: reminderWidget, title: item.title,
                                 due: item.due.date, list: item.list, highPriority: item.highPriority)
        }
        ReminderPopupCenter.shared.post(alerts, now: now)
    }

    /// 今天到期（含过期）、还没完成的提醒。和提醒事项卡片读的是同一份。
    private func fetchReminders(scope: Set<String>?, day: Date, now: Date) {
        guard !fetching else { return }
        fetchedAt = now
        fetchedDay = day
        fetchedScope = .some(scope)
        let store = ReminderSync.store
        let lists = store.calendars(for: .reminder)
        let wanted = scope.map { names in lists.filter { names.contains($0.title) } } ?? lists
        // 筛选的列表都已经删掉时退回全部，和卡片一样。
        let calendars = wanted.isEmpty ? lists : wanted
        guard !calendars.isEmpty, let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
            reminders = []
            return
        }
        fetching = true
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end,
                                                              calendars: calendars)
        Task { @MainActor in
            // 在回调里就拆成值：EKReminder 是活对象，不能带过线程。
            let fetched: [ScannedReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { found in
                    let rows = (found ?? []).compactMap { reminder -> ScannedReminder? in
                        guard let due = ReminderTiming.due(from: reminder.dueDateComponents) else { return nil }
                        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return ScannedReminder(id: reminder.calendarItemIdentifier,
                                               title: title.isEmpty ? tr("新提醒事项") : title,
                                               due: due, list: reminder.calendar?.title ?? "",
                                               highPriority: (1...4).contains(reminder.priority))
                    }
                    continuation.resume(returning: rows)
                }
            }
            self.fetching = false
            self.reminders = fetched
        }
    }

    // MARK: 准时

    private func keepPrecise(_ needed: Bool) {
        if needed, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                             reason: "到点提醒")
        } else if !needed, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }
}
