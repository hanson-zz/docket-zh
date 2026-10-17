import SwiftUI

/// 设置 ▸ AI ▸ AI 助手的常用提示词：增、删、改、上移下移。
///
/// 存在刘海对话的设置里（`AINotchSettings.prompts`），跟着状态文件和设置
/// 备份走。校验和排序都在 `AIPrompts` 里，这里只管界面。
struct AIPromptsSection: View {
    @Binding var prompts: [AIPrompt]

    /// 正在编辑的那一条；新建时 id 是 nil。
    @State private var editing: Editing?

    private struct Editing: Equatable {
        var id: String?
        var name = ""
        var content = ""
        var error: String?
    }

    var body: some View {
        Section {
            if prompts.isEmpty && editing == nil {
                Text("还没有常用提示词。")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                if editing?.id == prompt.id {
                    editor
                } else {
                    row(prompt, index: index)
                }
            }
            if editing != nil && editing?.id == nil {
                editor
            } else if editing == nil {
                Button {
                    editing = Editing()
                } label: {
                    Label("添加提示词…", systemImage: "plus")
                }
                .disabled(prompts.count >= AIPrompts.maxCount)
                .help(prompts.count >= AIPrompts.maxCount
                      ? tr("最多存 \(AIPrompts.maxCount) 条") : tr("名字加内容，内容里可以用 {文本}"))
            }
        } header: {
            Text("AI 助手的常用提示词")
        } footer: {
            Text(tr("在刘海对话的“常用”菜单里点一条，就把输入框里的文字（空着时用剪贴板）套进去发给当前服务：API 直接回答，网页复制提示词到网页里粘贴，跳转复制或带着问题打开。内容里写 {文本} 的地方换成那段文字，没写时文字接在内容后面。最多 \(AIPrompts.maxCount) 条。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ prompt: AIPrompt, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.name)
                Text(AIPrompts.preview(prompt.content, limit: 48))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            iconButton("chevron.up", label: tr("上移 \(prompt.name)"), disabled: index == 0) {
                AIPrompts.move(prompt.id, by: -1, in: &prompts)
            }
            iconButton("chevron.down", label: tr("下移 \(prompt.name)"), disabled: index == prompts.count - 1) {
                AIPrompts.move(prompt.id, by: 1, in: &prompts)
            }
            Button("编辑") {
                editing = Editing(id: prompt.id, name: prompt.name, content: prompt.content)
            }
            .controlSize(.small)
            .disabled(editing != nil)
            .accessibilityLabel(tr("编辑 \(prompt.name)"))
            Button("删除", role: .destructive) {
                AIPrompts.remove(prompt.id, from: &prompts)
            }
            .controlSize(.small)
            .disabled(editing != nil)
            .accessibilityLabel(tr("删除 \(prompt.name)"))
        }
    }

    private func iconButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(disabled || editing != nil)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var editor: some View {
        if let current = editing {
            VStack(alignment: .leading, spacing: 8) {
                TextField("名字", text: Binding(get: { editing?.name ?? "" },
                                               set: { editing?.name = $0; editing?.error = nil }),
                          prompt: Text("例如 写周报"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("提示词的名字")
                TextEditor(text: Binding(get: { editing?.content ?? "" },
                                         set: { editing?.content = $0; editing?.error = nil }))
                    .font(.system(size: 12))
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                    .accessibilityLabel("提示词的内容")
                HStack(spacing: 8) {
                    Text(current.error ?? tr("例如：把下面的会议记录整理成周报：{文本}"))
                        .font(.caption)
                        .foregroundStyle(current.error == nil ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("插入 {文本}") {
                        let content = editing?.content ?? ""
                        editing?.content = content + AIPrompts.placeholder
                    }
                    .controlSize(.small)
                    Button("取消") { editing = nil }
                        .keyboardShortcut(.cancelAction)
                    // 不挂回车快捷键：内容是多行的，回车要留给换行。
                    Button(current.id == nil ? tr("添加") : tr("保存"), action: save)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func save() {
        guard let current = editing else { return }
        let error: AIPrompts.EditError?
        if let id = current.id {
            error = AIPrompts.update(id, name: current.name, content: current.content, in: &prompts)
        } else {
            error = AIPrompts.add(name: current.name, content: current.content,
                                  id: String(UUID().uuidString.prefix(8)).lowercased(), to: &prompts)
        }
        if let error {
            editing?.error = error.message
        } else {
            editing = nil
        }
    }
}
