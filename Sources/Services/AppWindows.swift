import AppKit
import ApplicationServices

/// 应用切换器展开一个 App 时列出它的窗口，点一个跳过去。
///
/// 读窗口标题和把窗口提到最前都要「辅助功能」权限；没给时 `isTrusted` 是假，
/// 面板在窗口列表的位置写一行说明和「去授权」，固定、隐藏、排序照常。
/// 只在面板打开、展开或刷新时读一次，不常驻、不轮询。
@MainActor
enum AppWindows {
    /// 一个窗口。`element` 只在主线程用。
    struct Window: Identifiable {
        var id: Int
        var title: String
        var minimized: Bool
        var element: AXUIElement
    }

    /// 已经允许码头使用辅助功能（不弹窗）。
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 「去授权」：先让系统弹一次允许的提示，再打开 系统设置 ▸ 隐私与安全性 ▸ 辅助功能。
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 一个 App 正在运行的那个进程。
    static func process(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// 这个 App 的普通窗口和对话框，按系统给的先后（一般是最近用过的在前）。
    /// 没权限、App 没响应（最多等 0.25 秒）或没有窗口时是空的。
    static func windows(bundleID: String) -> [Window] {
        guard isTrusted, let app = process(bundleID: bundleID) else { return [] }
        return AXWindowReader.windows(pid: app.processIdentifier, timeout: 0.25).map {
            Window(id: $0.index, title: AppSwitcherList.windowTitle($0.title, minimized: $0.minimized),
                   minimized: $0.minimized, element: $0.element)
        }
    }

    /// 每个 App 有几个窗口，给列表右边的小角标；没权限时是空的。
    static func counts(bundleIDs: [String]) -> [String: Int] {
        guard isTrusted else { return [:] }
        var out: [String: Int] = [:]
        for id in bundleIDs { out[id] = windows(bundleID: id).count }
        return out
    }

    /// 跳到这个窗口：最小化的先还原，提到最前，再把 App 切到前台。
    static func focus(_ window: Window, bundleID: String) {
        guard let app = process(bundleID: bundleID) else { return }
        bringForward(window.element, minimized: window.minimized, app: app)
    }

    /// 把一个窗口带到最前（⌥Tab 窗口切换器也用）：App 隐藏着先取消隐藏，最小化的先还原，
    /// App 切到前台（AX 的 frontmost 加 `activate`，在别的桌面时系统会切过去），再把窗口
    /// 提到最前、设为主窗口。
    static func bringForward(_ element: AXUIElement, minimized: Bool, app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if minimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        AXUIElementSetAttributeValue(root, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = app.activate(options: [])
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
