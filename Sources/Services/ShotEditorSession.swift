import AppKit
import Observation
import SwiftUI
@preconcurrency import Translation

/// 截图编辑工具条：截完后选区原地留在屏幕上，旁边一排液态玻璃工具条。
///
/// - 入口：截图工具卡片「截完后」选「编辑」（新卡片的默认值）、截图编辑 / 截图翻译
///   快捷键、翻译面板的「截图翻译」。
/// - 截图：码头自己的选框（`RegionPicker`）框好，再 `screencapture -R` 截那一块到临时
///   文件，读进内存后马上删掉，不留副本；只有点了「存文件」才写进截图文件夹。
///   截窗口时交给 screencapture 点选，编辑区摆在屏幕中间。
/// - 窗口盖住鼠标所在的那块屏幕，选区外压暗；Esc 取消、回车完成（拷贝并关闭）、⌘Z 撤销。
/// - 截图翻译和贴图是 Pro（`ShotFeature`），没解锁时点了弹付费墙。
/// 判断逻辑（标注、撤销栈、工具条位置、翻译排版、键盘、Pro）在 Core/ShotEditor.swift。
@MainActor
final class ShotEditor: NSObject, NSWindowDelegate {
    static let shared = ShotEditor()

    enum Intent { case edit, translate }

    /// DocketApp 接上，「送翻译」「问 AI」找扩展栏上的卡片用。
    weak var app: AppState?

    private var window: ShotEditorWindow?
    private var model: ShotEditorModel?
    private var keyMonitor: Any?
    private var busy = false

    var isOpen: Bool { window != nil }

    private override init() {}

    private var unlocked: Bool { ProAccess.isUnlocked }

    // MARK: 开始

    /// 截图编辑快捷键、截图工具卡片（截完后选了「编辑」）。
    func begin(_ mode: ScreenCapture.Mode = .region, options: CaptureOptions = CaptureOptions(after: .edit),
               intent: Intent = .edit) {
        guard !busy, window == nil else { return }
        if intent == .translate, !ProLicenseGate.canUseShotFeature(.translate, unlocked: unlocked) {
            PaywallWindow.shared.show()
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard let shot = await capture(mode, delay: options.delay) else { return }
            open(shot, format: options.format, intent: intent)
        }
    }

    /// 截图翻译快捷键、翻译面板的「截图翻译」：框选完直接开始翻译。
    func beginTranslate() {
        begin(.region, options: CaptureOptions(after: .edit), intent: .translate)
    }

    private struct Shot {
        var image: CGImage
        /// 选区在 AppKit 屏幕坐标里的位置（点）。
        var frame: CGRect
        var screen: NSScreen
    }

    private func capture(_ mode: ScreenCapture.Mode, delay: Int) async -> Shot? {
        if !CGPreflightScreenCaptureAccess() {
            // 和录屏同一句话。截图照样能截，只是别的 App 的窗口可能是空的。
            QuickHint.show(tr("没有录到画面：请在“系统设置 ▸ 隐私与安全性 ▸ 屏幕录制”中允许码头。"),
                           symbol: "exclamationmark.triangle.fill", tint: .orange, seconds: 4)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockling-shot-\(UUID().uuidString).png")
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        switch mode {
        case .region:
            guard case .rect(let rect)? = await RegionPicker.pick(prompt: tr("拖动框选要截的区域，Esc 取消"),
                                                                  allowsFullScreen: false) else { return nil }
            if delay > 0 { await ScreenCapture.countdown(delay) }
            // 选框收起要一点时间，免得截进去。
            try? await Task.sleep(for: .milliseconds(160))
            _ = await ScreenCapture.run(["-x", "-R", rect.argument, url.path])
            guard let box = ShotImaging.loadAndDiscard(url) else { return nil }
            let frame = CGRect(x: CGFloat(rect.x), y: primaryHeight - CGFloat(rect.y) - CGFloat(rect.height),
                               width: CGFloat(rect.width), height: CGFloat(rect.height))
            return Shot(image: box.image, frame: frame, screen: screen(containing: frame))
        case .window:
            var frame: CGRect?
            if delay > 0 {
                await ScreenCapture.countdown(delay)
                if let id = ScreenCapture.windowUnderPointer() {
                    frame = windowFrame(id, primaryHeight: primaryHeight)
                    _ = await ScreenCapture.run(["-x", "-o", "-l\(id)", url.path])
                } else {
                    _ = await ScreenCapture.run(["-x", url.path])
                    frame = NSScreen.screens.first?.frame
                }
            } else {
                _ = await ScreenCapture.run(["-i", "-W", "-o", "-x", url.path])
            }
            guard let box = ShotImaging.loadAndDiscard(url) else { return nil }
            let target = frame.map(screen(containing:)) ?? pointerScreen()
            let placed = frame ?? centered(box.image, on: target)
            return Shot(image: box.image, frame: placed, screen: target)
        }
    }

    private func screen(containing frame: CGRect) -> NSScreen {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? pointerScreen()
    }

    private func pointerScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 点选窗口截的图不知道窗口在哪：按屏幕的倍率换成点，放在屏幕中间，太大就缩到可见范围的 85%。
    private func centered(_ image: CGImage, on screen: NSScreen) -> CGRect {
        let scale = max(screen.backingScaleFactor, 1)
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let visible = screen.visibleFrame
        let limit = CGSize(width: visible.width * 0.85, height: visible.height * 0.8)
        let shrink = min(1, limit.width / max(size.width, 1), limit.height / max(size.height, 1))
        size = CGSize(width: (size.width * shrink).rounded(), height: (size.height * shrink).rounded())
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 20,
                      width: size.width, height: size.height)
    }

    private func windowFrame(_ id: Int, primaryHeight: CGFloat) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]],
              let info = list.first, let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
        return CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    // MARK: 窗口

    private func open(_ shot: Shot, format: CaptureFormat, intent: Intent) {
        let screenFrame = shot.screen.frame
        let local = CGRect(x: shot.frame.minX - screenFrame.minX, y: screenFrame.maxY - shot.frame.maxY,
                           width: shot.frame.width, height: shot.frame.height)
        let model = ShotEditorModel(image: shot.image, selection: local,
                                    bounds: CGRect(origin: .zero, size: screenFrame.size),
                                    format: format, screenFrame: screenFrame)
        model.locked = !unlocked
        self.model = model
        let window = ShotEditorWindow(screen: shot.screen)
        window.delegate = self
        window.contentView = ShotEditorHostingView(rootView: ShotEditorView(model: model) { [weak self] action in
            self?.handle(action)
        })
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        watchKeys()
        if intent == .translate { translate() }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 付费墙关掉回来：编辑区再盖到最上层，解锁了就去掉 Pro 小锁。
        window?.level = .screenSaver
        model?.locked = !unlocked
    }

    private func watchKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, let model = self.model else { return event }
            // 中文输入法正在选字：回车、Esc 归输入法。
            if let field = window.firstResponder as? NSTextView, field.hasMarkedText() { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = ShotKeyCommand.resolve(keyCode: event.keyCode, command: flags.contains(.command),
                                                 shift: flags.contains(.shift), editingText: model.textEntry != nil)
            switch command {
            case .passThrough: return event
            case .cancel: self.handle(.cancel)
            case .done: self.handle(.done)
            case .undo: self.handle(.undo)
            case .copy: self.handle(.copy)
            case .cancelText: model.textEntry = nil
            case .commitText: model.commitText()
            }
            return nil
        }
    }

    // MARK: 工具条上的动作

    func handle(_ action: ShotAction) {
        guard let model else { return }
        switch action {
        case .tool(let tool):
            model.commitText()
            model.tool = model.tool == tool ? nil : tool
            if model.tool == .mosaic { model.preparePixelated() }
        case .color(let color):
            model.color = color
            ShotEditorModel.lastColor = color
            if var entry = model.textEntry {
                entry.color = color
                model.textEntry = entry
            }
        case .stroke(let stroke):
            model.stroke = stroke
            ShotEditorModel.lastStroke = stroke
            if model.tool == .mosaic { model.preparePixelated() }
        case .recognize:
            recognize()
        case .translate:
            translate()
        case .showTranslated(let on):
            model.showTranslated = on
        case .copyTranslation:
            QuickTool.copy(ShotTranslationLayout.joinedTranslation(model.overlay.map(\.item)))
            model.flash(tr("已拷贝译文"))
        case .copyText:
            QuickTool.copy(model.recognizedText)
            model.flash(tr("已拷贝文字"))
        case .sendToTranslate:
            sendToTranslate(model.recognizedText)
        case .askAI:
            askAI(model.recognizedText)
        case .closePanel:
            model.textPanel = false
        case .undo:
            if model.textEntry != nil {
                model.textEntry = nil
            } else if !model.document.undo() {
                NSSound.beep()
            }
        case .save:
            guard let image = model.rendered() else { return }
            let format = model.format
            close()
            if let url = ShotImaging.save(image, format: format) {
                QuickHint.show(tr("已存到“\(url.deletingLastPathComponent().lastPathComponent)”"),
                               symbol: "square.and.arrow.down")
            } else {
                QuickHint.show(tr("没能存下截图"), symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
        case .pin:
            guard ProLicenseGate.canUseShotFeature(.pin, unlocked: unlocked) else { return paywall() }
            guard let image = model.rendered() else { return }
            let frame = CGRect(x: model.screenFrame.minX + model.selection.minX,
                               y: model.screenFrame.maxY - model.selection.maxY,
                               width: model.selection.width, height: model.selection.height)
            close()
            ShotPin.open(image, frame: frame)
        case .copy:
            guard let image = model.rendered() else { return }
            ShotImaging.copy(image)
            model.flash(tr("已拷贝，可以接着画"))
        case .cancel:
            close()
        case .done:
            model.commitText()
            guard let image = model.rendered() else { return close() }
            ShotImaging.copy(image)
            close()
            QuickHint.show(tr("截图已拷贝"), symbol: "doc.on.clipboard")
        }
    }

    private func paywall() {
        // 编辑区在屏幕保护层，先降下来，付费墙才看得见；编辑区再成为焦点时升回去。
        window?.level = .normal
        PaywallWindow.shared.show()
    }

    // MARK: 取字和翻译

    private func recognize() {
        guard let model else { return }
        model.commitText()
        if model.textPanel {
            model.textPanel = false
            return
        }
        Task { @MainActor in
            await model.ensureLines()
            guard self.model === model else { return }
            if model.recognizedText.isEmpty {
                model.flash(tr("没有识别到文字"))
            } else {
                model.textPanel = true
            }
        }
    }

    private func translate() {
        guard let model else { return }
        guard ProLicenseGate.canUseShotFeature(.translate, unlocked: unlocked) else { return paywall() }
        model.commitText()
        switch model.translation {
        case .ready:
            model.showTranslated.toggle()
            return
        case .working:
            return
        case .idle, .failed:
            break
        }
        model.translation = .working(tr("正在识别文字…"))
        Task { @MainActor in
            await model.ensureLines()
            guard self.model === model else { return }
            guard !model.paragraphs.isEmpty else {
                model.translation = .failed(tr("没有识别到文字"))
                return
            }
            let all = model.paragraphs.map(\.text).joined(separator: "\n")
            let pair = ShotTranslateDirection.pair(for: all)
            if let source = pair.source {
                let status = try? await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                                      to: Locale.Language(identifier: pair.target))
                if status == .unsupported {
                    model.translation = .failed(tr("暂不支持从\(TranslationRunner.name(source))翻译成\(TranslationRunner.name(pair.target))。"))
                    return
                }
                model.translation = .working(status == .supported
                                             ? tr("首次翻译这对语言需要下载语言包，请在系统弹出的窗口中下载。")
                                             : tr("正在本机翻译…"))
            } else {
                model.translation = .working(tr("正在本机翻译…"))
            }
            let configuration = TranslationSession.Configuration(
                source: pair.source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: pair.target))
            if TranslationRunner.samePair(model.translationConfig, configuration) {
                model.translationConfig?.invalidate()
            } else {
                model.translationConfig = configuration
            }
        }
    }

    /// 视图的 `.translationTask` 拿到会话后调这里：一段一段翻（和翻译面板一样传字符串，
    /// 请求对象不跨线程），翻完一起盖上去。
    func runTranslation(_ session: TranslationSession, model: ShotEditorModel) async {
        guard case .working = model.translation, !model.paragraphs.isEmpty else { return }
        let texts = model.paragraphs.map(\.text)
        var translations: [String] = []
        do {
            for text in texts {
                let response = try await session.translate(text)
                translations.append(response.targetText)
            }
            guard self.model === model else { return }
            model.applyTranslations(translations)
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            model.translation = .failed(tr("翻译没有完成：\(error.localizedDescription)"))
        }
    }

    // MARK: 送到别的卡片

    private func widget(_ kind: WidgetKind) -> WidgetInstance? {
        app?.allWidgets.first { $0.kind == kind }
    }

    /// 「送翻译」：扩展栏上有翻译卡片就带进它的面板；没有就在截图上原位翻译。
    private func sendToTranslate(_ text: String) {
        guard !text.isEmpty else { return }
        guard let target = widget(.translate) else {
            model?.textPanel = false
            translate()
            return
        }
        ShotInbox.shared.translate[target.id] = text
        close()
        WidgetPanelOpener.shared.open(target.id)
    }

    /// 「问 AI」：文字带进第一张 AI 助手卡片的输入框，打开它的提问面板；没有 AI 助手卡片时拷贝。
    private func askAI(_ text: String) {
        guard !text.isEmpty else { return }
        close()
        ShotEditor.deliverToAI(text, widget: widget(.aiAssistant)?.id)
    }

    static func deliverToAI(_ text: String, widget: UUID?) {
        guard let widget else {
            QuickTool.copy(text)
            QuickHint.show(tr("已拷贝文字。扩展栏上还没有 AI 助手卡片"), symbol: "doc.on.clipboard", seconds: 3)
            return
        }
        let state = AIPanelState.shared
        state.setDraft(AIClipboard.insert(text, into: state.draft(widget)), for: widget)
        state.mode = .ask
        WidgetPanelOpener.shared.open(widget)
    }

    /// AI 助手面板的「截图问 AI」：系统框选一块，识别文字带进输入框，再打开面板。
    /// 截的图只在临时文件里待到识别完。
    static func askAIFromScreen(widget: UUID) {
        Task { @MainActor in
            guard let url = await QuickTool.pickRegion() else {
                WidgetPanelOpener.shared.open(widget)
                return
            }
            let text = await QuickTool.recognizeText(at: url)
            try? FileManager.default.removeItem(at: url)
            guard !text.isEmpty else {
                QuickHint.show(tr("没有识别到文字"), symbol: "text.viewfinder", tint: .secondary)
                WidgetPanelOpener.shared.open(widget)
                return
            }
            deliverToAI(text, widget: widget)
        }
    }
}

/// 工具条和小面板上的每个动作。
enum ShotAction: Equatable {
    case tool(ShotTool)
    case color(ShotColor)
    case stroke(ShotStroke)
    case recognize, translate
    case showTranslated(Bool)
    case copyTranslation, copyText, sendToTranslate, askAI, closePanel
    case undo, save, pin, copy, cancel, done
}

/// 「送翻译」时交给翻译卡片面板的文字：面板打开时取走，放进输入框。
@MainActor
@Observable
final class ShotInbox {
    static let shared = ShotInbox()
    var translate: [UUID: String] = [:]
    private init() {}

    func takeTranslate(_ widget: UUID) -> String? {
        translate.removeValue(forKey: widget)
    }
}

// MARK: - 窗口

/// 盖住一块屏幕的透明窗口，能成为键盘焦点（收 Esc、回车、⌘Z 和文字输入）。
final class ShotEditorWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 第一下点击就生效（窗口刚出来还没成为焦点时也一样）。
final class ShotEditorHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
