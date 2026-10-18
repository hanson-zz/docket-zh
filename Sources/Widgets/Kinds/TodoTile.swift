import SwiftUI

/// 快速待办的卡片：“今天三件事”，拖进来就记，做完了小熊猫庆祝。
///
/// The list is the widget's own (see `QuickTodo`), never the system's
/// Reminders, so it works with no permission and no account. The card's
/// click opens the panel, where items are added and marked for today. On the
/// card the circle beside each row finishes it and a link or file row has a
/// small button that opens it. Text, links and files dropped on the card each
/// become a task.
///
/// 第二天第一次显示时先收拾一遍（`QuickTodo.applyRollover`）：昨天做完的收进“已收起”（留 7 天），
/// 没做完的留给面板顶部问顺延还是放弃。
///
/// 设了提醒时间的一行后面有个小闹钟和时刻；到点那一秒弹出卡片（到点弹出卡片
/// ▸ 待办），在卡片上点完成时这里照样庆祝。弹出卡片关着时只响一声。
struct TodoTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var celebrateAt: Date?
    @State private var targeted = false

    private var today: String { TodoDay.key(context.now) }

    private var items: [TodoItem] {
        if context.isPreview {
            let day = TodoDay.key(context.now)
            return [TodoItem(id: "s1", text: tr("回复产品评审"), done: true, today: true, doneDay: day),
                    TodoItem(id: "s2", text: tr("取快递"), today: true),
                    TodoItem(id: "s3", text: tr("交电费"), today: true,
                             remindAt: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: context.now)),
                    TodoItem(id: "s4", text: tr("订周五的会议室"))]
        }
        return QuickTodo.items(instance.config)
    }

    var body: some View {
        let all = items
        let open = QuickTodo.open(all)
        let done = all.count - open.count
        let progress = all.isEmpty ? 0 : Double(done) / Double(all.count)
        let card = QuickTodo.cardRows(all)
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    VStack(spacing: 4) {
                        TileBadge(size: WidgetStyle.badgeCompact) {
                            badge(open: open.count, progress: progress, size: 13, empty: empty(all, open: open),
                                  badgeSize: WidgetStyle.badgeCompact)
                        }
                            .overlay { cheer(size: 60) }
                        Text(open.isEmpty ? (empty(all, open: open) ?? .todo).line(compact: true) : tr("\(open.count) 项"))
                            .font(WidgetStyle.title)
                            .foregroundStyle(WidgetStyle.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        checkButton(card.rows.first(where: { !$0.done }) ?? open.first, size: 10)
                    }
                } else if all.isEmpty || open.isEmpty {
                    finished(all: all)
                } else {
                    list(card, openCount: open.count)
                }
            }
            // 拖入时不再在清单上盖一层字：和文件暂存、隔空投送、废纸篓同一排法，
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
        .accessibilityLabel(card.rows.first.map { tr("快速待办：\($0.text)") } ?? tr("快速待办"))
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
        // 到点的提醒弹出卡片。`now` 每秒走一下，只看这一秒里到点的。
        .onChange(of: context.now) { old, new in popIfDue(from: old, to: new) }
        // 在弹出卡片上勾掉了最后一项：卡片上的小熊猫也欢呼。
        .onChange(of: cheerDeadline) { old, new in
            if old == nil, new != nil, celebrateAt == nil, !context.isPreview { celebrateAt = .now }
        }
    }

    private func popIfDue(from old: Date, to new: Date) {
        guard !context.isPreview else { return }
        let all = items
        let due = QuickTodo.dueReminders(all, after: old, upTo: new)
        guard !due.isEmpty else { return }
        guard ReminderPopupCenter.shared.shows(.todo) else {
            ReminderSoundPlayer.shared.play(.todo, now: new)
            return
        }
        ReminderPopupCenter.shared.post(due.compactMap { ReminderPopupAlerts.todo($0, in: all, widget: instance.id) },
                                        now: new)
    }

    // MARK: 横排

    /// 今天三件事，或者前几条没做完的。标题一行，下面最多三行，每行左边的圆圈勾完成。
    private func list(_ card: TodoCardRows, openCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(card.focused ? tr("今天三件事") : tr("快速待办"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(card.focused ? "\(card.done)/\(card.total)" : tr("\(openCount) 项"))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            ForEach(card.rows) { item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { cheer(size: 60) }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 5) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.done ? Self.green : WidgetStyle.secondary)
                    .frame(width: 13, height: 13)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help(item.done ? tr("标为未完成") : tr("完成“\(item.text)”"))
            .accessibilityLabel(item.done ? tr("标为未完成") : tr("完成 \(item.text)"))

            Text(item.text)
                .font(WidgetStyle.label(11))
                .foregroundStyle(item.done ? WidgetStyle.secondary : WidgetStyle.primary)
                .strikethrough(item.done, color: WidgetStyle.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let at = item.remindAt, !item.done {
                HStack(spacing: 2) {
                    Image(systemName: "alarm")
                        .font(.system(size: 8, weight: .semibold))
                    Text(QuickTodo.reminderLabel(at, now: context.now))
                        .font(WidgetStyle.caption(9))
                        .monospacedDigit()
                }
                .foregroundStyle(WidgetStyle.secondary.opacity(QuickTodo.reminderPassed(item, now: context.now) ? 0.6 : 1))
                .lineLimit(1)
                .fixedSize()
                .help(tr("\(QuickTodo.reminderLabel(at, now: context.now)) 提醒"))
                .accessibilityLabel(tr("\(QuickTodo.reminderLabel(at, now: context.now)) 提醒"))
            }
            if item.url != nil {
                Button {
                    TodoLinkOpener.open(item)
                } label: {
                    Image(systemName: TodoLinkOpener.symbol(item))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                        .frame(width: 14, height: 13)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .help(tr("打开“\(item.text)”"))
                .accessibilityLabel(tr("打开 \(item.text)"))
            }
        }
        .frame(height: 14)
    }

    /// 没有待办，或者全部做完：小熊猫，做完时是“今天清空啦”和连续清空的天数。
    private func finished(all: [TodoItem]) -> some View {
        let streak = context.isPreview ? 0 : QuickTodo.streak(instance.config, today: today)
        return HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge {
                PandaEmptyBadge(empty: all.isEmpty ? .todo : .todoDone, size: WidgetStyle.badge, fallback: "checklist")
            }
                .overlay { cheer(size: 70) }
            VStack(alignment: .leading, spacing: 1) {
                Text(all.isEmpty ? PandaEmpty.todo.line() : tr("今天清空啦"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if all.isEmpty {
                        Text(QuickTodo.caption(open: 0, done: 0))
                            .foregroundStyle(WidgetStyle.secondary)
                    } else if streak > 0 {
                        Text(tr("连续 \(streak) 天"))
                            .foregroundStyle(Self.green)
                    } else {
                        Text(QuickTodo.caption(open: 0, done: all.count))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    private static let green = Color(hex: "#34C759")

    private func toggle(_ item: TodoItem) {
        guard !context.isPreview else { return }
        let finishing = QuickTodo.finishesAll(toggling: item.id, in: QuickTodo.items(instance.config))
        withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(item.id, in: instance, cheering: finishing) }
        if finishing { celebrateAt = .now }
    }

    /// 庆祝的截止时刻，没有时为 nil。
    private var cheerDeadline: Double? {
        if case .number(let until) = instance.config[QuickTodo.cheerKey] { return until }
        return nil
    }

    /// The red panda popping out of the badge when the card's check closes
    /// the last task.
    @ViewBuilder
    private func cheer(size: CGFloat) -> some View {
        if let celebrateAt {
            TodoCheer(startedAt: celebrateAt, compact: true)
                .frame(width: size, height: size)
        }
    }

    /// 没有要做的事时用哪只小熊猫：一条都没有，或者都做完了。库里的样例不算空。
    private func empty(_ all: [TodoItem], open: [TodoItem]) -> PandaEmpty? {
        guard !context.isPreview, open.isEmpty else { return nil }
        return all.isEmpty ? .todo : .todoDone
    }

    @ViewBuilder
    private func badge(open: Int, progress: Double, size: CGFloat,
                       empty: PandaEmpty? = nil, badgeSize: CGFloat = WidgetStyle.badge) -> some View {
        if let empty {
            PandaEmptyBadge(empty: empty, size: badgeSize, fallback: "checklist")
        } else {
            ring(open: open, progress: progress, size: size)
        }
    }

    private func ring(open: Int, progress: Double, size: CGFloat) -> some View {
        ZStack {
            // 卡片的主题色（待办默认橙，见 `WidgetTint`）。
            TileRing(progress: progress)
            if open > 0 {
                Text("\(open)")
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            }
        }
    }

    /// Finishes the task on the card. With nothing open it is drawn as a
    /// plus that opens nothing of its own, so the card's click (the panel,
    /// where adding happens) is never stolen.
    @ViewBuilder
    private func checkButton(_ item: TodoItem?, size: CGFloat) -> some View {
        if let item {
            TileGlyph(symbol: "checkmark", size: size, action: context.isPreview ? nil : {
                let finishing = QuickTodo.finishesAll(toggling: item.id, in: QuickTodo.items(instance.config))
                withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(item.id, in: instance, cheering: finishing) }
                if finishing { celebrateAt = .now }
            })
            .help(tr("完成“\(item.text)”"))
            .accessibilityLabel(tr("完成 \(item.text)"))
        } else {
            TileGlyph(symbol: "plus", size: size, action: nil)
                .accessibilityHidden(true)
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
    }

    /// - Parameter cheering: 这一下勾掉了最后一项。同一次写入里记下庆祝的截止
    ///   时刻，免得“有未完成的待办时显示”在动效播出来之前就把卡片收走，也记一笔
    ///   连续清空的天数。
    static func toggle(_ id: String, in instance: WidgetInstance, cheering: Bool = false) {
        let day = today
        WidgetWriter.write(latest(instance)) { config in
            QuickTodo.store(QuickTodo.toggling(id, in: QuickTodo.items(config), day: day), in: &config)
            if cheering {
                QuickTodo.startCheer(in: &config)
                QuickTodo.recordCleared(in: &config, today: day)
            }
        }
    }

    /// 记一条：输入框、快捷键小框和拖放都走这里，记下今天的日子。
    static func add(_ text: String, link: String? = nil, to instance: WidgetInstance) {
        let day = today
        change(instance) { QuickTodo.adding(text, to: $0, link: link, day: day) }
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
    }

    /// 从“已收起”里删掉一条。
    static func removeArchived(_ id: String, in instance: WidgetInstance) {
        WidgetWriter.write(latest(instance)) { config in
            QuickTodo.storeArchive(QuickTodo.removingArchived(id, from: QuickTodo.archive(config)), in: &config)
        }
    }

    /// 新的一天第一次显示时收拾一遍。今天已经收拾过就什么也不写。
    static func rollOver(_ instance: WidgetInstance, today: String) {
        let current = latest(instance)
        guard QuickTodo.needsRollover(current.config, today: today) else { return }
        WidgetWriter.write(current) { QuickTodo.applyRollover(in: &$0, today: today) }
    }

    /// 庆祝播完：清掉记号。读的是现在保存着的那份，不会把中途的改动写回去。
    static func endCheer(_ instance: WidgetInstance) {
        let saved = latest(instance)
        guard saved.config[QuickTodo.cheerKey] != nil else { return }
        WidgetWriter.write(saved) { QuickTodo.endCheer(in: &$0) }
    }
}
