import AppKit
import ApplicationServices
import Observation

/// 应用切换器展开一个 App 时列出它的窗口，点一个跳过去。
///
/// 读窗口标题和把窗口提到最前都要「辅助功能」权限；没给时 `isTrusted` 是假，
/// 面板在窗口列表的位置写一行说明和「去授权」，固定、隐藏、排序照常。
/// 只在面板打开、展开或刷新时读一次，不常驻、不轮询。
@MainActor
enum AppWindows {
    /// 一个窗口。`element` 只在主线程用。`frame`、`windowID`、`pid` 给缩略图用
    /// （`AppWindowThumbnails`），只列标题的地方不用填。
    struct Window: Identifiable {
        var id: Int
        var title: String
        var minimized: Bool
        var element: AXUIElement
        /// AX 读到的位置和大小（左上角为原点的全局坐标）。
        var frame: CGRect = .zero
        /// 系统窗口号：AX 私有接口给的，拿不到时按位置和窗口服务器配对（`ServerWindows.match`）。
        var windowID: CGWindowID? = nil
        var pid: pid_t = 0
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
        let pid = app.processIdentifier
        return AXWindowReader.windows(pid: pid, timeout: 0.25).map {
            Window(id: $0.index, title: AppSwitcherList.windowTitle($0.title, minimized: $0.minimized),
                   minimized: $0.minimized, element: $0.element, frame: $0.frame, windowID: $0.windowID, pid: pid)
        }
    }

    /// 截缩略图用的窗口列表：和 `windows` 一样，再给 AX 拿不到窗口号的补上系统窗口号
    /// （同进程、同位置大小的屏幕窗口，`ServerWindows.match`，读一次窗口服务器几毫秒）。
    /// 太小的工具窗口不列，和 ⌥Tab 窗口切换器一样；最小化的保留（画占位，不截）。
    static func thumbnailWindows(bundleID: String) -> [Window] {
        guard isTrusted, let app = process(bundleID: bundleID) else { return [] }
        let pid = app.processIdentifier
        let raws = AXWindowReader.windows(pid: pid, timeout: 0.25).filter {
            $0.minimized || ($0.frame.width >= 40 && $0.frame.height >= 30)
        }
        let needsServer = raws.contains { $0.windowID == nil && !$0.minimized }
        let server = needsServer ? ServerWindows.read() : ServerWindows()
        return raws.map {
            Window(id: $0.index, title: AppSwitcherList.windowTitle($0.title, minimized: $0.minimized),
                   minimized: $0.minimized, element: $0.element, frame: $0.frame,
                   windowID: $0.windowID ?? server.match($0, pid: pid), pid: pid)
        }
    }

    // MARK: 屏幕录制

    /// 看窗口缩略图要「屏幕录制」权限（只查，不弹窗），和悬停窗口预览同一个判断。
    static var canCapture: Bool { WindowPreviewSource.canCapture }

    /// 「去授权」：系统没问过时先弹一次，再打开 系统设置 ▸ 隐私与安全性 ▸ 屏幕与系统录音。
    static func requestCapture() { WindowPreviewSource.requestCapture() }

    /// 每个 App 有几个窗口，给列表右边的小角标；没权限时是空的。
    static func counts(bundleIDs: [String]) -> [String: Int] {
        guard isTrusted else { return [:] }
        var out: [String: Int] = [:]
        // 和缩略图一样不数太小的工具窗口，角标和展开后的「N 个窗口」对得上。
        for id in bundleIDs {
            out[id] = windows(bundleID: id).filter {
                $0.minimized || ($0.frame.width >= 40 && $0.frame.height >= 30)
            }.count
        }
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

/// 应用切换器的窗口缩略图：卡片和面板共用一份缓存，按窗口号（没有时按进程、标题和位置）存。
///
/// 截图复用 `WindowShots`（ScreenCaptureKit 的 `SCScreenshotManager`，后台跑）。只在面板
/// 展开一个 App、大号卡片换了看的 App 时要图，重画不截：存着的 15 秒内直接用，过了先画旧的、
/// 后台再截一张换上。一次只跑一批（最多 4 张），新要的排队，同一个窗口不重复排；最多存 48 张，
/// 多了扔最久没用的。没给屏幕录制权限时什么都不截，界面改列窗口标题。
@MainActor
@Observable
final class AppWindowThumbnails {
    static let shared = AppWindowThumbnails()

    /// 改了就让用到的卡片、面板重画；读用 `image(for:)`。
    private(set) var revision = 0

    @ObservationIgnored private var cache = ExpiringLRUCache<WindowShot>(
        capacity: AppSwitcherLayout.shotCapacity, lifetime: AppSwitcherLayout.shotLifetime)
    @ObservationIgnored private var queue: [(key: String, request: WindowShotRequest)] = []
    @ObservationIgnored private var queued = Set<String>()
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// `clear` 时加一，旧的那一批截完的图不再存。
    @ObservationIgnored private var generation = 0

    private init() {}

    /// 缓存的键：有窗口号按窗口号，没有按进程、标题和位置大小。
    static func key(_ window: AppWindows.Window) -> String {
        if let id = window.windowID { return "w\(id)" }
        let f = window.frame
        return "\(window.pid)|\(window.title)|\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
    }

    /// 这个窗口存着的图（可能不新鲜）。重画时调，不截图。
    func image(for window: AppWindows.Window) -> CGImage? {
        _ = revision
        return cache.peek(Self.key(window))?.image
    }

    /// 要这些窗口的图：没有的、不新鲜的排进队里，最小化的不截。没权限时什么都不做。
    func request(_ windows: [AppWindows.Window], scale: CGFloat = 2) {
        guard AppWindows.canCapture else { return }
        let now = Date.now
        for window in windows where !window.minimized && window.pid != 0 {
            let key = Self.key(window)
            guard !cache.isFresh(key, at: now), !queued.contains(key) else { continue }
            queued.insert(key)
            queue.append((key, WindowShotRequest(
                key: 0, pid: window.pid, title: window.title, frame: window.frame,
                pixelSize: WindowPreview.captureSize(window: window.frame.size, scale: scale),
                windowID: window.windowID)))
        }
        // 排太多（来回悬停）时只留最近要的。
        let limit = AppSwitcherLayout.shotBatch * 3
        if queue.count > limit {
            for dropped in queue.prefix(queue.count - limit) { queued.remove(dropped.key) }
            queue.removeFirst(queue.count - limit)
        }
        startIfIdle()
    }

    /// 权限撤掉、App 退出时清掉，下次要图重新截。
    func clear() {
        generation += 1
        worker?.cancel()
        worker = nil
        queue = []
        queued = []
        cache.removeAll()
        revision += 1
    }

    private func startIfIdle() {
        guard worker == nil, !queue.isEmpty else { return }
        let generation = generation
        worker = Task { [weak self] in
            while let batch = self?.nextBatch(), !batch.isEmpty {
                if Task.isCancelled { break }
                let requests = batch.enumerated().map { index, item in
                    var request = item.request
                    request.key = index
                    return request
                }
                let keys = batch.map { $0.key }
                let shots = await WindowShots.capture(requests)
                guard self?.generation == generation else { return }
                self?.finish(keys: keys, shots: shots)
            }
            if self?.generation == generation { self?.worker = nil }
        }
    }

    private func nextBatch() -> [(key: String, request: WindowShotRequest)] {
        let batch = Array(queue.prefix(AppSwitcherLayout.shotBatch))
        queue.removeFirst(batch.count)
        return batch
    }

    private func finish(keys: [String], shots: [Int: WindowShot]) {
        let now = Date.now
        for (index, key) in keys.enumerated() {
            queued.remove(key)
            if let shot = shots[index] { cache.insert(shot, for: key, at: now) }
        }
        if !shots.isEmpty { revision += 1 }
    }
}
