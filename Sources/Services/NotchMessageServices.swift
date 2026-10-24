import AppKit

// MARK: - 屏幕上的窗口（只读归属和位置）

/// 消息灵动岛判断「自动让位」和全屏用的窗口列表。
///
/// CGWindowListCopyWindowInfo 只读主人名字、进程号、层级、透明度和边框：这几项不要
/// 屏幕录制权限（只有窗口标题 kCGWindowName 要），这里也不读标题、不截图。只取在
/// 屏幕上的窗口、不要桌面元素（壁纸占了完整列表的大半，见 MissionControlProbe）。
@MainActor
enum NotchWindowScanner {
    private static var bundleIDs: [pid_t: String?] = [:]

    /// 在屏幕上的窗口，AppKit 坐标。
    static func windows() -> [NotchForeignWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
        var result: [NotchForeignWindow] = []
        result.reserveCapacity(list.count)
        var alive = Set<pid_t>()
        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            alive.insert(pid)
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            result.append(NotchForeignWindow(ownerName: owner, bundleID: bundleID(pid), ownerPID: pid,
                                             frame: NotchWindowGeometry.appKit(bounds, primaryHeight: primaryHeight),
                                             layer: layer, alpha: alpha))
        }
        // 退出了的进程不留在缓存里。
        if bundleIDs.count > 64 { bundleIDs = bundleIDs.filter { alive.contains($0.key) } }
        return result
    }

    private static func bundleID(_ pid: pid_t) -> String? {
        if let cached = bundleIDs[pid] { return cached }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        bundleIDs[pid] = id
        return id
    }
}

// MARK: - 打开 App

@MainActor
enum NotchMessageOpener {
    /// 打开消息所在的 App：先替用户点一下系统横幅（系统会打开 App 并定位到那个聊天），
    /// 横幅已经不在了就直接打开 App。WhatsApp、微信没有能按名字定位聊天的公开方式，
    /// 只能靠点横幅定位。
    static func open(_ app: NotchMessageApp, banner: AXUIElement?) {
        if NotchBannerWatcher.press(banner) { return }
        activate(app)
    }

    /// 打开（已经开着就切到前台，窗口关了会重新打开主窗口）。
    static func activate(_ app: NotchMessageApp) {
        guard let url = appURL(app) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    static func appURL(_ app: NotchMessageApp) -> URL? {
        app.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    private static var icons: [NotchMessageApp: NSImage] = [:]

    /// App 自己的图标；没装时为 nil（画一个 SF Symbol 代替）。
    static func icon(_ app: NotchMessageApp) -> NSImage? {
        if let cached = icons[app] { return cached }
        guard let url = appURL(app) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[app] = image
        return image
    }
}

// MARK: - 信息的快速回复

/// 用 AppleScript 让「信息」发一条消息。脚本和结果判断在 Core 的 `NotchMessageReply`：
/// 按显示名找联系人或群，找不到、重名都不发。第一次会弹系统的「允许码头控制信息」。
enum MessagesReplier {
    private static let queue = DispatchQueue(label: "com.docket-zh.notch-message.reply")

    static func send(_ text: String, to recipient: String) async -> NotchMessageReply.Outcome {
        let source = NotchMessageReply.script(text: text, recipient: recipient)
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failed)
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                let number = error.map { ($0[NSAppleScript.errorNumber] as? Int) ?? 0 }
                continuation.resume(returning: NotchMessageReply.outcome(result: result.stringValue,
                                                                         errorNumber: number))
            }
        }
    }
}
