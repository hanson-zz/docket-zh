import Foundation

// 点弹出卡片主体（或股票、久坐通知）要打开某张小组件的面板时，面板从哪里长出来；
// 以及喝水提醒交给后台计时器以后，每一秒拿到的新时间怎么处理。纯逻辑，窗口和
// 计时器在 App/WidgetPanelOpener.swift 和 Services/WaterNotifier.swift。

// MARK: - 打开小组件面板

/// 打开某个小组件的详情面板时，面板挂在哪里。
public enum WidgetPanelRoute: Equatable, Sendable {
    /// 扩展栏上就是这张卡片：从它的位置长出来（扩展栏自动隐藏时先滑出来）。
    case tile
    /// 卡片收在当前布局的这个文件夹里：从文件夹的位置长出来，不用先打开文件夹。
    case folder(UUID)
    /// 在别的布局里、扩展栏没开（只用系统程序坞）或卡片被条件隐藏：以独立的
    /// 浮动面板打开，挂在屏幕顶部正中（弹出卡片刚才的位置），不切换布局。
    case floating
    /// 找不到这个小组件，或它没有面板。
    case none

    /// - Parameters:
    ///   - current: 当前布局顶层的项目（扩展栏显示的那一层）。
    ///   - existsAnywhere: 所有布局里有没有这个小组件。
    ///   - shelfShown: 扩展栏窗口在不在（自动隐藏滑到屏幕外也算在）。
    ///   - hasDetail: 这种小组件有没有面板。
    public static func decide(widget id: UUID, current: [DockItem], existsAnywhere: Bool,
                              shelfShown: Bool, hasDetail: Bool) -> WidgetPanelRoute {
        guard hasDetail, existsAnywhere || DockItemTree.widget(id, in: current) != nil else { return .none }
        guard shelfShown else { return .floating }
        for item in current {
            switch item {
            case .widget(let widget) where widget.id == id:
                return .tile
            case .group(let group) where DockItemTree.widget(id, in: group.items) != nil:
                return .folder(group.id)
            default:
                continue
            }
        }
        return .floating
    }
}

// MARK: - 喝水提醒的后台调度

/// 喝水提醒原来由喝水卡片显示时交来下一次提醒的时间，卡片在文件夹里、在别的
/// 布局里时不提醒，弹出卡片上「稍后 15 分钟」也排不上。现在由 `TimedAlertDriver`
/// 每秒把所有布局里每个喝水小组件的下一次提醒交给 `WaterNotifier`，这里判断
/// 每一次交来的时间要怎么处理。
public enum WaterAlertPlan {
    /// 弹卡片时，新交来的时间和正在等的那个比较之后要做的事。
    public enum Step: Equatable, Sendable {
        /// 和正在等的一样（差不到 1 秒），不动。
        case keep
        /// 换成新的时间等（nil 是不再提醒）。
        case rearm(Date?)
        /// 正在等的那个已经到点（下一次往后挪的那一秒往往就是它刚到点的那一秒），
        /// 先弹出它，再换成新的时间等。
        case fireThenRearm(due: Date, next: Date?)
    }

    public static func step(pending: Date?, next: Date?, now: Date) -> Step {
        if let pending, let next, abs(pending.timeIntervalSince(next)) < 1 { return .keep }
        if pending == nil, next == nil { return .keep }
        if let pending, pending <= now.addingTimeInterval(0.5) {
            return .fireThenRearm(due: pending, next: next)
        }
        return .rearm(next)
    }

    /// 上一秒还在、这一秒已经不在任何布局里的喝水小组件：撤掉它排着的提醒，
    /// 免得删掉的卡片还按旧时间弹一次。
    public static func removed(known: Set<UUID>, present: Set<UUID>) -> Set<UUID> {
        known.subtracting(present)
    }
}
