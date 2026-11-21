import Foundation

// MARK: - AI 助手：小组件面板的快捷操作

/// 小组件提问面板输入框下面那一排快捷操作胶囊。用户在面板的「助手设置」里
/// 勾选显示哪几个，存在 `AINotchSettings.panelChips`（没存过时用默认四个）。
public enum AIDockChip: String, CaseIterable, Sendable {
    case screenshot, clipboard, translate, summarize, polish, explain

    public var title: String {
        switch self {
        case .screenshot: tr("截图提问")
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
        case .clipboard: "doc.on.clipboard"
        case .translate: AIQuickAction.translate.symbol
        case .summarize: AIQuickAction.summarize.symbol
        case .polish: AIQuickAction.polish.symbol
        case .explain: AIQuickAction.explain.symbol
        }
    }

    /// 套提示词的那几个对应的快捷指令；截图和剪贴板不套提示词，为 nil。
    public var quickAction: AIQuickAction? {
        switch self {
        case .screenshot, .clipboard: nil
        case .translate: .translate
        case .summarize: .summarize
        case .polish: .polish
        case .explain: .explain
        }
    }
}

public enum AIDockChips {
    /// 没设置过时显示的四个：截图提问、处理剪贴板、翻译、总结。
    public static let defaults: [AIDockChip] = [.screenshot, .clipboard, .translate, .summarize]
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

    /// 小组件底部服务名旁边那一小句：这个服务按提交会发生什么。
    public static func modeAction(_ mode: AIOpenMode, appInstalled: Bool, supportsAsk: Bool) -> String {
        switch mode {
        case .api: return tr("在刘海里直接回答")
        case .web: return tr("复制后在刘海网页里粘贴")
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
    case regenerate
}

public enum AINotchChatText {
    /// 收起时刘海下沿那一条：低干扰的入口字样。
    public static var entryTitle: String { tr("✦ AI 助手") }

    /// 生成中刘海下沿那一条（和对话里还没出字时那一句）：「DeepSeek 正在思考」。
    public static func thinking(_ service: String?) -> String {
        let name = (service ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? tr("AI 正在思考") : tr("\(name) 正在思考")
    }

    /// 刘海对话底部输入框的占位：还没开始时问要做什么，有对话了就是继续追问。
    public static func inputPlaceholder(hasMessages: Bool) -> String {
        hasMessages ? tr("继续追问……") : tr("想让 AI 帮你做什么？")
    }

    /// 一条回答下面放哪些按钮。只有 API 对话有回答；还在流的、空的不放复制；
    /// 重新生成只给最后一条，而且这个服务没在生成时才有。
    public static func answerActions(mode: AIOpenMode, isLast: Bool, generating: Bool,
                                     streaming: Bool, hasText: Bool) -> [AIAnswerAction] {
        guard mode == .api, !streaming else { return [] }
        var actions: [AIAnswerAction] = []
        if hasText { actions.append(.copy) }
        if isLast, !generating { actions.append(.regenerate) }
        return actions
    }
}
