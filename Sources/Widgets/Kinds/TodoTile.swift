import SwiftUI

/// The next thing to do, with a check to finish it.
///
/// The list is the widget's own (see `QuickTodo`), never the system's
/// Reminders, so it works with no permission and no account. The card's
/// click opens the panel, where items are added; the check beside the task
/// is the only control on the card.
struct TodoTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var celebrateAt: Date?

    private var items: [TodoItem] {
        if context.isPreview {
            return [TodoItem(id: "s1", text: "回复产品评审意见"),
                    TodoItem(id: "s2", text: "取快递"),
                    TodoItem(id: "s3", text: "订周五的会议室"),
                    TodoItem(id: "s4", text: "交电费", done: true)]
        }
        return QuickTodo.items(instance.config)
    }

    var body: some View {
        let all = items
        let open = QuickTodo.open(all)
        let done = all.count - open.count
        let progress = all.isEmpty ? 0 : Double(done) / Double(all.count)
        return WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: WidgetStyle.badgeCompact) {
                        badge(open: open.count, progress: progress, size: 13, empty: empty(all, open: open),
                              badgeSize: WidgetStyle.badgeCompact)
                    }
                        .overlay { cheer(size: 60) }
                    Text(open.isEmpty ? (empty(all, open: open) ?? .todo).line(compact: true) : "\(open.count) 项")
                        .font(WidgetStyle.title)
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    checkButton(open.first, size: 10)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge {
                        badge(open: open.count, progress: progress, size: 15, empty: empty(all, open: open),
                              badgeSize: WidgetStyle.badge)
                    }
                        .overlay { cheer(size: 70) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(open.first?.text ?? (all.isEmpty ? PandaEmpty.todo : PandaEmpty.todoDone).line())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(QuickTodo.caption(open: open.count, done: done))
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    checkButton(open.first, size: 12)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(open.first.map { "快速待办：\($0.text)" } ?? "快速待办")
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
            TileRing(progress: progress, tint: tint)
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

    private var tint: Color {
        Color(hex: PaletteColor.orange.hex).mix(with: WidgetStyle.primary, by: 0.3)
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
            .help("完成“\(item.text)”")
            .accessibilityLabel("完成 \(item.text)")
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
    static func change(_ instance: WidgetInstance, _ edit: ([TodoItem]) -> [TodoItem]) {
        WidgetWriter.write(instance) { config in
            QuickTodo.store(edit(QuickTodo.items(config)), in: &config)
        }
    }

    /// - Parameter cheering: 这一下勾掉了最后一项。同一次写入里记下庆祝的截止
    ///   时刻，免得“有未完成的待办时显示”在动效播出来之前就把卡片收走。
    static func toggle(_ id: String, in instance: WidgetInstance, cheering: Bool = false) {
        WidgetWriter.write(instance) { config in
            QuickTodo.store(QuickTodo.toggling(id, in: QuickTodo.items(config)), in: &config)
            if cheering { QuickTodo.startCheer(in: &config) }
        }
    }

    /// 庆祝播完：清掉记号。读的是现在保存着的那份，不会把中途的改动写回去。
    static func endCheer(_ instance: WidgetInstance) {
        let latest = WidgetWriter.current(instance.id) ?? instance
        guard latest.config[QuickTodo.cheerKey] != nil else { return }
        WidgetWriter.write(latest) { QuickTodo.endCheer(in: &$0) }
    }
}
