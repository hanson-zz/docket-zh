import Foundation

/// 锁定扩展栏：锁住之后哪些操作还能做。
///
/// 锁的是布局，不是使用。改动“有什么、放在哪”的操作（拖动排序、拖出分组、
/// 拖进来加入、合成分组、拖动浮动扩展栏、右键里的移除、取消分组、加间隔这类）
/// 一律停用；打开、悬停、放大、右键打开、小组件自己的设置照常。
///
/// 只管扩展栏本身。分组窗口（应用分组、文件夹分组）里面的增删和排序不算：
/// 组里的移除、拖动排序、右键左移右移、从访达拖进组窗口都照常。
public enum ShelfLockAction: String, CaseIterable, Sendable {
    // 改布局：锁定时停用。
    /// 在扩展栏上拖动格子换位置。
    case reorder
    /// 把一个格子拖到另一个上合成分组，或加进已有分组。
    case combine
    /// 从分组窗口里把图标拖出来（离开分组、落回扩展栏）。
    case dragOutOfGroup
    /// 从访达拖 App 或文件进扩展栏，或拖到扩展栏上的分组格子。
    case dropIn
    /// 按住空白处拖动浮动扩展栏。
    case moveFloatingShelf
    /// 右键「从程序坞中移除」「从分组中移除」「移除间隔」。
    case remove
    /// 右键「取消分组」。
    case ungroup
    /// 右键「添加到分组」。
    case addToGroup
    /// 右键「添加间隔」。
    case addSpacer
    /// 右键「在程序坞中保留」（把正在运行的 App 固定上去）。
    case keepInDock

    // 使用：锁定时照常。
    /// 点一下打开 App、文件、小组件面板或分组。
    case open
    /// 悬停显示名字。
    case hover
    /// 指针下方放大。
    case magnify
    /// 右键菜单里的「打开」「退出」「在访达中显示」。
    case contextOpen
    /// 小组件自己的设置、样式、显示条件、分组改名和色调。
    case widgetSettings
    /// 分组窗口里的移除（右键「从分组中移除」）。
    case removeInGroup
    /// 分组窗口里的排序：拖动标签或图标、右键左移右移。
    case reorderInGroup
    /// 从访达把 App 或文件夹拖进打开的分组窗口。
    case dropIntoGroupWindow

    /// 这项操作会不会改动扩展栏的布局。
    public var changesLayout: Bool {
        switch self {
        case .reorder, .combine, .dragOutOfGroup, .dropIn, .moveFloatingShelf,
             .remove, .ungroup, .addToGroup, .addSpacer, .keepInDock:
            true
        case .open, .hover, .magnify, .contextOpen, .widgetSettings,
             .removeInGroup, .reorderInGroup, .dropIntoGroupWindow:
            false
        }
    }
}

public enum ShelfLock {
    /// 锁定时只放行不改布局的操作；没锁时什么都放行。
    public static func allows(_ action: ShelfLockAction, locked: Bool) -> Bool {
        !locked || !action.changesLayout
    }

    public static func allows(_ action: ShelfLockAction, settings: CustomDockSettings) -> Bool {
        allows(action, locked: settings.locked)
    }

    /// 锁定时试图拖动给的轻提示：格子沿扩展栏左右抖一下，幅度渐小，最后停回原位。
    public static let shakeAmplitude: Double = 4
    public static let shakeCycles: Double = 3
    /// 整段约 0.3 秒，轻而不拖沓。
    public static let shakeDuration: Double = 0.3

    /// 抖动进行到 `progress`（0 到 1）时偏离原位多少点。两头都是 0。
    public static func shakeOffset(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return shakeAmplitude * sin(2 * .pi * shakeCycles * p) * (1 - p)
    }

    /// 一次拖动手势里只抖一下：手势在移动时会反复报告，只有刚开始那次算数。
    public static func shouldShake(locked: Bool, alreadyNudged: Bool) -> Bool {
        locked && !alreadyNudged
    }
}
