import AppKit

/// 打字音效：开着且有输入监控权限时装上键盘监听，按键交给 `TypingSoundEngine` 出声。
///
/// - 默认关。关掉、没权限时不装监听，引擎也停掉、声音放掉。
/// - 权限可能随时在系统设置里被撤销或刚给：开着的时候每 3 秒、App 变成前台时各看一次，
///   没了就撤掉监听（不留一个被系统停掉的空监听），有了就装上。
/// - 真正响哪一款看 `TypingSoundGate.effectiveChoice`：没解锁时 Pro 款按青轴，选择不改。
///   授权会在后台变（试用到期、刚激活），同一个定时检查顺带看一眼。
/// - App 退出时 `shutdown`：撤监听、停引擎。
@MainActor
final class TypingSoundController {
    static let shared = TypingSoundController()

    private var settings = TypingSoundSettings()
    private let tap = TypingSoundTap()
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var pruned = false

    private init() {}

    func apply(_ next: TypingSoundSettings) {
        settings = next
        if !pruned {
            // 第一次拿到设置：清掉设置里已经没有的包的文件夹（恢复旧备份、上次没删干净）。
            pruned = true
            let ids = Set(next.packs.map(\.id))
            Task.detached(priority: .utility) { TypingSoundPackStore.prune(keeping: ids) }
        }
        refresh()
    }

    /// 撤监听、停引擎。App 退出时调。
    func shutdown() {
        stopMonitoring()
        tap.stop()
        TypingSoundEngine.shared.shutdown()
    }

    /// 设置里的「试听」：按现在选的那一款放一串，没开总开关、没权限也能听。
    /// 免费用户选着 Pro 款时按青轴放（和真正打字时一样）。
    func preview(_ settings: TypingSoundSettings) {
        let choice = TypingSoundGate.effectiveChoice(settings, unlocked: ProAccess.isUnlocked)
        TypingSoundEngine.shared.preview(choice: choice, packFolder: Self.packFolder(choice),
                                         volume: settings.clampedVolume)
    }

    private static func packFolder(_ choice: TypingSoundChoice) -> URL? {
        if case .pack(let id) = choice { return TypingSoundPackStore.url(for: id) }
        return nil
    }

    private func refresh() {
        guard settings.enabled else {
            stopMonitoring()
            tap.stop()
            TypingSoundEngine.shared.shutdown()
            return
        }
        startMonitoring()
        let choice = TypingSoundGate.effectiveChoice(settings, unlocked: ProAccess.isUnlocked)
        TypingSoundEngine.shared.configure(choice: choice, packFolder: Self.packFolder(choice),
                                           volume: settings.clampedVolume)
        let permitted = TypingSoundPermission.granted
        if TypingSoundGate.shouldListen(settings, permitted: permitted) {
            // 监听被系统停了又打不开（多半是权限刚被撤销又给回来）：重装一个。
            if tap.isRunning, !tap.isEnabled { tap.stop() }
            _ = tap.start()
        } else {
            tap.stop()
        }
    }

    private func startMonitoring() {
        if timer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }
}
