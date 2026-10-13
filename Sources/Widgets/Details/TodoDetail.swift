import SwiftUI

/// The whole list: a field to add to it, a check per task, and a way to
/// sweep the finished ones away.
///
/// Return adds and keeps the caret in the field, so a run of tasks can be
/// typed one after another. Double-clicking a task's words edits them.
struct TodoDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var editing: String?
    @State private var editDraft = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case add
        case edit(String)
    }

    private var items: [TodoItem] {
        if context.isPreview {
            return [TodoItem(id: "s1", text: "回复产品评审意见"),
                    TodoItem(id: "s2", text: "取快递"),
                    TodoItem(id: "s3", text: "订周五的会议室"),
                    TodoItem(id: "s4", text: "交电费", done: true)]
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
                    Text(all.isEmpty ? "清单是空的。输入一件事，按回车添加。" : "都做完了。")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(shown) { item in row(item) }
                        }
                    }
                    .frame(maxHeight: 280)
                    .scrollIndicators(.automatic)
                }
                if !done.isEmpty {
                    HStack {
                        if !showDone {
                            Text("已完成 \(done.count) 项（已隐藏）")
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
            }
        }
        .onAppear { if !context.isPreview { focus = .add } }
    }

    private func header(open: Int, done: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("待办")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(open == 0 ? "全部完成" : "\(open) 项未完成")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer()
            if done > 0 {
                StatChip(label: "已完成", value: "\(done)")
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
                guard !context.isPreview else { return }
                withAnimation(.snappy(duration: 0.3)) { TodoLog.toggle(item.id, in: instance) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.7))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "标为未完成" : "标为完成")

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
                guard !context.isPreview else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    TodoLog.change(instance) { QuickTodo.removing(item.id, from: $0) }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除 \(item.text)")
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
