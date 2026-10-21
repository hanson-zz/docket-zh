import AppKit
import ApplicationServices
import Foundation

/// 面板按钮控制网易云音乐、QQ 音乐、小宇宙（没有 AppleScript、读数来自系统「正在播放」的来源）。
///
/// 以前只模拟键盘媒体键：要辅助功能权限，没给时每按一次弹一次系统提示后什么都不做；
/// 码头是临时签名，每换一版权限就对不上新程序，设置里开关还亮着、实际已经失效，
/// 于是按钮看起来完全没反应。
///
/// 现在按 Core `NowPlayingControl.routes` 的顺序试：先发系统「正在播放」命令（经
/// osascript，不要任何权限），第一次发完核对读数；不灵再点 App 菜单栏的控制项，
/// 最后才模拟媒体键，这两条要辅助功能权限。全部在自己的串行队列上跑，不占主线程，
/// 也不挡 `Bridge` 每秒的读数。
enum NowPlayingCommander {
    private static let queue = DispatchQueue(label: "com.docket-zh.music.control")

    /// 系统命令对每个来源灵不灵。只在 `queue` 上读写。
    nonisolated(unsafe) private static var verdicts: [MusicSource: NowPlayingControl.Verdict] = [:]

    static func send(_ command: NowPlayingControl.Command, to source: MusicSource) {
        queue.async {
            let trusted = AXIsProcessTrusted()
            for route in NowPlayingControl.routes(remote: verdicts[source] ?? .unknown, trusted: trusted) {
                if perform(route, command, source) { break }
            }
            let hint = NowPlayingControl.needsAccessibility(remote: verdicts[source] ?? .unknown,
                                                            trusted: AXIsProcessTrusted())
            Task { @MainActor in
                MusicService.shared.setControlNeedsAccessibility(hint, for: source)
            }
        }
    }

    /// 这条路走通了（或者已经没有更好的路）就返回 true，不再往下试。
    private static func perform(_ route: NowPlayingControl.Route, _ command: NowPlayingControl.Command,
                                _ source: MusicSource) -> Bool {
        switch route {
        case .remote:
            return remote(command, source)
        case .menu:
            return MenuPress.press(command, bundleID: source.bundleID)
        case .mediaKey:
            MediaKeys.press(command.mediaKey)
            return true
        }
    }

    private static func remote(_ command: NowPlayingControl.Command, _ source: MusicSource) -> Bool {
        let verdict = verdicts[source] ?? .unknown
        guard NowPlayingControl.verifies(verdict) else {
            // 核对过灵的照发；核对过不灵、又没权限走别的路时也发一次，聊胜于无。
            _ = NowPlayingReader.sendCommand(command.remoteCode)
            return true
        }
        let before = snapshot(source)
        guard NowPlayingReader.sendCommand(command.remoteCode) else {
            verdicts[source] = .fails
            return false
        }
        // 最多等 1.5 秒看读数变没变。
        var last: NowPlayingControl.Snapshot?
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.25)
            guard let now = snapshot(source) else { continue }
            last = now
            if before != nil, NowPlayingControl.took(command, before: before, after: now) {
                verdicts[source] = .works
                return true
            }
        }
        // 前后都读到了、确实没变才判不灵；读不到就下次再核对，不重复按。
        guard before != nil, last != nil else { return true }
        verdicts[source] = .fails
        return false
    }

    private static func snapshot(_ source: MusicSource) -> NowPlayingControl.Snapshot? {
        guard let info = NowPlayingReader.info(),
              let track = info.track(for: source.bundleID, now: .now) else { return nil }
        return .init(title: track.title, isPlaying: track.isPlaying, elapsed: track.elapsed)
    }
}

/// 点播放器菜单栏里的「播放 / 暂停」「下一首」「上一首」，用辅助功能（AXUIElement），
/// 不需要「自动化」权限，也只会作用在这个 App 上。挑哪一项在 Core `NowPlayingControl.menuItem`。
enum MenuPress {
    static func press(_ command: NowPlayingControl.Command, bundleID: String) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let raw = copy(root, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return false
        }
        let bar = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, 0.5)
        var menus: [NowPlayingControl.Menu] = []
        var elements: [[AXUIElement]] = []
        for barItem in children(bar) {
            AXUIElementSetMessagingTimeout(barItem, 0.5)
            let title = (copy(barItem, kAXTitleAttribute) as? String) ?? ""
            let items = children(barItem).first.map(children) ?? []
            for item in items { AXUIElementSetMessagingTimeout(item, 0.5) }
            menus.append(.init(title: title, items: items.map { (copy($0, kAXTitleAttribute) as? String) ?? "" }))
            elements.append(items)
        }
        guard let hit = NowPlayingControl.menuItem(for: command, in: menus) else { return false }
        let item = elements[hit.menu][hit.item]
        if let enabled = copy(item, kAXEnabledAttribute) as? Bool, !enabled { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
