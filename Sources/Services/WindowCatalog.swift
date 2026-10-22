import AppKit
import ApplicationServices

/// ⌥Tab 窗口切换器的数据：所有 App 的窗口、在哪个桌面、屏幕上的前后次序。
///
/// 只在按下快捷键时读一次：各 App 的窗口在后台并发读（`AXWindowReader`，每个 App 最多等
/// 0.1 秒），总共最多等 `deadline`，没赶上的 App 这次不列，保证弹出快。屏幕上的前后次序
/// 和窗口号来自窗口服务器（公开接口，几毫秒）。桌面号用系统私有接口在运行时找，找不到
/// 就只标「其他桌面」。
enum WindowCatalog {

    /// 一个正在运行的 App，值类型，可以交给后台。
    struct AppInfo: Sendable {
        var pid: pid_t
        var name: String
        var hidden: Bool
        var rank: Int
    }

    /// 一个窗口：给 Core 排序搜索的 `entry`，加上动作要用的 AX 元素。
    struct Item: @unchecked Sendable {
        var entry: WindowSwitcher.Entry
        var element: AXUIElement
        var frame: CGRect
        var windowID: CGWindowID?
    }

    /// 读一遍所有 App 的窗口（最小化、隐藏的也读，过滤和排序在 Core）。
    @MainActor
    static func snapshot(deadline: TimeInterval = 0.12) async -> [Item] {
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
        let ranks = AppRecency.shared.ranks(for: running)
        let apps = running.map {
            AppInfo(pid: $0.processIdentifier, name: $0.localizedName ?? "", hidden: $0.isHidden,
                    rank: ranks[$0.processIdentifier] ?? running.count)
        }
        let raws = await read(apps: apps, deadline: deadline)
        let server = ServerWindows.read()
        return build(raws, server: server)
    }

    // MARK: 后台读

    private struct Read: @unchecked Sendable {
        var app: AppInfo
        var raw: AXWindowReader.Raw
    }

    private static func read(apps: [AppInfo], deadline: TimeInterval) async -> [Read] {
        guard !apps.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            let box = ReadBox(continuation)
            DispatchQueue.global(qos: .userInteractive).async {
                DispatchQueue.concurrentPerform(iterations: apps.count) { i in
                    let app = apps[i]
                    let raws = AXWindowReader.windows(pid: app.pid, timeout: 0.1)
                    box.add(raws.map { Read(app: app, raw: $0) })
                }
                box.finish()
            }
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + deadline) {
                box.finish()
            }
        }
    }

    /// 收集各线程读到的窗口；到点或读完时交出去一次，之后再来的丢掉。
    private final class ReadBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Read] = []
        private var continuation: CheckedContinuation<[Read], Never>?

        init(_ continuation: CheckedContinuation<[Read], Never>) { self.continuation = continuation }

        func add(_ more: [Read]) { lock.withLock { if continuation != nil { items += more } } }

        func finish() {
            let (c, out): (CheckedContinuation<[Read], Never>?, [Read]) = lock.withLock {
                let c = continuation
                continuation = nil
                return (c, items)
            }
            c?.resume(returning: out)
        }
    }

    // MARK: 拼成列表

    private static func build(_ reads: [Read], server: ServerWindows) -> [Item] {
        let spaces = DesktopSpaces.lookup(reads.compactMap { r in r.raw.windowID ?? server.match(r.raw, pid: r.app.pid) })
        var out: [Item] = []
        var nextID = 0
        for r in reads {
            let raw = r.raw
            // 零大小、太小的窗口多半是 App 藏着的工具窗口，不列。最小化的保留。
            if !raw.minimized, raw.frame.width < 40 || raw.frame.height < 30 { continue }
            let id = raw.windowID ?? server.match(raw, pid: r.app.pid)
            let z = id.flatMap { server.zOrder[$0] }
            let desktop: WindowSwitcher.Desktop
            if raw.minimized || r.app.hidden {
                desktop = id.flatMap { spaces?[$0] } ?? .current
            } else if z != nil {
                desktop = .current
            } else {
                desktop = id.flatMap { spaces?[$0] } ?? .other(nil)
            }
            let key = id.map { "w\($0)" }
                ?? "\(r.app.pid)|\(raw.title ?? "")|\(Int(raw.frame.minX)),\(Int(raw.frame.minY))"
            let entry = WindowSwitcher.Entry(
                id: nextID, key: key, pid: r.app.pid, appName: r.app.name,
                title: (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                zOrder: z, appRank: r.app.rank, windowIndex: raw.index,
                minimized: raw.minimized, hidden: r.app.hidden, desktop: desktop)
            nextID += 1
            out.append(Item(entry: entry, element: raw.element, frame: raw.frame, windowID: id))
        }
        return out
    }
}

// MARK: - 窗口服务器

/// 当前桌面屏幕上的普通窗口（第 0 层），从前往后。
struct ServerWindows {
    struct Window {
        var id: CGWindowID
        var pid: pid_t
        var bounds: CGRect
    }

    var onScreen: [Window] = []
    /// 窗口号 → 前后位置，0 最前。
    var zOrder: [CGWindowID: Int] = [:]

    static func read() -> ServerWindows {
        var out = ServerWindows()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return out }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            let id = CGWindowID(number)
            out.zOrder[id] = out.onScreen.count
            out.onScreen.append(Window(id: id, pid: pid_t(pid), bounds: bounds))
        }
        return out
    }

    /// 拿不到 AX 元素的窗口号时，按同进程、同位置大小配对屏幕上的窗口。
    func match(_ raw: AXWindowReader.Raw, pid: pid_t) -> CGWindowID? {
        guard !raw.minimized else { return nil }
        return onScreen.first { $0.pid == pid && WindowPreview.framesMatch($0.bounds, raw.frame) }?.id
    }
}

// MARK: - 桌面号

/// 窗口在哪个桌面（调度中心里的「桌面 N」）。用 SkyLight 的私有函数，运行时找，找不到
/// 或读不出来时返回 nil，界面只标「其他桌面」。每块显示器各自从 1 数起；全屏 App 的
/// 桌面不编号。
enum DesktopSpaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let raw = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(raw, to: type)
    }

    nonisolated(unsafe) private static let mainConnection = symbol("CGSMainConnectionID", as: MainConnection.self)
    nonisolated(unsafe) private static let copyDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)
    nonisolated(unsafe) private static let copySpacesForWindows = symbol("CGSCopySpacesForWindows", as: CopySpacesForWindows.self)

    static func lookup(_ windows: [CGWindowID]) -> [CGWindowID: WindowSwitcher.Desktop]? {
        guard !windows.isEmpty, let mainConnection, let copyDisplaySpaces, let copySpacesForWindows else { return nil }
        let cid = mainConnection()
        guard let raw = copyDisplaySpaces(cid)?.takeRetainedValue(),
              let displays = (raw as NSArray) as? [[String: Any]] else { return nil }
        var number: [UInt64: Int] = [:]
        var current = Set<UInt64>()
        for display in displays {
            if let space = display["Current Space"] as? [String: Any], let id = spaceID(space) { current.insert(id) }
            var n = 0
            for space in (display["Spaces"] as? [[String: Any]]) ?? [] {
                guard let id = spaceID(space) else { continue }
                // type 0 是普通桌面，4 是全屏 App。
                if (space["type"] as? Int ?? 0) == 0 {
                    n += 1
                    number[id] = n
                }
            }
        }
        guard !current.isEmpty else { return nil }
        var out: [CGWindowID: WindowSwitcher.Desktop] = [:]
        for window in Set(windows) {
            // 7 = 当前、其他、用户桌面都查。
            guard let raw = copySpacesForWindows(cid, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue(),
                  let list = (raw as NSArray) as? [NSNumber], let first = list.first else { continue }
            let ids = list.map(\.uint64Value)
            if ids.contains(where: current.contains) {
                out[window] = .current
            } else {
                out[window] = .other(number[first.uint64Value])
            }
        }
        return out
    }

    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        if let n = space["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
        if let n = space["id64"] as? NSNumber { return n.uint64Value }
        return nil
    }
}

// MARK: - App 最近使用

/// App 切到前台的先后，只听系统的「App 已激活」通知，不轮询，不按快捷键时没有开销。
/// 窗口切换器开着时才注册（`start`），关掉功能时 `stop`。
@MainActor
final class AppRecency {
    static let shared = AppRecency()

    private var order: [pid_t] = []
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication { order = [front.processIdentifier] }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let pid else { return }
                AppRecency.shared.touch(pid)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        order = []
    }

    private func touch(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
        if order.count > 64 { order.removeLast(order.count - 64) }
    }

    /// 每个 App 的先后，0 最近。没记到的按系统列表的先后排在后面，最前面的 App 永远是 0。
    func ranks(for apps: [NSRunningApplication]) -> [pid_t: Int] {
        var out: [pid_t: Int] = [:]
        var next = 0
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            out[front] = 0
            next = 1
        }
        let alive = Set(apps.map(\.processIdentifier))
        for pid in order where alive.contains(pid) && out[pid] == nil {
            out[pid] = next
            next += 1
        }
        for app in apps where out[app.processIdentifier] == nil {
            out[app.processIdentifier] = next
            next += 1
        }
        return out
    }
}
