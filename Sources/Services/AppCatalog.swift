import AppKit
import Observation

public struct RunningApp: Identifiable, Sendable, Hashable {
    public var id: String          // bundle identifier
    public var name: String
    public var url: URL?
    public var isActive: Bool
}

/// Knows what is running and what things look like.
///
/// Icon lookup goes through a cache because `NSWorkspace.icon(forFile:)` hits
/// the disk, and the shelf asks for every icon on every layout pass.
@MainActor
@Observable
public final class AppCatalog {
    public static let shared = AppCatalog()

    public private(set) var running: [RunningApp] = []
    /// Membership only, for the hot path.
    ///
    /// `isRunning` is asked once per tile per render - the context menu alone
    /// calls it for every icon on every layout pass - and a linear scan of
    /// `running` there costs hundreds of string compares a frame. Observed,
    /// not ignored, so a launch or quit still invalidates the tiles.
    public private(set) var runningIDs: Set<String> = []
    /// 最近切到的 App（bundle id），最新的在前，应用切换器「最近使用」排序用。
    /// 只记在内存里：码头重启后从当时的前台 App 记起，其余按打开先后。
    public private(set) var recentIDs: [String] = []

    /// 图标换过一次就加一。扩展栏读图标时顺带读它，所以变了会重画。
    public private(set) var iconRevision = 0

    private struct CachedIcon {
        var image: NSImage
        var stamp: AppIconStamp
    }
    @ObservationIgnored private var iconCache: [String: CachedIcon] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sweepTimer: Timer?

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    // App 退出或启动时最常见换图标（拾掇换完图标会重启自己）。
                    self?.sweepIcons()
                }
            })
        }
        // 码头切到前台时也扫一遍，平时每 5 秒扫一次。
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepIcons() }
        })
        let timer = Timer(timeInterval: AppIconStamp.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepIcons() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    public func refresh() {
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .map {
                RunningApp(id: $0.bundleIdentifier!,
                           name: $0.localizedName ?? $0.bundleIdentifier!,
                           url: $0.bundleURL,
                           isActive: $0.isActive)
            }
        runningIDs = Set(running.map(\.id))
        recentIDs = AppSwitcherList.noteActive(running.first(where: \.isActive)?.id, recent: recentIDs)
    }

    public func isRunning(bundleID: String) -> Bool {
        !bundleID.isEmpty && runningIDs.contains(bundleID)
    }

    /// Apps that are running but not pinned to the given profile - the shelf
    /// shows these after a separator, exactly like Apple's Dock.
    public func unpinned(from items: [DockItem]) -> [RunningApp] {
        let pinned = Set(items.compactMap { item -> String? in
            if case .app(_, let bundleID, _) = item { return bundleID }
            return nil
        })
        return running.filter { !pinned.contains($0.id) }
    }

    public func icon(for url: URL) -> NSImage {
        _ = iconRevision
        let key = url.path(percentEncoded: false)
        if let cached = iconCache[key] { return cached.image }
        let icon = Self.trashIcon(for: url) ?? NSWorkspace.shared.icon(forFile: key)
        icon.size = NSSize(width: 128, height: 128)
        iconCache[key] = CachedIcon(image: icon, stamp: AppIconStamp.read(path: key))
        return icon
    }

    /// 看一遍缓存里的图标有没有换过（比较 bundle、`Icon\r`、Info.plist、Resources
    /// 的修改时间），换过的丢掉，让扩展栏重画时重取。不在画的时候做，免得画到一半改状态。
    public func sweepIcons() {
        var changed: [String] = []
        for (key, entry) in iconCache
        where !AppIconStamp.isFresh(cached: entry.stamp, current: AppIconStamp.read(path: key)) {
            changed.append(key)
        }
        guard !changed.isEmpty else { return }
        for key in changed {
            iconCache[key] = nil
            NSWorkspace.shared.noteFileSystemChanged(key)
        }
        iconRevision &+= 1
    }

    /// 右键「刷新图标」：全部丢掉重取。
    public func refreshIcons() {
        for key in iconCache.keys { NSWorkspace.shared.noteFileSystemChanged(key) }
        iconCache.removeAll()
        iconRevision &+= 1
    }

    /// The Trash needs asking for by name.
    ///
    /// `NSWorkspace.icon(forFile:)` cannot see inside `~/.Trash` without Full
    /// Disk Access, and rather than failing it returns a generic document
    /// icon, which is worse than an error because it looks deliberate. The
    /// named system image is not behind any permission.
    ///
    /// Always the empty can, whatever is in there. Telling full from empty
    /// means listing the directory, and that is the same Full Disk Access
    /// again: the most invasive grant macOS has, asked for so a lid can look
    /// fuller. `NSTrashEmpty` is simply what a trash can looks like, and
    /// nobody reads it as a claim that it is empty.
    static func trashIcon(for url: URL) -> NSImage? {
        guard url.standardizedFileURL == Self.trashURL else { return nil }
        return NSImage(named: NSImage.trashEmptyName)
    }

    /// nil on a system with no home Trash, which should not happen but is not
    /// worth trapping over.
    static let trashURL: URL? = try? FileManager.default.url(
        for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    ).standardizedFileURL

    public func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return icon(for: url)
    }

    // MARK: Actions

    /// 只把开着的 App 切到前台，不开窗口。点图标请用 `bringForward`，这个只是它的兜底。
    public func activate(bundleID: String) -> Bool {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else { return false }
        if app.isHidden { app.unhide() }
        return app.activate(options: [])
    }

    /// 点图标打开或叫醒一个 App，和点系统程序坞一样（规则见 Core 的 `AppReopen`）。
    ///
    /// 在运行的也走 `openApplication`：系统给它发 reopen，没窗口的开一个新窗口，
    /// 全最小化的还原一个，有窗口的就切到前台（全屏的会切到它那个桌面）。
    /// 单纯 `activate` 做不到前两件，从不激活的扩展栏面板里调还可能被协作式激活
    /// 静默拒绝，这就是以前「点了日历、邮件没反应」的原因。reopen 报错时再单纯激活一次兜底。
    ///
    /// `completion` 在系统回话后调用，参数是 App 有没有起来或叫醒。
    public func bringForward(bundleID: String, savedURL: URL?,
                             completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        let process = bundleID.isEmpty ? nil
            : NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let registered = bundleID.isEmpty ? nil
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let plan = AppReopen.plan(isRunning: process != nil,
                                  runningURL: process?.bundleURL,
                                  savedURL: savedURL,
                                  registeredURL: registered)
        switch plan {
        case .unavailable:
            completion?(false)
        case .activateOnly:
            completion?(activate(bundleID: bundleID))
        case .launch(let url), .reopen(let url):
            // 藏起来的 App（⌘H）reopen 也会带出来，先取消隐藏更稳。
            if let process, process.isHidden { process.unhide() }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            if case .reopen = plan { configuration.addsToRecentItems = false }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                let ok = app != nil && error == nil
                Task { @MainActor in
                    if AppReopen.fallsBackToActivate(after: plan, succeeded: ok) {
                        completion?(self.activate(bundleID: bundleID))
                    } else {
                        completion?(ok)
                    }
                }
            }
        }
    }

    /// Opens an item, reporting when the launch has settled.
    ///
    /// The completion is what stops a launch bounce. Polling for the app in
    /// `running` instead was wrong twice over: that list is filtered to
    /// `activationPolicy == .regular`, so anything that opens without
    /// registering as an ordinary app never satisfied it, and a path that
    /// fails to resolve launches nothing at all - both left the tile bouncing
    /// until its give-up timer while the app was plainly open.
    public func open(_ item: DockItem,
                     completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        func done(_ ok: Bool) { completion?(ok) }

        switch item {
        case .app(_, let bundleID, let ref):
            // 开着的发 reopen（没窗口开窗、最小化还原），没开的启动；弹不弹跳由扩展栏按是否在运行决定。
            bringForward(bundleID: bundleID, savedURL: ref.resolve(), completion: completion)
        case .folder(_, let ref, _), .file(_, let ref):
            guard let url = ref.resolve() else { return done(false) }
            NSWorkspace.shared.open(url)
            done(true)
        case .link(_, let url, _):
            NSWorkspace.shared.open(url)
            done(true)
        // A group is expanded by the shelf, not opened by the workspace.
        case .spacer, .widget, .group:
            done(false)
        }
    }

    /// Opens whatever a widget points at.
    public func open(_ target: WidgetTarget) {
        switch target {
        case .app(let bundleID):
            bringForward(bundleID: bundleID, savedURL: nil)
        case .settings:
            guard let url = target.settingsURL else { return }
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks an app to quit, the way the Dock's own menu does.
    ///
    /// `terminate()` rather than `forceTerminate()`: a document with unsaved
    /// changes must still get its chance to object.
    public func quit(bundleID: String) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            running.terminate()
        }
    }

    public func reveal(_ item: DockItem) {
        guard let url = item.fileRef?.resolve() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
