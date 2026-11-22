import Foundation

// MARK: - AI 助手：小组件面板的快捷操作

/// 小组件提问面板输入框下面那一排快捷操作胶囊。用户在面板的「助手设置」里
/// 勾选显示哪几个，存在 `AINotchSettings.panelChips`（没存过时用默认四个）。
public enum AIDockChip: String, CaseIterable, Sendable {
    case screenshot, clipboardSummary, clipboard, translate, summarize, polish, explain

    public var title: String {
        switch self {
        case .screenshot: tr("截图提问")
        case .clipboardSummary: tr("剪贴板")
        case .clipboard: tr("处理剪贴板")
        case .translate: tr("翻译", context: "chip")
        case .summarize: tr("总结", context: "chip")
        case .polish: tr("润色", context: "chip")
        case .explain: tr("解释", context: "chip")
        }
    }

    public var symbol: String {
        switch self {
        case .screenshot: "text.viewfinder"
        case .clipboardSummary: "list.clipboard"
        case .clipboard: "doc.on.clipboard"
        case .translate: AIQuickAction.translate.symbol
        case .summarize: AIQuickAction.summarize.symbol
        case .polish: AIQuickAction.polish.symbol
        case .explain: AIQuickAction.explain.symbol
        }
    }

    /// 面板玻璃块、设置页和扩展栏竖版提示里用的名字，比 `title` 写得完整一点，做的事一样。
    public var gridTitle: String {
        switch self {
        case .screenshot: tr("截图提问")
        case .clipboardSummary: tr("总结剪贴板")
        case .clipboard: tr("处理剪贴板")
        case .translate: tr("翻译内容")
        case .summarize: tr("总结内容")
        case .polish: tr("写作优化")
        case .explain: tr("解释内容")
        }
    }

    /// 套提示词的那几个对应的快捷指令；截图和处理剪贴板不套提示词，为 nil。
    /// 剪贴板总结套「总结」，但只用剪贴板里的文字（见 `usesClipboardOnly`）。
    public var quickAction: AIQuickAction? {
        switch self {
        case .screenshot, .clipboard: nil
        case .clipboardSummary: .summarize
        case .translate: .translate
        case .summarize: .summarize
        case .polish: .polish
        case .explain: .explain
        }
    }

    /// 只认剪贴板，不看输入框（剪贴板总结）：剪贴板里没有文字时这个胶囊是灰的。
    public var usesClipboardOnly: Bool { self == .clipboardSummary || self == .clipboard }
}

public enum AIDockChips {
    /// 没设置过时显示的四个（和效果图一致）：截图提问、剪贴板总结、翻译、润色。
    public static let defaults: [AIDockChip] = [.screenshot, .clipboardSummary, .translate, .polish]
    /// 一排最多放几个（面板 380 宽，再多就挤了；后面还有「常用」菜单）。
    public static let maxCount = 4

    /// 存着的 id 变成要显示的胶囊：nil 用默认；认不出的跳过，重复的只留一个，
    /// 按固定顺序排，超过上限的截掉。存了空列表就是一个都不显示。
    public static func resolved(_ raw: [String]?) -> [AIDockChip] {
        guard let raw else { return defaults }
        let wanted = Set(raw.compactMap(AIDockChip.init(rawValue:)))
        return Array(AIDockChip.allCases.filter { wanted.contains($0) }.prefix(maxCount))
    }

    /// 勾上或取消一个，返回要存的新列表。已经满了时勾不上，列表不变。
    public static func toggled(_ chip: AIDockChip, in raw: [String]?) -> [String] {
        var current = resolved(raw)
        if let index = current.firstIndex(of: chip) {
            current.remove(at: index)
        } else if current.count < maxCount {
            current.append(chip)
        }
        let set = Set(current)
        return AIDockChip.allCases.filter { set.contains($0) }.map(\.rawValue)
    }

    /// 这一个现在能不能勾：已经勾上的总能取消，没勾的要还有空位。
    public static func canToggle(_ chip: AIDockChip, in raw: [String]?) -> Bool {
        let current = resolved(raw)
        return current.contains(chip) || current.count < maxCount
    }
}

// MARK: - AI 助手：从小组件交给刘海对话

/// 小组件里按了提交之后，问题交给谁。
public enum AIHandoff: Equatable, Sendable {
    /// 空白，不交。
    case blocked
    /// 要交给刘海对话，但刘海对话是码头 Pro，没解锁：弹付费墙，问题留在框里。
    case paywall
    /// API：交给刘海对话，在那里直接发出去流式回答。
    case notchAPI(String)
    /// 网页：复制问题，打开刘海对话里的网页，由用户自己粘贴发送（码头不替网页填字）。
    case notchWeb(String)
    /// App：留在小组件里跳转（复制或带进网址再打开 App 或浏览器），不进刘海对话。
    case app

    public static func plan(_ text: String, mode: AIOpenMode, notchUnlocked: Bool) -> AIHandoff {
        guard let question = AIAsk.question(text) else { return .blocked }
        switch mode {
        case .jump: return .app
        case .api: return notchUnlocked ? .notchAPI(question) : .paywall
        case .web: return notchUnlocked ? .notchWeb(question) : .paywall
        }
    }

    /// 交出去之后小组件面板要不要收起：交给刘海对话的收起，免得两个窗口叠在一起。
    public var closesDockPanel: Bool {
        switch self {
        case .notchAPI, .notchWeb: true
        case .blocked, .paywall, .app: false
        }
    }

    /// 网页模式交过去之后刘海对话里那一句：只说真做了的（已复制），不说已发送。
    public static func webNotice(service: String) -> String {
        tr("问题已复制，请在 \(service) 的输入框里粘贴（⌘V）后发送。")
    }

    /// 小组件底部服务名旁边那一小句：这个服务按提交会发生什么。要短，底栏里只放一行。
    public static func modeAction(_ mode: AIOpenMode, appInstalled: Bool, supportsAsk: Bool) -> String {
        switch mode {
        case .api: return tr("在刘海里直接回答")
        case .web: return tr("到刘海网页里粘贴")
        case .jump:
            if appInstalled { return tr("复制后打开 App") }
            return supportsAsk ? tr("带着问题打开网页") : tr("复制后打开网页")
        }
    }
}

// MARK: - AI 助手：刘海对话里显示什么

/// 一条回答下面的按钮。
public enum AIAnswerAction: Hashable, Sendable {
    case copy
    /// 继续追问：把光标放回底部输入条。
    case followUp
    case regenerate
}

public enum AINotchChatText {
    /// 收起态刘海下沿的胶囊：「● AI 助手」，圆点是画的，不在字里。
    public static var entryTitle: String { tr("AI 助手") }

    /// 生成中刘海下沿那一条（和对话里还没出字时那一句）：「DeepSeek 正在思考」。
    public static func thinking(_ service: String?) -> String {
        let name = (service ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? tr("AI 正在思考") : tr("\(name) 正在思考")
    }

    /// 刘海对话底部输入框的占位：还没开始时问要做什么，有对话了就是继续追问。
    public static func inputPlaceholder(hasMessages: Bool) -> String {
        hasMessages ? tr("继续追问……") : tr("想让 AI 帮你做什么？")
    }

    /// 一条回答下面放哪些按钮。只有 API 对话有回答；还在流的不放；空的不放复制；
    /// 继续追问和重新生成只给最后一条，而且这个服务没在生成时才有（继续追问还要有字）。
    public static func answerActions(mode: AIOpenMode, isLast: Bool, generating: Bool,
                                     streaming: Bool, hasText: Bool) -> [AIAnswerAction] {
        guard mode == .api, !streaming else { return [] }
        var actions: [AIAnswerAction] = []
        if hasText { actions.append(.copy) }
        if isLast, !generating {
            if hasText { actions.append(.followUp) }
            actions.append(.regenerate)
        }
        return actions
    }
}

// MARK: - AI 助手：小组件底栏

/// 小组件底栏左边的服务分段按钮：露出卡片上启用的前几个（默认三个），其余收进「…」。
/// 底栏放不下时（服务名长、面板窄）少露一个，见 `fallbackLimits`。
public enum AIServiceSegments {
    public static let maxShown = 3

    /// 放不下时依次试的个数：3、2、1。
    public static let fallbackLimits = [3, 2, 1]

    /// 露出哪几个、哪几个进「…」，都按卡片上的顺序。
    public static func split<ID: Equatable>(_ ids: [ID], limit: Int = maxShown) -> (shown: [ID], overflow: [ID]) {
        let count = max(0, min(limit, ids.count))
        return (Array(ids.prefix(count)), Array(ids.dropFirst(count)))
    }

    /// 选中的服务收在「…」里：「…」按钮画成选中，悬停写出它的名字。
    public static func overflowSelected<ID: Equatable>(_ selected: ID?, overflow: [ID]) -> Bool {
        guard let selected else { return false }
        return overflow.contains(selected)
    }
}

/// 一个服务能用哪几种打开方式：小组件底栏的模式胶囊和对话卡片顶上的分段控件共用。
public struct AIModeOption: Equatable, Sendable {
    public var mode: AIOpenMode
    /// 能不能选。API 要先在设置里填密钥和接口；网页要有网址；App 总能选。
    public var available: Bool

    public init(mode: AIOpenMode, available: Bool) {
        self.mode = mode
        self.available = available
    }
}

public enum AIModeChoice {
    /// 分段控件的顺序：API、网页、App（同效果图）。
    public static let order: [AIOpenMode] = [.api, .web, .jump]

    public static func options(hasAPI: Bool, hasWeb: Bool) -> [AIModeOption] {
        order.map { mode in
            switch mode {
            case .api: AIModeOption(mode: mode, available: hasAPI)
            case .web: AIModeOption(mode: mode, available: hasWeb)
            case .jump: AIModeOption(mode: mode, available: true)
            }
        }
    }

    /// 模式胶囊点一下换到下一种能用的（跳过不能用的，转一圈回来）；只有一种能用时不变。
    public static func next(after current: AIOpenMode, hasAPI: Bool, hasWeb: Bool) -> AIOpenMode {
        let usable = options(hasAPI: hasAPI, hasWeb: hasWeb).filter(\.available).map(\.mode)
        guard let index = usable.firstIndex(of: current) else { return usable.first ?? current }
        return usable[(index + 1) % usable.count]
    }

    /// 模式胶囊上的字：「API 模式」「网页模式」「App 模式」。
    public static func capsuleTitle(_ mode: AIOpenMode) -> String {
        switch mode {
        case .api: tr("API 模式")
        case .web: tr("网页模式")
        case .jump: tr("App 模式")
        }
    }

    /// 不能选时悬停说明为什么。
    public static func unavailableReason(_ mode: AIOpenMode) -> String? {
        switch mode {
        case .api: tr("先在设置 ▸ AI 里填好这个服务的 API 密钥")
        case .web: tr("这个服务没有网页版")
        case .jump: nil
        }
    }
}
