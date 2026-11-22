import AppKit
import SwiftUI
@preconcurrency import Translation

/// Where text is typed or pasted and comes back translated: a language bar,
/// the original and the translation on two glass cards, three buttons, and
/// the last translations underneath once there are any.
///
/// Apple's on-device Translation does the work: free, no key, and nothing
/// leaves the Mac. It translates a moment after typing stops, or at once on
/// ⌘↩. The first time a pair is used macOS asks to download its language
/// pack, and the panel says so while it waits.
struct TranslateDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @State private var result: TranslateRecord?
    @State private var message: String?
    @State private var working = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var pending: TranslateJob?
    /// The job whose answer is showing, so a pause after nothing changed
    /// does not translate the same text again.
    @State private var doneKey: String?
    @State private var copied = false
    /// 原文按字号量出的自然高度，输入框据此在上下限之间长高。
    @State private var naturalHeight = 0.0
    @State private var showsAllRecent = false
    @State private var supported: Set<String> = []
    @FocusState private var editing: Bool

    init(instance: WidgetInstance, context: WidgetContext) {
        self.instance = instance
        self.context = context
        // The library and the screenshots draw the panel once, before any
        // onAppear, so the sample has to be there from the start.
        if context.isPreview {
            _draft = State(initialValue: Self.sampleHistory[0].sourceText)
            _result = State(initialValue: Self.sampleHistory[0])
        }
    }

    private var config: WidgetConfig { instance.config }
    private var source: String { Translate.source(config) }
    private var smart: Bool { Translate.smartDirection(config) }
    private var chosenTarget: String { Translate.chosenTarget(config) }
    private var history: [TranslateRecord] {
        context.isPreview ? Self.sampleHistory : Translate.history(config)
    }

    /// The common languages this Mac can translate, then any others it can.
    private var languages: [TranslateLanguage] {
        guard !supported.isEmpty else { return Translate.common }
        let common = Translate.common.filter { supported.contains($0.code) }
        let known = Set(Translate.common.map(\.code))
        let extra = supported.subtracting(known).sorted().map {
            TranslateLanguage(code: $0, name: TranslationRunner.name($0), short: $0)
        }
        return common + extra
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.blue))
        } content: {
            // 不设固定高度、不另套滚动：内容少面板就矮，多了交给通用面板容器
            // （DetailPanelFit）限高并在面板里滚动。
            VStack(alignment: .leading, spacing: 10) {
                languageBar
                sourcePane
                resultPane
                statusLine
                actionRow
                if !history.isEmpty { historySection }
            }
        }
        .translationTask(configuration) { session in
            guard let job = pending else { return }
            let outcome = await TranslationRunner.run(session, job: job) {
                if pending == job { message = tr("首次翻译这对语言需要下载语言包，请在系统弹出的窗口中下载。") }
            }
            // A newer job, or this one asked again, picks up from here.
            guard pending == job, outcome != .cancelled else { return }
            pending = nil
            working = false
            switch outcome {
            case .done(let record):
                result = record
                message = nil
                doneKey = job.key
                remember(record)
            case .note(let text):
                message = text
            case .cancelled:
                break
            }
        }
        .task(id: draft) {
            // Translates once typing pauses rather than on every keystroke.
            guard !context.isPreview else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            translate()
        }
        .task {
            guard !context.isPreview else { return }
            supported = await TranslationRunner.supportedCodes()
        }
        .onChange(of: draft) { _, text in
            if text.count > Translate.maxCharacters { draft = Translate.clamped(text) }
        }
        // 换语言保留原文和译文，有原文就按新方向重新翻译。
        .onChange(of: "\(source)|\(smart)|\(chosenTarget)") { _, _ in translate(force: true) }
        .onAppear {
            guard !context.isPreview else { return }
            editing = true
            if takeShotText() { return }
            if Translate.clickAction(config) == .clipboard { pasteClipboard(now: true) }
        }
        .onChange(of: ShotInbox.shared.translate[instance.id]) { _, _ in _ = takeShotText() }
        .onDisappear { TranslateSpeaker.shared.stop() }
    }

    // MARK: Languages

    private var detectedSource: String? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if source != Translate.auto { return source }
        if let result, result.sourceText == text { return result.source }
        return Translate.detect(text)
    }

    private var currentTarget: String {
        Translate.target(source: detectedSource, text: draft, chosen: chosenTarget, smart: smart)
    }

    /// 源语言胶囊、交换键、目标语言胶囊，一排撑满。
    private var languageBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button { setSource(Translate.auto) } label: { menuLabel(tr("自动检测"), on: source == Translate.auto) }
                Divider()
                ForEach(languages) { language in
                    Button { setSource(language.code) } label: {
                        menuLabel(language.name, on: source == language.code)
                    }
                }
            } label: {
                chip(source == Translate.auto
                     ? (detectedSource.map { tr("自动 · \(TranslationRunner.name($0))") } ?? tr("自动检测"))
                     : TranslationRunner.name(source))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .help("源语言")

            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 32, height: 28)
                    .readableGlass(in: Capsule())
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("交换语言")
            .help("交换语言")

            Menu {
                Button { setSmart() } label: { menuLabel(tr("智能方向（中文译成英语，其他译成中文）"), on: smart) }
                Divider()
                ForEach(languages) { language in
                    Button { setTarget(language.code) } label: {
                        menuLabel(language.name, on: !smart && chosenTarget == language.code)
                    }
                }
            } label: {
                chip(smart ? tr("智能 · \(TranslationRunner.name(currentTarget))") : TranslationRunner.name(currentTarget))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .help("目标语言")
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func chip(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.panelPrimary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .readableGlass(in: Capsule())
        .contentShape(.capsule)
    }

    // MARK: Panes

    private func paneTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
    }

    /// 原文卡：输入框默认约两行高，随文字长高到上限，再多在卡内滚动。
    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            paneTitle(tr("原文"))
            ZStack(alignment: .topLeading) {
                // 看不见的同字号文字量出自然高度，输入框跟着它长高。
                Text(draft.isEmpty ? " " : draft + " ")
                    .font(.system(size: 14))
                    .padding(.leading, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { naturalHeight = $0 }
                if draft.isEmpty {
                    Text("输入或粘贴要翻译的文字")
                        .font(.system(size: 14))
                        .foregroundStyle(.panelTertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .foregroundStyle(.panelPrimary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                    .focused($editing)
                    .disabled(context.isPreview)
            }
            .frame(height: Translate.editorHeight(content: naturalHeight + 6))
            .clipped()
            HStack(spacing: 6) {
                Text(Translate.countText(draft.count))
                    .font(WidgetStyle.caption(13).monospacedDigit())
                    .foregroundStyle(.panelPrimary.opacity(draft.count >= Translate.maxCharacters ? 0.9 : 0.5))
                Spacer(minLength: 0)
                paneButton("speaker.wave.2", label: tr("朗读原文"), disabled: draft.isEmpty) {
                    TranslateSpeaker.shared.toggle(draft, language: detectedSource ?? Translate.chinese)
                }
                paneButton("xmark", label: tr("清除"), disabled: draft.isEmpty) {
                    draft = ""
                    result = nil
                    message = nil
                    doneKey = nil
                    editing = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .readableGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 译文卡：比原文更突出（字大一号、描一圈强调色），双击译文拷贝。
    private var resultPane: some View {
        let text = result?.resultText ?? ""
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                paneTitle(tr("译文"))
                if let result {
                    Text(Translate.pairText(source: result.source, target: result.target))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelTertiary)
                }
            }
            Text(text.isEmpty ? (working ? tr("正在翻译…") : tr("译文会显示在这里")) : text)
                .font(.system(size: 16, weight: text.isEmpty ? .regular : .medium))
                .foregroundStyle(.panelPrimary.opacity(text.isEmpty ? 0.4 : 1))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 5)
                .contentShape(.rect)
                .onTapGesture(count: 2) { copyResult(text) }
                .help(text.isEmpty ? "" : tr("双击拷贝译文"))
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                paneButton("speaker.wave.2", label: tr("朗读译文"), disabled: text.isEmpty) {
                    TranslateSpeaker.shared.toggle(text, language: result?.target ?? currentTarget)
                }
                paneButton(copied ? "checkmark" : "doc.on.doc", label: copied ? tr("已拷贝") : tr("拷贝译文"),
                           disabled: text.isEmpty) {
                    copyResult(text)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .readableGlass(in: shape)
        .overlay { shape.strokeBorder(accent.opacity(0.45), lineWidth: 1) }
        .contextMenu {
            if !text.isEmpty { Button("拷贝译文") { copyResult(text) } }
        }
    }

    private var accent: Color { WidgetStyle.tint(.blue) }

    private func copyResult(_ text: String) {
        guard !context.isPreview, !text.isEmpty else { return }
        ColorSampling.copy(text)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func paneButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 30, height: 26)
                .background(Color.panelFill, in: .rect(cornerRadius: 8, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    /// The language pack hint, an error, or the reassurance. Every path here
    /// is on the Mac: Apple's Translation, Vision for the screenshot's text
    /// and the system voice for reading aloud.
    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: message == nil ? "lock.shield" : "info.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(message ?? tr("由 macOS 在本机翻译，免费，文字不会上传。"))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(WidgetStyle.caption(13))
        .foregroundStyle(.panelPrimary.opacity(message == nil ? 0.55 : 0.8))
        .padding(.horizontal, 4)
    }

    // MARK: Buttons

    /// 粘贴、截图翻译、翻译一排；放不下带图标的就只留文字，文字不截断。
    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            buttons(icons: true)
            buttons(icons: false)
        }
    }

    private func buttons(icons: Bool) -> some View {
        HStack(spacing: 8) {
            actionButton(tr("粘贴"), symbol: icons ? "doc.on.clipboard" : nil) {
                pasteClipboard(now: true)
            }
            .help(tr("把剪贴板里的文字放进原文"))
            actionButton(tr("截图翻译", context: "button"), symbol: icons ? "text.viewfinder" : nil) {
                translateScreenshot()
            }
            .help(tr("框选屏幕上的一块，本机识别并把译文盖在原文的位置上"))
            actionButton(tr("翻译"), symbol: icons ? "translate" : nil, prominent: true) {
                translate(force: true)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help("⌘↩ 立即翻译")
        }
    }

    private func actionButton(_ title: String, symbol: String?, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(prominent ? Color.white : Color.panelPrimary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if prominent {
                    Capsule().fill(accent)
                } else {
                    ReadableGlass(shape: Capsule())
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: History

    /// 最近翻译：有记录才出现，先列三条，「全部」展开到最多二十条。
    private var historySection: some View {
        let shown = Translate.recentShown(history.count, expanded: showsAllRecent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("最近翻译")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 0)
                if history.count > Translate.recentCollapsed {
                    Button(showsAllRecent ? tr("收起") : tr("全部 \(history.count) 条")) {
                        showsAllRecent.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                }
                Button("清除") {
                    guard !context.isPreview else { return }
                    showsAllRecent = false
                    WidgetWriter.write(instance) { Translate.store([], in: &$0) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 6) {
                ForEach(Array(history.prefix(shown).enumerated()), id: \.offset) { index, record in
                    historyRow(record, index: index)
                }
            }
        }
    }

    private func historyRow(_ record: TranslateRecord, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            restore(record)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Translate.snippet(record.sourceText))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                    Text(Translate.snippet(record.resultText))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .readableGlass(in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(tr("重新填入这条"))
        .contextMenu {
            Button("拷贝译文") { ColorSampling.copy(record.resultText) }
            Button("拷贝原文") { ColorSampling.copy(record.sourceText) }
            Button("删除") {
                guard !context.isPreview else { return }
                WidgetWriter.write(instance) { config in
                    Translate.store(Translate.removing(at: index, from: Translate.history(config)), in: &config)
                }
            }
        }
    }

    // MARK: Actions

    /// Starts a translation of what is in the editor, unless that exact
    /// translation is already showing.
    private func translate(force: Bool = false) {
        guard !context.isPreview else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            pending = nil
            working = false
            result = nil
            message = nil
            doneKey = nil
            return
        }
        let from = source == Translate.auto ? Translate.detect(text) : source
        let to = Translate.target(source: from, text: text, chosen: chosenTarget, smart: smart)
        let job = TranslateJob(text: text, source: from, target: to)
        guard force || job.key != doneKey else { return }
        // Already on its way; asking again would only restart it.
        guard pending != job else { return }
        if let from, Translate.same(from, to) {
            pending = nil
            working = false
            message = tr("原文已经是\(TranslationRunner.name(to))，换一个目标语言试试。")
            return
        }
        pending = job
        working = true
        message = nil
        let next = TranslationRunner.configuration(for: job)
        if TranslationRunner.samePair(configuration, next) {
            configuration?.invalidate()
        } else {
            configuration = next
        }
    }

    /// 截图编辑工具条「取字」里点了「送翻译」：文字放进输入框，停顿后照常翻译。
    private func takeShotText() -> Bool {
        guard let text = ShotInbox.shared.takeTranslate(instance.id) else { return false }
        draft = Translate.clamped(text)
        return true
    }

    /// 「截图翻译」：收起面板，框选一块，在截图上原位显示译文（和截图编辑工具条的翻译同一套）。
    private func translateScreenshot() {
        guard !context.isPreview else { return }
        WidgetDetailWindow.shared.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            ShotEditor.shared.beginTranslate()
        }
    }

    /// 只在点「粘贴」（或卡片设成点按即翻译剪贴板）时读一次剪贴板，从不轮询。
    /// `now`：点面板里的「粘贴」时为 true，贴进来立刻翻译，不等打字的停顿。
    private func pasteClipboard(now: Bool) {
        guard !context.isPreview,
              let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !context.isPreview { message = tr("剪贴板里没有文字。") }
            return
        }
        draft = Translate.clamped(text)
        if now { translate(force: true) }
    }

    /// Turns the direction round: the target becomes the source, and the
    /// translation becomes the text to translate back.
    private func swap() {
        guard !context.isPreview else { return }
        let from = detectedSource ?? Translate.chinese
        let to = currentTarget
        WidgetWriter.write(instance) { config in
            config.set(Translate.sourceKey, .string(to))
            config.set(Translate.targetKey, .string(from))
            config.set("autoDirection", .bool(false))
        }
        if let result, !result.resultText.isEmpty {
            draft = Translate.clamped(result.resultText)
        }
        doneKey = nil
    }

    private func setSource(_ code: String) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { $0.set(Translate.sourceKey, .string(code)) }
    }

    private func setTarget(_ code: String) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { config in
            config.set(Translate.targetKey, .string(code))
            config.set("autoDirection", .bool(false))
        }
    }

    private func setSmart() {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { $0.set("autoDirection", .bool(true)) }
    }

    private func restore(_ record: TranslateRecord) {
        guard !context.isPreview else { return }
        draft = record.sourceText
        result = record
        message = nil
        let from = source == Translate.auto ? Translate.detect(record.sourceText) : source
        let to = Translate.target(source: from, text: record.sourceText, chosen: chosenTarget, smart: smart)
        // Restored as it was: the pause after the draft changes finds it
        // already translated and leaves it alone.
        if to == record.target {
            doneKey = TranslateJob(text: record.sourceText, source: from, target: to).key
        }
    }

    private func remember(_ record: TranslateRecord) {
        WidgetWriter.write(instance) { config in
            Translate.store(Translate.recording(record, in: Translate.history(config)), in: &config)
        }
    }

    private static let sampleHistory: [TranslateRecord] = [
        TranslateRecord(source: "zh-Hans", target: "en", sourceText: "你好，世界", resultText: "Hello, world"),
        TranslateRecord(source: "en", target: "zh-Hans", sourceText: "See you tomorrow", resultText: "明天见"),
        TranslateRecord(source: "ja", target: "zh-Hans", sourceText: "ありがとう", resultText: "谢谢"),
    ]
}
