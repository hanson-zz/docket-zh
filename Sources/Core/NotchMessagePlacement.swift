import Foundation

// MARK: - 消息卡放在哪：自动让位
//
// 用户同时在用的「拾掇」也占刘海（悬浮暂存架、提醒、专注计时的刘海指示），市面上
// 还有 NotchNook、boring.notch 这类刘海 App。码头用 CGWindowListCopyWindowInfo 只读
// 窗口的主人名字、进程号、层级、透明度和位置（不读窗口标题、不截图，所以不要屏幕
// 录制权限），找出刘海附近属于这些 App 的窗口，再决定消息卡放哪。这里只有判断，
// 读窗口在 Services。
//
// AppKit 屏幕坐标：y 向上，屏幕顶边是 `maxY`。CGWindowList 给的是左上角原点的
// 全局坐标，先用 `NotchWindowGeometry.appKit` 换过来。

/// 屏幕上别人的一个窗口，只有不要权限就能读的那几项。
public struct NotchForeignWindow: Equatable, Sendable {
    /// 窗口主人的名字（kCGWindowOwnerName，一般是 App 的显示名或进程名）。
    public var ownerName: String
    /// 主人的 bundle id（按进程号查到的，查不到为 nil）。
    public var bundleID: String?
    public var ownerPID: Int32
    /// AppKit 坐标。
    public var frame: CGRect
    /// 窗口层级（kCGWindowLayer），普通窗口是 0。
    public var layer: Int
    /// kCGWindowAlpha。
    public var alpha: Double

    public init(ownerName: String, bundleID: String? = nil, ownerPID: Int32 = 0, frame: CGRect,
                layer: Int = 0, alpha: Double = 1) {
        self.ownerName = ownerName
        self.bundleID = bundleID
        self.ownerPID = ownerPID
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
    }
}

public enum NotchWindowGeometry {
    /// CGWindowList 的边框（左上角原点，y 向下）换成 AppKit 坐标。`primaryHeight` 是
    /// 主屏（带菜单栏、原点所在的那块）的高度。
    public static func appKit(_ cgRect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cgRect.minX, y: primaryHeight - cgRect.minY - cgRect.height,
               width: cgRect.width, height: cgRect.height)
    }
}

// MARK: - 认刘海 App

/// 一个会占刘海的 App。按 bundle id 或窗口主人名字认，任一对上就算。
public struct NotchNeighborApp: Equatable, Sendable {
    public var name: String
    public var bundleIDs: [String]
    /// 窗口主人名字（小写比较）：中文显示名、英文显示名、进程名。
    public var ownerNames: [String]

    public init(name: String, bundleIDs: [String], ownerNames: [String]) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.ownerNames = ownerNames
    }

    public func matches(ownerName: String, bundleID: String?) -> Bool {
        if let bundleID, bundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            return true
        }
        let owner = ownerName.trimmingCharacters(in: .whitespaces).lowercased()
        return !owner.isEmpty && ownerNames.contains(owner)
    }
}

public enum NotchNeighbors {
    /// 拾掇：bundle id 来自它的 project.yml（PRODUCT_BUNDLE_IDENTIFIER，和
    /// `AIShiduo.bundleID` 是同一个），显示名中文「拾掇」、英文「Shiduo」，可执行文件
    /// 和 PRODUCT_NAME 是 Shiduo。窗口主人名字随系统语言是「拾掇」或「Shiduo」，三样都认。
    public static let shiduo = NotchNeighborApp(name: "拾掇", bundleIDs: [AIShiduo.bundleID],
                                                ownerNames: ["拾掇", "shiduo"])

    /// 常见的刘海 App。除拾掇外 bundle id 没有可靠来源，只按窗口主人名字认。
    public static let known: [NotchNeighborApp] = [
        shiduo,
        NotchNeighborApp(name: "NotchNook", bundleIDs: [], ownerNames: ["notchnook"]),
        NotchNeighborApp(name: "boring.notch", bundleIDs: [], ownerNames: ["boringnotch", "boring.notch"]),
        NotchNeighborApp(name: "Alcove", bundleIDs: [], ownerNames: ["alcove"]),
        NotchNeighborApp(name: "NotchDrop", bundleIDs: [], ownerNames: ["notchdrop"]),
        NotchNeighborApp(name: "MediaMate", bundleIDs: [], ownerNames: ["mediamate"]),
        NotchNeighborApp(name: "Dynamic Lake", bundleIDs: [], ownerNames: ["dynamic lake", "dynamiclake"]),
        NotchNeighborApp(name: "Atoll", bundleIDs: [], ownerNames: ["atoll"]),
    ]

    public static func app(ownerName: String, bundleID: String?) -> NotchNeighborApp? {
        known.first { $0.matches(ownerName: ownerName, bundleID: bundleID) }
    }
}

// MARK: - 放哪

public enum NotchMessagePlacement {
    /// 卡片宽度（效果图 452）。
    public static let cardWidth: CGFloat = 452
    /// 卡片列左右再放宽这么多，挨着卡片边的窗口也算在刘海附近。
    public static let columnSlack: CGFloat = 24
    /// 窗口伸到菜单栏下面超过这么深，就当是展开的面板（拾掇的暂存架约 200pt），
    /// 排队等它收起；浅一点的（提示条、专注指示）卡片落在它下面。
    public static let expandedDepth: CGFloat = 72
    /// 卡片落在别人窗口下面时空开的距离。
    public static let gap: CGFloat = 6
    /// 卡片、胶囊离屏幕左右边至少留的距离。
    public static let margin: CGFloat = 8

    /// 收起态刘海两侧的「耳朵」里一个 App 占的宽度（图标 18 + 间距 + 数字）。
    public static let earItemWidth: CGFloat = 44
    public static let earPadding: CGFloat = 10
    /// 刘海旁小胶囊里一个 App 占的宽度，和左右内边距。
    public static let capsuleItemWidth: CGFloat = 44
    public static let capsulePadding: CGFloat = 10
    public static let capsuleHeight: CGFloat = 24
    /// 胶囊离刘海（或挡着的窗口）的距离。
    public static let capsuleGap: CGFloat = 8

    // MARK: 刘海附近的别人的窗口

    /// 刘海附近、属于刘海 App 的窗口：看得见、有大小、从屏幕顶上挂下来（伸进菜单栏
    /// 那一条），横向压着卡片那一列。拾掇的悬浮暂存架不挂在顶上，不算。
    public static func neighbors(_ windows: [NotchForeignWindow], screen: AINotchScreen,
                                 width: CGFloat = cardWidth) -> [NotchForeignWindow] {
        let bar = AINotchLayout.menuBar(of: screen)
        let centre = screen.notch?.midX ?? screen.frame.midX
        let column = CGRect(x: centre - width / 2 - columnSlack, y: screen.frame.minY,
                            width: width + columnSlack * 2, height: screen.frame.height)
        return windows.filter { window in
            guard window.alpha > 0.05, window.frame.width >= 4, window.frame.height >= 4,
                  NotchNeighbors.app(ownerName: window.ownerName, bundleID: window.bundleID) != nil,
                  window.frame.intersects(screen.frame), window.frame.intersects(column) else { return false }
            return window.frame.maxY >= bar.minY + 2
        }
    }

    /// 卡片怎么出。
    public enum Card: Equatable, Sendable {
        /// 挂下来：顶边在 `top`。`fromNotch` 时正接在刘海下面（顶上画黑色过渡）。
        case hang(top: CGFloat, fromNotch: Bool)
        /// 刘海 App 的面板正展开，等它收起。
        case wait
        /// 改用刘海旁的小胶囊。
        case capsule
    }

    /// 卡片的出法。
    ///
    /// - 「刘海旁小胶囊」：一律胶囊。
    /// - 「刘海下方」：一律接在刘海下面，不管别人。
    /// - 「自动让位」：刘海附近有刘海 App 的窗口伸到菜单栏下面超过 `expandedDepth`
    ///   （面板正展开）时等，等满 `NotchMessagePriority.maxWait` 秒还没收起就改用胶囊；
    ///   只伸下来一点（提示条、指示）时落在它们下面；没有时接在刘海下面。拾掇在运行
    ///   但刘海附近没有它的窗口时，也接在刘海下面。
    public static func card(_ position: NotchMessagePosition, screen: AINotchScreen,
                            windows: [NotchForeignWindow], waited: TimeInterval) -> Card {
        let bar = AINotchLayout.menuBar(of: screen)
        let base = Card.hang(top: screen.notch == nil ? bar.minY - gap : bar.minY, fromNotch: screen.notch != nil)
        switch position {
        case .capsule: return .capsule
        case .belowNotch: return base
        case .auto: break
        }
        let near = neighbors(windows, screen: screen)
        guard !near.isEmpty else { return base }
        let deepest = near.map { bar.minY - $0.frame.minY }.max() ?? 0
        if deepest > expandedDepth {
            return waited < NotchMessagePriority.maxWait ? .wait : .capsule
        }
        if deepest > 0 {
            let lowest = near.map(\.frame.minY).min() ?? bar.minY
            return .hang(top: lowest - gap, fromNotch: false)
        }
        return base
    }

    /// 挂下来的卡片窗口：水平对着刘海（没有刘海对着屏幕中间），超出屏幕时往里收。
    public static func cardFrame(top: CGFloat, screen: AINotchScreen, size: CGSize) -> CGRect {
        let centre = screen.notch?.midX ?? screen.frame.midX
        var x = centre - size.width / 2
        x = min(max(x, screen.frame.minX + margin), screen.frame.maxX - size.width - margin)
        let y = max(screen.frame.minY + margin, top - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// 从胶囊点开的卡片：挂在胶囊下面、左边对着胶囊，有刘海时不压刘海中间。
    public static func cardFrame(belowCapsule capsule: CGRect, screen: AINotchScreen, size: CGSize) -> CGRect {
        let bar = AINotchLayout.menuBar(of: screen)
        var x = capsule.minX - 12
        if let notch = screen.notch { x = max(x, notch.maxX + 4) }
        x = min(max(x, screen.frame.minX + margin), screen.frame.maxX - size.width - margin)
        let top = min(capsule.minY, bar.minY) - gap
        let y = max(screen.frame.minY + margin, top - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: 收起态

    /// 收起态：刘海两侧的耳朵（左边第一个 App，右边其余的），或刘海旁小胶囊。
    public enum Indicator: Equatable, Sendable {
        case ears(left: CGRect, right: CGRect?)
        case capsule(CGRect)
    }

    public static func earWidth(items: Int) -> CGFloat {
        items <= 0 ? 0 : earPadding * 2 + CGFloat(items) * earItemWidth
    }

    public static func capsuleWidth(items: Int) -> CGFloat {
        capsulePadding * 2 + CGFloat(max(1, items)) * capsuleItemWidth
    }

    /// 收起态放哪。`apps` 是有未读的 App 个数。
    ///
    /// 有刘海、不是胶囊模式时是耳朵：贴着刘海左右两边、和菜单栏一样高，看起来像刘海
    /// 往两边长了一点，不盖刘海本身（刘海是 AI 入口）。自动让位时耳朵的位置上有刘海
    /// App 的窗口（拾掇的专注指示就在那儿），改成胶囊，排在那些窗口右边。没有刘海时
    /// 一律胶囊。
    public static func indicator(_ position: NotchMessagePosition, screen: AINotchScreen,
                                 windows: [NotchForeignWindow], apps: Int) -> Indicator {
        let bar = AINotchLayout.menuBar(of: screen)
        guard let notch = screen.notch, position != .capsule else {
            return .capsule(capsuleFrame(screen: screen, windows: windows, apps: apps))
        }
        let leftWidth = earWidth(items: 1)
        let rightWidth = earWidth(items: max(0, apps - 1))
        let left = CGRect(x: notch.minX - leftWidth, y: bar.minY, width: leftWidth, height: bar.height)
        let right = rightWidth > 0
            ? CGRect(x: notch.maxX, y: bar.minY, width: rightWidth, height: bar.height) : nil
        if position == .auto {
            let band = right.map { left.union($0) } ?? left.union(CGRect(x: notch.minX, y: bar.minY,
                                                                          width: notch.width, height: bar.height))
            let blocked = neighbors(windows, screen: screen).contains { $0.frame.intersects(band) }
            if blocked { return .capsule(capsuleFrame(screen: screen, windows: windows, apps: apps)) }
        }
        return .ears(left: left, right: right)
    }

    /// 刘海旁小胶囊：有刘海时在菜单栏那一条里、刘海右边（排在刘海附近别的刘海 App
    /// 窗口的右边），完全不占刘海中间；没有刘海时挂在菜单栏下沿正中。
    public static func capsuleFrame(screen: AINotchScreen, windows: [NotchForeignWindow], apps: Int) -> CGRect {
        let bar = AINotchLayout.menuBar(of: screen)
        let width = capsuleWidth(items: apps)
        let height = min(capsuleHeight, max(18, bar.height - 6))
        guard let notch = screen.notch else {
            return CGRect(x: screen.frame.midX - width / 2, y: bar.minY - 4 - height, width: width, height: height)
        }
        var x = notch.maxX + capsuleGap
        let band = CGRect(x: notch.minX, y: bar.minY, width: screen.frame.maxX - notch.minX, height: bar.height)
        for window in neighbors(windows, screen: screen, width: screen.frame.width) where window.frame.intersects(band) {
            x = max(x, window.frame.maxX + capsuleGap)
        }
        x = min(x, screen.frame.maxX - width - margin)
        return CGRect(x: x, y: bar.minY + (bar.height - height) / 2, width: width, height: height)
    }
}

// MARK: - 全屏和演示

/// 全屏 App、演示（Keynote 放映、全屏视频）时不弹：
///
/// - 有人盖满了整块屏幕（连菜单栏那一条）：前台 App 的普通窗口，或者任何人在普通
///   层级之上的窗口；
/// - 或者菜单栏不在屏幕上（全屏的空间里菜单栏是收起的），而前台 App 有一个窗口盖住
///   了刘海以下的整块屏幕（有刘海的 Mac 全屏时内容默认落在刘海下面）。只按这一条
///   时要求菜单栏不在，免得把「缩放到最大、程序坞隐藏」的普通窗口当成全屏。
///
/// 程序坞（调度中心的底）、码头自己、系统界面的窗口不算。菜单栏是 Window Server
/// 在 `menuBarLayer` 层（kCGMainMenuWindowLevel）的窗口，只看层级和位置，不读名字。
public enum NotchFullscreen {
    public static let ignoredOwners: Set<String> = [
        "window server", "dock", "程序坞", "dockling", "码头", "docket", "notificationcenter", "通知中心",
        "control center", "控制中心", "systemuiserver", "windowmanager", "loginwindow", "spotlight",
        "聚焦", "screenshot", "截屏", "textinputmenuagent", "universal control",
    ]

    /// kCGMainMenuWindowLevel。
    public static let menuBarLayer = 24

    /// 边差在这么多以内算盖满。
    static let tolerance: CGFloat = 2

    /// 盖满整块屏幕；`topAllowance` 给了时顶边可以低这么多（刘海下面的全屏内容）。
    public static func covers(_ frame: CGRect, screen: CGRect, topAllowance: CGFloat = 0) -> Bool {
        guard abs(frame.minX - screen.minX) <= tolerance, abs(frame.maxX - screen.maxX) <= tolerance,
              abs(frame.minY - screen.minY) <= tolerance, frame.maxY <= screen.maxY + tolerance else { return false }
        return frame.maxY >= screen.maxY - topAllowance - tolerance
    }

    /// 这块屏幕顶上有没有菜单栏。
    public static func menuBarVisible(_ windows: [NotchForeignWindow], screen: CGRect) -> Bool {
        windows.contains { window in
            window.layer == menuBarLayer && window.alpha > 0.05
                && window.frame.width >= screen.width * 0.5
                && window.frame.maxY >= screen.maxY - tolerance && window.frame.minY >= screen.maxY - 60
                && window.frame.intersects(screen)
        }
    }

    /// - Parameters:
    ///   - topInset: 刘海的高度（`safeAreaInsets.top`），没有刘海时 0。
    public static func isFullscreen(_ windows: [NotchForeignWindow], screen: CGRect, topInset: CGFloat = 0,
                                    frontmostPID: Int32?, ownPID: Int32) -> Bool {
        let candidates = windows.filter { window in
            window.ownerPID != ownPID && window.alpha > 0.5 && window.layer >= 0
                && window.layer != menuBarLayer
                && !ignoredOwners.contains(window.ownerName.lowercased())
        }
        let whole = candidates.contains { window in
            guard covers(window.frame, screen: screen) else { return false }
            return window.layer == 0 ? window.ownerPID == frontmostPID : true
        }
        if whole { return true }
        guard topInset > 0, !menuBarVisible(windows, screen: screen) else { return false }
        return candidates.contains { window in
            window.layer == 0 && window.ownerPID == frontmostPID
                && covers(window.frame, screen: screen, topAllowance: topInset)
        }
    }
}
