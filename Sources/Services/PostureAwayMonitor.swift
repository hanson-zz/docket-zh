import AppKit
import CoreGraphics
import Foundation
import Observation

/// 久坐提醒的离开检测：看着系统空闲时间和锁屏、休眠、屏保、显示器睡眠、切换用户，
/// 离开电脑满设定的时间（默认 5 分钟，卡片设置里可选 2、5、10）就自动算一次起身休息。
///
/// - 每 10 秒读一次距上次键盘鼠标输入的秒数（`CGEventSource`，不需要任何权限）。
/// - 锁屏、屏保（分布式通知）和休眠、显示器睡眠、切换用户（NSWorkspace）一来就算离开。
/// - 判断在 Core 的 `PostureAway.Tracker` 和 `PostureAway.steps` 里，这里只喂事件、
///   按结果写回每张开着离开检测的久坐卡片（`PostureLog`）：离开满门槛记一次「自动」
///   休息（起身时刻是离开那一刻）、计时清零，回来时从回来那一刻重新计时。
/// - 离开期间 `isAway` 为真，卡片据此不排通知、不弹到点；离开那一刻顺手把已排的
///   久坐通知撤掉（卡片可能不在屏幕上，等不到它重画）。
///
/// 和 `TimedAlertDriver` 一样从启动起就看着每个布局里的久坐卡片，DocketApp 接上 `widgets`。
@MainActor @Observable
final class PostureAwayMonitor {
    static let shared = PostureAwayMonitor()

    /// 现在离开着电脑。卡片和面板读它决定到点提不提醒。
    private(set) var isAway = false

    /// 每个布局里的每个小组件。DocketApp 接上。
    @ObservationIgnored var widgets: @MainActor () -> [WidgetInstance] = { [] }

    @ObservationIgnored private var tracker = PostureAway.Tracker(
        idleAfter: TimeInterval(PostureAway.defaultMinutes * 60))
    /// 这次离开已经算过休息的卡片。
    @ObservationIgnored private var rested: Set<UUID> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard timer == nil else { return }
        // 上次退出时还没回来的那段（退出或崩溃在离开中），这次启动就算回来了。
        let now = Date.now
        for instance in postures() where PostureAway.segments(instance.config, now: now).contains(where: { $0.end == nil }) {
            PostureLog.resume(instance, at: now, now: now)
        }

        let timer = Timer(timeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { PostureAwayMonitor.shared.sample() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, PostureAway.Event)] = [
            (NSWorkspace.willSleepNotification, .blocked(.asleep)),
            (NSWorkspace.didWakeNotification, .unblocked(.asleep)),
            (NSWorkspace.screensDidSleepNotification, .blocked(.displayOff)),
            (NSWorkspace.screensDidWakeNotification, .unblocked(.displayOff)),
            (NSWorkspace.sessionDidResignActiveNotification, .blocked(.userSwitched)),
            (NSWorkspace.sessionDidBecomeActiveNotification, .unblocked(.userSwitched)),
        ]
        for (name, event) in pairs {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PostureAwayMonitor.shared.feed(event) }
            })
        }

        // 锁屏和屏保是别的进程发的分布式通知，普通的通知中心收不到。
        let distributed = DistributedNotificationCenter.default()
        let named: [(String, PostureAway.Event)] = [
            ("com.apple.screenIsLocked", .blocked(.locked)),
            ("com.apple.screenIsUnlocked", .unblocked(.locked)),
            ("com.apple.screensaver.didstart", .blocked(.screensaver)),
            ("com.apple.screensaver.didstop", .unblocked(.screensaver)),
        ]
        for (name, event) in named {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil,
                                                                queue: .main) { _ in
                MainActor.assumeIsolated { PostureAwayMonitor.shared.feed(event) }
            })
        }
    }

    /// 开着离开检测的久坐卡片。
    private func postures() -> [WidgetInstance] {
        widgets().filter { $0.kind == .posture && PostureAway.isEnabled($0.config) }
    }

    private func sample() {
        feed(.idle(Self.idleSeconds()))
    }

    private func feed(_ event: PostureAway.Event, now: Date = .now) {
        let list = postures()
        // 门槛取所有开着的卡片里最短的；每张卡片满不满自己的门槛由 `steps` 再看。
        tracker.idleAfter = list.map { PostureAway.threshold($0.config) }.min()
            ?? TimeInterval(PostureAway.defaultMinutes * 60)
        let change = tracker.handle(event, at: now)

        switch change {
        case .left:
            isAway = true
            for instance in list { PostureNotifier.shared.update(instance, next: nil) }
        case .back(let start, let at):
            isAway = false
            for instance in list {
                apply(PostureAway.steps(instance.config, schedule: PostureSchedule(config: instance.config),
                                        since: start, now: now, back: at,
                                        rested: rested.contains(instance.id)), to: instance, now: now)
                reschedule(WidgetWriter.current(instance.id) ?? instance, now: now)
            }
            rested = []
            return
        case nil:
            break
        }

        // 还在离开：满门槛的卡片算一次休息。
        guard let start = tracker.since else { return }
        for instance in list where !rested.contains(instance.id) {
            apply(PostureAway.steps(instance.config, schedule: PostureSchedule(config: instance.config),
                                    since: start, now: now, back: nil, rested: false), to: instance, now: now)
        }
    }

    private func apply(_ steps: [PostureAway.Step], to instance: WidgetInstance, now: Date) {
        for step in steps {
            // 每一步都读最新存着的那份，前一步刚写过。
            let current = WidgetWriter.current(instance.id) ?? instance
            switch step {
            case .rest(let since, let logged):
                rested.insert(instance.id)
                PostureLog.logAutoBreak(current, since: since, logged: logged, now: now)
            case .resume(let at):
                PostureLog.resume(current, at: at, now: now)
            }
        }
    }

    /// 回来后把通知排回去，和卡片算的一样（卡片不在屏幕上时等不到它重画）。
    private func reschedule(_ instance: WidgetInstance, now: Date) {
        let timer = TimerStateProvider.shared.state
        guard !SitFocus.postureYields(to: timer, now: now) else { return }
        let raw = instance.config.double("lastBreak")
        let lastBreak = SitFocus.lastBreak(posture: raw > 0 ? Date(timeIntervalSince1970: raw) : nil, timer: timer)
        PostureNotifier.shared.update(instance, next: PostureSchedule(config: instance.config)
            .nextReminder(lastBreak: lastBreak, now: now))
    }

    /// 距上次键盘、鼠标、触控板输入多少秒。`kCGAnyInputEventType`（~0）在 Swift 里
    /// 造不出来时，退回几种常见输入里最近的那个。
    private static func idleSeconds() -> TimeInterval {
        if let any = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        }
        let kinds: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .scrollWheel, .leftMouseDragged, .flagsChanged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
