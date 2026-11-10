import AppKit
import ApplicationServices

/// 桌面宠物读系统程序坞：程序坞那一条（AXList）的位置和废纸篓图标的位置，还有
/// 前台 App 是不是全屏。都在 `queue` 上读，跨进程的辅助功能调用每次最多等 0.25 秒，
/// 不卡主线程。没有辅助功能权限时读不到，交给 `DesktopPetPlacement.estimatedDock` 估。
struct DesktopPetDockReading: Sendable {
    /// 屏幕坐标（左下原点）。
    var frame: CGRect?
    var trashX: Double?
    var fullScreen = false
}

final class DesktopPetDockReader: @unchecked Sendable {
    static let shared = DesktopPetDockReader()
    nonisolated static let queue = DispatchQueue(label: "com.docket-zh.desktop-pet.dock", qos: .utility)

    private var dockPID: pid_t = 0
    private var list: AXUIElement?

    /// 在 `queue` 上调。`primaryHeight` 是主屏高度（换算辅助功能的左上原点坐标），
    /// `frontPID` 是前台 App，`screen` 是要看全屏的那块屏幕（屏幕坐标）。
    func read(primaryHeight: CGFloat, frontPID: pid_t?, screen: CGRect?) -> DesktopPetDockReading {
        var reading = DesktopPetDockReading()
        if AXIsProcessTrusted(), let list = dockList() {
            if let rect = Self.frame(of: list) {
                reading.frame = CGRect(x: rect.minX, y: primaryHeight - rect.maxY,
                                       width: rect.width, height: rect.height)
            } else {
                self.list = nil
            }
            if let trash = trashItem(in: list), let rect = Self.frame(of: trash) {
                reading.trashX = Double(rect.midX)
            }
        }
        if let frontPID, let screen {
            reading.fullScreen = Self.isFullScreen(pid: frontPID, screen: screen, primaryHeight: primaryHeight)
        }
        return reading
    }

    private func dockList() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated }) else { return nil }
        let pid = dock.processIdentifier
        if pid == dockPID, let list { return list }
        dockPID = pid
        list = nil
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let children = Self.children(of: app) else { return nil }
        list = children.first { Self.string(of: $0, kAXRoleAttribute) == (kAXListRole as String) }
        if let list { AXUIElementSetMessagingTimeout(list, 0.25) }
        return list
    }

    private func trashItem(in list: AXUIElement) -> AXUIElement? {
        Self.children(of: list)?.last { Self.string(of: $0, kAXSubroleAttribute) == "AXTrashDockItem" }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// 辅助功能坐标（主屏左上原点）里的矩形。
    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// 前台 App 有一个普通层级的窗口铺满这块屏幕：全屏（或者铺满的演示），小熊猫让开。
    private static func isFullScreen(pid: pid_t, screen: CGRect, primaryHeight: CGFloat) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        // 窗口列表是左上原点，换成屏幕坐标再比。
        for info in windows {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            let rect = CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
            if DesktopPetPlacement.coversScreen(rect, screen: screen) { return true }
        }
        return false
    }
}

/// 废纸篓救回的「放回原处」：先请访达放回（自动化，第一次系统会问），访达不让时
/// 由调用方弹气泡，让人点按钮再用 `TrashMonitor.putBack` 移回去。
enum DesktopPetPutBack {
    /// 在后台请访达把这几项放回原处，回主线程报哪几项没放回去。
    @MainActor
    static func viaFinder(_ items: [TrashedItem], done: @escaping @MainActor @Sendable ([TrashedItem]) -> Void) {
        let trash = TrashMonitor.trashURL
        let jobs: [(TrashedItem, String, String, String)] = items.compactMap { item in
            guard let origin = item.origin else { return nil }
            return (item, trash.appendingPathComponent(item.trashName).path, origin.folder, origin.name)
        }
        let unknown = items.filter { $0.origin == nil }
        let lines = DesktopPetRescue.finderScript.split(separator: "\n").map(String.init)
        Task.detached(priority: .userInitiated) {
            var failed: [TrashedItem] = unknown
            let manager = FileManager.default
            for (item, source, folder, name) in jobs {
                var isFolder: ObjCBool = false
                let plan = TrashPutBack.plan(
                    origin: item.origin,
                    folderExists: manager.fileExists(atPath: folder, isDirectory: &isFolder) && isFolder.boolValue,
                    targetExists: manager.fileExists(atPath: (folder as NSString).appendingPathComponent(name)))
                guard case .move = plan, manager.fileExists(atPath: source),
                      run(lines: lines, arguments: [source, folder, name]) else {
                    failed.append(item)
                    continue
                }
            }
            let result = failed
            await MainActor.run {
                TrashMonitor.shared.check(force: true)
                done(result)
            }
        }
    }

    /// 跑一段 AppleScript，30 秒没跑完（比如一直没回答自动化的询问）算失败。
    nonisolated private static func run(lines: [String], arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] } + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
