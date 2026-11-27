import ApplicationServices
import Foundation

/// Pro 窗口标题读取器。只在「已购买 + 单独同意 + 系统辅助功能已授权」时由
/// TimeInsightsTracker 主动调用；无辅助功能权限时绝不调用 AXUIElementCopyAttributeValue。
/// 从不读取键盘内容、屏幕像素或后台窗口。
struct NativeTimeInsightsWindowTitleSource: TimeInsightsWindowTitleSource {
    var isConnected: Bool { AXIsProcessTrusted() }

    /// 只由用户点击设置页的「授权辅助功能」按钮触发，不在启动时弹窗。
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func title(forProcess pid: Int32) -> String? {
        guard pid > 0, isConnected else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue)
                == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = windowValue as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
                == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return TimeInsightsTitlePrivacy.sanitize(value as? String)
    }
}
