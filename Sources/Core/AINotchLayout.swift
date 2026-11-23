import Foundation

// MARK: - 刘海入口：放在哪

/// 一块屏幕，按刘海入口需要的样子描述。AppKit 屏幕坐标：y 向上，顶边是 `maxY`。
public struct AINotchScreen: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    /// 刘海的范围；没有刘海的屏幕为 nil。见 `AINotchLayout.notchRect`。
    public var notch: CGRect?
    /// 菜单栏的高度（`frame.maxY - visibleFrame.maxY`，菜单栏自动隐藏时可能是 0）。
    public var menuBarHeight: CGFloat
    /// 带菜单栏的主屏。
    public var isMain: Bool

    public init(id: UInt32, frame: CGRect, notch: CGRect?, menuBarHeight: CGFloat, isMain: Bool) {
        self.id = id
        self.frame = frame
        self.notch = notch
        self.menuBarHeight = menuBarHeight
        self.isMain = isMain
    }
}

/// 入口长什么样。
public enum AINotchEntry: Equatable, Sendable {
    /// 刘海本身：窗口正好盖住刘海那一段，不向两侧多出一点，不占菜单栏的
    /// 水平空间。点一下展开对话；提示从刘海下沿往下长出一条（见 `strip`）。
    case notch(frame: CGRect, strip: CGRect)
    /// 没有刘海的屏幕：菜单栏下沿正下方的小胶囊，不在菜单栏里。
    case capsule(frame: CGRect)

    public var frame: CGRect {
        switch self {
        case .notch(let frame, _): frame
        case .capsule(let frame): frame
        }
    }
}

/// 刘海下沿那一条里显示什么。
public enum AINotchStripContent: Equatable, Sendable {
    /// 指针在刘海上：收起态胶囊「● AI 助手」。
    case hint
    /// 回答生成中：「DeepSeek 正在思考」加三个小点（减弱动态效果时不跳）。
    case thinking
}

public enum AINotchLayout {
    /// 刘海下沿往下长出的那一块胶囊（收起态「● AI 助手」、生成中「ChatGPT 正在思考」）
    /// 的高度：上面 `stripTextRow` 放一行 13pt 的字，下面吉祥物从下沿探出头来。
    public static let stripHeight: CGFloat = 38
    /// 胶囊里放字的那一行。
    public static let stripTextRow: CGFloat = 22
    /// 胶囊里探头的吉祥物（整张图的边长；下沿把它裁掉一截，只露头和耳朵）。
    public static let stripPandaSize: CGFloat = 24
    /// 胶囊字左右的留白。
    public static let stripPadding: CGFloat = 12
    /// 收起态字前面那颗小圆点和它后面的间距。
    public static let stripDot: CGFloat = 6
    public static let stripDotGap: CGFloat = 6
    /// 「正在思考」后面三个小点（3pt，间距 2.1）和它前面的间距。
    public static let stripDotsWidth: CGFloat = 3 * 3 + 2 * 2.1
    public static let stripDotsGap: CGFloat = 6
    /// 指针离开刘海后，那一块过多久收回。
    public static let stripLinger: TimeInterval = 0.3
    /// 外接屏胶囊的大小。
    public static let capsuleSize = CGSize(width: 44, height: 18)
    /// 外接屏胶囊离菜单栏下沿的距离。
    public static let capsuleGap: CGFloat = 2
    /// 外接屏胶囊平时的不透明度，指针移上去或回答生成中时完全显示。
    public static let capsuleRestingOpacity: Double = 0.4
    /// 菜单栏自动隐藏（量出来是 0）时按这个高度避开它。
    public static let fallbackMenuBarHeight: CGFloat = 24
    /// 展开的对话卡片：放在菜单栏下面，不往两侧盖菜单栏图标，宽度不过宽。
    public static let panelSize = CGSize(width: 400, height: 520)
    /// 对话卡片离菜单栏下沿多远（和刘海小岛的展开卡片一样，见 `NotchIslandLayout.cardGap`）。
    public static let cardGap: CGFloat = NotchIslandLayout.cardGap
    /// 面板离屏幕边缘至少留的距离。
    public static let margin: CGFloat = 8

    /// 刘海的范围：左右两块“刘海旁边的可用区域”（`auxiliaryTopLeftArea`、
    /// `auxiliaryTopRightArea`）中间那一段，高度是顶部的安全区。缺一样就当
    /// 没有刘海。
    public static func notchRect(screen: CGRect, topInset: CGFloat,
                                 leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
        guard topInset > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
        return CGRect(x: leftArea.maxX, y: screen.maxY - topInset,
                      width: rightArea.minX - leftArea.maxX, height: topInset)
    }

    /// 菜单栏这一条（量不到高度时按刘海高度，再不行按默认高度）。
    public static func menuBar(of screen: AINotchScreen) -> CGRect {
        var height = screen.menuBarHeight
        if height <= 0 { height = screen.notch?.height ?? fallbackMenuBarHeight }
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                      width: screen.frame.width, height: height)
    }

    /// 哪几块屏幕要放入口。“只在主屏显示”时只留主屏；找不到主屏时用第一块。
    public static func screens(_ all: [AINotchScreen], mainOnly: Bool) -> [AINotchScreen] {
        guard mainOnly else { return all }
        if let main = all.first(where: \.isMain) { return [main] }
        return Array(all.prefix(1))
    }

    /// 入口要不要画：总开关开着，并且灵动提示没有在显示（灵动提示出现时
    /// AI 入口让位，收起后恢复）。
    public static func isVisible(enabled: Bool, islandShowing: Bool) -> Bool {
        enabled && !islandShowing
    }

    /// 一块屏幕上的入口，没有入口时为 nil。
    ///
    /// 有刘海：入口就是刘海那一段（左右正好到两块可用区域的边上，高度是菜单
    /// 栏高度），下沿条在菜单栏下方。拾掇在运行时刘海让给拾掇，这块屏幕上
    /// 不放入口（改用快捷键和货架上的小熊猫）。没有刘海：菜单栏下沿正下方
    /// 正中的小胶囊。
    public static func entry(for screen: AINotchScreen, shiduoRunning: Bool) -> AINotchEntry? {
        let bar = menuBar(of: screen)
        if let notch = screen.notch {
            if shiduoRunning { return nil }
            let frame = CGRect(x: notch.minX, y: bar.minY, width: notch.width, height: bar.height)
            return .notch(frame: frame, strip: stripWindow(notch: notch, menuBar: bar))
        }
        let size = capsuleSize
        return .capsule(frame: CGRect(x: screen.frame.midX - size.width / 2,
                                      y: bar.minY - capsuleGap - size.height,
                                      width: size.width, height: size.height))
    }

    /// 面板从哪里长出来。有入口时就是入口；拾掇占着刘海时没有入口，快捷键
    /// 和货架打开的面板仍然接在刘海下面（只是打开，不在刘海上放常驻窗口）。
    public static func anchor(for screen: AINotchScreen, shiduoRunning: Bool) -> CGRect {
        if let entry = entry(for: screen, shiduoRunning: shiduoRunning) { return entry.frame }
        let bar = menuBar(of: screen)
        if let notch = screen.notch {
            return CGRect(x: notch.minX, y: bar.minY, width: notch.width, height: bar.height)
        }
        return CGRect(x: screen.frame.midX, y: bar.minY, width: 0, height: bar.height)
    }

    /// 刘海下沿那一条显示什么，nil 表示收起。回答生成中优先显示「正在思考」（不需要
    /// 悬停）；否则指针在刘海上时显示入口字样。入口隐藏（小岛、消息卡片占着刘海）或
    /// 面板开着时不显示。
    public static func stripContent(visible: Bool, panelOpen: Bool,
                                    hovering: Bool, generating: Bool) -> AINotchStripContent? {
        guard visible, !panelOpen else { return nil }
        if generating { return .thinking }
        return hovering ? .hint : nil
    }

    // MARK: 刘海下沿的胶囊有多宽
    //
    // 和刘海小岛同一套规则（`NotchIslandLayout`）：字一律 13pt、按同样的字宽估算，内容放得进
    // 刘海宽度时胶囊就和刘海一样宽；放不下才往两侧各加一点，每侧不超过 `NotchIslandLayout.maxWing`
    // （70pt），字再长就截断。胶囊整个在菜单栏下面，所以无论多宽都不盖住菜单栏右边的图标。

    /// 胶囊里的内容（不含左右留白）多宽。
    public static func stripContentWidth(_ content: AINotchStripContent, service: String?) -> CGFloat {
        switch content {
        case .hint:
            return stripDot + stripDotGap + NotchIslandLayout.textWidth(AINotchChatText.entryTitle)
        case .thinking:
            return NotchIslandLayout.textWidth(AINotchChatText.thinking(service)) + stripDotsGap + stripDotsWidth
        }
    }

    /// 内容比刘海宽时每侧多出来多少：向上取整，最多 `NotchIslandLayout.maxWing`。
    public static func stripSideExtra(contentWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let needed = contentWidth + stripPadding * 2
        guard needed > notchWidth else { return 0 }
        return min(NotchIslandLayout.maxWing, ceil((needed - notchWidth) / 2))
    }

    /// 胶囊的宽度：刘海宽度加两侧多出来的。
    public static func stripWidth(_ content: AINotchStripContent, service: String?, notchWidth: CGFloat) -> CGFloat {
        notchWidth + 2 * stripSideExtra(contentWidth: stripContentWidth(content, service: service),
                                        notchWidth: notchWidth)
    }

    /// 放胶囊的窗口：顶边贴菜单栏下沿，以刘海中线对称，宽度按最宽的胶囊（每侧加满
    /// `maxWing`）留好，胶囊在窗口里居中按内容伸缩。窗口透明、不接鼠标。
    public static func stripWindow(notch: CGRect, menuBar: CGRect) -> CGRect {
        let wing = NotchIslandLayout.maxWing
        return CGRect(x: notch.minX - wing, y: menuBar.minY - stripHeight,
                      width: notch.width + wing * 2, height: stripHeight)
    }

    /// 外接屏胶囊的不透明度。
    public static func capsuleOpacity(hovering: Bool, generating: Bool) -> Double {
        hovering || generating ? 1 : capsuleRestingOpacity
    }

    /// 入口是不是刘海（刘海那一段有宽度、高度是菜单栏高度，至少 22）；外接屏胶囊只有
    /// 18 高，没有入口时按屏幕中点算的位置宽度是 0。
    public static func hangsFromNotch(_ anchor: CGRect) -> Bool {
        anchor.width > 0 && anchor.height >= 22
    }

    /// 接在刘海下面的卡片（输入法提示、消息卡片）顶上那条黑色过渡的高度：从卡片顶边
    /// （刘海下沿）往下，由刘海的纯黑渐隐到玻璃。AI 对话卡片放在菜单栏下面，不用它。
    public static let notchBlendHeight: CGFloat = 12

    /// 刘海下卡片顶上那条黑色过渡的位置，卡片自己的坐标（原点在左上，y 向下）：
    /// 和刘海同宽、正对刘海，卡片被屏幕边推开时跟着刘海走，超出卡片的部分裁掉。
    /// 不挂在刘海下面（外接屏胶囊、没有刘海）时为 nil。
    public static func notchBlend(entry: CGRect, panel: CGRect) -> CGRect? {
        guard hangsFromNotch(entry) else { return nil }
        let minX = max(entry.minX - panel.minX, 0)
        let maxX = min(entry.maxX - panel.minX, panel.width)
        guard maxX > minX else { return nil }
        return CGRect(x: minX, y: 0, width: maxX - minX, height: notchBlendHeight)
    }

    /// 面板和小岛之间留的空。
    public static let blockerGap: CGFloat = 6

    /// 两块是不是真的叠在一起（只碰到边不算）。
    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let common = a.intersection(b)
        return !common.isNull && common.width > 1 && common.height > 1
    }

    /// 面板最后放在哪：先照常放在入口下面；和正在显示的刘海小岛（专注计时、
    /// 下载）或灵动提示重叠时，不盖住它们，整块往下挪到它们下沿下面（`clearedBlockers`）。
    public static func placement(below entry: CGRect, screen: CGRect, size: CGSize = panelSize,
                                 avoiding blockers: [CGRect]) -> (frame: CGRect, clearedBlockers: Bool) {
        let base = panelFrame(below: entry, screen: screen, size: size)
        let hits = blockers.filter { overlaps($0, base) }
        guard let lowest = hits.map(\.minY).min() else { return (base, false) }
        return (fitted(base, top: lowest - blockerGap, screen: screen), true)
    }

    /// 让开遮挡后面板最矮多高：再矮输入条和一两条消息就放不下了。
    public static let minPanelHeight: CGFloat = 300

    /// 面板顶边放在 `top`，往下摆；下面空间不够原高时先缩短面板（消息列表在面板里滚动），
    /// 最矮到 `minPanelHeight`，不再一味往下挪到底边再被夹回来压住小岛。小屏、放大显示或
    /// 刘海上同时有几个活动时会走到这里。连最矮都放不下（极端缩放）才贴底边。
    static func fitted(_ frame: CGRect, top: CGFloat, screen: CGRect) -> CGRect {
        let floor = screen.minY + margin
        let room = top - floor
        var out = frame
        out.size.height = min(frame.height, max(minPanelHeight, room))
        out.origin.y = max(top - out.height, floor)
        return out
    }

    /// 面板已经开着、刘海上后来才出现或变高的东西压到它（典型是面板打开以后才出现的倒计时小岛，
    /// 下面那条约 26 点高的剩余时间会伸进面板顶上一截）：面板往下挪到它下沿下面，留 `blockerGap`，
    /// 底边不出屏幕（`margin`），空间不够时缩短面板（`fitted`）。只往下挪、不往上回：小岛闪一下收起又出现时面板不跟着上下跳，
    /// 收起再打开时按当时的情况重新摆（`placement`）。不用挪时 nil。
    public static func avoidance(current: CGRect, screen: CGRect, avoiding blockers: [CGRect]) -> CGRect? {
        let hits = blockers.filter { overlaps($0, current) }
        guard let lowest = hits.map(\.minY).min() else { return nil }
        let frame = fitted(current, top: lowest - blockerGap, screen: screen)
        return frame.maxY < current.maxY ? frame : nil
    }

    /// 展开的对话卡片：在入口正下方，水平对着入口中间，超出屏幕时往里收。刘海入口时
    /// 卡片整个在菜单栏下面、空出 `cardGap`（和专注卡片一样），不接在刘海上；外接屏
    /// 胶囊下面空 4。
    public static func panelFrame(below entry: CGRect, screen: CGRect, size: CGSize = panelSize) -> CGRect {
        var x = entry.midX - size.width / 2
        x = min(max(x, screen.minX + margin), screen.maxX - size.width - margin)
        var top = entry.minY
        if hangsFromNotch(entry) {
            top -= cardGap
        } else if entry.height < 22 {
            top -= 4
        }
        var y = top - size.height
        y = max(y, screen.minY + margin)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - 避让拾掇

/// 拾掇（另一个 App）的悬浮暂存架在指针碰到刘海、或者拖文件到刘海时弹出。
/// 拾掇在运行时码头不在刘海上放任何入口窗口，刘海的点击和悬停都让给拾掇。
public enum AIShiduo {
    /// 拾掇的 bundle id（它的 project.yml 里的 PRODUCT_BUNDLE_IDENTIFIER）。
    public static let bundleID = "io.github.hanson-zz.shiduo"

    public static func isRunning(_ bundleIDs: [String?]) -> Bool {
        bundleIDs.contains { $0?.lowercased() == bundleID }
    }

    public static let explanation =
        tr("检测到「拾掇」正在运行：拾掇的悬浮暂存架在指针碰到刘海或把文件拖到刘海时弹出，为了不和它抢，码头不在刘海上放任何 AI 入口，刘海的点击和悬停都让给拾掇。这时请用快捷键或货架上 AI 卡片的小熊猫展开对话。")
}

// MARK: - 展开的对话卡片

/// 对话卡片顶上那一行：小熊猫 + 「AI 助手」（下面一行小字是当前服务，点开换服务）+
/// API / 网页 / App 分段控件。分段控件每一段能不能点见 `AIModeChoice.options`。
public enum AINotchPanelHeader {
    /// 刷新、在浏览器打开只有网页模式有。
    public static func showsWebControls(_ mode: AIOpenMode) -> Bool { mode == .web }

    /// 服务名下面那一行要不要能点（几个服务时才有得换）。
    public static func canSwitchService(serviceCount: Int) -> Bool { serviceCount > 1 }
}
