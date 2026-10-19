import AppKit
import Observation
import SwiftUI
@preconcurrency import UserNotifications

/// 读系统通知授权。只读不问：问是第一次真要发通知时各自的通知器做的事。
///
/// 码头多半不在前台（扩展栏是不激活本应用的面板），从系统设置改完回来也不一定
/// 收到“变成活跃应用”的通知，所以提示还挂在界面上时每几秒重读一次，读的是本机
/// 的设置，不费事。
@MainActor
@Observable
final class NotificationAccessMonitor {
    static let shared = NotificationAccessMonitor()

    private(set) var access: NotificationAccess = .unknown

    private init() {}

    func refresh() {
        guard NotificationAccess.canReadSettings(bundleURL: Bundle.main.bundleURL) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let raw = settings.authorizationStatus.rawValue
            Task { @MainActor in
                NotificationAccessMonitor.shared.access = NotificationAccess(authorizationStatus: raw)
            }
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
            while !Task.isCancelled {
                monitor.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}
