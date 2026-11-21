import AppKit
import ApplicationServices
import Observation

/// 动态图标「消息未读」的数据：每 2 秒读一次 Apple 程序坞上信息、微信、邮件自己的角标
/// （AXStatusLabel，跟刘海消息同一种读法），只读数字，不碰聊天内容。
///
/// 没给辅助功能权限、程序坞上没有这个 App、读失败时是「未知」，图标保持原样。
/// 只有扩展栏上挂着这几个图标、开着动态图标时才读（`retain` / `release` 计数），
/// 没人用就停。读程序坞在后台队列上，结果回主线程发布。
@MainActor @Observable
final class LiveBadgeMonitor {
    static let shared = LiveBadgeMonitor()
    static let interval: TimeInterval = 2

    private(set) var readings: [LiveBadgeApp: LiveBadgeReading] = [:]
    private(set) var pulses: [LiveBadgeApp: LiveBadgePulse] = [:]

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let reader = LiveBadgeDockReader()

    func reading(_ app: LiveBadgeApp) -> LiveBadgeReading { readings[app] ?? .unknown }
    func pulseGeneration(_ app: LiveBadgeApp) -> Int { pulses[app]?.generation ?? 0 }

    func retain() {
        users += 1
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                try? await Task.sleep(for: .seconds(lowPower ? Self.interval * 2 : Self.interval))
            }
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        loop?.cancel()
        loop = nil
    }

    private func poll() async {
        guard AXIsProcessTrusted() else {
            if !readings.isEmpty { readings = [:] }
            return
        }
        let reader = self.reader
        let raw: [LiveBadgeApp: NotchDockBadge] = await withCheckedContinuation { done in
            LiveBadgeDockReader.queue.async { done.resume(returning: reader.sample()) }
        }
        let now = Date()
        var next: [LiveBadgeApp: LiveBadgeReading] = [:]
        var nextPulses = pulses
        for app in LiveBadgeApp.allCases {
            let reading = raw[app].map(LiveBadgeReading.init) ?? .unknown
            next[app] = reading
            var pulse = nextPulses[app] ?? LiveBadgePulse()
            pulse.update(reading, now: now)
            nextPulses[app] = pulse
        }
        if next != readings { readings = next }
        if nextPulses != pulses { pulses = nextPulses }
    }
}

/// 记住三个 App 在程序坞里的那一项，只读它们的 AXStatusLabel；每 20 秒、读失败或程序坞
/// 换了进程时重新找一遍。只在 `queue` 上用。
final class LiveBadgeDockReader: @unchecked Sendable {
    nonisolated static let queue = DispatchQueue(label: "com.docket-zh.live-badge.dock", qos: .utility)
    private static let refreshInterval: TimeInterval = 20

    private var items: [LiveBadgeApp: AXUIElement] = [:]
    private var dockPID: pid_t = 0
    private var lastRefresh: Date?

    func sample(now: Date = Date()) -> [LiveBadgeApp: NotchDockBadge] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated }) else { return [:] }
        let pid = dock.processIdentifier
        if pid != dockPID || lastRefresh.map({ now.timeIntervalSince($0) > Self.refreshInterval }) ?? true {
            refresh(pid: pid, now: now)
        }
        var badges: [LiveBadgeApp: NotchDockBadge] = [:]
        var failed = false
        for (app, item) in items {
            AXUIElementSetMessagingTimeout(item, 0.2)
            var label: CFTypeRef?
            switch AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &label) {
            case .success:
                badges[app] = NotchDockBadge.parse(label as? String)
            case .noValue, .attributeUnsupported:
                badges[app] = NotchDockBadge.none
            default:
                failed = true
            }
        }
        if failed { lastRefresh = nil }
        return badges
    }

    private func refresh(pid: pid_t, now: Date) {
        dockPID = pid
        lastRefresh = now
        items = [:]
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var lists: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &lists) == .success,
              let children = lists as? [AXUIElement] else { return }
        for list in children {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &raw) == .success,
                  let entries = raw as? [AXUIElement] else { continue }
            for item in entries.prefix(80) {
                AXUIElementSetMessagingTimeout(item, 0.2)
                var url: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url) == .success,
                      let bundleURL = url as? URL,
                      let id = Bundle(url: bundleURL)?.bundleIdentifier,
                      let found = LiveBadgeApp(bundleID: id),
                      items[found] == nil else { continue }
                items[found] = item
            }
        }
    }
}
