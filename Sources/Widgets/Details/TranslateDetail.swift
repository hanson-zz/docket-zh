import AppKit
import SwiftUI
@preconcurrency import Translation

/// Where text is typed or pasted and comes back translated, with the last
/// twenty translations underneath.
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
            VStack(alignment: .leading, spacing: 10) {
                languageBar
                sourcePane
                resultPane
                statusLine
                HStack(spacing: 8) {
                    PanelButton(title: "粘贴剪贴板", symbol: "doc.on.clipboard") { pasteClipboard() }
                    PanelButton(title: "翻译", symbol: "translate", prominent: true) { translate(force: true) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("⌘↩ 立即翻译")
                }
                historySection
            }
        }
        .translationTask(configuration) { session in
            guard let job = pending else { return }
            let outcome = await TranslationRunner.run(session, job: job) {
                if pending == job { message = "首次翻译这对语言需要下载语言包，请在系统弹出的窗口中下载。" }
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
        .onChange(of: "\(source)|\(smart)|\(chosenTarget)") { _, _ in translate(force: true) }
        .onAppear {
            guard !context.isPreview else { return }
            editing = true
            if Translate.clickAction(config) == .clipboard { pasteClipboard() }
        }
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

    private var languageBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button { setSource(Translate.auto) } label: { menuLabel("自动检测", on: source == Translate.auto) }
                Divider()
                ForEach(languages) { language in
                    Button { setSource(language.code) } label: {
                        menuLabel(language.name, on: source == language.code)
                    }
                }
            } label: {
                chip(source == Translate.auto
                     ? (detectedSource.map { "自动 · \(TranslationRunner.name($0))" } ?? "自动检测")
                     : TranslationRunner.name(source))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("源语言")

            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.14), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("交换语言")
            .help("交换语言")

            Menu {
                Button { setSmart() } label: { menuLabel("智能方向（中文译成英语，其他译成中文）", on: smart) }
                Divider()
                ForEach(languages) { language in
                    Button { setTarget(language.code) } label: {
                        menuLabel(language.name, on: !smart && chosenTarget == language.code)
                    }
                }
            } label: {
                chip(smart ? "智能 · \(TranslationRunner.name(currentTarget))" : TranslationRunner.name(currentTarget))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("目标语言")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func chip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.white.opacity(0.16), in: .capsule)
    }

    // MARK: Panes

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("输入或粘贴要翻译的文字")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($editing)
                    .disabled(context.isPreview)
            }
            .frame(height: 78)
            HStack(spacing: 6) {
                Text("\(draft.count) / \(Translate.maxCharacters)")
                    .font(WidgetStyle.caption(10).monospacedDigit())
                    .foregroundStyle(.white.opacity(draft.count >= Translate.maxCharacters ? 0.9 : 0.5))
                Spacer(minLength: 0)
                paneButton("speaker.wave.2", label: "朗读原文", disabled: draft.isEmpty) {
                    TranslateSpeaker.shared.toggle(draft, language: detectedSource ?? Translate.chinese)
                }
                paneButton("xmark", label: "清除", disabled: draft.isEmpty) {
                    draft = ""
                    result = nil
                    message = nil
                    doneKey = nil
                    editing = true
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 12)
    }

    private var resultPane: some View {
        let text = result?.resultText ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                Text(text.isEmpty ? (working ? "正在翻译…" : "译文会显示在这里") : text)
                    .font(.system(size: 14, weight: text.isEmpty ? .regular : .medium))
                    .foregroundStyle(.white.opacity(text.isEmpty ? 0.4 : 1))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 5)
            }
            .scrollIndicators(.never)
            .frame(height: 78)
            HStack(spacing: 6) {
                Text(result.map { Translate.pairText(source: $0.source, target: $0.target) } ?? " ")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                paneButton("speaker.wave.2", label: "朗读译文", disabled: text.isEmpty) {
                    TranslateSpeaker.shared.toggle(text, language: result?.target ?? currentTarget)
                }
                paneButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "已拷贝" : "拷贝译文",
                           disabled: text.isEmpty) {
                    ColorSampling.copy(text)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 12)
    }

    private func paneButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 24, height: 22)
                .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    /// One line, always there, so the panel does not change height under
    /// the pointer: the language pack hint, an error, or the reassurance.
    private var statusLine: some View {
        HStack(spacing: 5) {
            Image(systemName: message == nil ? "lock.shield" : "info.circle")
                .font(.system(size: 10, weight: .semibold))
            Text(message ?? "由 macOS 在本机翻译，免费，文字不会上传。")
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(WidgetStyle.caption(10))
        .foregroundStyle(.white.opacity(message == nil ? 0.5 : 0.8))
        .frame(height: 26, alignment: .leading)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("最近翻译")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                if !history.isEmpty {
                    Button("清除") {
                        guard !context.isPreview else { return }
                        WidgetWriter.write(instance) { Translate.store([], in: &$0) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)
            if history.isEmpty {
                PanelNote(symbol: "clock.arrow.circlepath", text: "翻译过的内容会保存在这里，最多 \(Translate.maxHistory) 条。")
                    .frame(height: 132)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(history.enumerated()), id: \.offset) { index, record in
                            historyRow(record, index: index)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: 132)
            }
        }
    }

    private func historyRow(_ record: TranslateRecord, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(Translate.pairText(source: record.source, target: record.target))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Color.white.opacity(0.12), in: .capsule)
            VStack(alignment: .leading, spacing: 1) {
                Text(Translate.snippet(record.resultText))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                Text(Translate.snippet(record.sourceText))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture { restore(record) }
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
            message = "原文已经是\(TranslationRunner.name(to))，换一个目标语言试试。"
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

    private func pasteClipboard() {
        guard !context.isPreview,
              let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !context.isPreview { message = "剪贴板里没有文字。" }
            return
        }
        draft = Translate.clamped(text)
        translate(force: true)
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
