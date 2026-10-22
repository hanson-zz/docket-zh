import AppKit
import ApplicationServices

/// 用辅助功能读一个进程的窗口，应用切换器、悬停窗口预览和 ⌥Tab 窗口切换器共用。
///
/// 不隔离到主线程：窗口切换器在后台并发读各个 App。AX 元素是 CF 对象，各线程读不同
/// 的元素没有问题。每个元素都设超时，App 卡住时最多等 `timeout` 秒，不设会按系统默认
/// 等约 6 秒。
enum AXWindowReader {
    /// 读到的一个窗口。`element` 只拿来调 AX，跨线程交出去后不再在原线程用。
    struct Raw: @unchecked Sendable {
        /// 在这个 App 的窗口列表里的位置（系统给的先后，一般最近用过的在前）。
        var index: Int
        var title: String?
        var minimized: Bool
        /// 左上角为原点的全局坐标。
        var frame: CGRect
        var element: AXUIElement
        /// 系统窗口号，私有接口拿不到时是 nil，再按位置配对。
        var windowID: CGWindowID?
    }

    /// 这个进程的普通窗口和对话框，按系统给的先后。没权限、App 没响应时是空的。
    static func windows(pid: pid_t, timeout: Float) -> [Raw] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, timeout)
        guard let list = copy(root, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        var out: [Raw] = []
        for (index, window) in list.enumerated() {
            AXUIElementSetMessagingTimeout(window, timeout)
            let subrole = copy(window, kAXSubroleAttribute) as? String
            if let subrole, subrole != (kAXStandardWindowSubrole as String),
               subrole != (kAXDialogSubrole as String) { continue }
            out.append(Raw(index: index,
                           title: copy(window, kAXTitleAttribute) as? String,
                           minimized: (copy(window, kAXMinimizedAttribute) as? Bool) ?? false,
                           frame: frame(of: window),
                           element: window,
                           windowID: windowID(of: window)))
        }
        return out
    }

    /// 按窗口的关闭按钮，和点红色圆点一样（有未存的改动时 App 自己会问）。
    @discardableResult
    static func pressClose(_ window: AXUIElement) -> Bool {
        guard let raw = copy(window, kAXCloseButtonAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let button = raw as! AXUIElement
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// 最小化到程序坞。
    @discardableResult
    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    static func frame(of window: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let raw = copy(window, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgPoint, &origin)
        }
        if let raw = copy(window, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    // MARK: 系统窗口号

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `_AXUIElementGetWindow` 不在公开头文件里，运行时找；找不到就退回按位置配对。
    nonisolated(unsafe) private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(window, &id) == .success, id != 0 else { return nil }
        return id
    }
}
