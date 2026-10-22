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
    /// 没响应时是空的。读法和 ⌥Tab 窗口切换器共用 `AXWindowReader`。
    static func windows(bundleID: String) -> [Window] {
        guard AppWindows.isTrusted, let app = AppWindows.process(bundleID: bundleID) else { return [] }
        return AXWindowReader.windows(pid: app.processIdentifier, timeout: 0.25).map {
            Window(id: $0.index, title: WindowPreview.displayTitle($0.title), minimized: $0.minimized,
                   frame: $0.frame, element: $0.element)
        }
    }

    /// 关掉这个窗口：按它的关闭按钮，和点红色圆点一样（有未存的改动时 App 自己会问）。
    @discardableResult
    static func close(_ window: Window) -> Bool {
        AXWindowReader.pressClose(window.element)
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
    /// 系统窗口号；有的话直接按它找，不再按位置和标题配对（⌥Tab 窗口切换器传）。
    var windowID: CGWindowID? = nil
}

/// 用 ScreenCaptureKit 的 `SCScreenshotManager` 一次截一个窗口。不隔离到任何
/// actor，从主线程 `await` 时在后台跑，不卡扩展栏。
enum WindowShots {
    static func capture(_ requests: [WindowShotRequest]) async -> [Int: WindowShot] {
        let box = ShotBox()
        await capture(requests) { key, shot in box.put(key, shot) }
        return box.shots
    }

    /// 一张一张截，截好一张交出一张（⌥Tab 窗口切换器边截边换上）。
    static func capture(_ requests: [WindowShotRequest],
                        each: @escaping @Sendable (Int, WindowShot) async -> Void) async {
        guard !requests.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return }
        var used = Set<CGWindowID>()
        for request in requests {
            if Task.isCancelled { break }
            let window: SCWindow?
            if let id = request.windowID {
                window = content.windows.first { $0.windowID == id }
            } else {
                let mine = content.windows.filter {
                    $0.owningApplication?.processID == request.pid && !used.contains($0.windowID)
                }
                let sameFrame = mine.filter { WindowPreview.framesMatch($0.frame, request.frame) }
                window = sameFrame.first(where: { ($0.title ?? "") == request.title }) ?? sameFrame.first
            }
            guard let window else { continue }
            used.insert(window.windowID)

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(request.pixelSize.width))
            config.height = max(1, Int(request.pixelSize.height))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                await each(request.key, WindowShot(image))
            }
        }
    }
}

/// 收集一批截图（只在 `capture` 里顺序写入）。
private final class ShotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [Int: WindowShot] = [:]
    func put(_ key: Int, _ shot: WindowShot) { lock.withLock { store[key] = shot } }
    var shots: [Int: WindowShot] { lock.withLock { store } }
}
