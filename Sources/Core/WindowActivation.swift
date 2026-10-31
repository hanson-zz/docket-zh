import Foundation

// 码头是菜单栏 App（accessory），设置、小组件库这些普通窗口要靠它自己把 App 叫到前台，
// 窗口才有激活外观（彩色红绿灯、标题和侧边栏选中项不发灰、开关是强调色）。
// 这里只做判断，不碰界面；用的地方在 App/WindowControllers.swift（AccessoryActivation）
// 和 App/ReminderPopupController.swift。
//
// macOS 14 起 `NSApp.activate()` 是「请求」，系统不一定给：从菜单栏菜单、非激活面板
// （扩展栏、桌面卡片）点出来的请求在 macOS 26/27 上常被忽略。窗口照样排到最前、
// 也成了 key，但 App 没激活，整个窗口显示成非激活的灰色。非激活面板拿过键盘以后，
// 再点普通窗口也只是在 App 里换 key，不一定把 App 带到前台。所以一步步升级：
// 先请求，没成再强制，还不成就临时切成普通 App 再激活，普通窗口都关了再切回。

public enum WindowActivationPlan {

    public enum Step: Sendable, Equatable {
        /// `NSApp.activate()`：新的协作式激活。
        case request
        /// `activate(ignoringOtherApps: true)`：旧接口，系统多数时候仍会给。
        case force
        /// 临时切成 `.regular` 再强制激活；普通窗口都关了再切回 `.accessory`。
        case promote
    }

    /// 第 `attempt` 次检查（从 0 数）时 App 还没激活，这一步做什么；已经激活或
    /// 三步都试过了返回 nil。
    public static func step(attempt: Int, isActive: Bool) -> Step? {
        guard !isActive else { return nil }
        switch attempt {
        case 0: return .request
        case 1: return .force
        case 2: return .promote
        default: return nil
        }
    }

    /// 每一步之后等多久再看有没有激活（秒）。激活是异步的，马上看总是「没激活」。
    public static func wait(after step: Step) -> Double {
        switch step {
        case .request: return 0.12
        case .force: return 0.25
        case .promote: return 0.4
        }
    }

    /// 什么时候切回 `.accessory`：只切回自己临时改过的，而且要等普通窗口一个都不剩。
    /// 窗口还开着就切回，有的系统版本会顺手把 App 退到后台，窗口又变灰。
    public static func shouldRestoreAccessory(promoted: Bool, openWindows: Int) -> Bool {
        promoted && openWindows <= 0
    }

    /// 普通窗口收到点击时要不要重新走一遍激活：App 没激活就要。
    public static func activateOnClick(isActive: Bool) -> Bool { !isActive }
}

/// 浮动面板（扩展栏弹出、桌面卡片、到点卡片、刘海面板）什么时候可以成为 key。
///
/// key 只有一个：浮动面板一拿走，开着的设置窗口立刻显示成非激活的样子。
/// 所以只在用户点了它、而且它要打字或接 Esc 时才拿；指针路过（悬停）不抢
/// 码头自己开着的普通窗口的 key。
public enum FloatingKeyPolicy {

    public enum Trigger: Sendable, Equatable {
        /// 用户点了这个面板（或点了打开它的格子）。
        case click
        /// 指针移到面板上。
        case hover
        /// 计时器、通知、内容刷新这类不是用户操作的出现或重画。
        case automatic
    }

    /// - Parameters:
    ///   - needsKeyboard: 面板里有输入框，或者要接 Esc 收起。
    ///   - regularWindowIsKey: 码头自己的普通窗口（设置、小组件库…）此刻是 key。
    public static func mayTakeKey(_ trigger: Trigger, needsKeyboard: Bool, regularWindowIsKey: Bool) -> Bool {
        guard needsKeyboard else { return false }
        switch trigger {
        case .click: return true
        case .hover: return !regularWindowIsKey
        case .automatic: return false
        }
    }
}
