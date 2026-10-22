import SwiftUI

// MARK: - 剪贴板接力、快捷指令和常用提示词（共用）

/// 刘海对话和 AI 任意门迷你提问面板共用的一排：剪贴板接力、翻译、总结、
/// 润色、解释和“常用”菜单，下面一行是提示或剪贴板预览。
///
/// 只管画和把点击交出去；文字从哪来、交给谁由用它的地方决定（刘海对话交给
/// `AIChatCenter`，迷你提问面板照平时提问交给选中的服务）。哪些显示、第二行
/// 显示什么见 Core 的 `AIPromptStrip`。颜色用面板语义色：迷你提问面板是液态
/// 玻璃，刘海对话挂在刘海下面时是纯黑（环境深色，语义色解析成白）。
struct AIPromptChipBar: View {
    /// 有没有输入框：刘海对话的网页模式没有，剪贴板按钮和点预览带进去都不出现。
    var hasInput: Bool
    var clipboardPreview: String?
    var notice: String?
    var prompts: [AIPrompt]
    /// 快捷指令按钮的悬停说明，按各自的模式说清楚会发生什么。
    var actionHelp: (AIQuickAction) -> String
    /// 预览那一行的悬停说明。
    var clipboardHelp: String
    var paste: () -> Void
    var runAction: (AIQuickAction) -> Void
    var runPrompt: (AIPrompt) -> Void
    var managePrompts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if AIPromptStrip.showsClipboardChip(hasInput: hasInput) {
                    chip(tr("剪贴板", context: "chip"), symbol: "doc.on.clipboard", enabled: clipboardPreview != nil,
                         help: clipboardPreview.map { tr("带进输入框：\($0)") } ?? tr("剪贴板里没有文字"),
                         label: tr("把剪贴板文字带进输入框"), action: paste)
                }
                ForEach(AIQuickAction.allCases, id: \.self) { action in
                    chip(action.chipTitle, symbol: nil, enabled: true,
                         help: actionHelp(action), label: tr("\(action.title)输入框或剪贴板里的文字")) {
                        // 点按钮不会让输入法先确认选字，还有没确认的字时不交出去。
                        guard !AskTextView.keyWindowIsComposing else { return }
                        runAction(action)
                    }
                }
                Spacer(minLength: 0)
                promptMenu
            }
            statusLine
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch AIPromptStrip.statusLine(notice: notice, clipboardPreview: clipboardPreview) {
        case .notice(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        case .clipboard(let preview):
            Button {
                if hasInput { paste() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text(tr("剪贴板：\(preview)"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!hasInput)
            .help(clipboardHelp)
            .accessibilityLabel(tr("剪贴板预览：\(preview)"))
        case .none:
            EmptyView()
        }
    }

    private var promptMenu: some View {
        Menu {
            if prompts.isEmpty {
                Text("还没有常用提示词")
            }
            ForEach(prompts) { prompt in
                Button(prompt.name) {
                    guard !AskTextView.keyWindowIsComposing else { return }
                    runPrompt(prompt)
                }
            }
            Divider()
            Button("管理常用提示词…", action: managePrompts)
        } label: {
            HStack(spacing: 3) {
                Text("常用")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.panelSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("常用提示词：内容里的 {文本} 换成输入框或剪贴板里的文字")
        .accessibilityLabel("常用提示词")
    }

    private func chip(_ title: String, symbol: String?, enabled: Bool, help: String, label: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                // 英文按钮比中文宽，挤的时候先缩小字号，不截成“Transl…”。
                Text(title).font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.panelPrimary.opacity(enabled ? 0.85 : 0.35))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(.panelFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
    }
}
