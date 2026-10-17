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
    /// 贴着刘海：左右各多出一截黑色，和刘海连成一体。`frame` 是窗口（按
    /// 指针移过去变宽后的大小留足），`notch` 是刘海本身。
    case notch(frame: CGRect, notch: CGRect)
    /// 顶部的小胶囊。`aside` 为 true 时是为了避让拾掇，放在刘海右边。
    case capsule(frame: CGRect, aside: Bool)

    public var frame: CGRect {
        switch self {
        case .notch(let frame, _): frame
        case .capsule(let frame, _): frame
        }
    }
}

public enum AINotchLayout {
    /// 刘海两边各多出的宽度（放小熊猫和字牌）。
    public static let wing: CGFloat = 34
    /// 指针移过去时每边再宽出这么多。只是视觉，不展开。
    public static let hoverGrow: CGFloat = 5
    /// 小胶囊静止时的大小。
    public static let capsuleSize = CGSize(width: 66, height: 22)
    /// 避让拾掇时，胶囊离刘海右边的距离（变宽后也不会碰到刘海）。
    public static let asideGap: CGFloat = 16
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

    /// 一块屏幕上的入口。
    ///
    /// 有刘海并且拾掇没在运行：贴着刘海。拾掇在运行：刘海右边隔一段距离的
    /// 小胶囊，不和刘海重叠，免得挡住拾掇在刘海上的悬停和拖放。没有刘海：
    /// 顶部正中的小胶囊。
    public static func entry(for screen: AINotchScreen, shiduoRunning: Bool) -> AINotchEntry {
        let band = max(screen.menuBarHeight, capsuleSize.height + 2)
        let capsuleY = screen.frame.maxY - band + (band - capsuleSize.height) / 2
        let width = capsuleSize.width + hoverGrow * 2
        if let notch = screen.notch {
            if shiduoRunning {
                // 菜单栏右边的状态图标是靠右排的，紧挨刘海右边通常是空的。
                return .capsule(frame: CGRect(x: notch.maxX + asideGap, y: capsuleY,
                                              width: width, height: capsuleSize.height),
                                aside: true)
            }
            let side = wing + hoverGrow
            return .notch(frame: CGRect(x: notch.minX - side, y: notch.minY,
                                        width: notch.width + side * 2, height: notch.height),
                          notch: notch)
        }
        return .capsule(frame: CGRect(x: screen.frame.midX - width / 2, y: capsuleY,
                                      width: width, height: capsuleSize.height),
                        aside: false)
    }

    /// 画出来的黑色部分有多宽：静止时比窗口窄，指针移过去时撑满窗口。
    public static func visibleWidth(_ entry: AINotchEntry, hovering: Bool) -> CGFloat {
        let grow = hovering ? 0 : hoverGrow * 2
        return entry.frame.width - grow
    }

    /// 展开的面板：从入口正下方长出来，水平对着入口中间，超出屏幕时往里收。
    public static func panelFrame(below entry: CGRect, screen: CGRect, size: CGSize = panelSize) -> CGRect {
        var x = entry.midX - size.width / 2
        x = min(max(x, screen.minX + margin), screen.maxX - size.width - margin)
        var top = entry.minY
        // 胶囊下面空一点，刘海下面直接接上。
        if entry.height < 30 { top -= 4 }
        var y = top - size.height
        y = max(y, screen.minY + margin)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// MARK: - 避让拾掇

/// 拾掇（另一个 App）的悬浮暂存架在指针碰到刘海、或者拖文件到刘海时弹出。
/// 码头的 AI 入口不响应悬停和拖拽，只认点击和快捷键；拾掇在运行时入口
/// 离开刘海。
public enum AIShiduo {
    /// 拾掇的 bundle id（它的 project.yml 里的 PRODUCT_BUNDLE_IDENTIFIER）。
    public static let bundleID = "io.github.hanson-zz.shiduo"

    public static func isRunning(_ bundleIDs: [String?]) -> Bool {
        bundleIDs.contains { $0?.lowercased() == bundleID }
    }

    public static let explanation =
        "检测到「拾掇」正在运行：拾掇的悬浮暂存架在指针碰到刘海或把文件拖到刘海时弹出，为了不挡住它，AI 入口不贴刘海，改放在刘海右侧的小胶囊里。码头的 AI 入口只认点击和快捷键，不响应悬停和拖拽。"
}
