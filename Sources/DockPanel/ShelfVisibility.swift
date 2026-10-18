import AppKit
import Observation

/// Whether the shelf's cards are actually on screen: the window is ordered
/// in, not slid off the edge by auto-hide, and not covered.
///
/// Animated cards (the 电池 looks) read this to stop drawing frames nobody
/// can see. `DockPanelController` keeps it current. It starts true so a card
/// hosted anywhere else is never frozen by a shelf it does not live in.
@MainActor @Observable
final class ShelfVisibility {
    static let shared = ShelfVisibility()

    private(set) var cardsOnScreen = true

    private init() {}

    func update(_ shown: Bool) {
        if shown != cardsOnScreen { cardsOnScreen = shown }
    }
}

/// 扩展栏窗口在不在、滑出来和它滑出来以后的位置，给不在扩展栏视图里的人用：
/// 点弹出卡片主体打开小组件面板时，扩展栏自动隐藏着就先滑出来，面板按滑出来
/// 以后的位置挂上去。`DockPanelController` 接上。
@MainActor
final class ShelfPresence {
    static let shared = ShelfPresence()

    /// 扩展栏窗口开着（自动隐藏滑到屏幕外也算）。只用系统程序坞时为 false。
    var isShown: @MainActor () -> Bool = { false }
    /// 现在是不是滑在屏幕外。
    var isTuckedAway: @MainActor () -> Bool = { false }
    /// 滑出来。
    var reveal: @MainActor () -> Void = {}
    /// 滑出来时窗口的位置。
    var revealedFrame: @MainActor () -> CGRect? = { nil }

    private init() {}
}
