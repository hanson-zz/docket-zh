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
                    TileBadge(size: 34) { badge(open: open.count, progress: progress, size: 13) }
                    Text(open.isEmpty ? "无待办" : "\(open.count) 项")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    checkButton(open.first, size: 10)
                }
            } else {
                HStack(spacing: 10) {
                    TileBadge { badge(open: open.count, progress: progress, size: 15) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(open.first?.text ?? (all.isEmpty ? "没有待办" : "都做完了"))
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
    }

    private func badge(open: Int, progress: Double, size: CGFloat) -> some View {
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
                withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(item.id, in: instance) }
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

    static func toggle(_ id: String, in instance: WidgetInstance) {
        change(instance) { QuickTodo.toggling(id, in: $0) }
    }
}
