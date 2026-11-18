import AppKit
import Foundation
import Observation

/// 问 Chrome「front window 的 active tab 在不在加载」，给扩展栏上 Chrome 图标的转动用。
///
/// 只在动态图标的 Chrome 开关开着、Chrome 正在运行、扩展栏上有 Chrome 图标时才问：
/// Chrome 在前台约 0.5 秒一次，在后台或低电量 1.5 秒一次。脚本在自己的串行队列上跑，
/// 不阻塞主线程；同一时间只有一个在跑。用户拒绝自动化权限后不再问，图标退回到
/// 「启动那一下转一圈」，绝不显示假进度。
@MainActor @Observable
final class ChromeLoadingMonitor {
    static let shared = ChromeLoadingMonitor()

    /// 当前标签页正在加载。读不到时始终是 false。
    private(set) var loading = false
    /// 读数可不可信；不是 `.available` 时图标走退回方案。
    private(set) var status: LiveChromeAvailability.Status = .unknown

    @ObservationIgnored private var availability = LiveChromeAvailability()
    @ObservationIgnored private var clients: Set<UUID> = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private init() {}

    /// 一个 Chrome 图标说它要不要读数。所有图标都不要了就停。
    func want(_ client: UUID, _ on: Bool) {
        if on {
            let fresh = clients.isEmpty
            clients.insert(client)
            if fresh {
                // 重新开始：开关重开、Chrome 重新启动后再给一次机会。
                availability.reset()
                status = .unknown
            }
            startIfNeeded()
        } else {
            clients.remove(client)
            if clients.isEmpty { stop() }
        }
    }

    private func startIfNeeded() {
        guard loop == nil, !clients.isEmpty, !availability.stopped else { return }
        generation += 1
        let mine = generation
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let wait = await self.tick() else { break }
                try? await Task.sleep(for: .seconds(wait))
            }
            // 只清自己：停掉后又重新开的那一轮不受影响。
            if let self, self.generation == mine { self.loop = nil }
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        if loading { loading = false }
    }

    /// 问一次，返回下一次隔多久；该停时返回 nil。
    private func tick() async -> Double? {
        guard !clients.isEmpty, !availability.stopped else { return nil }
        guard Self.chromeRunning else {
            if loading { loading = false }
            return nil
        }
        let reading = await Self.probe()
        guard !Task.isCancelled, !clients.isEmpty else { return nil }
        let spinning = availability.record(reading)
        if loading != spinning { loading = spinning }
        if status != availability.status { status = availability.status }
        if availability.stopped { return nil }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LiveIconApp.chromeBundleID
        return LiveIconMotion.chromePollInterval(chromeFrontmost: front,
                                                 lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                                 failures: availability.failures)
    }

    private static var chromeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: LiveIconApp.chromeBundleID).isEmpty
    }

    // MARK: AppleScript

    nonisolated private static let queue = DispatchQueue(label: "dockling.live-icons.chrome", qos: .utility)

    /// 只在 `queue` 上碰，不用加锁。编译一次反复用。
    nonisolated(unsafe) private static var compiled: NSAppleScript?

    /// 先判断 Chrome 还在不在跑，免得 `tell` 把刚退出的 Chrome 又拉起来。
    nonisolated private static let source = """
    if application id "com.google.Chrome" is running then
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then return false
            return loading of active tab of front window
        end tell
    end if
    return false
    """

    nonisolated private static func probe() async -> LiveChromeReading {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: run()) }
        }
    }

    nonisolated private static func run() -> LiveChromeReading {
        let script: NSAppleScript
        if let cached = compiled {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed }
            made.compileAndReturnError(nil)
            compiled = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return LiveChromeReading(loading: nil, errorCode: (error[NSAppleScript.errorNumber] as? Int) ?? 0)
        }
        return LiveChromeReading(loading: result.booleanValue, errorCode: nil)
    }
}
