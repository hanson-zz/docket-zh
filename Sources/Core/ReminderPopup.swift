import Foundation

// 到点提醒弹出页：提醒事项、喝水、待办到点时，从刘海下方滑出一张深色玻璃卡片。
//
// 这里只放纯逻辑（哪几类弹、几秒内的几条合成一张、自动收起的计时、卡片上的
// 几行字、推迟落在哪一刻、窗口摆在哪），窗口和画法在 App/ReminderPopupController.swift，
// 方便单独测试。声音照旧走 `ReminderSoundPlayer`，判断见 ReminderSound.swift。

// MARK: - 设置

/// 设置 ▸ 扩展栏 ▸ 音效 ▸ 提醒音效旁边的「到点弹出卡片」，每类各自一个开关，默认都开。
///
/// 喝水关掉时退回原来的系统通知；提醒事项和待办关掉时只响一声（音效照旧）；
/// 倒计时和闹钟关掉时照样到点响、卡片照样变橙，只是不弹这张卡片。
public struct ReminderPopupSettings: Codable, Hashable, Sendable {
    public var reminders: Bool = true
    public var water: Bool = true
    public var todo: Bool = true
    public var countdown: Bool = true
    public var alarm: Bool = true

    public init() {}

    public func enabled(_ kind: ReminderSoundKind) -> Bool {
        switch kind {
        case .reminders: reminders
        case .water: water
        case .todo: todo
        case .countdown: countdown
        case .alarm: alarm
        }
    }

    public mutating func setEnabled(_ on: Bool, for kind: ReminderSoundKind) {
        switch kind {
        case .reminders: reminders = on
        case .water: water = on
        case .todo: todo = on
        case .countdown: countdown = on
        case .alarm: alarm = on
        }
    }

    /// 宽松解码：旧的状态文件没有这一项，缺哪个就是默认的开。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reminders = (try? c.decodeIfPresent(Bool.self, forKey: .reminders)) ?? true
        water = (try? c.decodeIfPresent(Bool.self, forKey: .water)) ?? true
        todo = (try? c.decodeIfPresent(Bool.self, forKey: .todo)) ?? true
        countdown = (try? c.decodeIfPresent(Bool.self, forKey: .countdown)) ?? true
        alarm = (try? c.decodeIfPresent(Bool.self, forKey: .alarm)) ?? true
    }
}

public enum ReminderPopupDecision {
    /// 这一类到点时弹不弹卡片。
    public static func shows(_ kind: ReminderSoundKind, settings: ReminderPopupSettings) -> Bool {
        settings.enabled(kind)
    }

    /// 喝水还要不要排系统通知：弹卡片时不排，免得同一次提醒出现两回。
    public static func waterUsesNotification(_ settings: ReminderPopupSettings) -> Bool {
        !settings.water
    }

    /// 应用里的计时器到点时晚了多久还弹：合盖睡眠醒来不补弹几小时前的提醒，
    /// 和提醒音效不补响一样。
    public static func isFresh(due: Date, now: Date) -> Bool {
        let late = now.timeIntervalSince(due)
        return late >= -1 && late <= ReminderSoundDecision.maxGap
    }

    /// 不点的话多久自动收起。闹钟要响两分钟，卡片陪它响完；其余 30 秒。
    public static func autoHideSeconds(_ kind: ReminderSoundKind) -> TimeInterval {
        switch kind {
        case .alarm: TimeInterval(AlarmBook.chimeSeconds)
        case .countdown: max(ReminderPopupCountdown.defaultDuration, TimeInterval(CountdownRun.chimeSeconds))
        case .reminders, .water, .todo: ReminderPopupCountdown.defaultDuration
        }
    }

    /// 按 Esc 时要不要连计时一起停：倒计时和闹钟的卡片就是“响着的那个”，
    /// 关掉卡片却让它接着响没有意义；其余几类 Esc 只收起卡片。
    public static func escapeStops(_ kind: ReminderSoundKind) -> Bool {
        kind.isTimer
    }
}

// MARK: - 一条到点的提醒

/// 喝水卡片上的进度。
public struct WaterPopupInfo: Equatable, Hashable, Sendable {
    public var total: Int
    public var goal: Int
    /// 设置里的一杯容量（毫升）。
    public var cup: Int
    public var ounces: Bool
    /// 选的角色（`WaterCharacter` 的 rawValue），还没解锁的角色（锁着的 Pro 角色、还没达标解锁的柴犬橘猫）已经换成小熊猫。
    public var character: String
    public var lastDrink: Date?

    public init(total: Int, goal: Int, cup: Int, ounces: Bool, character: String, lastDrink: Date?) {
        self.total = total
        self.goal = goal
        self.cup = cup
        self.ounces = ounces
        self.character = character
        self.lastDrink = lastDrink
    }

    public var filledCups: Int { WaterPetCards.filledCups(total: total, goal: goal) }
    public var cupsLeft: Int { WaterCupPage.cupsLeft(total: total, goal: goal, cup: cup) }
}

/// 待办卡片上的来源和“今天三件事”。
public struct TodoPopupInfo: Equatable, Hashable, Sendable {
    public struct Row: Equatable, Hashable, Sendable {
        public var text: String
        public var done: Bool

        public init(text: String, done: Bool) {
            self.text = text
            self.done = done
        }
    }

    /// 是不是“今天三件事”之一。
    public var today: Bool
    /// 记下的那天（`TodoDay` 的键）。
    public var addedDay: String?
    /// 今天三件事里的另外几条（这一条是其中之一时）。
    public var others: [Row]
    /// 今天三件事做完几条、一共几条。
    public var todayDone: Int
    public var todayTotal: Int

    public init(today: Bool, addedDay: String?, others: [Row] = [], todayDone: Int = 0, todayTotal: Int = 0) {
        self.today = today
        self.addedDay = addedDay
        self.others = others
        self.todayDone = todayDone
        self.todayTotal = todayTotal
    }

    /// 从清单里取出一条的来源。
    public static func from(_ item: TodoItem, in items: [TodoItem]) -> TodoPopupInfo {
        let marked = QuickTodo.todayItems(items)
        guard item.today else { return TodoPopupInfo(today: false, addedDay: item.addedDay) }
        let others = marked.filter { $0.id != item.id }.map { Row(text: $0.text, done: $0.done) }
        return TodoPopupInfo(today: true, addedDay: item.addedDay, others: others,
                             todayDone: marked.filter(\.done).count, todayTotal: marked.count)
    }
}

/// 倒计时和闹钟卡片上的东西。
public struct TimerPopupInfo: Equatable, Hashable, Sendable {
    /// 倒计时这一轮的时长（秒），「再来一次」照这个再计。闹钟为 0。
    public var duration: TimeInterval
    /// 闹钟在小组件里的 id；倒计时是同时跑的其余计时器的 id，第一个计时器为空。
    public var alarmID: String
    /// 闹钟定的时刻“14:30”；倒计时为空。
    public var clock: String
    /// 这次是稍后再响的那一次。
    public var snoozed: Bool
    /// 卡片设置里提示音开着。
    public var sound: Bool

    public init(duration: TimeInterval = 0, alarmID: String = "", clock: String = "",
                snoozed: Bool = false, sound: Bool = true) {
        self.duration = duration
        self.alarmID = alarmID
        self.clock = clock
        self.snoozed = snoozed
        self.sound = sound
    }
}

/// 一条到点的提醒，从卡片、计时器交给弹出页。
public struct ReminderAlert: Equatable, Hashable, Sendable, Identifiable {
    public var kind: ReminderSoundKind
    /// 提醒事项的 `calendarItemIdentifier`、待办的 id，喝水是小组件的 id。
    public var itemID: String
    /// 点卡片主体打开哪个小组件的面板。
    public var widgetID: UUID?
    public var title: String
    /// 到点的那一刻。
    public var due: Date
    /// 提醒事项所在的列表。
    public var list: String
    public var highPriority: Bool
    public var water: WaterPopupInfo?
    public var todo: TodoPopupInfo?
    public var timer: TimerPopupInfo?

    public init(kind: ReminderSoundKind, itemID: String, widgetID: UUID? = nil, title: String, due: Date,
                list: String = "", highPriority: Bool = false,
                water: WaterPopupInfo? = nil, todo: TodoPopupInfo? = nil, timer: TimerPopupInfo? = nil) {
        self.kind = kind
        self.itemID = itemID
        self.widgetID = widgetID
        self.title = title
        self.due = due
        self.list = list
        self.highPriority = highPriority
        self.water = water
        self.todo = todo
        self.timer = timer
    }

    /// 同一条同一时刻只算一次：几张卡片同时看到同一条到点，也只弹一张。
    public var id: String { "\(kind.rawValue):\(itemID):\(Int(due.timeIntervalSince1970.rounded(.down)))" }
}

// MARK: - 合并

/// 一张弹出卡片：同一类、几秒内一起到点的几条。第一条是大字标题，其余列在下面。
public struct ReminderPopupCard: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ReminderSoundKind
    public var alerts: [ReminderAlert]
    public var postedAt: Date

    public var primary: ReminderAlert? { alerts.first }
    public var others: [ReminderAlert] { Array(alerts.dropFirst()) }
}

/// 弹出页的队列：几秒内同一类到点的几条合成一张，别的类排在后面（底下叠一层），
/// 前一张收起后再出下一张。几张卡片看到同一条到点只收一次。
public struct ReminderPopupQueue: Sendable {
    /// 几秒内到点的算“一起到点”，和提醒音效合成一声的窗口一样长。
    public static let mergeWindow: TimeInterval = ReminderSoundGate.defaultWindow
    /// 记住弹过哪些多久，免得另一张卡片晚一秒看到同一条又弹一次。
    public static let rememberFor: TimeInterval = 10 * 60

    public private(set) var cards: [ReminderPopupCard] = []
    private var seen: [String: Date] = [:]

    public init() {}

    public enum Outcome: Equatable, Sendable {
        /// 新的一张，现在就显示。
        case shown
        /// 并进已有的一张，不再另响。
        case merged
        /// 新的一张，排在正显示的那张后面。
        case queued
        /// 已经弹过。
        case ignored
    }

    public var front: ReminderPopupCard? { cards.first }

    /// 所有还没收起的（正显示的和排着的）。
    public var alerts: [ReminderAlert] { cards.flatMap(\.alerts) }

    /// 卡片底下要不要叠一层：这一张合了几条，或者后面还排着。
    public var stacked: Bool { cards.count > 1 || (front?.alerts.count ?? 0) > 1 }

    public mutating func post(_ alert: ReminderAlert, now: Date, cardID: UUID = UUID()) -> Outcome {
        seen = seen.filter { now.timeIntervalSince($0.value) < Self.rememberFor }
        guard seen[alert.id] == nil else { return .ignored }
        seen[alert.id] = now

        // 同一条又到点（喝水没理会又提醒一次、待办稍后又到点）：换掉原来的那条。
        for index in cards.indices {
            if let at = cards[index].alerts.firstIndex(where: { $0.kind == alert.kind && $0.itemID == alert.itemID }) {
                cards[index].alerts[at] = alert
                cards[index].alerts = Self.sorted(cards[index].alerts)
                return .merged
            }
        }
        if let index = cards.firstIndex(where: {
            $0.kind == alert.kind && now >= $0.postedAt && now.timeIntervalSince($0.postedAt) < Self.mergeWindow
        }) {
            cards[index].alerts = Self.sorted(cards[index].alerts + [alert])
            return .merged
        }
        cards.append(ReminderPopupCard(id: cardID, kind: alert.kind, alerts: [alert], postedAt: now))
        return cards.count == 1 ? .shown : .queued
    }

    /// 先到点的在前，同一时刻按标题。
    static func sorted(_ alerts: [ReminderAlert]) -> [ReminderAlert] {
        alerts.sorted { $0.due == $1.due ? $0.title < $1.title : $0.due < $1.due }
    }

    /// 收起正显示的那张（Esc、自动收起、点了卡片主体）。
    public mutating func dismissFront() {
        guard !cards.isEmpty else { return }
        cards.removeFirst()
    }

    /// 一条处理完了（完成、推迟、加了一杯）：从它那张里拿掉，那张空了就收起。
    public mutating func resolve(_ alertID: String) {
        for index in cards.indices.reversed() {
            cards[index].alerts.removeAll { $0.id == alertID }
            if cards[index].alerts.isEmpty { cards.remove(at: index) }
        }
    }

    /// 换掉一条的内容（加了一杯以后的新进度），位置不变。
    public mutating func update(_ alert: ReminderAlert) {
        for index in cards.indices {
            if let at = cards[index].alerts.firstIndex(where: { $0.id == alert.id }) {
                cards[index].alerts[at] = alert
            }
        }
    }

    public mutating func clear() {
        cards.removeAll()
    }
}

// MARK: - 自动收起

/// 不点的话约 30 秒后自动收起；指针停在卡片上时暂停，移开后接着数。
///
/// 时长固定，不放进设置：卡片本来就不挡事（不抢焦点、点穿不了的只有卡片本身），
/// 多一个选项不如少一个。
public struct ReminderPopupCountdown: Equatable, Sendable {
    public static let defaultDuration: TimeInterval = 30

    public let duration: TimeInterval
    private var startedAt: Date?
    private var spent: TimeInterval = 0

    public init(duration: TimeInterval = ReminderPopupCountdown.defaultDuration) {
        self.duration = max(1, duration)
    }

    /// 新的一张出现：从头数。
    public mutating func start(at now: Date) {
        spent = 0
        startedAt = now
    }

    public var isPaused: Bool { startedAt == nil }

    /// 指针移上卡片。
    public mutating func pause(at now: Date) {
        guard let startedAt else { return }
        spent += max(0, now.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    /// 指针移开：接着数，但至少再留几秒，免得一移开就收走。
    public mutating func resume(at now: Date, atLeast floor: TimeInterval = 5) {
        guard startedAt == nil else { return }
        spent = min(spent, max(0, duration - floor))
        startedAt = now
    }

    public func remaining(at now: Date) -> TimeInterval {
        let running = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, duration - spent - running)
    }

    public func isExpired(at now: Date) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }
}

// MARK: - 推迟

/// 提醒事项卡片上「推迟」的三个去处。
public enum ReminderSnoozeChoice: String, CaseIterable, Sendable {
    case hour, tonight, tomorrow

    public var title: String {
        switch self {
        case .hour: tr("1 小时")
        case .tonight: tr("今晚")
        case .tomorrow: tr("明天")
        }
    }
}

public enum ReminderPopupSnooze {
    /// “今晚”是晚上 8 点。
    public static let tonightHour = 20
    /// 喝水的「稍后」。
    public static let waterMinutes = 15
    /// 待办的「稍后」。
    public static let todoMinutes = 10
    /// 闹钟的「稍后」，和卡片、面板上的一样。
    public static var alarmMinutes: Int { AlarmBook.snoozeMinutes }

    /// 今晚 8 点；已经不到 10 分钟就到或者过了时为 nil（菜单里不列）。
    public static func tonight(now: Date, calendar: Calendar = .current) -> Date? {
        guard let at = calendar.date(bySettingHour: tonightHour, minute: 0, second: 0, of: now),
              at.timeIntervalSince(now) >= 10 * 60 else { return nil }
        return at
    }

    /// 菜单里列哪几个。
    public static func choices(now: Date, calendar: Calendar = .current) -> [ReminderSnoozeChoice] {
        ReminderSnoozeChoice.allCases.filter { $0 != .tonight || tonight(now: now, calendar: calendar) != nil }
    }

    /// 提醒事项推迟后的到期时间。“1 小时”和卡片悬停时的推迟一样（过了的从现在
    /// 往后推）；“明天”是明天的同一时刻。
    public static func reminderDue(_ choice: ReminderSnoozeChoice, from due: ReminderDue, now: Date,
                                   calendar: Calendar = .current) -> ReminderDue? {
        switch choice {
        case .hour: return ReminderTiming.snoozed(due, now: now, calendar: calendar)
        case .tonight: return tonight(now: now, calendar: calendar).map { ReminderDue(date: $0, hasTime: true) }
        case .tomorrow:
            return ReminderTiming.tomorrow(ReminderDue(date: due.date, hasTime: true), now: now, calendar: calendar)
        }
    }

    /// 喝水、待办的「稍后 N 分钟」：从现在起，抹掉秒数后再加一分钟以内，落在整分。
    public static func later(minutes: Int, now: Date, calendar: Calendar = .current) -> Date {
        let moved = now.addingTimeInterval(TimeInterval(minutes * 60))
        return ReminderTiming.wholeMinute(moved, calendar: calendar)
    }
}

// MARK: - 卡片上的字

/// 右上角的喇叭：写出音色；这一类选了不响、音效关着，或者现在因为勿扰、屏幕
/// 共享不响时，喇叭划掉。
public struct ReminderPopupSoundChip: Equatable, Sendable {
    public var label: String
    public var muted: Bool

    public init(label: String, muted: Bool) {
        self.label = label
        self.muted = muted
    }

    public static func make(_ kind: ReminderSoundKind, settings: ReminderSoundSettings,
                            master: WidgetSoundSettings,
                            environment: ReminderSoundEnvironment) -> ReminderPopupSoundChip {
        let chosen = settings.tone(for: kind)
        guard chosen != .off, settings.enabled, master.enabled else {
            return ReminderPopupSoundChip(label: chosen == .off ? ReminderTone.off.title : chosen.title, muted: true)
        }
        let playing = ReminderSoundDecision.toneToPlay(for: kind, settings: settings, master: master,
                                                       environment: environment)
        return ReminderPopupSoundChip(label: chosen.title, muted: playing == nil)
    }
}

extension ReminderPopupSoundChip {
    /// 倒计时和闹钟的喇叭：写出计时器自己的提示音，卡片设置里关了提示音时划掉。
    public static func timer(_ kind: ReminderSoundKind, sound: Bool) -> ReminderPopupSoundChip {
        ReminderPopupSoundChip(label: kind == .alarm ? "Sosumi" : "Glass", muted: !sound)
    }
}

public enum ReminderPopupText {
    /// “15:00”：24 小时制，和设计稿一样。
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 第一行：“提醒事项 · 现在”“喝水 · 现在”“待办 · 16:00”。提醒事项和喝水
    /// 到点一分钟内写“现在”，晚了就写时刻；待办总写时刻。
    public static func header(_ kind: ReminderSoundKind, due: Date, now: Date,
                              calendar: Calendar = .current) -> String {
        let when: String
        if kind != .todo, abs(now.timeIntervalSince(due)) < 60 {
            when = tr("现在")
        } else {
            when = clock(due, calendar: calendar)
        }
        return "\(kind.title) · \(when)"
    }

    /// 提醒事项第三行：“15:00 到点 · 工作 · 高优先级 !!!”。
    public static func reminderDetail(due: Date, list: String, highPriority: Bool,
                                      calendar: Calendar = .current) -> String {
        var parts = [tr("\(clock(due, calendar: calendar)) 到点")]
        if !list.isEmpty { parts.append(list) }
        if highPriority { parts.append(tr("高优先级 !!!")) }
        return parts.joined(separator: " · ")
    }

    /// 同时到点列表右边：“15:00 · 工作”。
    public static func listStamp(due: Date, list: String, calendar: Calendar = .current) -> String {
        let time = clock(due, calendar: calendar)
        return list.isEmpty ? time : "\(time) · \(list)"
    }

    /// “同时到点的还有 2 条”。
    public static func moreLine(_ count: Int) -> String {
        tr("同时到点的还有 \(count) 条")
    }

    /// 喝水第三行：“14:30 · 上一杯在 1 小时 40 分钟前”，今天还没喝时写“今天还没喝”。
    public static func waterDetail(due: Date, lastDrink: Date?, now: Date,
                                   calendar: Calendar = .current) -> String {
        let time = clock(due, calendar: calendar)
        guard let lastDrink, calendar.isDate(lastDrink, inSameDayAs: now), lastDrink <= now else {
            return tr("\(time) · 今天还没喝")
        }
        let minutes = Int(now.timeIntervalSince(lastDrink) / 60)
        if minutes < 1 { return tr("\(time) · 刚喝过") }
        return tr("\(time) · 上一杯在 \(ReminderTiming.duration(minutes))前")
    }

    /// “1250 / 2000 毫升”。
    public static func waterTally(_ info: WaterPopupInfo) -> String {
        "\(WaterIntake.figure(info.total, ounces: info.ounces)) / \(WaterIntake.figure(info.goal, ounces: info.ounces)) \(WaterIntake.unitLabel(ounces: info.ounces))"
    }

    /// “还差 3 杯”，达标后“达标啦”。
    public static func cupsLeft(_ info: WaterPopupInfo) -> String {
        info.cupsLeft == 0 ? tr("达标啦") : tr("还差 \(info.cupsLeft) 杯")
    }

    /// 喝水主按钮：“加一杯 250 毫升”。
    public static func drinkButton(_ info: WaterPopupInfo) -> String {
        tr("加一杯 \(WaterIntake.amount(info.cup, ounces: info.ounces))")
    }

    /// 待办第三行：“今天三件事之一 · 昨天记下的”。
    public static func todoDetail(_ info: TodoPopupInfo?, today: String, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if info?.today == true { parts.append(tr("今天三件事之一")) }
        if let added = info?.addedDay, let line = addedLine(added, today: today, calendar: calendar) {
            parts.append(line)
        }
        return parts.isEmpty ? tr("快速待办") : parts.joined(separator: " · ")
    }

    /// “今天记下的”“昨天记下的”“10 月 16 日记下的”。
    static func addedLine(_ added: String, today: String, calendar: Calendar) -> String? {
        if added == today { return tr("今天记下的") }
        if TodoDay.previous(today, calendar: calendar) == added { return tr("昨天记下的") }
        guard let date = TodoDay.date(added, calendar: calendar) else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return tr("\(parts.month ?? 0) 月 \(parts.day ?? 0) 日记下的")
    }

    // MARK: 倒计时和闹钟

    /// 倒计时的大字：“泡面 时间到”，没起名字时“时间到”。
    public static func countdownTitle(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? tr("时间到") : tr("\(trimmed) 时间到")
    }

    /// 倒计时第三行：“15:03 到点 · 共 3 分钟”。
    public static func countdownDetail(due: Date, duration: TimeInterval, calendar: Calendar = .current) -> String {
        "\(tr("\(clock(due, calendar: calendar)) 到点")) · \(tr("共 \(CountdownRun.lengthText(duration))"))"
    }

    /// 闹钟第三行：“14:30 · 闹钟”，稍后再响的那次“14:39 · 稍后再响 · 原定 14:30”。
    public static func alarmDetail(due: Date, info: TimerPopupInfo, calendar: Calendar = .current) -> String {
        let time = clock(due, calendar: calendar)
        guard info.snoozed else { return "\(time) · \(tr("闹钟"))" }
        let planned = info.clock.isEmpty ? "" : " · \(tr("原定 \(info.clock)"))"
        return "\(time) · \(tr("稍后再响"))\(planned)"
    }

    /// 倒计时和闹钟底下那行小字。
    public static func timerHint(_ kind: ReminderSoundKind, info: TimerPopupInfo?) -> String {
        if kind == .alarm {
            return tr("稍后：\(ReminderPopupSnooze.alarmMinutes) 分钟后再响一次")
        }
        return tr("再来一次：重新计 \(CountdownRun.lengthText(info?.duration ?? 0))")
    }

    /// “今天 1 / 3”。
    public static func todoProgress(done: Int, total: Int) -> String {
        tr("今天 \(done) / \(total)")
    }

    /// 底下那行小字，告诉你按钮会做什么。
    public static func hint(_ kind: ReminderSoundKind, choices: [ReminderSnoozeChoice]) -> String {
        switch kind {
        case .reminders:
            return tr("推迟：\(choices.map(\.title).joined(separator: " / "))")
        case .water: return tr("喝下后举杯 3 秒，达标换欢呼")
        case .todo: return tr("点完成：小熊猫欢呼，卡片划掉")
        case .countdown, .alarm: return timerHint(kind, info: nil)
        }
    }
}

// MARK: - 窗口摆在哪

/// 弹出页的窗口位置，和 AppKit 分开算，方便测试。AppKit 屏幕坐标：y 向上。
public enum ReminderPopupLayout {
    /// 卡片宽 380pt。
    public static let cardWidth: CGFloat = 380
    /// 窗口左右和下面给阴影留的边。
    public static let shadowInset: CGFloat = 24
    public static var windowWidth: CGFloat { cardWidth + shadowInset * 2 }
    /// 刘海下沿到卡片顶的距离。
    public static let notchGap: CGFloat = 6
    /// 菜单栏下沿到卡片顶的距离。
    public static let menuBarGap: CGFloat = 8
    /// 靠右摆时离屏幕右边的距离。
    public static let edgeMargin: CGFloat = 12
    /// 灵动提示在显示时，卡片放在它下面再空这么多。
    public static let islandGap: CGFloat = 6

    /// 卡片从哪里出来。
    public enum Origin: Equatable, Sendable {
        /// 有刘海：从刘海下方滑出，水平居中。
        case notch
        /// 没有刘海（外接屏）：菜单栏下方居中。
        case menuBar
        /// 有刘海但拾掇在运行：刘海让给拾掇的暂存架，卡片放到菜单栏下方靠右，
        /// 系统通知出现的那个角，不压着刘海下面那块。
        case corner
    }

    public static func origin(hasNotch: Bool, shiduoRunning: Bool) -> Origin {
        guard hasNotch else { return .menuBar }
        return shiduoRunning ? .corner : .notch
    }

    /// 窗口的位置和大小。
    ///
    /// - Parameters:
    ///   - screen: 带菜单栏的那块屏幕的整块范围。
    ///   - visibleMaxY: 它 `visibleFrame` 的顶（菜单栏下沿）。
    ///   - notch: `safeAreaInsets.top`，没有刘海时为 0。
    ///   - island: 灵动提示正显示时它占的地方，没有时为 nil。
    ///   - height: 卡片连同叠层和阴影要的高度。
    public static func windowFrame(screen: CGRect, visibleMaxY: CGFloat, notch: CGFloat,
                                   shiduoRunning: Bool, island: CGRect?, height: CGFloat) -> CGRect {
        let placement = origin(hasNotch: notch > 0, shiduoRunning: shiduoRunning)
        var top: CGFloat
        switch placement {
        case .notch: top = screen.maxY - notch - notchGap
        case .menuBar, .corner: top = min(visibleMaxY, screen.maxY) - menuBarGap
        }
        let width = windowWidth
        var x: CGFloat
        switch placement {
        case .notch, .menuBar: x = screen.midX - width / 2
        case .corner: x = screen.maxX - edgeMargin - cardWidth - shadowInset
        }
        // 居中的不会出界；靠右的卡片右沿离屏幕边 12pt，留给阴影的透明边伸到屏幕外也无妨。
        if placement != .corner { x = min(max(x, screen.minX), screen.maxX - width) }
        // 灵动提示的胶囊也在刘海下面：横向压着时卡片让到它下面。
        if let island, island.maxX > x, island.minX < x + width, island.minY < top {
            top = island.minY - islandGap
        }
        return CGRect(x: x, y: max(screen.minY, top - height), width: width, height: height)
    }
}
