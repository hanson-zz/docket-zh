import AppKit
import EventKit
import Observation

/// 程序坞日历动态图标的数据：今天的日程，从共用的 `CalendarEventStore` 读。
///
/// 只有扩展栏上挂着日历图标、开着这个动态图标时才读（`retain` / `release` 计数），没人用就停。
/// 日程库变了（`.EKEventStoreChanged`，含 iCloud 同步）、过了零点、改了系统时间时马上重读，
/// 平时每 5 分钟补读一次。不要授权、不弹框：没有日历权限时是空的，图标保持系统原样。
/// 读到的东西只在内存里，不写盘、不上传。
@MainActor @Observable
final class LiveCalendarMonitor {
    static let shared = LiveCalendarMonitor()
    static let refreshInterval: TimeInterval = 5 * 60

    private(set) var events: [LiveCalendarEvent] = []

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// 悬停列表：今天还没结束的几场。
    func agenda(now: Date = .now) -> [LiveCalendarEvent] {
        LiveCalendar.agenda(events, now: now, calendar: .current)
    }

    func retain() {
        users += 1
        guard loop == nil else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged, .NSSystemClockDidChange,
                     .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LiveCalendarMonitor.shared.reload() }
            })
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.reload()
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                try? await Task.sleep(for: .seconds(lowPower ? Self.refreshInterval * 2 : Self.refreshInterval))
            }
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        loop?.cancel()
        loop = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func reload() {
        let next = CalendarEventStore.todayForLiveIcon(now: .now)
        if next != events { events = next }
    }
}
