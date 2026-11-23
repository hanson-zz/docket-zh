import AppKit
import Observation
import WebKit

/// 刘海对话和货架上 AI 卡片共用的会话状态。
///
/// 一份草稿（切换服务不丢）、每个服务各自的对话记录和网页、正在生成的
/// 服务。面板关了再开还是原来的对话；回答生成中收起面板也不打断。服务
/// 列表取第一个 AI 助手小组件的设置（先找当前布局，再找别的布局），一个
/// 都没放时用默认三块。
@MainActor @Observable
final class AIChatCenter {
    static let shared = AIChatCenter()

    @ObservationIgnored weak var app: AppState?

    var draft = ""
    /// 本次运行里选中的服务；nil 时用上次保存的，再没有就用卡片的默认服务。
    private(set) var selectedID: String?
    private(set) var conversations: [String: [AIChatMessage]] = [:]
    private(set) var generating: Set<String> = []
    /// 钉住后点面板外面不收起。
    var pinned = false
    /// App 模式下做完之后的一句话。
    var jumpHint: String?
    /// 正在显示谷歌登录页的网页。
    private(set) var googleSignIn: Set<String> = []
    private(set) var loading: Set<String> = []
    /// 密钥改过就加一，让读“有没有密钥”的界面重画。
    private(set) var keyRevision = 0
    /// 剪贴板里现在的文字（只在面板开着时读），没有文字时为 nil。
    private(set) var clipboardText: String?
    /// 快捷指令和常用提示词做完之后的一句话（网页模式下尤其要说清楚）。
    var notice: String?
    /// 刘海对话里那一排快捷指令和常用提示词展开着。默认折叠，只留一行开关，
    /// 对话区占更多地方；本次运行里记住，不存进设置。
    var promptsExpanded = false
    /// 小组件刚把问题交过来、刘海对话正要打开：这一次打开不清掉 `notice`
    /// （网页模式那句「已复制，请粘贴」要留着给用户看）。
    @ObservationIgnored var holdNoticeOnce = false
    /// 加一就让完整对话面板把光标放进底部输入条（快捷结果卡片的「继续追问」）。
    private(set) var focusRequest = 0

    @ObservationIgnored private var clipboardChangeCount = -1
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// 每个服务正在流的那一条回答。被新问题顶掉的旧请求晚到的收尾只改它自己那条，
    /// 不会把新请求的「生成中」清掉。
    @ObservationIgnored private var activeReply: [String: UUID] = [:]
    @ObservationIgnored private var webViews: [String: WKWebView] = [:]
    @ObservationIgnored private var webDelegates: [String: AIWebDelegate] = [:]

    private init() {}

    var isGenerating: Bool { !generating.isEmpty }

    /// 正在生成的那个服务的名字（刘海下沿「DeepSeek 正在思考」用），没在生成时为 nil。
    var generatingTitle: String? {
        guard !generating.isEmpty else { return nil }
        if let current, generating.contains(current.id) { return current.title }
        return allServices.first { generating.contains($0.id) }?.title
    }

    // MARK: 设置和服务

    var settings: AINotchSettings { app?.state.aiNotch ?? AINotchSettings() }

    func updateSettings(_ change: (inout AINotchSettings) -> Void) {
        guard let app else { return }
        var next = app.state.aiNotch
        change(&next)
        if next != app.state.aiNotch { app.state.aiNotch = next }
    }

    /// 第一个 AI 助手小组件。
    var widget: WidgetInstance? {
        guard let app else { return nil }
        func find(_ items: [DockItem]) -> WidgetInstance? {
            for item in items {
                switch item {
                case .widget(let widget) where widget.kind == .aiAssistant: return widget
                case .group(let group): if let found = find(group.items) { return found }
                default: continue
                }
            }
            return nil
        }
        if let profile = app.customProfile, let found = find(profile.items) { return found }
        for profile in app.state.profiles {
            if let found = find(profile.items) { return found }
        }
        return nil
    }

    var widgetConfig: WidgetConfig { widget?.config ?? WidgetConfig() }

    /// 卡片上勾选的服务，也就是面板顶部的字牌胶囊。
    var services: [AIService] { AIServices.enabled(in: widgetConfig) }

    /// 设置表里列出的：内置的加自定义的。
    var allServices: [AIService] { AIServices.all(in: widgetConfig) }

    var current: AIService? {
        let list = services
        let id = selectedID ?? settings.lastServiceID
        return list.first { $0.id == id } ?? AIServices.defaultService(in: widgetConfig, enabled: list)
    }

    func hasKey(_ serviceID: String) -> Bool {
        _ = keyRevision
        return AIKeyStore.hasKey(serviceID)
    }

    func mode(for service: AIService) -> AIOpenMode {
        AIOpenModes.mode(for: service, settings: settings, hasKey: hasKey(service.id))
    }

    func endpoint(for service: AIService) -> AIEndpoint? {
        AIEndpoints.resolved(service.id, override: settings.endpoints[service.id])
    }

    func modeLabel(for service: AIService) -> String {
        let current = self.mode(for: service)
        return AIOpenModes.label(current, model: current == .api ? self.endpoint(for: service)?.model : nil)
    }

    /// 这个服务的 API、网页、App 哪几种能选（小组件的模式胶囊、对话卡片的分段控件）。
    func modeOptions(for service: AIService) -> [AIModeOption] {
        AIModeChoice.options(hasAPI: hasKey(service.id) && endpoint(for: service) != nil,
                             hasWeb: service.homeURL != nil)
    }

    /// 换这个服务的打开方式，和设置 ▸ AI 里改的是同一个键。不能选的不换。
    func setMode(_ mode: AIOpenMode, for service: AIService) {
        guard modeOptions(for: service).contains(where: { $0.mode == mode && $0.available }),
              self.mode(for: service) != mode else { return }
        jumpHint = nil
        notice = nil
        updateSettings { $0.modes[service.id] = mode }
    }

    /// 模式胶囊点一下：换到下一种能选的。
    func cycleMode(for service: AIService) {
        let options = modeOptions(for: service)
        let next = AIModeChoice.next(after: mode(for: service),
                                     hasAPI: options.first { $0.mode == .api }?.available ?? false,
                                     hasWeb: options.first { $0.mode == .web }?.available ?? false)
        setMode(next, for: service)
    }

    func select(_ id: String) {
        guard services.contains(where: { $0.id == id }) else { return }
        selectedID = id
        jumpHint = nil
        notice = nil
        if settings.lastServiceID != id { updateSettings { $0.lastServiceID = id } }
    }

    func keysChanged() { keyRevision += 1 }

    /// 按 id 找服务（卡片上勾选的和设置里列出的都算）。
    func service(_ id: String) -> AIService? {
        services.first { $0.id == id } ?? allServices.first { $0.id == id }
    }

    /// 让完整对话面板把光标放进输入条。
    func requestInputFocus() { focusRequest += 1 }

    // MARK: API 对话

    func messages(_ serviceID: String) -> [AIChatMessage] { conversations[serviceID] ?? [] }

    func isGenerating(_ serviceID: String) -> Bool { generating.contains(serviceID) }

    /// 发出草稿。空白不发；这个服务还在生成时不发。
    func send() {
        guard let service = current, mode(for: service) == .api,
              !generating.contains(service.id), let question = AIAsk.question(draft) else { return }
        conversations[service.id, default: []].append(AIChatMessage(role: .user, text: question))
        draft = ""
        start(service)
    }

    /// 小组件交过来的结果。
    enum Handoff: Equatable {
        /// 交过来了（API 已经开始回答，网页已复制）。
        case accepted
        /// 这个服务还在回答，没交。
        case busy
        /// 刘海对话的服务列表里没有它（用的是另一张 AI 卡片），没交。
        case unavailable
    }

    /// 小组件提问面板交过来的问题。先切到同一个服务（和小组件共用当前服务），
    /// API 直接发出去，请求挂在这里，不挂在任何视图上，面板关了也照样答完；
    /// 刘海输入框里写了一半的字不动。网页复制好问题、载入网页，提示用户粘贴，
    /// 不假装已经发送。App 方式不经过这里。
    ///
    /// 连续提问（上一条还在生成时又从小组件提问）：取消，不排队。上一条停在已经流出来的
    /// 地方（标为已停止，字留着），马上答新问题。小组件提问是「换个问题」的意思，排队要
    /// 等上一条答完才动，结果卡片会一直停在旧回答上，看起来像没反应。刘海对话里自己的
    /// 发送键仍然是「生成中变停止」，不走这里。
    func receive(_ question: String, for service: AIService) -> Handoff {
        select(service.id)
        guard current?.id == service.id else { return .unavailable }
        switch mode(for: service) {
        case .api:
            if generating.contains(service.id) { cancelInFlight(service.id) }
            conversations[service.id, default: []].append(AIChatMessage(role: .user, text: question))
            notice = nil
            holdNoticeOnce = false
            start(service)
        case .web:
            AIServiceOpener.copy(question)
            _ = webView(for: service)
            notice = AIHandoff.webNotice(service: service.title)
            holdNoticeOnce = true
        case .jump:
            return .unavailable
        }
        return .accepted
    }

    /// 重新回答最后一个问题：去掉最后的回答（出错、停止或者已经答完的都算）。
    /// `serviceID` 不给时用当前服务（快捷结果卡片给它自己那个服务）。
    func retry(_ serviceID: String? = nil) {
        guard let service = serviceID.flatMap({ self.service($0) }) ?? current,
              !generating.contains(service.id) else { return }
        var list = conversations[service.id] ?? []
        while let last = list.last, last.role == .assistant { list.removeLast() }
        guard list.last?.role == .user else { return }
        conversations[service.id] = list
        start(service)
    }

    func stop() {
        guard let id = current?.id else { return }
        tasks[id]?.cancel()
    }

    /// 清空当前服务的对话，重新开始。
    func clear() {
        guard let id = current?.id else { return }
        tasks[id]?.cancel()
        conversations[id] = []
    }

    /// 停掉这个服务正在流的回答，同步收尾（标为已停止、清掉生成中），好马上发下一条。
    private func cancelInFlight(_ serviceID: String) {
        tasks[serviceID]?.cancel()
        tasks[serviceID] = nil
        generating.remove(serviceID)
        if let messageID = activeReply.removeValue(forKey: serviceID),
           let index = conversations[serviceID]?.firstIndex(where: { $0.id == messageID }),
           conversations[serviceID]?[index].status == .streaming {
            conversations[serviceID]?[index].status = .stopped
        }
    }

    func copy(_ text: String) {
        AIServiceOpener.copy(text)
    }

    private func start(_ service: AIService) {
        let id = service.id
        // 被换掉的旧问题不带上，连着的问题合成一条（见 `AIChatContext.outgoing`）。
        let history = AIChatContext.outgoing(conversations[id] ?? [])
        let reply = AIChatMessage(role: .assistant, text: "", status: .streaming)
        conversations[id, default: []].append(reply)
        guard let endpoint = self.endpoint(for: service) else { return finish(id, reply.id, .failed(AIChatFailure.missingEndpoint.message)) }
        guard let key = AIKeyStore.read(id) else { return finish(id, reply.id, .failed(AIChatFailure.missingKey.message)) }
        guard let request = AIChatRequest.urlRequest(endpoint: endpoint, key: key, history: history) else {
            return finish(id, reply.id, .failed(AIChatFailure.badURL.message))
        }
        generating.insert(id)
        activeReply[id] = reply.id
        tasks[id] = Task { [weak self] in
            do {
                for try await piece in AIChatClient.stream(request) {
                    self?.append(piece, to: reply.id, in: id)
                }
                self?.finish(id, reply.id, Task.isCancelled ? .stopped : .done)
            } catch let failure as AIChatFailure {
                self?.finish(id, reply.id, .failed(failure.message))
            } catch {
                self?.finish(id, reply.id, .stopped)
            }
        }
    }

    private func append(_ piece: String, to messageID: UUID, in serviceID: String) {
        // 已经被顶掉（停止）的旧请求晚到的字不再往上接。
        guard activeReply[serviceID] == messageID else { return }
        guard let index = conversations[serviceID]?.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[serviceID]?[index].text += piece
    }

    private func finish(_ serviceID: String, _ messageID: UUID, _ status: AIChatMessage.Status) {
        // 只有还是这个服务当前那条请求时才清「生成中」：被新问题顶掉的旧请求晚到的收尾
        // 不能把新请求的状态清掉（见 `cancelInFlight`）。没开始流就失败的也走这里。
        if activeReply[serviceID] == messageID || activeReply[serviceID] == nil {
            generating.remove(serviceID)
            tasks[serviceID] = nil
            activeReply[serviceID] = nil
        }
        guard let index = conversations[serviceID]?.firstIndex(where: { $0.id == messageID }),
              conversations[serviceID]?[index].status == .streaming else { return }
        conversations[serviceID]?[index].status = status
    }

    // MARK: 网页

    /// 这个服务自己的网页，第一次用到时建好并载入，之后一直留着（切换不重载）。
    /// 登录信息存在默认的持久数据仓库里，下次打开还在。
    func webView(for service: AIService) -> WKWebView? {
        if let existing = webViews[service.id] { return existing }
        guard let home = service.homeURL else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), configuration: configuration)
        view.customUserAgent = AIWeb.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        let delegate = AIWebDelegate(serviceID: service.id, home: home, center: self)
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        view.setAccessibilityLabel(tr("\(service.title) 网页"))
        webViews[service.id] = view
        webDelegates[service.id] = delegate
        view.load(URLRequest(url: home))
        return view
    }

    func reload(_ service: AIService) {
        guard let view = webViews[service.id] else { return }
        if view.url == nil, let home = service.homeURL { view.load(URLRequest(url: home)) } else { view.reload() }
    }

    func openInBrowser(_ service: AIService) {
        let url = webViews[service.id]?.url ?? service.homeURL
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }

    func showsGoogleWarning(_ serviceID: String) -> Bool { googleSignIn.contains(serviceID) }

    func isLoading(_ serviceID: String) -> Bool { loading.contains(serviceID) }

    fileprivate func webChanged(_ serviceID: String, url: URL?, loading isLoading: Bool) {
        if AIWeb.isGoogleSignIn(url) { googleSignIn.insert(serviceID) } else { googleSignIn.remove(serviceID) }
        if isLoading { loading.insert(serviceID) } else { loading.remove(serviceID) }
    }

    // MARK: 剪贴板接力

    /// 重新读一下剪贴板。剪贴板没变过就不读内容。
    func refreshClipboard() {
        let board = NSPasteboard.general
        guard board.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = board.changeCount
        let text = board.string(forType: .string)
        clipboardText = AIAsk.question(text ?? "") == nil ? nil : text
    }

    /// 剪贴板一行预览，太长的截断。
    var clipboardPreview: String? { AIClipboard.preview(clipboardText, limit: 48) }

    /// 把剪贴板文字带进输入框：输入框空着就换成它，否则另起一行接在后面。
    func pasteClipboard() {
        refreshClipboard()
        guard let clip = clipboardText else {
            notice = tr("剪贴板里没有文字。")
            return
        }
        draft = AIClipboard.insert(clip, into: draft)
        jumpHint = nil
        notice = AIPromptStrip.pasteHint(clipboard: clip)
    }

    // MARK: 快捷指令和常用提示词

    var prompts: [AIPrompt] { settings.prompts }

    func run(_ action: AIQuickAction) { run(template: action.template, name: action.title) }

    func run(_ prompt: AIPrompt) { run(template: prompt.content, name: prompt.name) }

    /// 把输入框（空着时用剪贴板）的文字套进提示词，交给当前服务：API 直接
    /// 发出去流式回答；网页复制提示词，到网页里粘贴；App 和平时提问一样，
    /// 能带问题的带着打开，其余复制再打开。网页模式没有输入框，只用剪贴板。
    func run(template: String, name: String) {
        guard let service = current else { return }
        refreshClipboard()
        let mode = self.mode(for: service)
        let source = mode == .web ? "" : draft
        guard let prompt = AIPrompts.compose(template, draft: source, clipboard: clipboardText) else {
            notice = mode == .web ? tr("先复制要处理的文字。") : tr("先在输入框里写字，或者复制要处理的文字。")
            return
        }
        switch mode {
        case .api:
            guard !generating.contains(service.id) else {
                notice = tr("还在回答，先停止或等它答完。")
                return
            }
            notice = nil
            draft = prompt
            send()
        case .web:
            AIServiceOpener.copy(prompt)
            _ = webView(for: service)
            notice = tr("“\(name)”的提示词已复制，在 \(service.title) 的输入框里粘贴发送。")
        case .jump:
            notice = nil
            jump(prompt)
        }
    }

    // MARK: App

    /// App 模式：装了 Mac App 就复制问题再打开 App；没装时服务正式支持的带着
    /// 问题开浏览器，其余复制问题再打开网页。
    func jump() { jump(draft) }

    private func jump(_ text: String) {
        guard let service = current else { return }
        let plan = AIAsk.plan(text, service: service, appInstalled: AIServiceOpener.installedApp(service) != nil)
        switch plan {
        case .blocked:
            jumpHint = AIAsk.hint(after: plan, service: service)
            return
        case .openWithQuestion(let url):
            guard AIServiceOpener.open(url) else {
                jumpHint = tr("没能打开 \(service.title)。")
                return
            }
        case .copyThenOpen(let question):
            AIServiceOpener.copy(question)
            guard AIServiceOpener.open(service) else {
                jumpHint = tr("已复制，但没能打开 \(service.title)。")
                return
            }
        }
        draft = ""
        jumpHint = AIAsk.hint(after: plan, service: service)
    }

    /// 只打开服务，不带问题。
    func openService() {
        guard let service = current else { return }
        if !AIServiceOpener.open(service) { jumpHint = tr("没能打开 \(service.title)。") }
    }
}

/// 一个服务网页的导航和新窗口处理。
@MainActor
final class AIWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    let serviceID: String
    let home: URL
    weak var center: AIChatCenter?

    init(serviceID: String, home: URL, center: AIChatCenter) {
        self.serviceID = serviceID
        self.home = home
        self.center = center
    }

    /// 不是网页的链接（mailto:、App 自己的协议）交给系统。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        if ["http", "https", "about", "blob", "data", "javascript"].contains(scheme) { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    /// target=_blank 和 window.open：同一家网站和登录页在当前视图打开，
    /// 别的网站交给浏览器。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        switch AIWeb.newWindowTarget(url, home: home) {
        case .sameView: webView.load(navigationAction.request)
        case .browser: if let url { NSWorkspace.shared.open(url) }
        case .ignore: break
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        center?.webChanged(serviceID, url: webView.url, loading: true)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        center?.webChanged(serviceID, url: webView.url, loading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        center?.webChanged(serviceID, url: webView.url, loading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        center?.webChanged(serviceID, url: webView.url, loading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        center?.webChanged(serviceID, url: webView.url, loading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: any Error) {
        center?.webChanged(serviceID, url: webView.url, loading: false)
    }

    /// 网页进程崩了：重新载入，不留一块白板。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
