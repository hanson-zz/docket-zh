import AppKit
import EventKit
import SwiftUI

// MARK: - 桌面卡片专属布局：Tasks 组
//
// 快速待办、提醒事项、便签、习惯打卡、喝水、久坐提醒、小熊猫的竹篮、电子宠物钉在桌面时，
// 小 160×160 / 中 340×160 / 大 340×340 各有专门排的布局（纯判断见 Core 的
// `DesktopCardsTasksPlan`）：
// - 小号：一个核心数字或状态，加最多一个能直接点的操作。
// - 中号：核心加两到四条次要信息，或一排操作。
// - 大号：核心加列表、图表或操作区，完整显示不用滚（便签纸里照旧能滚）。
//
// 数据和扩展栏是同一份：读 `WidgetInstance` 的配置，写走各小组件自己的 Log（`TodoLog`、
// `HabitLog`、`WaterLog`、`PostureLog`、`PetLog`、`StickyLog`）或系统“提醒事项”，两边同步。
// 字最小 13pt，颜色用面板语义色（液态玻璃浅色深色都能读），主题色当字时用 panelReadable。

enum DesktopCardsTasks {
    /// 本组小组件的桌面视图；不是本组的返回 nil，走原来的通用逻辑。
    /// 便签要知道钉的是哪一张（`DesktopPin.sheetID`），仍由通用逻辑画 `DesktopNoteSheet`（在本文件里）。
    @MainActor
    static func view(_ widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsTasksPlan.handles(widget.kind) else { return nil }
        switch widget.kind {
        case .todo: return AnyView(TasksPinTodo(widget: widget, size: size, now: now))
        case .reminders: return AnyView(TasksPinReminders(widget: widget, size: size, now: now))
        case .habit: return AnyView(TasksPinHabit(widget: widget, size: size, now: now))
        case .water: return AnyView(TasksPinWater(widget: widget, size: size, now: now))
        case .posture: return AnyView(TasksPinPosture(widget: widget, size: size, now: now))
        case .perfectDay: return AnyView(TasksPinPerfectDay(widget: widget, size: size, now: now))
        case .pet: return AnyView(TasksPinPet(widget: widget, size: size, now: now))
        default: return nil
        }
    }

    /// 卡片四边的留白：小号 14，中大号 16。
    static func inset(_ size: DesktopPinSize) -> CGFloat { size == .small ? 14 : 16 }
}

// MARK: - 共用小件

/// 进度环：细轨道加一段主题色弧，中间放数字或图。
private struct TasksPinRing<Inner: View>: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat
    var inner: Inner

    init(fraction: Double, tint: Color, lineWidth: CGFloat, @ViewBuilder inner: () -> Inner) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
        self.inner = inner()
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.panelTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(tint.panelGraphic, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            inner
        }
        .padding(lineWidth / 2)
        .animation(.snappy(duration: 0.35), value: fraction)
    }
}

/// 胶囊按钮。`filled` 是实心主题色（白字或深字，看底色深浅），否则是浮起的玻璃小块。
private struct TasksPinPill: View {
    var title: String
    var symbol: String?
    var tint: Color
    var filled: Bool
    var height: CGFloat = 32
    var ink: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(filled ? (ink ?? .white) : Color.panelPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if filled {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(Color.panelRaised).panelLift()
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// 列表行前的大圆圈：点一下完成。勾上时填绿、打勾。
private struct TasksPinCheck: View {
    var checked: Bool
    var ring: Color
    var size: CGFloat = 22
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(ring, lineWidth: 1.6).opacity(checked ? 0 : 1)
                Circle().fill(TasksPinPalette.green).opacity(checked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
            }
            .frame(width: size, height: size)
            .padding(4)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .padding(-4)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 「还有 3 项」这一行。
private struct TasksPinMore: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
    }
}

private enum TasksPinPalette {
    static let green = Color(hex: "#2FA36B")
    static let red = Color(hex: "#E5484D")
    static let orange = Color(hex: PaletteColor.orange.hex)
}

/// 小熊猫的图（Resources/Pet），没有图时什么都不画。
private struct TasksPinPanda: View {
    var name: String
    var size: CGFloat
    var body: some View {
        TodoPanda(name: name, size: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 快速待办

/// 小：进度环写今天还剩几件，下面今天第一条能直接勾。
/// 中：左边进度环，右边今天最前三条（放不下写「还有 N 项」）。
/// 大：进度环和「已完成 2 / 5」，输入框回车记一条，下面今天的清单，最后写稍后几件。
/// 今天清空时小熊猫欢呼、连续天数和最近 7 天；一条都没有时是歇着的小熊猫。
private struct TasksPinTodo: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 刚勾上、约 1 秒后才写进去的几条（和扩展栏卡片一样先划线）。
    @State private var completing: Set<String> = []
    @State private var celebrateAt: Date?
    @State private var draft = ""

    private var today: String { TodoDay.key(now) }
    private var unlocked: Bool { ProAccess.isUnlocked }
    private var orange: Color { TasksPinPalette.orange }

    var body: some View {
        let all = QuickTodo.items(widget.config)
        let state = QuickTodo.cardState(all)
        let rows = QuickTodo.cardTodayRows(all, limit: 99)
        let left = max(0, rows.count - completing.count)
        Group {
            switch size {
            case .small: small(all, state: state, rows: rows, left: left)
            case .medium: medium(all, state: state, rows: rows, left: left)
            case .large: large(all, state: state, rows: rows, left: left)
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: today) { TodoLog.rollOver(widget, today: today) }
        .task(id: celebrateAt) {
            guard celebrateAt != nil else { return }
            try? await Task.sleep(for: .seconds(CheerMotion.duration))
            guard !Task.isCancelled else { return }
            celebrateAt = nil
        }
        .task(id: cheerDeadline) {
            guard let cheerDeadline else { return }
            let wait = cheerDeadline - Date().timeIntervalSince1970
            if wait > 0 {
                try? await Task.sleep(for: .seconds(min(wait, QuickTodo.cheerHold + 1)))
                guard !Task.isCancelled else { return }
            }
            TodoLog.endCheer(widget)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("快速待办"))
    }

    // MARK: 三档

    @ViewBuilder
    private func small(_ all: [TodoItem], state: TodoCardState, rows: [TodoItem], left: Int) -> some View {
        switch state {
        case .empty:
            emptyBlock(compact: true)
        case .cleared:
            clearedBlock(all, compact: true)
        case .list:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ring(all, left: left, size: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("今天"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.panelPrimary)
                        Text(tr("还剩 \(left) 件"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                if let first = rows.first {
                    row(first, font: 15, lines: 2)
                }
            }
        }
    }

    @ViewBuilder
    private func medium(_ all: [TodoItem], state: TodoCardState, rows: [TodoItem], left: Int) -> some View {
        switch state {
        case .empty:
            HStack(spacing: 14) {
                TasksPinPanda(name: "pet-panda-rest", size: 76)
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("清单空空的"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    input
                }
            }
            .frame(maxHeight: .infinity)
        case .cleared:
            clearedBlock(all, compact: false)
        case .list:
            let cut = DesktopCardsTasksPlan.cut(total: rows.count,
                                                rows: DesktopCardsTasksPlan.listRows(.todo, size: .medium))
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 6) {
                    ring(all, left: left, size: 72)
                    Text(tr("今天"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelSecondary)
                }
                .frame(width: 80)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(cut.shown)) { item in
                        row(item, font: 15, lines: 1)
                    }
                    if cut.more > 0 {
                        TasksPinMore(text: tr("还有 \(cut.more) 项"))
                            .padding(.leading, 30)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func large(_ all: [TodoItem], state: TodoCardState, rows: [TodoItem], left: Int) -> some View {
        let tally = QuickTodo.todayTally(all, today: today)
        let later = QuickTodo.items(in: .later, of: all).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ring(all, left: left, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("今天"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(tr("已完成 \(min(tally.done + completing.count, tally.total)) / \(tally.total)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                let streak = QuickTodo.streak(widget.config, today: today)
                if streak > 0 {
                    Text(tr("连续 \(streak) 天"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TasksPinPalette.green.panelReadable)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(TasksPinPalette.green.opacity(0.14)))
                }
            }
            input
            switch state {
            case .empty:
                VStack(spacing: 8) {
                    TasksPinPanda(name: "pet-panda-rest", size: 92)
                    Text(tr("清单空空的"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(tr("在上面写一件，回车记下"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .cleared:
                VStack(spacing: 10) {
                    cheerFigure(size: 84)
                    Text(tr("今天清空啦"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    TodoWeekDots(days: TodoStreak.week(widget.config, today: today), labels: nil, size: 14)
                    if later > 0 {
                        TasksPinMore(text: tr("稍后还有 \(later) 件"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .list:
                let cut = DesktopCardsTasksPlan.cut(total: rows.count,
                                                    rows: DesktopCardsTasksPlan.listRows(.todo, size: .large))
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(rows.prefix(cut.shown)) { item in
                        row(item, font: 15, lines: 1)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        if cut.more > 0 { TasksPinMore(text: tr("还有 \(cut.more) 项")) }
                        Spacer(minLength: 0)
                        if later > 0 { TasksPinMore(text: tr("稍后 \(later) 件")) }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: 部件

    private func ring(_ all: [TodoItem], left: Int, size: CGFloat) -> some View {
        let tally = QuickTodo.todayTally(all, today: today)
        let done = min(tally.done + completing.count, tally.total)
        let fraction = tally.total == 0 ? 0 : Double(done) / Double(tally.total)
        return TasksPinRing(fraction: fraction, tint: orange, lineWidth: size > 60 ? 6 : 5) {
            Text(verbatim: "\(left)")
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .overlay { cheer(size: size * 1.4) }
        .accessibilityLabel(tr("今天还剩 \(left) 件"))
    }

    private func row(_ item: TodoItem, font: CGFloat, lines: Int) -> some View {
        let checked = item.done || completing.contains(item.id)
        let tag = TodoTag.shown(item.tag, unlocked: unlocked)
        return HStack(alignment: lines > 1 ? .top : .center, spacing: 8) {
            TasksPinCheck(checked: checked, ring: tag?.graphic ?? Color.panelTertiary,
                          help: tr("完成“\(item.text)”")) { toggle(item) }
                .disabled(checked)
            Text(item.text)
                .font(.system(size: font, weight: .medium))
                .foregroundStyle(checked ? Color.panelSecondary : Color.panelPrimary)
                .strikethrough(checked, color: Color.panelSecondary)
                .lineLimit(lines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !checked, lines == 1, let badge = QuickTodo.dueBadge(item, now: now) {
                dueCapsule(badge, alarm: item.remindAt != nil)
            }
        }
        .frame(minHeight: 26)
    }

    private func dueCapsule(_ badge: TodoDueBadge, alarm: Bool) -> some View {
        let ink: Color
        let fill: Color
        switch badge.tone {
        case .late:
            ink = TasksPinPalette.red.panelReadable(minContrast: 4.5)
            fill = TasksPinPalette.red.opacity(0.14)
        case .today:
            ink = orange.panelReadable(minContrast: 4.5)
            fill = orange.opacity(0.16)
        case .later:
            ink = Color.panelSecondary
            fill = Color.panelFill
        }
        return HStack(spacing: 3) {
            if alarm { Image(systemName: "alarm").font(.system(size: 11, weight: .semibold)) }
            Text(badge.text).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(fill))
        .fixedSize()
    }

    /// 输入框：回车记一条（认「明天 9 点交稿」这类时间，和面板一样）。
    private var input: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(orange.panelReadable)
            TextField("", text: $draft,
                      prompt: Text(tr("记一件事，回车记下")).foregroundStyle(Color.panelTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Color.panelPrimary)
                .onSubmit(add)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.panelFill))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy(duration: 0.3)) { TodoLog.add(text, to: widget) }
        draft = ""
    }

    @ViewBuilder
    private func emptyBlock(compact: Bool) -> some View {
        VStack(spacing: 6) {
            TasksPinPanda(name: "pet-panda-rest", size: compact ? 70 : 84)
            Text(tr("清单空空的"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
            Text(tr("拖进扩展栏记一件"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func clearedBlock(_ all: [TodoItem], compact: Bool) -> some View {
        let streak = QuickTodo.streak(widget.config, today: today)
        let later = QuickTodo.items(in: .later, of: all).count
        if compact {
            VStack(spacing: 6) {
                cheerFigure(size: 72)
                Text(tr("今天清空啦"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(streak > 0 ? tr("连续 \(streak) 天") : tr("稍后还有 \(later) 件"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(streak > 0 ? TasksPinPalette.green.panelReadable : Color.panelSecondary)
                    .opacity(streak > 0 || later > 0 ? 1 : 0)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 16) {
                cheerFigure(size: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("今天清空啦"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    if streak > 0 {
                        Text(tr("连续 \(streak) 天"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TasksPinPalette.green.panelReadable)
                    }
                    TodoWeekDots(days: TodoStreak.week(widget.config, today: today), labels: nil, size: 13)
                    if later > 0 { TasksPinMore(text: tr("稍后还有 \(later) 件")) }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func cheerFigure(size: CGFloat) -> some View {
        TasksPinRing(fraction: 1, tint: TasksPinPalette.green, lineWidth: 5) {
            TasksPinPanda(name: "pet-panda-cheer", size: size * 0.72)
        }
        .frame(width: size, height: size)
        .overlay { cheer(size: size * 1.4) }
    }

    @ViewBuilder
    private func cheer(size: CGFloat) -> some View {
        if let celebrateAt {
            TodoCheer(startedAt: celebrateAt, compact: true)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }

    private var cheerDeadline: Double? {
        if case .number(let until) = widget.config[QuickTodo.cheerKey] { return until }
        return nil
    }

    private func toggle(_ item: TodoItem) {
        guard !completing.contains(item.id), !item.done else { return }
        let id = item.id
        guard !reduceMotion else {
            commit(id)
            return
        }
        withAnimation(.spring(duration: 0.2, bounce: 0.4)) { _ = completing.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            commit(id)
            completing.remove(id)
        }
    }

    private func commit(_ id: String) {
        let latest = WidgetWriter.current(widget.id) ?? widget
        let current = QuickTodo.items(latest.config)
        guard current.contains(where: { $0.id == id && !$0.done }) else { return }
        let clearing = QuickTodo.clearsToday(toggling: id, in: current)
        withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(id, in: latest, cheering: clearing) }
        if clearing { celebrateAt = .now }
    }
}

// MARK: - 提醒事项

/// 小：今天到期几项（过期的标红），下面下一项能直接点圆圈完成。
/// 中：左边大数字，右边三条（圆圈、标题、时间）。
/// 大：「已过期 / 今天到期」两个数，下一项带「完成」「推迟 1 小时」，下面再列四条。
/// 和扩展栏一样只读系统“提醒事项”，不在画出来时弹授权，点了才问。
private struct TasksPinReminders: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @State private var access = EKEventStore.authorizationStatus(for: .reminder)
    @State private var rows: [TasksPinReminder] = []
    @State private var generation = 0
    @State private var finishing: Set<String> = []

    private var store: EKEventStore { ReminderSync.store }
    private var granted: Bool { access == .fullAccess }
    private var listFilter: String { widget.config.string("list").trimmingCharacters(in: .whitespaces) }
    private static let accent = Color(hex: WidgetCatalog.accentHex(.reminders) ?? PaletteColor.orange.hex)
    private var overdueInk: Color { TasksPinPalette.red.panelReadable(minContrast: 4.5) }

    private var ordered: [TasksPinReminder] {
        let items = rows.filter { !finishing.contains($0.id) }
        return items.filter { $0.isOverdue(now) } + items.filter { !$0.isOverdue(now) }
    }

    var body: some View {
        let items = ordered
        let overdue = items.filter { $0.isOverdue(now) }.count
        Group {
            if !granted {
                lockNote
            } else {
                switch size {
                case .small: small(items, overdue: overdue)
                case .medium: medium(items, overdue: overdue)
                case .large: large(items, overdue: overdue)
                }
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { load() }
        .onChange(of: listFilter) { load() }
        .onChange(of: Int(now.timeIntervalSince1970) / 300) { load() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
    }

    // MARK: 三档

    @ViewBuilder
    private func small(_ items: [TasksPinReminder], overdue: Int) -> some View {
        if items.isEmpty {
            emptyNote(compact: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(items.count)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                    Text(tr("项到期"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                }
                Text(overdue > 0 ? tr("\(overdue) 项已过期") : tr("都还没过期"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(overdue > 0 ? overdueInk : Color.panelSecondary)
                Spacer(minLength: 8)
                if let first = items.first {
                    row(first, lines: 2, stamp: false)
                }
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func medium(_ items: [TasksPinReminder], overdue: Int) -> some View {
        if items.isEmpty {
            emptyNote(compact: false)
        } else {
            let cut = DesktopCardsTasksPlan.cut(total: items.count,
                                                rows: DesktopCardsTasksPlan.listRows(.reminders, size: .medium))
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(verbatim: "\(items.count)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                    Text(tr("今天到期"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                    if overdue > 0 {
                        Text(tr("\(overdue) 项已过期"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(overdueInk)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 84)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.prefix(cut.shown)) { item in row(item, lines: 1, stamp: true) }
                    if cut.more > 0 {
                        TasksPinMore(text: tr("还有 \(cut.more) 项")).padding(.leading, 30)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func large(_ items: [TasksPinReminder], overdue: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                figure(overdue, tr("已过期"), late: overdue > 0)
                Rectangle().fill(Color.panelSeparator).frame(width: 0.5, height: 36)
                figure(items.count - overdue, tr("今天到期"), late: false)
            }
            .frame(height: 52)
            if let next = items.first {
                nextCard(next)
                let rest = Array(items.dropFirst())
                let cut = DesktopCardsTasksPlan.cut(total: rest.count,
                                                    rows: DesktopCardsTasksPlan.listRows(.reminders, size: .large) - 1)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rest.prefix(cut.shown)) { item in row(item, lines: 1, stamp: true) }
                    if cut.more > 0 {
                        TasksPinMore(text: tr("还有 \(cut.more) 项")).padding(.leading, 30)
                    }
                }
                Spacer(minLength: 0)
            } else {
                emptyNote(compact: false)
            }
        }
    }

    // MARK: 部件

    private func figure(_ value: Int, _ label: String, late: Bool) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(late ? overdueInk : Color.panelPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 下一项：标题、「40 分钟后 · 15:00 · 工作」，「完成」「推迟 1 小时」两个按钮。
    private func nextCard(_ item: TasksPinReminder) -> some View {
        let late = item.isOverdue(now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if item.isHighPriority {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Self.accent.panelReadable)
                }
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
            }
            Text(nextLine(item))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(late ? overdueInk : Self.accent.panelReadable)
                .monospacedDigit()
                .lineLimit(1)
            HStack(spacing: 8) {
                TasksPinPill(title: tr("完成"), symbol: "checkmark", tint: Self.accent, filled: true, height: 30) {
                    complete(item)
                }
                TasksPinPill(title: tr("推迟 1 小时"), symbol: "clock.arrow.circlepath", tint: Self.accent,
                             filled: false, height: 30) {
                    ReminderSync.reschedule(item.id, to: ReminderTiming.snoozed(item.dueValue, now: now))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.panelFill))
    }

    private func row(_ item: TasksPinReminder, lines: Int, stamp: Bool) -> some View {
        let late = item.isOverdue(now)
        return HStack(alignment: lines > 1 ? .top : .center, spacing: 8) {
            TasksPinCheck(checked: false, ring: late ? overdueInk : Color.panelTertiary,
                          help: tr("完成“\(item.title)”")) { complete(item) }
            Text(item.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(lines)
                .frame(maxWidth: .infinity, alignment: .leading)
            if stamp {
                Text(stampText(item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(late ? overdueInk : Color.panelSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(minHeight: 26)
    }

    private var lockNote: some View {
        let permission = TilePermission.name(for: WidgetKind.reminders.rawValue) ?? "提醒事项"
        return Button {
            Task { @MainActor in await OnboardingPermissions.request(permission) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: size == .small ? 24 : 28, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Text(TilePermission.prompt(permission, compact: size == .small))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(TilePermission.prompt(permission))
    }

    private func emptyNote(compact: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: compact ? 34 : 40))
                .foregroundStyle(Self.accent.panelGraphic)
            Text(tr("今天没有到期事项。"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stampText(_ item: TasksPinReminder) -> String {
        if let word = ReminderTiming.shortDay(item.dueValue, now: now) { return word }
        guard Calendar.current.isDate(item.due, inSameDayAs: now) else {
            return item.due.formatted(.dateTime.day().month(.abbreviated))
        }
        return item.due.formatted(date: .omitted, time: .shortened)
    }

    private func nextLine(_ item: TasksPinReminder) -> String {
        let line = ReminderTiming.nextLine(item.dueValue, now: now,
                                           clock: item.due.formatted(date: .omitted, time: .shortened))
        return item.list.isEmpty ? line : "\(line) · \(item.list)"
    }

    private func complete(_ item: TasksPinReminder) {
        guard granted else { return }
        withAnimation(.snappy(duration: 0.25)) { _ = finishing.insert(item.id) }
        if !ReminderSync.complete(item.id) {
            withAnimation(.snappy(duration: 0.25)) { _ = finishing.remove(item.id) }
        }
    }

    /// 和扩展栏卡片读的一样：没完成、到今天结束为止到期的（过期加今天），按列表名筛。
    private func load() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != access {
            if status == .fullAccess { store.reset() }
            access = status
        }
        guard status == .fullAccess else {
            rows = []
            return
        }
        let lists = store.calendars(for: .reminder)
        let scope = listFilter.isEmpty ? lists : lists.filter { $0.title == listFilter }
        let wanted = scope.isEmpty ? lists : scope
        guard !wanted.isEmpty,
              let end = Calendar.current.date(byAdding: .day, value: 1,
                                              to: Calendar.current.startOfDay(for: Date())) else {
            rows = []
            return
        }
        generation += 1
        let token = generation
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end,
                                                              calendars: wanted)
        Task { @MainActor in
            let fetched: [TasksPinReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).compactMap(TasksPinReminder.init))
                }
            }
            guard token == generation else { return }
            rows = fetched.sorted { $0.due == $1.due ? $0.title < $1.title : $0.due < $1.due }
            finishing = finishing.filter { id in fetched.contains { $0.id == id } }
        }
    }
}

/// 一条提醒，读出来时就从 `EKReminder` 上摘下来（`EKReminder` 不能跨线程带）。
private struct TasksPinReminder: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var due: Date
    var hasTime: Bool
    var list: String
    var isHighPriority: Bool

    init?(_ reminder: EKReminder) {
        guard let parsed = ReminderTiming.due(from: reminder.dueDateComponents) else { return nil }
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        id = reminder.calendarItemIdentifier
        self.title = title.isEmpty ? tr("新提醒事项") : title
        due = parsed.date
        hasTime = parsed.hasTime
        list = reminder.calendar?.title ?? ""
        isHighPriority = (1...4).contains(reminder.priority)
    }

    var dueValue: ReminderDue { ReminderDue(date: due, hasTime: hasTime) }
    func isOverdue(_ now: Date) -> Bool { ReminderTiming.isOverdue(dueValue, now: now) }
}

// MARK: - 便签

/// 便签的一张纸摊开：整张纸显示全文、纸里滚动、点一下就写，停手半秒自动保存。
/// 叠着的每一张都能单独钉出来，各自认 `StickySheet.id`，翻页不影响。
///
/// 纸感：顶上一条半透明胶带、右下角卷起、上浅下深一点点的光。中大号顶上一行「便签 · 第 2 张」；
/// 小号不写标题，字从顶上开始、小一档（不小于 13pt），叠了几张在右下角写「2/3」。
struct DesktopNoteSheet: View {
    var widget: WidgetInstance
    var sheetID: String?
    var size: DesktopPinSize

    @State private var draft: String
    @State private var editing = false
    /// 先不可编辑地造出编辑器，进窗口后再打开：可编辑的编辑器一造出来就把光标和滚动放到
    /// 末尾，桌面上的纸应该从头摊开。
    @State private var armed = false
    @State private var editor = StickyEditorHandle()
    @State private var hint: String?
    /// 不换：光标只在点纸时落下，不自己跳到末尾。
    private static let focusToken = UUID()

    init(widget: WidgetInstance, sheetID: String?, size: DesktopPinSize) {
        self.widget = widget
        self.sheetID = sheetID
        self.size = size
        _draft = State(initialValue: Self.locate(widget.config, sheetID)?.sheet.text ?? "")
    }

    /// 这一张在叠里第几张、现在的样子。钉的是整张便签（没有标识）时按最上面那张。
    static func locate(_ config: WidgetConfig, _ id: String?) -> (index: Int, count: Int, sheet: StickySheet)? {
        let pile = StickyStack.pile(config)
        if let id {
            guard let index = pile.index(ofSheet: id) else { return nil }
            return (index, pile.count, pile.sheets[index])
        }
        return (pile.page, pile.count, pile.front)
    }

    private var located: (index: Int, count: Int, sheet: StickySheet)? { Self.locate(widget.config, sheetID) }
    private var stored: String { located?.sheet.text ?? "" }
    private var unlocked: Bool { ProAccess.isUnlocked }
    private var swatch: PaperColor { located?.sheet.paper(unlocked: unlocked) ?? .yellow }
    private var noteFont: StickyNoteFont { StickyNoteFont.of(widget.config) }
    private var pointSize: CGFloat {
        let panel = StickyNoteType.panel(noteFont, StickyNoteSize.of(widget.config))
        return CGFloat(DesktopCardsTasksPlan.notePointSize(panel: panel, size: size))
    }
    private var showsTitle: Bool { DesktopCardsTasksPlan.noteShowsTitle(size) }

    var body: some View {
        let ink = Color(hex: swatch.inkHex)
        let dark = swatch.isDark
        ZStack(alignment: .topLeading) {
            Color(hex: swatch.hex)
            // 上浅下深一点点，纸有一点受光的感觉；不改字的对比度。
            LinearGradient(colors: [.white.opacity(dark ? 0.06 : 0.22), .clear, .black.opacity(dark ? 0.10 : 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                if showsTitle {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: .semibold))
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let hint {
                            Text(hint)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(ink.opacity(0.78))
                }
                StickyNoteEditor(
                    text: $draft,
                    look: .init(font: noteFont, size: pointSize, ink: swatch.inkHex,
                                faded: PaperInk.faded(on: swatch.hex), paper: swatch.hex),
                    editable: armed,
                    focusToken: Self.focusToken,
                    handle: editor,
                    onEditingChanged: { focused in
                        editing = focused
                        if !focused { commitLater() }
                    },
                    onCollapse: {
                        commitLater()
                        DesktopPinController.shared.releaseFocus()
                    },
                    onSend: send)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, size == .small ? 12 : 16)
            .padding(.top, size == .small ? 16 : 18)
            .padding(.bottom, size == .small ? 10 : 12)
        }
        .overlay(alignment: .top) { tape(dark: dark) }
        .overlay(alignment: .bottomTrailing) { curl(dark: dark) }
        .overlay(alignment: .bottomTrailing) {
            if !showsTitle { smallFooter(ink: ink) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            armed = true
        }
        .onChange(of: stored) { _, note in if !editing { draft = note } }
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !editor.isComposing else { return }
            commit()
        }
        .task(id: hint) {
            guard hint != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { hint = nil }
        }
    }

    /// 顶上一条斜贴的半透明胶带。
    private func tape(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(.white.opacity(dark ? 0.26 : 0.5))
            .frame(width: size == .small ? 44 : 60, height: 12)
            .rotationEffect(.degrees(-3))
            .offset(y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 右下角卷起的纸角。
    private func curl(dark: Bool) -> some View {
        Canvas { canvas, box in
            let w = box.width, h = box.height
            var shadow = Path()
            shadow.move(to: CGPoint(x: w, y: 0))
            shadow.addLine(to: CGPoint(x: 0, y: h))
            shadow.addLine(to: CGPoint(x: w, y: h))
            shadow.closeSubpath()
            canvas.fill(shadow, with: .color(.black.opacity(dark ? 0.30 : 0.10)))
            var flap = Path()
            flap.move(to: CGPoint(x: w, y: 0))
            flap.addLine(to: CGPoint(x: 0, y: h))
            flap.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.3, y: h * 0.3))
            flap.closeSubpath()
            canvas.fill(flap, with: .color(.white.opacity(dark ? 0.22 : 0.55)))
        }
        .frame(width: 18, height: 18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 小号没有标题行：叠了几张写「2/3」，刚发到待办这类提示也写在这里。
    @ViewBuilder
    private func smallFooter(ink: Color) -> some View {
        let text = hint ?? located.flatMap { $0.count > 1 ? "\($0.index + 1)/\($0.count)" : nil }
        if let text {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(0.75))
                .lineLimit(1)
                .padding(.trailing, 22)
                .padding(.bottom, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private var title: String {
        let name = WidgetCatalog.entry(.notes)?.name ?? tr("便签")
        guard let located, located.count > 1 else { return name }
        return name + " · " + tr("第 \(located.index + 1) 张")
    }

    private func commit() {
        guard draft != stored else { return }
        write(draft)
    }

    /// 失焦时的保存放到下一轮，回调在 SwiftUI 更新视图的中途触发。
    private func commitLater() {
        guard draft != stored else { return }
        let words = draft
        Task { @MainActor in write(words) }
    }

    /// 写回这一张（按标识找，不翻页）；找不到这张时（刚被撕掉）什么都不写。
    private func write(_ words: String) {
        let id = sheetID
        StickyLog.change(widget) { pile in
            if let id {
                guard let index = pile.index(ofSheet: id) else { return pile }
                return pile.writing(words, at: index)
            }
            return pile.writing(words)
        }
    }

    private func send(_ line: Int) {
        guard let words = StickyEditing.sendable(line: line, in: draft) else { return }
        guard let target = QuickTodoCapture.shared.target() else {
            NSSound.beep()
            withAnimation(.easeIn(duration: 0.15)) { hint = tr("没有快速待办") }
            return
        }
        TodoLog.add(words, to: target)
        withAnimation(.easeIn(duration: 0.15)) { hint = tr("已发到快速待办") }
    }
}

// MARK: - 习惯打卡

/// 小：今天打卡几项的环，下面一个大按钮给下一个没打的习惯打卡。
/// 中：三行，图标、名字、最近 7 天、连续天数、今天的打卡圆钮。
/// 大：顶上环和「今天 2/3」，下面最多六行，每行多一行连续天数。没解锁时第 4 个起画淡、点了弹付费墙。
private struct TasksPinHabit: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var habits: [Habit] { HabitTracker.habits(widget.config) }
    private var unlocked: Bool { ProAccess.isUnlocked }
    private var showsStreak: Bool { widget.config.bool("showStreak", default: true) }

    var body: some View {
        let all = habits
        let done = HabitTracker.doneToday(all, today: now)
        Group {
            if all.isEmpty {
                VStack(spacing: 8) {
                    TasksPinPanda(name: "pet-panda-rest", size: size == .small ? 70 : 84)
                    Text(tr("还没有习惯"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(tr("在扩展栏的面板里添加"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch size {
                case .small: small(all, done: done)
                case .medium: list(all, rows: DesktopCardsTasksPlan.listRows(.habit, size: .medium), roomy: false)
                case .large:
                    VStack(alignment: .leading, spacing: 14) {
                        header(all, done: done)
                        list(all, rows: DesktopCardsTasksPlan.listRows(.habit, size: .large), roomy: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("习惯打卡，\(HabitTracker.caption(done: done, total: all.count))"))
    }

    private var accent: Color { HabitStyle.accent }

    private func small(_ all: [Habit], done: Int) -> some View {
        let next = DesktopCardsTasksPlan.nextHabit(all, today: now, unlocked: unlocked)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                summaryRing(done: done, total: all.count, size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("今天打卡"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(tr("\(done) / \(all.count) 项"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if let next {
                let tint = HabitStyle.color(next)
                TasksPinPill(title: buttonTitle(next), symbol: next.iconName, tint: tint, filled: true,
                             height: 36, ink: Color(hex: PaperInk.ink(on: next.color?.hex ?? (WidgetCatalog.accentHex(.habit) ?? PaletteColor.green.hex)))) {
                    tap(next)
                }
                .help(todayHelp(next))
            } else {
                Label(tr("今天都打完了"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TasksPinPalette.green.panelReadable)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
        }
    }

    private func header(_ all: [Habit], done: Int) -> some View {
        let best = all.map { HabitTracker.streak($0, today: now) }.max() ?? 0
        return HStack(spacing: 12) {
            summaryRing(done: done, total: all.count, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("今天打卡"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(HabitTracker.caption(done: done, total: all.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if showsStreak, best > 0 {
                Text(tr("最长连续 \(best) 天"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent.panelReadable)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(accent.opacity(0.14)))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func summaryRing(done: Int, total: Int, size: CGFloat) -> some View {
        TasksPinRing(fraction: total == 0 ? 0 : Double(done) / Double(total), tint: accent, lineWidth: 5) {
            if total > 0, done >= total {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(accent.panelReadable)
            } else {
                Text(verbatim: "\(done)")
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }

    private func list(_ all: [Habit], rows: Int, roomy: Bool) -> some View {
        let cut = DesktopCardsTasksPlan.cut(total: all.count, rows: rows)
        return VStack(alignment: .leading, spacing: roomy ? 10 : 8) {
            ForEach(all.prefix(cut.shown)) { habit in
                habitRow(habit, locked: ProLicenseGate.isHabitLocked(habit.id, in: all, unlocked: unlocked),
                         roomy: roomy)
            }
            if cut.more > 0 { TasksPinMore(text: tr("还有 \(cut.more) 项")) }
        }
        .frame(maxHeight: roomy ? nil : .infinity)
    }

    private func habitRow(_ habit: Habit, locked: Bool, roomy: Bool) -> some View {
        let tint = HabitStyle.color(habit)
        let streak = HabitTracker.streak(habit, today: now)
        return HStack(spacing: 8) {
            Image(systemName: locked ? "lock.fill" : habit.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(locked ? Color.panelTertiary : tint.panelReadable)
                .frame(width: 18)
            if roomy {
                VStack(alignment: .leading, spacing: 0) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                    if showsStreak {
                        Text(tr("连续 \(streak) 天"))
                            .font(.system(size: 13))
                            .foregroundStyle(streak > 0 ? tint.panelReadable : Color.panelSecondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(habit.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            dots(habit, size: roomy ? 11 : 10)
            if showsStreak, !roomy {
                Text(verbatim: "\(streak)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(streak > 0 ? tint.panelReadable : Color.panelSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .trailing)
                    .help(tr("连续打卡 \(streak) 天"))
            }
            todayButton(habit, size: roomy ? 30 : 26)
        }
        .opacity(locked ? 0.5 : 1)
        .frame(minHeight: roomy ? 34 : 26)
    }

    /// 最近 6 天（今天在右边的打卡钮里）。
    private func dots(_ habit: Habit, size: CGFloat) -> some View {
        let tint = HabitStyle.color(habit)
        return HStack(spacing: 4) {
            ForEach(HabitTracker.week(habit, today: now).filter { !$0.isToday }, id: \.key) { day in
                Circle()
                    .fill(day.done ? tint.panelGraphic : Color.panelTrack)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// 今天的打卡钮：没打是空心圈（计数习惯按比例填一块），打了是实心打勾。
    private func todayButton(_ habit: Habit, size: CGFloat) -> some View {
        let tint = HabitStyle.color(habit)
        let done = HabitTracker.isDone(habit, on: now)
        let progress = done ? 0 : HabitTracker.progress(habit, on: now)
        return Button { tap(habit) } label: {
            ZStack {
                Circle().fill(done ? tint.panelGraphic : Color.panelFill)
                if !done { Circle().strokeBorder(tint.panelGraphic, lineWidth: 1.8) }
                if progress > 0 { HabitPie(fraction: progress).fill(tint.panelGraphic.opacity(0.55)) }
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(todayHelp(habit))
        .accessibilityLabel(done ? tr("取消 \(habit.name) 今天的打卡") : tr("\(habit.name) 今天打卡"))
    }

    private func buttonTitle(_ habit: Habit) -> String {
        guard habit.goal > 1 else { return habit.name }
        return "\(habit.name) \(HabitTracker.todayText(habit, today: now))"
    }

    private func todayHelp(_ habit: Habit) -> String {
        if HabitTracker.isDone(habit, on: now) { return tr("取消今天的打卡") }
        guard habit.goal > 1 else { return tr("今天打卡：\(habit.name)") }
        return tr("\(habit.name) 今天 \(HabitTracker.todayText(habit, today: now))，点一下加 1")
    }

    private func tap(_ habit: Habit) {
        withAnimation(.snappy(duration: 0.25)) { HabitLog.tap(habit.id, day: now, in: widget) }
    }
}

// MARK: - 喝水

/// 小：进度（圆环 / 角色 / 液态，跟卡片样式走）、「1200 / 2000」，右上角「+」加一杯。
/// 中：左边进度，中间数字、还差多少、上一杯几点，右边「+ 一杯」和「撤销」。
/// 大：再加最近 7 天的柱子和连续达标天数，底下「+ 一杯」「+ 半杯」「撤销」。
private struct TasksPinWater: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelTint) private var panelTint

    private var unlocked: Bool { ProAccess.isUnlocked }
    private var layout: WaterLayout {
        let earned = !unlocked && ProFeatures.waterCharacterEarned(widget.config, now: now)
        return ProLicenseGate.waterLayout(config: widget.config, unlocked: unlocked, earnedCharacter: earned)
    }
    private var ounces: Bool { WaterIntake.usesOunces(widget.config) }
    private var cup: Int { WaterIntake.cupSize(widget.config) }
    private var water: Color { panelTint.accent(or: WaterStyle.water) }

    var body: some View {
        let day = WaterIntake.today(widget.config, now: now)
        Group {
            switch size {
            case .small: small(day)
            case .medium: medium(day)
            case .large: large(day)
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("喝水，\(WaterIntake.tally(total: day.total, goal: day.goal, ounces: ounces))"))
    }

    private func small(_ day: WaterDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                progress(day, size: 74)
                Spacer(minLength: 0)
                plusButton(size: 38)
            }
            Spacer(minLength: 6)
            Text(verbatim: "\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
            Text(day.isMet ? tr("今天达标啦")
                 : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(day.isMet ? water.panelReadable : Color.panelSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func medium(_ day: WaterDay) -> some View {
        HStack(spacing: 16) {
            progress(day, size: 108)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: WaterIntake.figure(day.total, ounces: ounces))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                Text(verbatim: "/ \(WaterIntake.figure(day.goal, ounces: ounces)) \(WaterIntake.unitLabel(ounces: ounces))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                Text(day.isMet ? tr("今天达标啦") : WaterIntake.remainingLine(total: day.total, goal: day.goal, ounces: ounces))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(day.isMet ? water.panelReadable : Color.panelPrimary)
                if let last = lastDrink {
                    Text(tr("上一杯 \(last.formatted(date: .omitted, time: .shortened))"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                plusButton(size: 50)
                Text(verbatim: "+\(WaterIntake.figure(cup, ounces: ounces))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .monospacedDigit()
                undoButton
            }
            .frame(width: 64)
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ day: WaterDay) -> some View {
        let days = WaterIntake.days(widget.config)
        let week = WaterIntake.lastDays(days, goal: day.goal, today: now)
        let streak = WaterIntake.streak(days, goal: day.goal, today: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                progress(day, size: 96)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: WaterIntake.figure(day.total, ounces: ounces))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.panelPrimary)
                            .monospacedDigit()
                        Text(verbatim: "/ \(WaterIntake.figure(day.goal, ounces: ounces)) \(WaterIntake.unitLabel(ounces: ounces))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                    }
                    Text(day.isMet ? tr("今天达标啦") : WaterIntake.remainingLine(total: day.total, goal: day.goal, ounces: ounces))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(day.isMet ? water.panelReadable : Color.panelPrimary)
                    if streak > 0 {
                        Text(tr("连续达标 \(streak) 天"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(water.panelReadable)
                    } else if let last = lastDrink {
                        Text(tr("上一杯 \(last.formatted(date: .omitted, time: .shortened))"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            weekBars(week)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(Array(DesktopCardsTasksPlan.waterQuickAmounts(cup: cup).enumerated()), id: \.offset) { index, amount in
                    TasksPinPill(title: "+\(WaterIntake.amount(amount, ounces: ounces))", symbol: index == 0 ? "drop.fill" : nil,
                                 tint: water, filled: index == 0, height: 36) {
                        drink(amount)
                    }
                    .help(tr("喝了 \(WaterIntake.amount(amount, ounces: ounces))"))
                }
                TasksPinPill(title: tr("撤销"), symbol: "arrow.uturn.backward", tint: water, filled: false, height: 36) {
                    withAnimation(.snappy(duration: 0.3)) { WaterLog.undo(widget) }
                }
                .frame(width: 92)
                .disabled(day.entries.isEmpty)
            }
        }
    }

    // MARK: 部件

    private var lastDrink: Date? { WaterIntake.lastDrink(WaterIntake.days(widget.config)) }

    /// 进度：角色样式画角色，液态画一颗装水的球，圆环画圆环（超过目标不封顶，满圈后打勾）。
    @ViewBuilder
    private func progress(_ day: WaterDay, size: CGFloat) -> some View {
        let level = WaterIntake.progress(total: day.total, goal: day.goal)
        switch layout {
        case .character:
            let parched = WaterParched.isParched(widget.config, now: now)
            let look = WaterPose.look(stage: WaterPose.stage(total: day.total, goal: day.goal),
                                      dryHours: WaterPose.dryHours(widget.config, now: now),
                                      parched: parched, gulping: false)
            WaterPoseFigure(character: WaterCharacter.shown(widget.config, unlocked: unlocked), look: look,
                            height: size, reduceMotion: reduceMotion)
                .frame(width: size, height: size)
        case .liquid:
            ZStack(alignment: .bottom) {
                Circle().fill(water.opacity(0.12))
                Rectangle()
                    .fill(LinearGradient(colors: [water.opacity(0.65), water], startPoint: .top, endPoint: .bottom))
                    .frame(height: size * CGFloat(min(max(level, 0), 1)))
                Text(verbatim: "\(WaterIntake.percent(total: day.total, goal: day.goal))%")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                    .frame(maxHeight: .infinity)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(water.panelGraphic.opacity(0.5), lineWidth: 1))
            .animation(.smooth(duration: 0.5), value: level)
        case .ring:
            TasksPinRing(fraction: level, tint: water, lineWidth: size > 90 ? 9 : 7) {
                if day.isMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(water.panelReadable)
                } else {
                    Text(verbatim: "\(WaterIntake.percent(total: day.total, goal: day.goal))%")
                        .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func plusButton(size: CGFloat) -> some View {
        Button { drink(cup) } label: {
            Image(systemName: "plus")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(water.panelGraphic))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(tr("喝了一杯水（\(WaterIntake.amount(cup, ounces: ounces))）"))
        .accessibilityLabel(tr("记录一杯水，\(WaterIntake.amount(cup, ounces: ounces))"))
    }

    private var undoButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { WaterLog.undo(widget) }
        } label: {
            Text(tr("撤销"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.panelFill))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(tr("撤销上一杯"))
    }

    private func weekBars(_ week: [WaterDayReading]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(week, id: \.key) { reading in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.panelTrack)
                        Capsule()
                            .fill(reading.isMet ? water.panelGraphic : water.panelGraphic.opacity(0.55))
                            .frame(height: max(4, 54 * CGFloat(reading.fraction)))
                    }
                    .frame(width: 14, height: 54)
                    Text(reading.isToday ? tr("今天") : weekday(reading.date))
                        .font(.system(size: 13, weight: reading.isToday ? .bold : .regular))
                        .foregroundStyle(reading.isToday ? Color.panelPrimary : Color.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: L10n.interfaceLocale).weekday(.narrow))
    }

    private func drink(_ amount: Int) {
        withAnimation(.snappy(duration: 0.35)) { WaterLog.drink(.water, amount: amount, in: widget) }
    }
}

// MARK: - 久坐提醒

/// 小：小熊猫（打盹 / 伸懒腰 / 趴着）、已坐几分钟，底下「起来了」（到点时是实心粉色）。
/// 中：左边小熊猫，中间状态、六格进度、今日起身几次，右边大按钮。
/// 大：再加下次提醒时间、近 7 天每天起身次数的柱子和目标线，底下整条「我起身活动了」。
private struct TasksPinPosture: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var schedule: PostureSchedule { PostureSchedule(config: widget.config) }
    private var timer: TimerState { TimerStateProvider.shared.state }

    private var lastBreak: Date? {
        let raw = widget.config.double("lastBreak")
        return SitFocus.lastBreak(posture: raw > 0 ? Date(timeIntervalSince1970: raw) : nil, timer: timer)
    }
    private var active: Bool { schedule.isActive(now) }
    private var yields: Bool { SitFocus.postureYields(to: timer, now: now) }
    private var away: Bool { PostureAway.suppresses(widget.config, away: PostureAwayMonitor.shared.isAway) }
    private var remaining: TimeInterval { schedule.remaining(lastBreak: lastBreak, now: now) }
    private var sat: TimeInterval { SitFocus.sat(schedule, lastBreak: lastBreak, now: now) }
    private var due: Bool { active && !yields && !away && remaining <= 0 }
    private var breaksToday: Int {
        PostureTally.today(storedDay: widget.config.string("breakDay"),
                           count: widget.config.int("breakCount"), now: now)
    }
    private var nextReminder: Date? {
        guard !yields, !away else { return nil }
        return schedule.nextReminder(lastBreak: lastBreak, now: now)
    }
    private var pandaName: String {
        if due { return "pet-panda-cheer" }
        if yields { return "pet-panda-melt" }
        return "pet-panda-rest"
    }
    private var pink: Color { Color.timerPink }

    var body: some View {
        ZStack {
            if due { wash }
            Group {
                switch size {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
            .padding(DesktopCardsTasks.inset(size))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { PostureNotifier.shared.update(widget, next: nextReminder) }
        .onChange(of: nextReminder) { _, next in PostureNotifier.shared.update(widget, next: next) }
    }

    /// 到点时小熊猫身后一层渐隐的粉色淡底（不顶替玻璃，字照旧在玻璃上读）。
    private var wash: some View {
        RadialGradient(colors: [pink.opacity(0.30), pink.opacity(0)], center: .topLeading,
                       startRadius: 10, endRadius: size == .medium ? 220 : 240)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 状态的一大一小两行。
    private var headline: (title: String, detail: String) {
        if due { return (tr("该起来走走了"), SitFocus.satText(max(60, sat))) }
        if yields { return (tr("专注中"), tr("休息时再起身")) }
        if away { return (tr("离开电脑中"), tr("回来后从头计时")) }
        if !active { return (tr("不在提醒时段"), tr("今日已起身 \(breaksToday) 次")) }
        return (SitFocus.satText(sat), SitFocus.dueText(schedule.interval))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                TimerPanda(name: pandaName, fallback: "figure.stand", height: 58)
                    .frame(width: 52)
                Spacer(minLength: 0)
                if active, !yields {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "\(Int(sat / 60))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.panelPrimary)
                            .monospacedDigit()
                        Text(tr("分钟"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(due ? tr("该起来走走了") : headline.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            breakButton(title: tr("起来了"), height: 32)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            TimerPanda(name: pandaName, fallback: "figure.stand", height: 96)
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(headline.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                Text(headline.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                if active, !yields { cells(width: 20) }
                Text(tr("今日已起身 \(breaksToday) 次"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            breakButton(title: tr("起来了"), height: 44)
                .frame(width: 76)
        }
        .frame(maxHeight: .infinity)
    }

    private var large: some View {
        let goal = PostureTrack.goal(widget.config)
        let week = PostureTrack.week(widget.config, todayCount: breaksToday, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TimerPanda(name: pandaName, fallback: "figure.stand", height: 92)
                    .frame(width: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                    Text(headline.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                    if active, !yields { cells(width: 24) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                infoTile(tr("今日起身"), value: tr("\(breaksToday) / \(goal) 次"))
                infoTile(tr("下次提醒"), value: nextReminder.map { $0.formatted(date: .omitted, time: .shortened) } ?? "--")
            }
            weekBars(week, goal: goal)
            Spacer(minLength: 0)
            breakButton(title: tr("我起身活动了"), height: 40)
        }
    }

    private func cells(width: CGFloat) -> some View {
        let lit = SitFocus.litCells(sat: sat, interval: schedule.interval)
        return HStack(spacing: 4) {
            ForEach(0..<SitFocus.cells, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? pink.panelGraphic : Color.panelTrack)
                    .frame(width: width, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func infoTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
    }

    private func weekBars(_ week: [PostureTrack.Day], goal: Int) -> some View {
        let ceiling = Double(PostureTrack.chartCeiling(week, goal: goal))
        let height: CGFloat = 46
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(week, id: \.date) { day in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.panelTrack)
                        Capsule()
                            .fill(day.count >= goal ? pink.panelGraphic : pink.panelGraphic.opacity(0.55))
                            .frame(height: max(4, height * CGFloat(Double(day.count) / max(ceiling, 1))))
                    }
                    .frame(width: 14, height: height)
                    Text(day.isToday ? tr("今天")
                         : day.date.formatted(Date.FormatStyle(locale: L10n.interfaceLocale).weekday(.narrow)))
                        .font(.system(size: 13, weight: day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? Color.panelPrimary : Color.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// 到点时是实心粉色，平时是浮起的玻璃小块（提前起身也能记一次，和面板一样）。
    private func breakButton(title: String, height: CGFloat) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.35)) { PostureLog.logBreak(widget) }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(due ? Color.timerPinkInk : Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    if due {
                        Capsule().fill(pink)
                    } else {
                        Capsule().fill(Color.panelRaised).panelLift()
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("记录一次起身"))
    }
}

// MARK: - 小熊猫的竹篮

/// 小：今天的竹叶（今日三环样式画三环），下面三个小环。
/// 中：左边竹叶，右边三行，每行小环、名字和「1200/2000 毫升」。
/// 大：竹叶和一句话，三行带进度条，底下近 7 天每天收到的竹叶。只读，不写别的小组件。
private struct TasksPinPerfectDay: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var center: PerfectDayCenter { .shared }
    private var isRings: Bool { TodayRings.isRings(widget.config) }

    var body: some View {
        let items = center.progress(now: now)
        let tier = PerfectDay.record(items, key: "").tier
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    TasksPinPanda(name: "pet-panda-rest", size: size == .small ? 66 : 80)
                    Text(tr("把喝水、习惯打卡或专注计时放进扩展栏"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch size {
                case .small: small(items, tier: tier)
                case .medium: medium(items, tier: tier)
                case .large: large(items, tier: tier)
                }
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { center.refresh(now: now) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("小熊猫的竹篮，今天\(tier.map { tr("收到\($0.leafName)") } ?? tr("还没有竹叶"))"))
    }

    @ViewBuilder
    private func hero(_ items: [PerfectDayProgress], tier: PerfectDayTier?, size: CGFloat) -> some View {
        if isRings {
            TasksPinTriRing(items: items)
                .frame(width: size, height: size)
        } else {
            LeafGlyph(tier: tier, size: size, emptyInk: Color.panelTertiary)
                .frame(width: size, height: size)
                .animation(.smooth(duration: 0.4), value: tier)
        }
    }

    private func title(_ tier: PerfectDayTier?) -> String { tier?.title ?? tr("还没有竹叶") }

    private func small(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        VStack(spacing: 8) {
            hero(items, tier: tier, size: 68)
            Text(title(tier))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tier == nil ? Color.panelSecondary : Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(spacing: 10) {
                ForEach(items) { item in PerfectItemRing(progress: item, size: 22, track: Color.panelPrimary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                hero(items, tier: tier, size: 84)
                Text(title(tier))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tier == nil ? Color.panelSecondary : Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 96)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in itemRow(item, bar: false) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        let week = TodayRings.week(center.records(now: now), today: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                hero(items, tier: tier, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(tier))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                    Text(PerfectDay.headline(tier))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                ForEach(items) { item in itemRow(item, bar: true) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(week) { day in
                    VStack(spacing: 3) {
                        LeafGlyph(tier: day.record?.tier, size: 24, emptyInk: Color.panelTertiary)
                            .frame(width: 24, height: 24)
                        Text(day.label)
                            .font(.system(size: 13, weight: day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? Color.panelPrimary : Color.panelSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func itemRow(_ item: PerfectDayProgress, bar: Bool) -> some View {
        let tint = Color(hex: item.item.hex)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                PerfectItemRing(progress: item, size: 20, track: Color.panelPrimary)
                Text(item.item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                Spacer(minLength: 6)
                Text(item.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.mark == .met ? tint.panelReadable : Color.panelSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            if bar {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.panelTrack)
                        Capsule()
                            .fill(tint.panelGraphic)
                            .frame(width: max(6, proxy.size.width * CGFloat(min(max(item.fraction, 0), 1))))
                            .opacity(item.mark.takesPart ? 1 : 0)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

/// 今日三环样式：喝水、专注、习惯三圈同心环。
private struct TasksPinTriRing: View {
    var items: [PerfectDayProgress]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.11
            ZStack {
                ForEach(Array(TodayRings.order.enumerated()), id: \.offset) { index, kind in
                    let item = items.first { $0.item == kind }
                    let inset = CGFloat(index) * (line + 2) + line / 2
                    Circle()
                        .stroke(Color(hex: kind.hex).opacity(0.18), lineWidth: line)
                        .padding(inset)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(item?.fraction ?? 0, 0), 1)))
                        .stroke(Color(hex: kind.hex).panelGraphic, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                        .opacity(item?.mark.takesPart == true ? 1 : 0)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 电子宠物

/// 小：角色、「名字 · 状态」一行，底下一个按钮做眼下最要紧的事（病了看病，否则照顾最低的那项）。
/// 中：左边角色，右边名字状态和四个需求格（点一格喂、玩、睡、洗）。
/// 大：角色放大在上，整体几成，四个大格带数值，病了多一个「带它看病」。
private struct TasksPinPet: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @AppStorage(VirtualPet.missedDaysDefault) private var missedDays = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var character: WaterCharacter {
        WaterCharacter.petShown(widget.config, unlocked: ProAccess.isUnlocked)
    }
    private var petName: String { VirtualPet.name(widget.config, fallback: character.title) }
    private var dried: Bool { VirtualPet.isDried(widget.config, missedDays: missedDays) }
    private var melted: Bool { PetMelt.now }
    private var state: PetState {
        VirtualPet.advanced(VirtualPet.state(widget.config, now: now), to: now)
    }

    var body: some View {
        let s = state
        let look = VirtualPet.look(s, now: now, dried: dried, melted: melted)
        Group {
            switch size {
            case .small: small(s, look: look)
            case .medium: medium(s, look: look)
            case .large: large(s, look: look)
            }
        }
        .padding(DesktopCardsTasks.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { PetLog.collect(in: widget, now: now) }
        .onChange(of: now) { _, value in PetLog.collect(in: widget, now: value) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("电子宠物\(petName)，\(VirtualPet.statusLine(s, now: now, dried: dried, melted: melted))"))
    }

    private func status(_ s: PetState) -> String {
        VirtualPet.statusLine(s, now: now, dried: dried, melted: melted)
    }

    private func figure(_ s: PetState, look: PetLook, height: CGFloat) -> some View {
        PetFigure(character: character, look: look, height: height, effect: VirtualPet.effect(s, now: now))
            .frame(height: height)
            .help(petName)
    }

    private func small(_ s: PetState, look: PetLook) -> some View {
        let action = DesktopCardsTasksPlan.petPrimaryAction(s)
        return VStack(spacing: 6) {
            figure(s, look: look, height: 64)
            Text(verbatim: "\(petName) · \(status(s))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PetStyle.headline(look: look, health: s.health).panelReadable)
            Spacer(minLength: 0)
            TasksPinPill(title: actionTitle(action, s), symbol: action.symbol, tint: PetStyle.accent,
                         filled: action == .heal, height: 30) {
                act(action)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ s: PetState, look: PetLook) -> some View {
        HStack(spacing: 14) {
            figure(s, look: look, height: 112)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: petName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(status(s))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PetStyle.tint(look: look, health: s.health).panelReadable)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                needGrid(s, tall: false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ s: PetState, look: PetLook) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                figure(s, look: look, height: 120)
                    .frame(width: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: petName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(status(s))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PetStyle.tint(look: look, health: s.health).panelReadable)
                    Text(tr("整体 \(Int(s.health.rounded()))") + "%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            needGrid(s, tall: true)
            if VirtualPet.isSick(s) {
                TasksPinPill(title: tr("带它看病"), symbol: PetAction.heal.symbol, tint: TasksPinPalette.red,
                             filled: true, height: 32) {
                    act(.heal)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func needGrid(_ s: PetState, tall: Bool) -> some View {
        let urgent = WaterPetCards.mostNeeded(s)
        return Grid(horizontalSpacing: 8, verticalSpacing: tall ? 8 : 6) {
            GridRow {
                needCell(.food, s, urgent: urgent, tall: tall)
                needCell(.mood, s, urgent: urgent, tall: tall)
            }
            GridRow {
                needCell(.energy, s, urgent: urgent, tall: tall)
                needCell(.clean, s, urgent: urgent, tall: tall)
            }
        }
    }

    /// 一个需求格：图标、名字（大号再写数值）、一条进度条，点一下做对应的事。
    private func needCell(_ need: PetNeed, _ s: PetState, urgent: PetNeed?, tall: Bool) -> some View {
        let action = WaterPetCards.action(for: need)
        let hot = need == urgent
        let red = TasksPinPalette.red
        return Button { act(action) } label: {
            VStack(alignment: .leading, spacing: tall ? 6 : 4) {
                HStack(spacing: 5) {
                    Image(systemName: need.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Text(need.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    if tall {
                        Text(verbatim: "\(Int(s[need].rounded()))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(hot ? red.panelReadable(minContrast: 4.5) : Color.panelPrimary)
                .lineLimit(1)
                PetBar(value: s[need], height: tall ? 6 : 5, tint: hot ? red : nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, tall ? 10 : 5)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hot ? red.opacity(0.14) : Color.panelFill))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(WaterPetCards.cellHelp(need, state: s))
        .accessibilityLabel(WaterPetCards.cellHelp(need, state: s))
    }

    private func actionTitle(_ action: PetAction, _ s: PetState) -> String {
        action == .sleep && s.isSleeping ? tr("叫醒") : action.title
    }

    private func act(_ action: PetAction) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { PetLog.act(action, in: widget) }
    }
}
