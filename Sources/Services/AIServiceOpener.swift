import AppKit
import Observation

/// 打开 AI 服务：装了它的 Mac App 就开 App，没装就开网页。
///
/// 只是打开，什么都不发送。找 App 的顺序：设置里亲手选的、服务自己记下的
/// 路径（自定义服务）、候选 bundle id、最后在「应用程序」文件夹里按 App 名
/// 找（见 `AIAppMatch`）。带问题的网址只在没装 App 时走浏览器。
@MainActor
enum AIServiceOpener {
    /// 这个服务在本机能打开的 App，没有为 nil。
    static func installedApp(_ service: AIService) -> URL? {
        app(for: service)?.url
    }

    /// 找到的 App 和它是怎么找到的（设置里显示「会打开你选的 X」还是「会打开 X」）。
    static func app(for service: AIService) -> (url: URL, chosen: Bool)? {
        let manager = FileManager.default
        if let path = AIChatCenter.shared.settings.appPaths[service.id], manager.fileExists(atPath: path) {
            return (URL(fileURLWithPath: path), true)
        }
        if let path = service.appPath, !path.isEmpty, manager.fileExists(atPath: path) {
            return (URL(fileURLWithPath: path), service.isCustom)
        }
        for id in AIAppMatch.bundleIDs(for: service) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return (url, false) }
        }
        for folder in applicationFolders {
            if let name = AIAppMatch.bestMatch(for: service, among: listing(folder)) {
                return (folder.appendingPathComponent(name), false)
            }
        }
        return nil
    }

    /// 设置展开区里那行字用的：会打开什么。
    static func target(for service: AIService) -> AIAppMatch.Target {
        if let found = app(for: service) {
            let name = AIAppMatch.displayName(found.url.path)
            return found.chosen ? .chosen(name: name) : .found(name: name)
        }
        return service.homeURL == nil ? .nothing : .web
    }

    private static var applicationFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// 文件夹里的 .app 名字。设置页每次重画都会问，按文件夹缓存 5 秒。
    private static var listings: [URL: (date: Date, names: [String])] = [:]

    private static func listing(_ folder: URL) -> [String] {
        if let cached = listings[folder], Date().timeIntervalSince(cached.date) < 5 { return cached.names }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".app") }
            .sorted()
        listings[folder] = (Date(), names)
        return names
    }

    /// 点字牌：App 优先，否则网页。两样都打不开时返回 false。
    @discardableResult
    static func open(_ service: AIService) -> Bool {
        if let app = installedApp(service) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
            return true
        }
        guard let url = service.homeURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// 带着问题的网址，在默认浏览器里打开。
    @discardableResult
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// 把问题放进剪贴板（纯文本，覆盖原有内容）。
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

/// 卡片和面板共用的状态：面板在提问还是管理字牌、每张卡片的草稿和提示。
///
/// 草稿放在这里而不是面板的 @State 里：面板关了再开、或者中间开过别的
/// 小组件的面板，写了一半的问题都还在，直到成功交出去为止。
@MainActor @Observable
final class AIPanelState {
    static let shared = AIPanelState()

    enum Mode: Equatable { case ask, manage }

    var mode: Mode = .ask
    /// 下一次打开管理页时直接展开“自定义…”。
    var wantsCustomForm = false

    /// “自定义…”里填了一半的内容。选 App 时面板会被收起，存在这里就不会丢。
    struct Form: Equatable {
        var name = ""
        var address = ""
        var appPath: String?
        var appBundleID: String?
    }

    var form = Form()
    private(set) var drafts: [UUID: String] = [:]
    private(set) var hints: [UUID: String] = [:]
    /// 选 App 时面板是自己收起的，选完要原样回来，这一次关闭不重置。
    var holdingForAppChooser = false

    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    private init() {
        // 面板关上（点外面、Esc、再点卡片）就回到提问页，“管理字牌”和填了
        // 一半的“自定义…”都不留到下次。同步收通知：选 App 的流程紧接着就
        // 要把模式设回管理页。
        closeObserver = NotificationCenter.default.addObserver(
            forName: WidgetDetailWindow.didClose, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { AIPanelState.shared.panelClosed() }
        }
    }

    /// 面板关了：回到提问页，收起自定义表单。草稿和提示另算，照旧保留。
    func panelClosed() {
        guard !holdingForAppChooser else { return }
        mode = .ask
        wantsCustomForm = false
        if form != Form() { form = Form() }
    }

    func draft(_ id: UUID) -> String { drafts[id] ?? "" }

    func setDraft(_ text: String, for id: UUID) {
        drafts[id] = text.isEmpty ? nil : text
        // 一开始改问题，上一次的提示就不再对应它了。
        if hints[id] != nil { hints[id] = nil }
    }

    func hint(_ id: UUID) -> String? { hints[id] }

    func setHint(_ text: String?, for id: UUID) { hints[id] = text }

    /// 请扩展栏打开（或关掉）这张卡片的面板。扩展栏手里有锚点，所以由它来开。
    static let openRequest = Notification.Name("com.docket-zh.ai-assistant.open")

    /// - Parameter origin: 收起前面板的中心点。带上时由那块屏幕上的扩展栏
    ///   来开，不跟着指针跑（见 `AIPanelReturn`）。
    func requestPanel(_ id: UUID, mode: Mode, toggle: Bool = false, customForm: Bool = false,
                      origin: CGPoint? = nil) {
        self.mode = mode
        wantsCustomForm = customForm
        var info: [String: Any] = ["id": id.uuidString, "toggle": toggle]
        if let origin { info["origin"] = NSValue(point: origin) }
        NotificationCenter.default.post(name: Self.openRequest, object: nil, userInfo: info)
    }
}
