import AppKit
import Observation

/// 打开 AI 服务：装了它的 Mac App 就开 App，没装就开网页。
///
/// 只是打开，什么都不发送。带问题的网址（服务正式支持时）一定走浏览器，
/// 因为 App 不接这个网址；复制问题再打开时优先 App，用户在里面粘贴。
@MainActor
enum AIServiceOpener {
    /// 这个服务在本机能打开的 App，没有为 nil。
    static func installedApp(_ service: AIService) -> URL? {
        if let path = service.appPath, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let id = service.appBundleID, !id.isEmpty {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        return nil
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

    private init() {}

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

    func requestPanel(_ id: UUID, mode: Mode, toggle: Bool = false, customForm: Bool = false) {
        self.mode = mode
        wantsCustomForm = customForm
        NotificationCenter.default.post(name: Self.openRequest, object: nil,
                                        userInfo: ["id": id.uuidString, "toggle": toggle])
    }
}
