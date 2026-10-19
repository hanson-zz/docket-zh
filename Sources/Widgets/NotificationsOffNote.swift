import AppKit
import Observation
import SwiftUI
@preconcurrency import UserNotifications

/// 读系统通知授权。只读不问：问是第一次真要发通知时各自的通知器做的事。
///
/// 全应用共用一个：提示第一次出现时读一次，应用变成活跃时再读一次。码头多半不在
/// 前台（扩展栏是不激活本应用的面板），从系统设置改完回来也不一定收到“变成活跃
/// 应用”的通知，所以只在读到“已关闭”且还有提示挂在界面上时，由这一个监视器每几秒
/// 重读一次，读到恢复就停。
@MainActor
@Observable
final class NotificationAccessMonitor {
    static let shared = NotificationAccessMonitor()

    private(set) var access: NotificationAccess = .unknown

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    private init() {}

    /// 有一条提示出现在界面上。第一条出现时读一次并开始听“应用变成活跃”。
    func attach() {
        watchers += 1
        guard watchers == 1 else { return }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    let monitor = NotificationAccessMonitor.shared
                    guard monitor.watchers > 0 else { return }
                    await monitor.refresh()
                }
            }
        }
        Task { await refresh() }
    }

    /// 提示离开界面。最后一条离开时停掉轮询。
    func detach() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard NotificationAccess.canReadSettings(bundleURL: Bundle.main.bundleURL) else { return }
        let raw = await Self.readStatus()
        access = NotificationAccess(authorizationStatus: raw)
        updatePolling()
    }

    /// 在系统线程上读，只把原始值带回主 actor。
    private nonisolated static func readStatus() async -> Int {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus.rawValue
    }

    /// 只有“已关闭”且有人在看时才轮询，全应用最多一个循环。
    private func updatePolling() {
        guard access == .denied, watchers > 0 else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.pollTask = nil
            await self.refresh()
        }
    }

    static func openSettings() {
        guard let url = NotificationAccess.settingsURL(bundleID: Bundle.main.bundleIdentifier) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 发通知的开关旁边那一行：通知被系统关了时显示「系统通知已关闭 · 去开启」，
/// 点了打开 系统设置 ▸ 通知 ▸ 码头。授权正常、或者开关本来关着时什么都不画。
///
/// 久坐、喝水、股票到价、播客、GitHub、Codex 用量、电池、调休提醒、电子宠物
/// 共用这一个视图，面板的深色玻璃和设置窗口的表单里都看得清（橙色字）。
struct NotificationsOffNote: View {
    /// 这个开关此刻开着（会发通知）。
    var active: Bool = true
    var preview: Bool = false

    @State private var monitor = NotificationAccessMonitor.shared

    var body: some View {
        // 垫一块 0×0 的透明：什么都不画时 .task 也照样跑（空视图上的 .task 不会触发）。
        ZStack(alignment: .leading) {
            Color.clear.frame(width: 0, height: 0)
            if monitor.access.warns(switchOn: active) {
                Button {
                    guard !preview else { return }
                    NotificationAccessMonitor.openSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(tr("系统通知已关闭 · 去开启"))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.orange)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("码头的通知在系统设置里被关掉了，开关开着也不会提醒。点按打开系统设置的通知页。"))
                .accessibilityLabel(tr("系统通知已关闭，点按去开启"))
            }
        }
        .task(id: active) {
            guard active, !preview,
                  NotificationAccess.canReadSettings(bundleURL: Bundle.main.bundleURL) else { return }
            monitor.attach()
            // 挂到视图消失或开关关掉（任务被取消）为止，再交还给共享监视器。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
            monitor.detach()
        }
    }
}
