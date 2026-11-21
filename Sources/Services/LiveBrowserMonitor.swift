import AppKit
import ApplicationServices
import Observation

/// Chrome、Safari 动态图标的真实状态：下载、播放，以及 Safari 的加载（Chrome 的加载另由
/// `ChromeLoadingMonitor` 用 AppleScript 读）。
///
/// - 下载：只看「下载」文件夹第一层的 .download（Safari）和 .crdownload（Chrome），
///   30 秒内还在变的才算在下。Safari 读包里 Info.plist 的字节数画进度，Chrome 只挂徽标。
/// - 播放：系统音频进程里有没有这个浏览器（含 WebKit 网页进程、Chrome Helper）在出声，
///   跟「App 音量」同一种读法，不录音、不读内容。
/// - Safari 加载：窗口工具栏上有没有「停止载入」按钮（要辅助功能权限，只读按钮名字）。
///
/// 只有扩展栏上挂着这两个图标、开关开着、浏览器在运行时才读，没人用就停。读不到就是默认值（不画）。
@MainActor @Observable
final class LiveBrowserMonitor {
    static let shared = LiveBrowserMonitor()
    static let interval: TimeInterval = 1.5

    private(set) var states: [LiveBrowser: LiveBrowserState] = [:]

    @ObservationIgnored private var users: [LiveBrowser: Int] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?

    func state(_ browser: LiveBrowser) -> LiveBrowserState { states[browser] ?? LiveBrowserState() }

    func want(_ browser: LiveBrowser, _ on: Bool) {
        users[browser, default: 0] += on ? 1 : -1
        if users[browser, default: 0] <= 0 {
            users[browser] = nil
            states[browser] = nil
        }
        if users.isEmpty {
            loop?.cancel()
            loop = nil
        } else if loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                    try? await Task.sleep(for: .seconds(lowPower ? Self.interval * 2 : Self.interval))
                }
            }
        }
    }

    private func poll() async {
        let wanted = Set(users.keys)
        let running = wanted.filter { Self.pid(of: $0) != nil }
        var next: [LiveBrowser: LiveBrowserState] = [:]
        guard !running.isEmpty else {
            if !states.isEmpty { states = [:] }
            return
        }
        let playing = Self.playing(running)
        let safariPID = running.contains(.safari) ? Self.pid(of: .safari) : nil
        let (downloads, safariLoading) = await withCheckedContinuation { done in
            LiveBrowserReader.queue.async {
                let d = LiveBrowserReader.downloads(now: Date())
                let l = safariPID.map { LiveBrowserReader.safariLoading(pid: $0) } ?? false
                done.resume(returning: (d, l))
            }
        }
        guard !Task.isCancelled else { return }
        for browser in running where users[browser] != nil {
            next[browser] = LiveBrowserState(loading: browser == .safari && safariLoading,
                                             download: downloads[browser] ?? .none,
                                             playing: playing.contains(browser))
        }
        if next != states { states = next }
    }

    private static func bundleID(_ browser: LiveBrowser) -> String {
        browser == .chrome ? LiveIconApp.chromeBundleID : LiveBrowser.safariBundleID
    }

    private static func pid(of browser: LiveBrowser) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID(browser)).first?.processIdentifier
    }

    /// 哪个浏览器在出声：先问系统这个进程归谁管（Safari 的声音从 WebKit 进程出来），
    /// 问不到再按 bundle id 前缀认（Chrome Helper）。
    private static func playing(_ browsers: Set<LiveBrowser>) -> Set<LiveBrowser> {
        let ids = browsers.map(bundleID)
        var result: Set<LiveBrowser> = []
        for process in CoreAudioReader.processes() where process.isRunningOutput && !process.bundleID.isEmpty {
            let owner = Responsibility.ownerBundleID(of: process.pid)
                ?? AudioAppList.owner(of: process.bundleID, apps: ids)
            if let browser = LiveBrowser(bundleID: owner), browsers.contains(browser) {
                result.insert(browser)
            }
        }
        return result
    }
}

/// 后台读文件夹和辅助功能，只在 `queue` 上用。
enum LiveBrowserReader {
    static let queue = DispatchQueue(label: "com.docket-zh.live-browser", qos: .utility)

    static func downloads(now: Date) -> [LiveBrowser: LiveBrowserDownload] {
        let fm = FileManager.default
        guard let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [:] }
        var parts: [LiveBrowser: [(done: Double, total: Double)?]] = [:]
        for item in items {
            guard let browser = LiveBrowserDownload.browser(forExtension: item.pathExtension),
                  let modified = latestModification(item),
                  LiveBrowserDownload.isActive(modified: modified, now: now) else { continue }
            switch browser {
            case .safari:
                let plist = NSDictionary(contentsOf: item.appendingPathComponent("Info.plist")) as? [String: Any]
                parts[.safari, default: []].append(plist.flatMap(LiveBrowserDownload.safariBytes))
            case .chrome:
                parts[.chrome, default: []].append(nil)
            }
        }
        return parts.mapValues(LiveBrowserDownload.combine)
    }

    /// 文件本身或包里各文件最近一次改动。
    private static func latestModification(_ url: URL) -> Date? {
        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let inner = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in inner {
                if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   date > (latest ?? .distantPast) {
                    latest = date
                }
            }
        }
        return latest
    }

    /// Safari 主窗口工具栏上有没有「停止载入」按钮。没权限、找不到都算没在加载。
    static func safariLoading(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var raw: CFTypeRef?
        let window: AXUIElement
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &raw) == .success, let w = raw {
            window = w as! AXUIElement
        } else if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
                  let list = raw as? [AXUIElement], let first = list.first {
            window = first
        } else {
            return false
        }
        guard let toolbar = children(window).first(where: { role($0) == kAXToolbarRole as String }) else { return false }
        var budget = 300
        return search(toolbar, depth: 0, budget: &budget)
    }

    private static func search(_ element: AXUIElement, depth: Int, budget: inout Int) -> Bool {
        budget -= 1
        guard budget > 0, depth < 8 else { return false }
        if role(element) == kAXButtonRole as String {
            let texts = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].compactMap {
                string(element, $0 as String)
            }
            if LiveSafariLoading.isStopButton(texts) { return true }
            return false
        }
        for child in children(element) {
            if search(child, depth: depth + 1, budget: &budget) { return true }
        }
        return false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    private static func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute as String) }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}
