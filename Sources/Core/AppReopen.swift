import Foundation

/// 点扩展栏上一个 App 时怎么打开它，照系统程序坞的做法。
///
/// 系统程序坞点一个已经在运行的 App，发的不是单纯的「激活」，而是 reopen
/// （kAEReopenApplication）：App 没有窗口时开一个新窗口（日历、邮件、备忘录、
/// 访达都这样），窗口全最小化时还原一个，有窗口时就只是切到前台。只调
/// `NSRunningApplication.activate` 做不到前两件，macOS 14 起从不激活的面板里调
/// 还可能被系统拒绝（协作式激活），表现就是点了没反应。
///
/// 所以运行中的 App 也走 `NSWorkspace.openApplication`（activates = true）：
/// 对已经开着的 App 它不会再起一份，只发 reopen 并把它带到前台，和点系统程序坞一样。
/// 拿不到 App 的位置时才退回单纯激活。
///
/// 全是纯函数，测试用。
public enum AppReopen {

    public enum Plan: Equatable, Sendable {
        /// 没在运行：启动（扩展栏会弹跳）。
        case launch(URL)
        /// 在运行：发 reopen 并带到前台（不弹跳）。
        case reopen(URL)
        /// 在运行但找不到 App 的位置：只能单纯激活。
        case activateOnly
        /// 没在运行也找不到：什么都做不了。
        case unavailable
    }

    /// 选用哪个位置的 App。
    ///
    /// 在运行时优先用正在跑的那一份（`runningURL`）：同一个 bundle id 装了两份
    /// （比如「应用程序」和下载文件夹里各一份）时，拿另一份的路径去打开会再起一个进程，
    /// 而不是叫醒开着的那个。没在运行时按扩展栏存的位置、再按系统登记的位置。
    public static func url(isRunning: Bool, runningURL: URL?, savedURL: URL?, registeredURL: URL?) -> URL? {
        if isRunning, let runningURL { return runningURL }
        return savedURL ?? registeredURL ?? (isRunning ? nil : runningURL)
    }

    public static func plan(isRunning: Bool, runningURL: URL?, savedURL: URL?, registeredURL: URL?) -> Plan {
        let url = url(isRunning: isRunning, runningURL: runningURL, savedURL: savedURL, registeredURL: registeredURL)
        switch (isRunning, url) {
        case (true, let url?): return .reopen(url)
        case (true, nil): return .activateOnly
        case (false, let url?): return .launch(url)
        case (false, nil): return .unavailable
        }
    }

    /// reopen 失败（系统报错、App 不响应）后要不要再单纯激活一次兜底。
    public static func fallsBackToActivate(after plan: Plan, succeeded: Bool) -> Bool {
        guard !succeeded, case .reopen = plan else { return false }
        return true
    }

    /// 扩展栏这一格要不要弹跳：只有冷启动弹，叫醒开着的 App 不弹（和系统程序坞一样）。
    public static func bounces(_ plan: Plan) -> Bool {
        if case .launch = plan { return true }
        return false
    }
}
