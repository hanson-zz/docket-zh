import AppKit
import Observation
import SwiftUI

/// 到点提醒弹出页：提醒事项、喝水、待办到点时，从刘海下方滑出的深色玻璃卡片。
///
/// 窗口和灵动提示、AI 刘海对话一样是状态栏层级、不激活本应用的浮动面板，码头
/// 不在前台也照样出现，也不抢正在打字的那个窗口的键盘：只有指针移到卡片上（或
/// 点了它）时卡片才接键盘，这时按 Esc 关闭。
///
/// 摆放：有刘海的屏幕从刘海下方滑出、水平居中；外接屏没有刘海时放菜单栏下方
/// 居中；拾掇在运行时刘海让给它的暂存架，卡片放到菜单栏下方靠右。灵动提示正
/// 显示时让到它下面。见 `ReminderPopupLayout`。
///
/// 合并：几秒内同一类到点的几条合成一张，别的类排在后面，底下叠一层，只响一声
/// （`ReminderPopupQueue` 和 `ReminderSoundPlayer` 的合并窗口）。勿扰、专注、屏幕
/// 共享时只出卡片不响，右上角的喇叭划掉。
///
/// 收起：不点的话 30 秒后自动收起，指针停在卡片上时暂停；Esc 关闭；点卡片主体
/// 打开对应小组件的面板。打开“减少动态效果”时直接淡入淡出。
@MainActor
final class ReminderPopupCenter {
    static let shared = ReminderPopupCenter()

    /// 请打开某个小组件的面板（点了卡片主体）。由 `WidgetPanelOpener` 分派：卡片在
    /// 扩展栏上或当前布局的文件夹里时交给扩展栏从那一格长出来，否则以独立浮动面板
    /// 打开。`userInfo["id"]` 是小组件 id 的字符串。
    static let openPanelRequest = Notification.Name("com.docket-zh.reminder-popup.open-panel")

    private(set) var settings = ReminderPopupSettings()
    private var queue = ReminderPopupQueue()
    private let model = ReminderPopupModel()
    private var panel: KeyablePanel?
    private var countdown = ReminderPopupCountdown()
    private var timer: Timer?
    private var hideGeneration = 0
    private var shownCardID: UUID?
    private var contentHeight: CGFloat = 220
    private var screenObserver: NSObjectProtocol?

    private init() {
        model.perform = { [weak self] action in self?.perform(action) }
        model.hover = { [weak self] inside in self?.hover(inside) }
        model.heightChanged = { [weak self] height in self?.heightChanged(height) }
    }

    /// AppState 启动和设置变化时调用。喝水的开关变了，喝水提醒随即在卡片和系统
    /// 通知之间换过去。
    func configure(_ next: ReminderPopupSettings) {
        let waterChanged = next.water != settings.water
        settings = next
        if waterChanged { WaterNotifier.shared.popupSettingChanged() }
        if let front = queue.front, !next.enabled(front.kind) {
            queue.dismissFront()
            refresh()
        }
    }

    /// 卡片正显示着（消息灵动岛排队等它收起，见 `NotchMessagePriority`）。
    var isShowing: Bool { panel?.isVisible == true && queue.front != nil }

    func shows(_ kind: ReminderSoundKind) -> Bool {
        ReminderPopupDecision.shows(kind, settings: settings)
    }

    // MARK: 来了几条

    /// 几条到点了。新出的一张响一声（几秒内多条只响一声由 `ReminderSoundPlayer`
    /// 合并），并进已有那张的不再响。
    func post(_ alerts: [ReminderAlert], now: Date = .now) {
        var chime: ReminderSoundKind?
        for alert in alerts where shows(alert.kind) {
            switch queue.post(alert, now: now) {
            // 倒计时和闹钟自己每 4 秒响一声（`TimedAlertDriver`），这里不再叠一声。
            case .shown, .queued: if !alert.kind.isTimer { chime = chime ?? alert.kind }
            case .merged, .ignored: break
            }
        }
        if let chime { ReminderSoundPlayer.shared.play(chime, now: now) }
        refresh()
    }

    /// 还没收起的几条（正显示的和排着的）。
    var pending: [ReminderAlert] { queue.alerts }

    /// 这几条在别处处理掉了（卡片上点了停、关掉、稍后）：从弹出页拿掉。
    func withdraw(_ ids: Set<String>) {
        guard model.finishing == nil else { return }
        for id in ids { queue.resolve(id) }
        refresh()
    }

    // MARK: 动作

    enum Action {
        case complete
        case completeAll
        case snooze(ReminderSnoozeChoice)
        case snoozeMenu
        case drink
        case later
        case open
        case dismiss
        /// 倒计时「再来一次」。
        case again
        /// 倒计时、闹钟「关闭」：停下这次响铃。
        case stop
    }

    private func perform(_ action: Action) {
        guard let card = queue.front, let primary = card.primary else { return }
        let now = Date.now
        switch action {
        case .dismiss:
            // 倒计时和闹钟的卡片按 Esc 连响铃一起停，见 `ReminderPopupDecision.escapeStops`。
            if ReminderPopupDecision.escapeStops(card.kind) { return perform(.stop) }
            queue.dismissFront()
            refresh()
        case .again:
            if let id = primary.widgetID, let instance = WidgetWriter.current(id) {
                WidgetWriter.write(instance) {
                    TimedAlertScan.restartingCountdown(&$0, duration: primary.timer?.duration ?? 0, now: now,
                                                       timerID: primary.timer?.alarmID ?? "")
                }
            }
            queue.resolve(primary.id)
            refresh()
        case .stop:
            stopTimer(primary, now: now)
        case .open:
            if let id = primary.widgetID {
                NotificationCenter.default.post(name: Self.openPanelRequest, object: nil,
                                                userInfo: ["id": id.uuidString])
            }
            queue.dismissFront()
            refresh()
        case .snoozeMenu:
            showSnoozeMenu(now: now)
        case .snooze(let choice):
            for alert in card.alerts where alert.kind == .reminders {
                let due = ReminderDue(date: alert.due, hasTime: true)
                if let moved = ReminderPopupSnooze.reminderDue(choice, from: due, now: now) {
                    ReminderSync.reschedule(alert.itemID, to: moved)
                }
            }
            queue.dismissFront()
            refresh()
        case .complete:
            complete(primary, card: card)
        case .completeAll:
            for alert in card.alerts { ReminderSync.complete(alert.itemID) }
            finish(primary.id, all: true)
        case .drink:
            drink(primary)
        case .later:
            later(primary, now: now)
        }
    }

    private func complete(_ alert: ReminderAlert, card: ReminderPopupCard) {
        switch alert.kind {
        case .reminders:
            ReminderSync.complete(alert.itemID)
        case .todo:
            guard let id = alert.widgetID, let instance = WidgetWriter.current(id) else { break }
            let items = QuickTodo.items(instance.config)
            guard let item = items.first(where: { $0.id == alert.itemID }), !item.done else { break }
            let finishing = QuickTodo.finishesAll(toggling: item.id, in: items)
            // 和卡片上勾掉一样：勾掉最后一项时记下庆祝，卡片上的小熊猫跟着欢呼。
            TodoLog.toggle(item.id, in: instance, cheering: finishing)
        case .water, .countdown, .alarm:
            break
        }
        finish(alert.id, all: false)
    }

    /// 倒计时回到没开始；闹钟这次关掉（今天不再响，稍后再响的也取消）。
    private func stopTimer(_ alert: ReminderAlert, now: Date) {
        if let id = alert.widgetID, let instance = WidgetWriter.current(id) {
            switch alert.kind {
            case .countdown:
                WidgetWriter.write(instance) {
                    TimedAlertScan.stoppingCountdown(&$0, timerID: alert.timer?.alarmID ?? "")
                }
            case .alarm:
                if let alarmID = alert.timer?.alarmID {
                    WidgetWriter.write(instance) { config in
                        if AlarmBook.isLegacy(config) { AlarmBook.store(AlarmBook.items(config), in: &config) }
                        AlarmBook.dismiss(alarmID, in: &config, now: now)
                    }
                }
            case .reminders, .water, .todo:
                break
            }
        }
        queue.resolve(alert.id)
        refresh()
    }

    /// 完成以后先划掉、换成欢呼，停一下再收起这一条（下一条顶上来）。
    private func finish(_ alertID: String, all: Bool) {
        model.finishing = alertID
        countdown.pause(at: .now)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(reduce ? 500 : 900))
            guard let self else { return }
            self.model.finishing = nil
            if all { self.queue.dismissFront() } else { self.queue.resolve(alertID) }
            self.countdown.start(at: .now)
            self.refresh()
        }
    }

    /// 加一杯：走喝水卡片的记录（角色举杯三秒、达标欢呼），卡片上的进度跟着涨。
    private func drink(_ alert: ReminderAlert) {
        guard let id = alert.widgetID, let instance = WidgetWriter.current(id) else {
            queue.resolve(alert.id)
            return refresh()
        }
        WaterLog.drink(.water, amount: WaterIntake.cupSize(instance.config), in: instance)
        if let saved = WidgetWriter.current(id) {
            var updated = alert
            updated.water = ReminderPopupAlerts.waterInfo(saved.config)
            queue.update(updated)
            model.card = queue.front
        }
        model.drinking = true
        finish(alert.id, all: false)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.model.drinking = false
        }
    }

    /// 喝水稍后 15 分钟、待办稍后 10 分钟、闹钟稍后 9 分钟。
    private func later(_ alert: ReminderAlert, now: Date) {
        switch alert.kind {
        case .water:
            if let id = alert.widgetID, let instance = WidgetWriter.current(id) {
                let at = ReminderPopupSnooze.later(minutes: ReminderPopupSnooze.waterMinutes, now: now)
                WaterLog.set(WaterReminder.overrideKey, .number(at.timeIntervalSince1970), in: instance)
            }
        case .todo:
            if let id = alert.widgetID, let instance = WidgetWriter.current(id) {
                let at = ReminderPopupSnooze.later(minutes: ReminderPopupSnooze.todoMinutes, now: now)
                TodoLog.change(instance) { QuickTodo.settingReminder(alert.itemID, at: at, in: $0) }
            }
        case .alarm:
            if let id = alert.widgetID, let instance = WidgetWriter.current(id), let alarmID = alert.timer?.alarmID {
                WidgetWriter.write(instance) { config in
                    if AlarmBook.isLegacy(config) { AlarmBook.store(AlarmBook.items(config), in: &config) }
                    AlarmBook.snooze(alarmID, in: &config, now: now)
                }
            }
        case .reminders, .countdown:
            break
        }
        queue.resolve(alert.id)
        refresh()
    }

    private func showSnoozeMenu(now: Date) {
        let menu = NSMenu()
        for choice in ReminderPopupSnooze.choices(now: now) {
            let item = NSMenuItem(title: choice.title, action: #selector(SnoozeTarget.pick(_:)), keyEquivalent: "")
            item.target = SnoozeTarget.shared
            item.representedObject = choice.rawValue
            menu.addItem(item)
        }
        SnoozeTarget.shared.onPick = { [weak self] raw in
            guard let choice = ReminderSnoozeChoice(rawValue: raw) else { return }
            self?.perform(.snooze(choice))
        }
        countdown.pause(at: .now)
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        countdown.resume(at: .now)
    }

    // MARK: 显示

    private func refresh() {
        let front = queue.front
        model.card = front
        model.stacked = queue.stacked
        if let front {
            if front.kind.isTimer {
                model.chip = .timer(front.kind, sound: front.primary?.timer?.sound ?? true)
            } else {
                model.chip = ReminderPopupSoundChip.make(front.kind, settings: ReminderSoundPlayer.shared.settings,
                                                         master: ReminderSoundPlayer.shared.master,
                                                         environment: ReminderSoundPlayer.environment())
            }
            if shownCardID != front.id {
                shownCardID = front.id
                // 闹钟要响两分钟，卡片陪它响完；其余 30 秒。
                countdown = ReminderPopupCountdown(duration: ReminderPopupDecision.autoHideSeconds(front.kind))
                countdown.start(at: .now)
            }
            show()
        } else {
            shownCardID = nil
            hide()
        }
    }

    private func show() {
        hideGeneration += 1
        let panel = panel ?? makePanel()
        place(panel)
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            // 下一拍再放进来，插入的过渡才会播。
            Task { @MainActor [weak self] in
                self?.model.presented = true
            }
        } else {
            model.presented = true
        }
        startTimer()
    }

    private func hide() {
        model.presented = false
        stopTimer()
        guard let panel, panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.hideGeneration == generation, self.queue.front == nil else { return }
            panel.orderOut(nil)
        }
    }

    private func hover(_ inside: Bool) {
        let now = Date.now
        if inside {
            countdown.pause(at: now)
            // 指针在卡片上时才接键盘，Esc 才关得掉；不在上面时不抢别的窗口的键盘。
            panel?.makeKey()
        } else {
            countdown.resume(at: now)
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard queue.front != nil, model.finishing == nil else { return }
        if countdown.isExpired(at: .now) {
            queue.dismissFront()
            refresh()
        }
    }

    private func heightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        if let panel, panel.isVisible { place(panel) }
    }

    private func makePanel() -> KeyablePanel {
        let size = CGSize(width: ReminderPopupLayout.windowWidth, height: contentHeight)
        let host = FirstMouseHostingView(rootView: ReminderPopupView(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        let panel = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.onCancel = { [weak self] in self?.perform(.dismiss) }
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 阴影由卡片自己画，窗口的阴影会把透明的边也画出来。
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar
        panel.acceptsMouseMovedEvents = true
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.place(panel)
            }
        }
        return panel
    }

    /// 带菜单栏的那块屏幕。
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let frame = ReminderPopupLayout.windowFrame(screen: screen.frame,
                                                    visibleMaxY: screen.visibleFrame.maxY,
                                                    notch: screen.safeAreaInsets.top,
                                                    shiduoRunning: AINotchController.checkShiduo(),
                                                    island: IslandOccupancy.shared.frame,
                                                    height: contentHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

/// 「推迟」菜单的目标：NSMenuItem 要一个 Objective-C 对象接动作。
@MainActor
private final class SnoozeTarget: NSObject {
    static let shared = SnoozeTarget()
    var onPick: ((String) -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        onPick?(raw)
    }
}

/// 从小组件的配置拼出喝水卡片要的东西。
@MainActor
enum ReminderPopupAlerts {
    static func waterInfo(_ config: WidgetConfig, now: Date = .now) -> WaterPopupInfo {
        let today = WaterIntake.today(config, now: now)
        return WaterPopupInfo(total: today.total, goal: today.goal, cup: WaterIntake.cupSize(config),
                              ounces: WaterIntake.usesOunces(config),
                              character: WaterCharacter.shown(config, unlocked: ProAccess.isUnlocked, now: now).rawValue,
                              lastDrink: WaterIntake.lastDrink(WaterIntake.days(config)))
    }

    static func water(_ instance: WidgetInstance, due: Date, now: Date = .now) -> ReminderAlert {
        ReminderAlert(kind: .water, itemID: instance.id.uuidString, widgetID: instance.id,
                      title: tr("该喝水啦"), due: due, water: waterInfo(instance.config, now: now))
    }

    static func todo(_ item: TodoItem, in items: [TodoItem], widget: UUID) -> ReminderAlert? {
        guard let at = item.remindAt else { return nil }
        return ReminderAlert(kind: .todo, itemID: item.id, widgetID: widget, title: item.text, due: at,
                             todo: TodoPopupInfo.from(item, in: items))
    }
}

/// 卡片画什么，SwiftUI 那边观察。
@MainActor @Observable
final class ReminderPopupModel {
    var card: ReminderPopupCard?
    var stacked = false
    var presented = false
    var chip = ReminderPopupSoundChip(label: "", muted: false)
    /// 刚点完成的那一条：划掉、换欢呼，停一下再收起。
    var finishing: String?
    /// 刚加了一杯：喝水角色举着杯子。
    var drinking = false

    @ObservationIgnored var perform: (ReminderPopupCenter.Action) -> Void = { _ in }
    @ObservationIgnored var hover: (Bool) -> Void = { _ in }
    @ObservationIgnored var heightChanged: (CGFloat) -> Void = { _ in }
}

// MARK: - 卡片

struct ReminderPopupView: View {
    var model: ReminderPopupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.presented, let card = model.card {
                ReminderPopupCardView(card: card, model: model)
                    .id(card.id)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                              removal: .move(edge: .top).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82),
                   value: model.presented)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: model.card?.id)
        .environment(\.colorScheme, .dark)
    }
}

/// 一张卡片本身。截图工具（Tools/Shots）也直接拿它拍，所以不是 private。
struct ReminderPopupCardView: View {
    var card: ReminderPopupCard
    var model: ReminderPopupModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primary: ReminderAlert { card.primary ?? card.alerts[0] }
    private var finishing: Bool { model.finishing == primary.id }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            content(now: tick.date)
        }
        .padding(.horizontal, ReminderPopupLayout.shadowInset)
        .padding(.bottom, ReminderPopupLayout.shadowInset)
        // 按自己要的高度量，窗口跟着这个高度改，不被窗口当下的高度压扁。
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.heightChanged($0) }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 13) {
                ReminderPopupAvatar(image: avatarName, accent: accent)
                VStack(alignment: .leading, spacing: 3) {
                    headerRow(now: now)
                    Text(primary.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(finishing ? 0.5 : 1))
                        .strikethrough(finishing, color: .white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        // 英文的“last drink 2 h 5 min ago”更长，允许折成两行。
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                    section(now: now)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer(now: now)
        }
        .padding(15)
        .frame(width: ReminderPopupLayout.cardWidth, alignment: .leading)
        .background { glass }
        .background(alignment: .bottom) {
            if model.stacked {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "#1b1d22").opacity(0.8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.6)
                    }
                    .frame(height: 24)
                    .padding(.horizontal, 12)
                    .offset(y: 7)
            }
        }
        .padding(.bottom, model.stacked ? 7 : 0)
        .contentShape(.rect)
        .onTapGesture { model.perform(.open) }
        .onHover { model.hover($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(card.kind.title)：\(primary.title)"))
        .accessibilityAction(named: Text(tr("关闭"))) { model.perform(.dismiss) }
    }

    // MARK: 头

    private func headerRow(now: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(ReminderPopupText.header(card.kind, due: primary.due, now: now))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 6)
            soundChip
        }
    }

    private var soundChip: some View {
        HStack(spacing: 4) {
            Image(systemName: model.chip.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(model.chip.label)
                .font(.system(size: 13, weight: .semibold))
                .strikethrough(model.chip.muted, color: accent)
        }
        .foregroundStyle(accent.opacity(model.chip.muted ? 0.6 : 0.95))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(accent.opacity(0.12)))
        .help(model.chip.muted ? tr("这次不响") : tr("到点提示音"))
    }

    private func detail(now: Date) -> String {
        switch card.kind {
        case .reminders:
            ReminderPopupText.reminderDetail(due: primary.due, list: primary.list, highPriority: primary.highPriority)
        case .water:
            ReminderPopupText.waterDetail(due: primary.due, lastDrink: primary.water?.lastDrink, now: now)
        case .todo:
            ReminderPopupText.todoDetail(primary.todo, today: TodoDay.key(now))
        case .countdown:
            ReminderPopupText.countdownDetail(due: primary.due, duration: primary.timer?.duration ?? 0)
        case .alarm:
            ReminderPopupText.alarmDetail(due: primary.due, info: primary.timer ?? TimerPopupInfo())
        }
    }

    // MARK: 中间

    @ViewBuilder
    private func section(now: Date) -> some View {
        switch card.kind {
        case .reminders:
            if !card.others.isEmpty { othersList(dashes: false) }
        case .water:
            if let info = primary.water { waterRow(info) }
        case .todo:
            if !card.others.isEmpty {
                othersList(dashes: false)
            } else if let info = primary.todo, info.today, !info.others.isEmpty {
                todayRows(info)
            }
        case .countdown, .alarm:
            if !card.others.isEmpty { othersList(dashes: false) }
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.vertical, 5)
    }

    private func othersList(dashes: Bool) -> some View {
        let shown = Array(card.others.prefix(3))
        let more = card.others.count - shown.count
        return VStack(alignment: .leading, spacing: 5) {
            divider
            Text(ReminderPopupText.moreLine(card.others.count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            ForEach(shown) { alert in
                HStack(spacing: 7) {
                    Circle().strokeBorder(accent.opacity(0.8), lineWidth: 1.2).frame(width: 10, height: 10)
                    Text(alert.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ReminderPopupText.listStamp(due: alert.due, list: alert.list))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            if more > 0 {
                Text(tr("还有 \(more) 项"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// 杯子、“1250 / 2000 毫升”和“还差 3 杯”。英文的“3 cups to go”更长，一行放不下时
    /// “还差几杯”挪到下一行，喝了多少那串数字永远不截断。
    private func waterRow(_ info: WaterPopupInfo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                cupsAndTally(info)
                Spacer(minLength: 4)
                cupsLeftText(info)
            }
            VStack(alignment: .leading, spacing: 3) {
                cupsAndTally(info)
                cupsLeftText(info)
            }
        }
        .lineLimit(1)
        .padding(.top, 8)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: info.total)
    }

    private func cupsAndTally(_ info: WaterPopupInfo) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<WaterPetCards.cupSlots, id: \.self) { index in
                let full = index < info.filledCups
                CupShape()
                    .fill(full ? accent.opacity(0.75) : .white.opacity(0.08))
                    .overlay { CupShape().stroke(.white.opacity(0.25), lineWidth: 0.5) }
                    .frame(width: 10, height: 15)
            }
            Text(ReminderPopupText.waterTally(info))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .padding(.leading, 6)
                .contentTransition(.numericText())
                .fixedSize()
        }
    }

    private func cupsLeftText(_ info: WaterPopupInfo) -> some View {
        Text(ReminderPopupText.cupsLeft(info))
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize()
    }

    private func todayRows(_ info: TodoPopupInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            divider
            ForEach(Array(info.others.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 7) {
                    Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(row.done ? accent : .white.opacity(0.6))
                    Text(row.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(row.done ? 0.5 : 0.9))
                        .strikethrough(row.done, color: .white.opacity(0.5))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if index == 0 {
                        Text(ReminderPopupText.todoProgress(done: info.todayDone, total: info.todayTotal))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: 底

    /// 底下一行：说明小字和按钮。放得下就同一行；英文的说明和按钮都更长，放不下时
    /// 说明单独占一行（最多两行），按钮靠右排在下面，不再截成“Raises the cup for 3…”；
    /// 按钮一行还放不下时竖排。
    private func footer(now: Date) -> some View {
        let choices = ReminderPopupSnooze.choices(now: now)
        let hint = card.kind.isTimer ? ReminderPopupText.timerHint(card.kind, info: primary.timer)
                                     : ReminderPopupText.hint(card.kind, choices: choices)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                hintText(hint)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 6)
                buttons()
            }
            VStack(alignment: .leading, spacing: 6) {
                hintText(hint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    buttons()
                }
            }
            // 窄卡上三个按钮（完成、全部完成、推迟）的英文排一行也会超宽：按钮竖排靠右。
            VStack(alignment: .leading, spacing: 6) {
                hintText(hint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .trailing, spacing: 5) {
                    buttons()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .disabled(model.finishing != nil)
    }

    private func hintText(_ hint: String) -> some View {
        Text(hint)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.5))
    }

    @ViewBuilder
    private func buttons() -> some View {
        switch card.kind {
        case .reminders:
            PopupButton(title: tr("完成"), primary: true) { model.perform(.complete) }
            if card.alerts.count > 1 {
                PopupButton(title: tr("全部完成")) { model.perform(.completeAll) }
            }
            PopupButton(title: tr("推迟"), chevron: true) { model.perform(.snoozeMenu) }
        case .water:
            if let info = primary.water {
                PopupButton(title: ReminderPopupText.drinkButton(info), primary: true) { model.perform(.drink) }
            }
            PopupButton(title: tr("稍后 \(ReminderPopupSnooze.waterMinutes) 分钟")) { model.perform(.later) }
        case .todo:
            PopupButton(title: tr("完成"), primary: true) { model.perform(.complete) }
            PopupButton(title: tr("稍后 \(ReminderPopupSnooze.todoMinutes) 分钟")) { model.perform(.later) }
        case .countdown:
            PopupButton(title: tr("再来一次"), primary: true) { model.perform(.again) }
            PopupButton(title: tr("关闭")) { model.perform(.stop) }
        case .alarm:
            PopupButton(title: tr("稍后 \(ReminderPopupSnooze.alarmMinutes) 分钟"), primary: true) {
                model.perform(.later)
            }
            PopupButton(title: tr("关闭")) { model.perform(.stop) }
        }
    }

    // MARK: 角色

    private var accent: Color {
        switch card.kind {
        case .reminders: Color(hex: "#FF8D28")
        case .water: Color(hex: "#5ac8fa")
        case .todo: Color(hex: "#6fdc9a")
        case .countdown, .alarm: Color.timerOrange
        }
    }

    /// 提醒事项是站着等你的小熊猫；喝水是选的角色在喝水（小熊猫没有喝水图，用
    /// 站着的），加了一杯举杯、达标欢呼；待办平时站着，点完成换欢呼。
    private var avatarName: String {
        switch card.kind {
        case .reminders:
            return finishing ? "pet-panda-cheer" : "pet-panda-idle"
        case .todo:
            return finishing ? "pet-panda-cheer" : "pet-panda-idle"
        case .countdown, .alarm:
            return "pet-panda-idle"
        case .water:
            let character = WaterCharacter(rawValue: primary.water?.character ?? "") ?? .redPanda
            let met = primary.water.map { WaterIntake.isMet(total: $0.total, goal: $0.goal) } ?? false
            guard character.hasMoods else { return met ? "pet-panda-cheer" : "pet-panda-idle" }
            return character.imageName(met && !model.drinking ? .cheer : .drink)
        }
    }

    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(Color(hex: "#1b1d22").opacity(0.92))
            .overlay { shape.fill(.white.opacity(0.07)) }
            .overlay {
                // 顶部一点高光，往下淡掉。
                shape.fill(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0)],
                                          startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

/// 圆底加角色图，图从圆底下沿站出来一点。
private struct ReminderPopupAvatar: View {
    var image: String
    var accent: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(accent.opacity(0.14))
                .overlay { Circle().strokeBorder(accent.opacity(0.3), lineWidth: 0.6) }
            if let picture = PopupArt.image(image) {
                Image(nsImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                    .offset(y: 2)
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

/// 一只小杯：上宽下窄。
private struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.15
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 白色主按钮和半透明次按钮，胶囊形。
private struct PopupButton: View {
    var title: String
    var primary = false
    var chevron = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: primary ? .bold : .semibold))
                    .lineLimit(1)
                if chevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
            }
            .foregroundStyle(primary ? Color(hex: "#1b1d22") : .white.opacity(0.92))
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background {
                Capsule()
                    .fill(primary ? Color.white.opacity(0.92) : Color.white.opacity(0.12))
                    .overlay { if !primary { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) } }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// 角色图：Resources/Pet 和 Resources/Water 里现成的 PNG，读一次。
@MainActor
private enum PopupArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}
