import SwiftUI

/// 快速待办的卡片（v3，204×58pt，竖排 76pt 宽）：左边进度环写「今天」还剩几件，右边今天
/// 最前两条（13pt，圆圈按标签色，截止胶囊照旧）。
///
/// 只读「今天」一组：今天空了而稍后有事时写「今天清空啦」，不去拉稍后的上来；清空时
/// 环变绿、小熊猫欢呼，写连续几天和最近 7 天的小点。一条都没有时是歇着的小熊猫，
/// 点卡片打开面板，光标直接在输入框里。拖文字、链接、文件进来：橙色虚线框，松手记成
/// 一条，落进「稍后」。
///
/// 在卡片上点圆圈：填色打勾、划线，约 1 秒后下一条顶上来、环走一格（减少动态效果时直接换）；
/// 点其余地方打开面板；链接行的小按钮照旧能打开。到点照旧弹卡片（`TimedAlertDriver`）。
///
/// 第二天第一次显示时先收拾一遍（`QuickTodo.applyRollover`）：昨天做完的收进“已收起”（留 7 天），
/// 昨天没做完的「今天」自动排到今天最前面。
struct TodoTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrateAt: Date?
    @State private var targeted = false
    /// 在卡片上刚勾上、还没真的写进去的几条（约 1 秒后才写）。
    @State private var completing: Set<String> = []

    private var today: String { TodoDay.key(context.now) }
    private var unlocked: Bool { context.isPreview || ProAccess.isUnlocked }

    private var items: [TodoItem] {
        if context.isPreview {
            let day = TodoDay.key(context.now)
            let yesterday = TodoDay.previous(day) ?? day
            return [TodoItem(id: "s1", text: tr("回复产品评审"), done: true, today: true, doneDay: day),
                    TodoItem(id: "s2", text: tr("交电费"), today: true, addedDay: yesterday,
                             todaySince: yesterday, tag: .red),
                    TodoItem(id: "s3", text: tr("回复产品评审意见"), today: true,
                             remindAt: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: context.now),
                             todaySince: day, tag: .orange),
                    TodoItem(id: "s4", text: tr("取快递"), today: true, todaySince: day),
                    TodoItem(id: "s5", text: tr("订周五的会议室"))]
        }
        return QuickTodo.items(instance.config)
    }

    var body: some View {
        let all = items
        let state: TodoCardState = context.isPreview ? .list : QuickTodo.cardState(all)
        let rows = QuickTodo.cardTodayRows(all)
        let left = QuickTodo.items(in: .today, of: all).filter { !completing.contains($0.id) }.count
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    vertical(state: state, rows: rows, left: left, all: all)
                } else {
                    switch state {
                    case .empty: emptyCard
                    case .cleared: clearedCard(all)
                    case .list: listCard(rows, left: left, all: all)
                    }
                }
            }
            // 拖入时不在清单上盖字：和文件暂存、隔空投送、废纸篓同一排法，
            // 橙色虚线框写“记一条待办 / 文字、链接、文件都行”，松手回到清单。
            .dropHidden(targeted)
        }
        .dropTargetOutline(targeted, prompt: .todo, compact: context.position.isVertical)
        .onDrop(of: TodoDropDelegate.types, delegate: TodoDropDelegate(
            enabled: !context.isPreview,
            targeted: { targeted = $0 },
            receive: { drops in
                withAnimation(.snappy(duration: 0.3)) { TodoLog.add(drops, to: instance) }
            }))
        .help(context.isPreview ? "" : tr("把文字、链接或文件拖到这里，记一条待办"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rows.first.map { tr("快速待办：\($0.text)") } ?? tr("快速待办"))
        // 第二天第一次画出来时收拾一遍；`now` 每秒走一下，日子变了才会再跑。
        .task(id: today) {
            guard !context.isPreview else { return }
            TodoLog.rollOver(instance, today: today)
        }
        .task(id: celebrateAt) {
            guard celebrateAt != nil else { return }
            try? await Task.sleep(for: .seconds(CheerMotion.duration))
            guard !Task.isCancelled else { return }
            celebrateAt = nil
        }
        // 设成“有未完成的待办时显示”时，全部完成后卡片要等庆祝播完才收起：
        // 勾掉最后一项时记下了截止时刻，到点由卡片自己清掉，扩展栏随即把它收起。
        // 放在卡片上而不只在面板里，面板中途关掉时也照样会清。
        .task(id: cheerDeadline) {
            guard let cheerDeadline, !context.isPreview else { return }
            let left = cheerDeadline - Date().timeIntervalSince1970
            if left > 0 {
                try? await Task.sleep(for: .seconds(min(left, QuickTodo.cheerHold + 1)))
                guard !Task.isCancelled else { return }
            }
            TodoLog.endCheer(instance)
        }
        // 在弹出卡片或面板里把「今天」清空了：卡片上的小熊猫也欢呼。
        .onChange(of: cheerDeadline) { old, new in
            if old == nil, new != nil, celebrateAt == nil, !context.isPreview { celebrateAt = .now }
        }
    }

    // MARK: 横排

    /// 左边进度环写还剩几件，右边今天最前两条。
    private func listCard(_ rows: [TodoItem], left: Int, all: [TodoItem]) -> some View {
        HStack(spacing: 10) {
            ring(all, left: left, size: 44)
                .overlay { cheer(size: 60) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { item in
                    row(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ring(_ all: [TodoItem], left: Int, size: CGFloat) -> some View {
        let tally = QuickTodo.todayTally(all, today: today)
        let done = tally.done + completing.count
        let fraction = tally.total == 0 ? 0 : Double(min(done, tally.total)) / Double(tally.total)
        return TodoProgressRing(fraction: fraction, complete: false, lineWidth: 4, tint: Self.orange) {
            Text(verbatim: "\(left)")
                .font(.system(size: size * 0.42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: left)
        .accessibilityLabel(tr("今天还剩 \(left) 件"))
    }

    private func row(_ item: TodoItem) -> some View {
        let checked = item.done || completing.contains(item.id)
        let tag = TodoTag.shown(item.tag, unlocked: unlocked)
        return HStack(spacing: 6) {
            Button {
                toggle(item)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(tag?.graphic ?? WidgetStyle.secondary, lineWidth: 1.4)
                        .opacity(checked ? 0 : 1)
                    Circle()
                        .fill(Self.green)
                        .opacity(checked ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(checked ? 1 : 0)
                }
                .frame(width: 15, height: 15)
                .frame(width: 18, height: 20)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview || checked)
            .help(tr("完成“\(item.text)”"))
            .accessibilityLabel(tr("完成 \(item.text)"))

            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(checked ? WidgetStyle.secondary : WidgetStyle.primary)
                .strikethrough(checked, color: WidgetStyle.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if item.url != nil {
                Button {
                    TodoLinkOpener.open(item)
                } label: {
                    Image(systemName: TodoLinkOpener.symbol(item))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                        .frame(width: 16, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .help(tr("打开“\(item.text)”"))
                .accessibilityLabel(tr("打开 \(item.text)"))
            }
            if !checked, let badge = QuickTodo.dueBadge(item, now: context.now) {
                capsule(badge, alarm: item.remindAt != nil)
            }
        }
        .frame(height: 20)
    }

    /// 截止胶囊：过期红、今天橙、以后灰；有提醒的带小闹钟。
    private func capsule(_ badge: TodoDueBadge, alarm: Bool) -> some View {
        let ink: Color
        let fill: Color
        switch badge.tone {
        case .late:
            ink = Self.red.panelReadable(minContrast: 4.5)
            fill = Self.red.opacity(0.15)
        case .today:
            ink = Self.orange.panelReadable(minContrast: 4.5)
            fill = Self.orange.opacity(0.17)
        case .later:
            ink = WidgetStyle.secondary
            fill = WidgetStyle.primary.opacity(0.08)
        }
        return HStack(spacing: 2) {
            if alarm {
                Image(systemName: "alarm")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(badge.text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Capsule().fill(fill))
        .fixedSize()
        .help(alarm ? tr("\(badge.text) 提醒") : badge.text)
    }

    /// 「今天」清空：环变绿、小熊猫欢呼，写连续几天和最近 7 天的小点。
    private func clearedCard(_ all: [TodoItem]) -> some View {
        let streak = context.isPreview ? 3 : QuickTodo.streak(instance.config, today: today)
        let week = context.isPreview ? [false, false, false, false, true, true, true]
            : TodoStreak.week(instance.config, today: today)
        let later = QuickTodo.items(in: .later, of: all).count
        return HStack(spacing: 10) {
            TodoProgressRing(fraction: 1, complete: true, lineWidth: 3.5, tint: Self.green) {
                TodoPanda(name: "pet-panda-cheer", size: 34)
            }
            .frame(width: 44, height: 44)
            .overlay { cheer(size: 70) }
            VStack(alignment: .leading, spacing: 4) {
                Text("今天清空啦")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    if streak > 0 {
                        Text(tr("连续 \(streak) 天"))
                            .foregroundStyle(Self.green.panelReadable)
                    } else if later > 0 {
                        Text(tr("稍后还有 \(later) 件"))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    TodoWeekDots(days: week, labels: nil, size: 8)
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 一条都没有：歇着的小熊猫。
    private var emptyCard: some View {
        HStack(spacing: 10) {
            TodoPanda(name: "pet-panda-rest", size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("清单空空的")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("点我写一件，或拖进来")
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 竖排（76pt 宽）

    @ViewBuilder
    private func vertical(state: TodoCardState, rows: [TodoItem], left: Int, all: [TodoItem]) -> some View {
        VStack(spacing: 4) {
            switch state {
            case .empty:
                TodoPanda(name: "pet-panda-rest", size: 40)
                Text("空空的")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case .cleared:
                TodoProgressRing(fraction: 1, complete: true, lineWidth: 3, tint: Self.green) {
                    TodoPanda(name: "pet-panda-cheer", size: 30)
                }
                .frame(width: 40, height: 40)
                .overlay { cheer(size: 60) }
                Text("清空啦")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.green.panelReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case .list:
                ring(all, left: left, size: 40)
                    .overlay { cheer(size: 60) }
                Text("今天")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                if let first = rows.first {
                    row(first)
                }
            }
        }
    }

    private static let green = Color(hex: "#2FA36B")
    private static let red = Color(hex: "#E5484D")
    private static let orange = Color(hex: PaletteColor.orange.hex)

    /// 在卡片上点圆圈：先填色划线，约 1 秒后才写进去（下一条顶上来、环走一格）。
    private func toggle(_ item: TodoItem) {
        guard !context.isPreview, !completing.contains(item.id) else { return }
        let id = item.id
        guard !reduceMotion, !item.done else {
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
        let current = QuickTodo.items(instance.config)
        guard current.contains(where: { $0.id == id && !$0.done }) else { return }
        let clearing = QuickTodo.clearsToday(toggling: id, in: current)
        withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(id, in: instance, cheering: clearing) }
        if clearing { celebrateAt = .now }
    }

    /// 庆祝的截止时刻，没有时为 nil。
    private var cheerDeadline: Double? {
        if case .number(let until) = instance.config[QuickTodo.cheerKey] { return until }
        return nil
    }

    /// 「今天」清空那一下小熊猫从环里跳出来。
    @ViewBuilder
    private func cheer(size: CGFloat) -> some View {
        if let celebrateAt {
            TodoCheer(startedAt: celebrateAt, compact: true)
                .frame(width: size, height: size)
        }
    }
}

/// The writes both the tile and the panel make, each from the instance's
/// current list so the two can never disagree.
@MainActor
enum TodoLog {
    /// 现在保存着的那份：拖放和转成提醒事项是异步落下的，手里的可能已经旧了。
    private static func latest(_ instance: WidgetInstance) -> WidgetInstance {
        WidgetWriter.current(instance.id) ?? instance
    }

    static var today: String { TodoDay.key(Date()) }

    static func change(_ instance: WidgetInstance, _ edit: ([TodoItem]) -> [TodoItem]) {
        WidgetWriter.write(latest(instance)) { config in
            QuickTodo.store(edit(QuickTodo.items(config)), in: &config)
        }
        synced(instance)
    }

    /// 写过清单：这张卡片打开了和提醒事项的双向同步（Pro）时排一轮。
    private static func synced(_ instance: WidgetInstance) {
        TodoReminderSyncService.shared.localChanged(instance.id)
    }

    /// - Parameter cheering: 这一下把「今天」一组清空了。同一次写入里记下庆祝的截止
    ///   时刻，免得“有未完成的待办时显示”在动效播出来之前就把卡片收走，也记一笔
    ///   连续清空的天数。
    static func toggle(_ id: String, in instance: WidgetInstance, cheering: Bool = false) {
        let day = today
        WidgetWriter.write(latest(instance)) { config in
            // 重复待办（Pro）勾掉时生成下一次；没解锁时规则照旧存着，只是不生成。
            QuickTodo.store(QuickTodo.toggling(id, in: QuickTodo.items(config), day: day,
                                               repeats: ProLicenseGate.canRepeatTodos(unlocked: ProAccess.isUnlocked)),
                            in: &config)
            if cheering {
                QuickTodo.startCheer(in: &config)
                QuickTodo.recordCleared(in: &config, today: day)
            }
        }
        synced(instance)
    }

    /// 记一条：输入框和快捷键小框都走这里，记下今天的日子。
    ///
    /// 认自然语言时间（`TodoTimeParse`）：「明天 9 点交稿」记成“交稿”，明天 9:00
    /// 提醒，在「稍后」；提醒在今天或只说了“今天”的放进「今天」。认不出时整句照记。
    static func add(_ text: String, link: String? = nil, to instance: WidgetInstance, now: Date = Date()) {
        let day = TodoDay.key(now)
        if let parsed = TodoTimeParse.parse(text, now: now) {
            change(instance) {
                QuickTodo.adding(parsed.title, to: $0, link: link, day: day,
                                 today: parsed.today, remindAt: parsed.remindAt)
            }
        } else {
            change(instance) { QuickTodo.adding(text, to: $0, link: link, day: day) }
        }
    }

    static func add(_ drops: [TodoDrop], to instance: WidgetInstance) {
        let day = today
        change(instance) { items in
            drops.reduce(items) { QuickTodo.adding($1.text, to: $0, link: $1.link, day: day) }
        }
    }

    /// 从“已收起”里恢复一条，放回清单末尾当作今天没做完的。
    static func restore(_ id: String, in instance: WidgetInstance) {
        let day = today
        WidgetWriter.write(latest(instance)) { config in
            let result = QuickTodo.restoring(id, items: QuickTodo.items(config),
                                             archive: QuickTodo.archive(config), today: day)
            QuickTodo.store(result.items, in: &config)
            QuickTodo.storeArchive(result.archive, in: &config)
        }
        synced(instance)
    }

    /// 从“已收起”里删掉一条。
    static func removeArchived(_ id: String, in instance: WidgetInstance) {
        WidgetWriter.write(latest(instance)) { config in
            QuickTodo.storeArchive(QuickTodo.removingArchived(id, from: QuickTodo.archive(config)), in: &config)
        }
        synced(instance)
    }

    /// 新的一天第一次显示时收拾一遍。今天已经收拾过就什么也不写。
    static func rollOver(_ instance: WidgetInstance, today: String) {
        let current = latest(instance)
        guard QuickTodo.needsRollover(current.config, today: today) else { return }
        WidgetWriter.write(current) { QuickTodo.applyRollover(in: &$0, today: today) }
        synced(instance)
    }

    /// 庆祝播完：清掉记号。读的是现在保存着的那份，不会把中途的改动写回去。
    static func endCheer(_ instance: WidgetInstance) {
        let saved = latest(instance)
        guard saved.config[QuickTodo.cheerKey] != nil else { return }
        WidgetWriter.write(saved) { QuickTodo.endCheer(in: &$0) }
    }
}
