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
    /// 指针在刘海上：小熊猫。
    case panda
    /// 回答生成中：三个跳动的小点。
    case dots
}

public enum AINotchLayout {
    /// 刘海下沿往下长出的那一条的高度。宽度和刘海一样。
    public static let stripHeight: CGFloat = 18
    /// 那一条里小熊猫的大小。
    public static let stripPandaSize: CGFloat = 14
    /// 指针离开刘海后，那一条过多久收回。
    public static let stripLinger: TimeInterval = 0.3
    /// 外接屏胶囊的大小。
    public static let capsuleSize = CGSize(width: 44, height: 18)
    /// 外接屏胶囊离菜单栏下沿的距离。
    public static let capsuleGap: CGFloat = 2
    /// 外接屏胶囊平时的不透明度，指针移上去或回答生成中时完全显示。
    public static let capsuleRestingOpacity: Double = 0.4
    /// 菜单栏自动隐藏（量出来是 0）时按这个高度避开它。
    public static let fallbackMenuBarHeight: CGFloat = 24
    /// 展开的对话面板。
    public static let panelSize = CGSize(width: 420, height: 520)
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
            let strip = CGRect(x: notch.minX, y: bar.minY - stripHeight, width: notch.width, height: stripHeight)
            return .notch(frame: frame, strip: strip)
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

    /// 刘海下沿那一条显示什么，nil 表示收起。回答生成中优先显示小点（不需要
    /// 悬停）；否则指针在刘海上时显示小熊猫。入口隐藏或面板开着时不显示。
    public static func stripContent(visible: Bool, panelOpen: Bool,
                                    hovering: Bool, generating: Bool) -> AINotchStripContent? {
        guard visible, !panelOpen else { return nil }
        if generating { return .dots }
        return hovering ? .panda : nil
    }

    /// 外接屏胶囊的不透明度。
    public static func capsuleOpacity(hovering: Bool, generating: Bool) -> Double {
        hovering || generating ? 1 : capsuleRestingOpacity
    }

    /// 展开的面板：从入口正下方长出来，水平对着入口中间，超出屏幕时往里收。
    public static func panelFrame(below entry: CGRect, screen: CGRect, size: CGSize = panelSize) -> CGRect {
        var x = entry.midX - size.width / 2
        x = min(max(x, screen.minX + margin), screen.maxX - size.width - margin)
        var top = entry.minY
        // 胶囊下面空一点，刘海下面直接接上。
        if entry.height < 22 { top -= 4 }
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
        "检测到「拾掇」正在运行：拾掇的悬浮暂存架在指针碰到刘海或把文件拖到刘海时弹出，为了不和它抢，码头不在刘海上放任何 AI 入口，刘海的点击和悬停都让给拾掇。这时请用快捷键或货架上 AI 卡片的小熊猫展开对话。"
}
