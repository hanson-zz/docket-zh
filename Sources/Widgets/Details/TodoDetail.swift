import SwiftUI

/// The whole list: a field to add to it, a check per task, and a way to
/// sweep the finished ones away.
///
/// Return adds and keeps the caret in the field, so a run of tasks can be
/// typed one after another. Double-clicking a task's words edits them.
/// Dragging a row to the left deletes it, and deleting or checking a task can
/// be undone for a few seconds, the last five steps one at a time, each put
/// back where it was. Checking the last open task brings out the red panda.
struct TodoDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var editing: String?
    @State private var editDraft = ""
    @FocusState private var focus: Field?
    @State private var celebrateAt: Date?
    /// 最近几步删除和完成，撤销条按后进先出一步步退回。
    @State private var undo = TodoUndoStack()
    /// 每记一步换一个，撤销条从最后一次改动起再停几秒。
    @State private var undoToken = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case add
        case edit(String)
    }

    private var items: [TodoItem] {
        if context.isPreview {
            return [TodoItem(id: "s1", text: tr("回复产品评审意见")),
                    TodoItem(id: "s2", text: tr("取快递")),
                    TodoItem(id: "s3", text: tr("订周五的会议室")),
                    TodoItem(id: "s4", text: tr("交电费"), done: true)]
        }
        return QuickTodo.items(instance.config)
    }

    private var showDone: Bool { instance.config.bool("showDone", default: true) }

    var body: some View {
        let all = items
        let open = QuickTodo.open(all)
        let done = all.filter(\.done)
        let shown = showDone ? open + done : open
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(open: open.count, done: done.count)
                addField
                if shown.isEmpty {
                    Text(all.isEmpty ? tr("清单是空的。输入一件事，按回车添加。") : tr("都做完了。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(shown) { item in
                                row(item)
                                    .swipeToDelete(enabled: !context.isPreview && editing != item.id) {
                                        delete(item, animated: false)
                                    }
                                    .transition(reduceMotion
                                                ? .opacity
                                                : .asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)),
                                                              removal: .opacity))
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .scrollIndicators(.automatic)
                }
                if !done.isEmpty {
                    HStack {
                        if !showDone {
                            Text(tr("已完成 \(done.count) 项（已隐藏）"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Button("清除已完成") {
                            guard !context.isPreview else { return }
                            withAnimation(.snappy(duration: 0.3)) {
                                TodoLog.change(instance) { QuickTodo.clearingDone($0) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if let step = undo.last {
                    TodoUndoBar(step: step, more: undo.count - 1) { restore() }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if let celebrateAt {
                    TodoCheer(startedAt: celebrateAt)
                        .frame(width: 220, height: 200)
                }
            }
        }
        .onAppear { if !context.isPreview { focus = .add } }
        .task(id: undoToken) {
            guard !undo.isEmpty else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(barAnimation) { undo.clear() }
        }
        .task(id: celebrateAt) {
            guard celebrateAt != nil else { return }
            try? await Task.sleep(for: .seconds(CheerMotion.duration))
            guard !Task.isCancelled else { return }
            celebrateAt = nil
            // 卡片会在到点时清掉记号；面板也清一次，卡片恰好不在屏幕上时也不会卡住。
            if !context.isPreview { TodoLog.endCheer(instance) }
        }
    }

    private func header(open: Int, done: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("待办")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(open == 0 ? tr("全部完成") : tr("\(open) 项未完成"))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer()
            if done > 0 {
                StatChip(label: tr("已完成"), value: "\(done)")
                    .frame(width: 76)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
            TextField("", text: $draft, prompt: Text("添加待办，按回车"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($focus, equals: .add)
                .onSubmit(add)
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .glassPane(cornerRadius: 10)
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.7))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? tr("标为未完成") : tr("标为完成"))

            if editing == item.id {
                TextField("", text: $editDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .edit(item.id))
                    .onSubmit { finishEditing(item.id) }
                    .onChange(of: focus) { _, now in
                        if now != .edit(item.id), editing == item.id { finishEditing(item.id) }
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(item.done ? 0.45 : 0.95))
                    .strikethrough(item.done, color: .white.opacity(0.45))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { beginEditing(item) }
                    .help("双击编辑")
            }

            Button {
                delete(item, animated: true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("删除 \(item.text)"))
            .help("删除，也可以把这一行往左拖")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func add() {
        guard !context.isPreview, QuickTodo.clean(draft) != nil else { return }
        let text = draft
        withAnimation(.snappy(duration: 0.3)) {
            TodoLog.change(instance) { QuickTodo.adding(text, to: $0) }
        }
        draft = ""
        focus = .add
    }

    private var listAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3) }
    private var barAnimation: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25) }

    /// 勾掉一项会记进撤销栈；把已完成的重新打开不记。
    private func toggle(_ item: TodoItem) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        let finishing = QuickTodo.finishesAll(toggling: item.id, in: current)
        let completing = current.first(where: { $0.id == item.id })?.done == false
        withAnimation(listAnimation) { TodoLog.toggle(item.id, in: instance, cheering: finishing) }
        if completing { record { $0.recordCompletion(of: item.id, in: current) } }
        if finishing { celebrateAt = .now }
    }

    /// Removes the task and offers it back for a few seconds. A swipe has
    /// already slid the row away, so it is not animated a second time.
    private func delete(_ item: TodoItem, animated: Bool) {
        guard !context.isPreview else { return }
        let current = QuickTodo.items(instance.config)
        if editing == item.id { editing = nil }
        withAnimation(animated ? listAnimation : nil) {
            TodoLog.change(instance) { QuickTodo.removing(item.id, from: $0) }
        }
        record { $0.recordDeletion(of: item.id, in: current) }
    }

    private func record(_ change: (inout TodoUndoStack) -> Void) {
        withAnimation(barAnimation) { change(&undo) }
        undoToken = UUID()
    }

    /// 退回最近的一步，放回它原来的位置；栈里还有就继续显示撤销条。
    private func restore() {
        guard !context.isPreview, let step = undo.pop() else { return }
        withAnimation(listAnimation) {
            TodoLog.change(instance) { TodoUndoStack.undoing(step, in: $0) }
        }
        undoToken = UUID()
    }

    private func beginEditing(_ item: TodoItem) {
        guard !context.isPreview else { return }
        editDraft = item.text
        editing = item.id
        focus = .edit(item.id)
    }

    private func finishEditing(_ id: String) {
        let text = editDraft
        editing = nil
        TodoLog.change(instance) { QuickTodo.renaming(id, to: text, in: $0) }
    }

    private var accent: Color {
        WidgetCatalog.accentHex(.todo).map { Color(hex: $0) } ?? WidgetStyle.primary
    }
}
