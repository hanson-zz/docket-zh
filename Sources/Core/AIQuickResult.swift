import Foundation

// MARK: - AI 助手：Dock 提问后刘海里的快捷结果卡片
//
// 小组件面板里用 API 提问后，面板收起，刘海下方自动长出一张约 420 宽的结果卡片：先是
// 「ChatGPT 正在思考」，流式回答一边来一边显示，答完给「复制回答」「继续追问」「展开」。
// 这里是不碰界面的那部分：设置项、卡片多高、什么时候自动收起、要不要弹、弹在哪。

/// 设置 ▸ AI「回答显示位置」。
public enum AIAnswerPlacement: String, Codable, CaseIterable, Sendable {
    /// 刘海优先（推荐）：刘海下方弹快捷结果卡片，刘海被占着时用备用浮窗。
    case notch
    /// 小组件面板：保持原来的做法，交给刘海里完整的对话面板。
    case panel

    public var title: String {
        switch self {
        case .notch: tr("刘海优先（推荐）")
        case .panel: tr("小组件面板")
        }
    }

    /// 小组件底栏「回答位置：刘海」里冒号后面那个短词。
    public var shortTitle: String {
        switch self {
        case .notch: tr("刘海")
        case .panel: tr("小组件面板")
        }
    }
}

/// 设置 ▸ AI「回答完成后」。
public enum AIAutoCollapse: String, Codable, CaseIterable, Sendable {
    /// 保持显示、手动收起（推荐）。
    case manual
    case after15
    case after30

    public var title: String {
        switch self {
        case .manual: tr("保持显示、手动收起（推荐）")
        case .after15: tr("15 秒后自动收起")
        case .after30: tr("30 秒后自动收起")
        }
    }

    /// 答完后多少秒收起；手动收起时 nil。
    public var seconds: TimeInterval? {
        switch self {
        case .manual: nil
        case .after15: 15
        case .after30: 30
        }
    }
}

/// 卡片头部的状态胶囊。
public enum AIQuickResultPhase: Equatable, Sendable {
    /// 还没出第一个字。
    case thinking
    /// 正在流。
    case answering
    /// 答完（包括用户停止后留下的字）。
    case done
    /// 出错，附一句原因。
    case failed(String)

    public var title: String {
        switch self {
        case .thinking: tr("正在思考")
        case .answering: tr("正在回答")
        case .done: tr("已完成")
        case .failed: tr("失败")
        }
    }

    public var isFinished: Bool {
        switch self {
        case .done, .failed: true
        case .thinking, .answering: false
        }
    }
}

/// 交给 API 之后结果放在哪。
public enum AIQuickResultTarget: Equatable, Sendable {
    /// 刘海下方的快捷结果卡片（小熊猫从刘海探头）。
    case notchCard
    /// 备用浮窗：同样的卡片，不带探头。刘海被专注计时、小岛、消息卡片或拾掇占着时用。
    case floating
    /// 原来的做法：打开刘海里完整的对话面板（「回答显示位置」选了小组件面板）。
    case fullPanel
    /// 不自动弹：只在刘海下沿显示「正在思考」，点刘海看回答（「提交问题后自动展开结果」关着）。
    case quiet
    /// 不走快捷卡片：网页、App 方式（码头拿不到回答），或者没解锁码头 Pro（走原来的回退）。
    case none
}

public enum AIQuickResult {
    /// 卡片宽度。
    public static let width: CGFloat = 420
    /// 卡片高度随内容在这两个数之间，再长就在卡片里滚动。
    public static let minHeight: CGFloat = 180
    public static let maxHeight: CGFloat = 300
    /// 头部（服务名、状态、按钮）连分隔线的高度。
    public static let headerHeight: CGFloat = 56
    /// 底部一排按钮连上下留白的高度。
    public static let footerHeight: CGFloat = 56
    /// 正文区和头部之间的距离（分隔线和留白；正文自己的上下内边距算在量出来的高度里）。
    public static let bodyChrome: CGFloat = 12
    /// 贴在刘海下时，小熊猫趴在卡片上沿，头部往下让这么多。
    public static let mascotInset: CGFloat = 10
    /// 刘海里探出来的小熊猫图的高度。
    public static let mascotHeight: CGFloat = 40
    /// 卡片和屏幕边、菜单栏之间留的距离（同刘海对话面板）。
    public static let margin: CGFloat = AINotchLayout.margin

    /// 卡片高度：头、尾、正文（量出来的字高）加起来，夹在 180 到 300 之间。
    public static func cardHeight(bodyHeight: CGFloat, withMascot: Bool = false) -> CGFloat {
        let body = bodyHeight.isFinite ? max(0, bodyHeight) : 0
        let chrome = headerHeight + footerHeight + bodyChrome + (withMascot ? mascotInset : 0)
        return min(maxHeight, max(minHeight, ceil(chrome + body)))
    }

    /// 正文区能占的最大高度（超过就在里面滚动）。
    public static func bodyLimit(withMascot: Bool = false) -> CGFloat {
        maxHeight - headerHeight - footerHeight - bodyChrome - (withMascot ? mascotInset : 0)
    }

    /// 要不要弹卡片、弹在哪。
    ///
    /// - mode: 这个服务这次实际用的打开方式。只有 API 码头自己拿得到回答；网页、App 方式
    ///   照旧跳转，不弹卡片，不假装已经拿到回答。
    /// - unlocked: 码头 Pro（刘海对话）解锁没有。没解锁时走原来的回退（付费墙），不弹。
    /// - notchOccupied: 刘海这会儿被专注计时、刘海小岛（通知、下载等）、消息卡片占着，
    ///   或者拾掇在运行（刘海让给拾掇）。这时用备用浮窗，不盖住它们。
    public static func target(mode: AIOpenMode, unlocked: Bool, placement: AIAnswerPlacement,
                              autoShow: Bool, notchOccupied: Bool) -> AIQuickResultTarget {
        guard mode == .api, unlocked else { return .none }
        if placement == .panel { return .fullPanel }
        if !autoShow { return .quiet }
        return notchOccupied ? .floating : .notchCard
    }

    /// 卡片显示着时，刘海占用变了之后它该待在哪：刘海卡片和备用浮窗之间来回换，结果不丢。
    public static func relocated(_ current: AIQuickResultTarget, notchOccupied: Bool) -> AIQuickResultTarget {
        switch current {
        case .notchCard, .floating: notchOccupied ? .floating : .notchCard
        default: current
        }
    }

    /// 一条回答在卡片上算哪个阶段。没有回答（还没开始）时算正在思考。
    public static func phase(status: AIChatMessage.Status?, text: String) -> AIQuickResultPhase {
        switch status {
        case nil: return .thinking
        case .streaming?: return text.isEmpty ? .thinking : .answering
        case .done?: return .done
        case .stopped?: return text.isEmpty ? .failed(tr("已停止生成")) : .done
        case .failed(let reason)?: return .failed(reason)
        }
    }

    /// 答完多少秒后自动收起；不该倒计时（手动收起、固定了、指针在卡片上、还没答完、失败）时 nil。
    /// 失败不自动收：错误那一句和「重试」要留给用户看。
    public static func collapseDelay(_ setting: AIAutoCollapse, phase: AIQuickResultPhase,
                                     pinned: Bool, hovering: Bool) -> TimeInterval? {
        guard phase == .done, !pinned, !hovering else { return nil }
        return setting.seconds
    }

    /// 点卡片外面要不要收起：固定了不收；还在思考、回答时也不收（刚交过来，下一下点击多半
    /// 是在别处干活，回答照样在后台答完，收了就看不到过程）。
    public static func closesOnOutsideClick(phase: AIQuickResultPhase, pinned: Bool) -> Bool {
        !pinned && phase.isFinished
    }

    /// 回答拆成「标题」和正文：第一行是 Markdown 标题（`# ...`）、整行加粗（`**...**`），
    /// 或者是一行不带句末标点的短句、后面还有正文时，第一行当标题加粗显示。
    public static func splitTitle(_ text: String) -> (title: String?, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newline = trimmed.firstIndex(of: "\n") else { return (nil, text) }
        let first = trimmed[..<newline].trimmingCharacters(in: .whitespaces)
        let rest = trimmed[trimmed.index(after: newline)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty, !first.isEmpty else { return (nil, text) }
        if first.hasPrefix("#") {
            let title = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? (nil, text) : (title, rest)
        }
        if first.count > 4, first.hasPrefix("**"), first.hasSuffix("**") {
            let title = String(first.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            return title.isEmpty || title.contains("**") ? (nil, text) : (title, rest)
        }
        let enders: Set<Character> = ["。", "，", ",", ".", "！", "!", "？", "?", "；", ";", "：", ":", "、", "）", ")"]
        if first.count <= maxTitleLength, let last = first.last, !enders.contains(last),
           !first.hasPrefix("-"), !first.hasPrefix("*"), !first.hasPrefix("`"), !first.hasPrefix(">") {
            return (first, rest)
        }
        return (nil, text)
    }

    /// 不带标点的第一行最多多少字才当标题。
    public static let maxTitleLength = 24

    // MARK: 放在哪

    /// 贴在刘海下的卡片：顶边在菜单栏下沿下面 `AINotchLayout.cardGap`，水平对着入口中间，
    /// 不往上盖菜单栏的图标；刘海小岛、灵动提示显示着时整块挪到它们下面（同对话面板）。
    public static func notchFrame(below entry: CGRect, screen: CGRect, height: CGFloat,
                                  avoiding blockers: [CGRect]) -> CGRect {
        AINotchLayout.placement(below: entry, screen: screen, size: CGSize(width: width, height: height),
                                avoiding: blockers).frame
    }

    /// 备用浮窗：刘海那边有小岛（专注计时、通知、下载）挡着时放在它们下面（同对话面板的
    /// 避让）；没有可避让的（拾掇占着刘海、消息卡片展开着、插电动画在播）时放在屏幕右上角、
    /// 菜单栏下方。
    ///
    /// `animation` 是插电霓虹动画占着的那一块（刘海往下到霓虹数字，见 `BatteryNeon.Plug.window`）：
    /// 它很高，放到它下面卡片就掉到屏幕中间，所以先放右上角；屏幕太窄、右上角也压到它时
    /// 才整块挪到它下面。
    public static func floatingFrame(screen: CGRect, menuBar: CGRect, entry: CGRect, height: CGFloat,
                                     blockers: [CGRect], animation: CGRect? = nil) -> CGRect {
        let size = CGSize(width: width, height: height)
        let onScreen = blockers.filter { $0.intersects(screen) }
        let playing = animation.flatMap { $0.intersects(screen) ? $0 : nil }
        if !onScreen.isEmpty {
            let placed = AINotchLayout.placement(below: entry, screen: screen, size: size, avoiding: onScreen)
            if placed.clearedBlockers, !(playing.map { AINotchLayout.overlaps($0, placed.frame) } ?? false) {
                return placed.frame
            }
        }
        let x = screen.maxX - margin - size.width
        let y = max(menuBar.minY - AINotchLayout.cardGap - size.height, screen.minY + margin)
        let corner = CGRect(x: max(x, screen.minX + margin), y: y, width: size.width, height: size.height)
        guard let playing, AINotchLayout.overlaps(playing, corner) else { return corner }
        return AINotchLayout.placement(below: entry, screen: screen, size: size,
                                       avoiding: onScreen + [playing]).frame
    }

    /// 卡片窗口：贴在刘海下时往上多留一截给探头的小熊猫（那一截透明，点击穿过去）。
    public static func windowFrame(card: CGRect, withMascot: Bool) -> CGRect {
        guard withMascot else { return card }
        let extra = AINotchLayout.cardGap
        return CGRect(x: card.minX, y: card.minY, width: card.width, height: card.height + extra)
    }
}

// MARK: - 小组件面板：字数

public enum AIAskLimit {
    /// 一次最多交多少字。超过时不截断（截断会打断输入法选字），主按钮和 Enter 都不提交。
    public static let maxLength = 2000

    public static func count(_ text: String) -> Int { text.count }

    public static func withinLimit(_ text: String) -> Bool { count(text) <= maxLength }

    /// 输入框右下角「24 / 2000」。
    public static func label(_ text: String) -> String { "\(count(text)) / \(maxLength)" }

    /// 超过上限时面板上的一句。
    public static var overLimitHint: String { tr("最多 2000 字，删掉一些再提交。") }
}
