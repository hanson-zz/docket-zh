import AppKit
import ApplicationServices
import ScreenCaptureKit

/// 窗口预览小窗的数据：一个 App 的窗口（辅助功能读标题、位置、是否最小化）、
/// 关窗口，以及屏幕录制权限。截图在 `WindowShots`，不在主线程上跑。
///
/// 列窗口、跳到窗口复用应用切换器的 `AppWindows`（同样要辅助功能权限，
/// 读一次最多等 0.25 秒）。不轮询，只在小窗打开和关掉一个窗口后读。
@MainActor
enum WindowPreviewSource {
    /// 一个窗口。`frame` 是 AX 读到的位置和大小（左上角为原点的全局坐标），
    /// 用来和截图那边的窗口配对。`element` 只在主线程用。
    struct Window: Identifiable {
        var id: Int
        var title: String
        var minimized: Bool
        var frame: CGRect
        var element: AXUIElement

        /// 给 `AppWindows.focus` 用的那一份。
        var appWindow: AppWindows.Window {
            AppWindows.Window(id: id, title: title, minimized: minimized, element: element)
        }

        /// 缩略图缓存的键：同一个进程、同样的标题和位置，几秒内当成同一个窗口。
        func cacheKey(pid: pid_t) -> String {
            "\(pid)|\(title)|\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
        }
    }

    /// 已经允许屏幕录制（只查，不弹窗）。
    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// 用户点了「打开屏幕录制权限」：系统还没问过时先弹一次，再打开
    /// 系统设置 ▸ 隐私与安全性 ▸ 屏幕与系统录音。启动时从不主动调。
    static func requestCapture() {
        if CGRequestScreenCaptureAccess() { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 这个 App 的普通窗口和对话框，按系统给的先后。没辅助功能权限、App 不在了、
    /// 没响应时是空的。
    static func windows(bundleID: String) -> [Window] {
        guard AppWindows.isTrusted, let app = AppWindows.process(bundleID: bundleID) else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let list = copy(root, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        var out: [Window] = []
        for (index, window) in list.enumerated() {
            AXUIElementSetMessagingTimeout(window, 0.25)
            let subrole = copy(window, kAXSubroleAttribute) as? String
            if let subrole, subrole != (kAXStandardWindowSubrole as String),
               subrole != (kAXDialogSubrole as String) { continue }
            let title = WindowPreview.displayTitle(copy(window, kAXTitleAttribute) as? String)
            let minimized = (copy(window, kAXMinimizedAttribute) as? Bool) ?? false
            out.append(Window(id: index, title: title, minimized: minimized,
                              frame: frame(of: window), element: window))
        }
        return out
    }

    /// 关掉这个窗口：按它的关闭按钮，和点红色圆点一样（有未存的改动时 App 自己会问）。
    @discardableResult
    static func close(_ window: Window) -> Bool {
        guard let raw = copy(window.element, kAXCloseButtonAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let button = raw as! AXUIElement
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func frame(of window: AXUIElement) -> CGRect {
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

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}

/// 截好的一张缩略图。CGImage 截好后只读，跨线程交出去是安全的。
final class WindowShot: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// 截一张窗口缩略图要的东西，全是值，可以交给后台。
struct WindowShotRequest: Sendable {
    /// 小窗里那张卡片的编号（`WindowPreviewSource.Window.id`）。
    var key: Int
    var pid: pid_t
    var title: String
    var frame: CGRect
    var pixelSize: CGSize
}

/// 用 ScreenCaptureKit 的 `SCScreenshotManager` 一次截一个窗口。不隔离到任何
/// actor，从主线程 `await` 时在后台跑，不卡扩展栏。
enum WindowShots {
    static func capture(_ requests: [WindowShotRequest]) async -> [Int: WindowShot] {
        guard !requests.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return [:] }
        var out: [Int: WindowShot] = [:]
        var used = Set<CGWindowID>()
        for request in requests {
            if Task.isCancelled { break }
            let mine = content.windows.filter {
                $0.owningApplication?.processID == request.pid && !used.contains($0.windowID)
            }
            let sameFrame = mine.filter { WindowPreview.framesMatch($0.frame, request.frame) }
            guard let window = sameFrame.first(where: { ($0.title ?? "") == request.title }) ?? sameFrame.first
            else { continue }
            used.insert(window.windowID)

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(request.pixelSize.width))
            config.height = max(1, Int(request.pixelSize.height))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                out[request.key] = WindowShot(image)
            }
        }
        return out
    }
}
