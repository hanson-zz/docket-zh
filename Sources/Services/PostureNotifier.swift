import Foundation
@preconcurrency import UserNotifications

/// Schedules the stand-up reminder's notification.
///
/// One pending request per widget, replaced whenever the next reminder moves:
/// a break is logged, the interval or the hours change, or an ignored one
/// fires and the next repeat comes due. Permission is asked the first time a
/// reminder is scheduled, not at launch.
@MainActor
final class PostureNotifier {
    static let shared = PostureNotifier()

    private var scheduled: [UUID: Date] = [:]
    private var asked = false
    private let presenter = BannerPresenter()

    private init() {}

    private static func identifier(_ id: UUID) -> String { "docket.posture.\(id.uuidString)" }

    /// `next` nil, or notifications turned off, withdraws the pending one.
    func update(_ instance: WidgetInstance, next: Date?) {
        let id = Self.identifier(instance.id)
        guard let next, instance.config.bool("notify", default: true) else {
            if scheduled.removeValue(forKey: instance.id) != nil {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            }
            return
        }
        if let existing = scheduled[instance.id], abs(existing.timeIntervalSince(next)) < 1 { return }
        scheduled[instance.id] = next
        let minutes = max(1, Int(PostureSchedule(config: instance.config).interval / 60))
        Task { await schedule(id: id, at: next, minutes: minutes) }
    }

    private func schedule(id: String, at date: Date, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        // 标题是小组件名，正文配卡片上伸懒腰的小熊猫；卡片自己写「该起来走走了」。
        content.title = tr("久坐提醒")
        content.body = tr("伸个懒腰吧，已坐 \(minutes) 分钟")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

/// Shows the banner even while Docket happens to be the active app, which it
/// is whenever its settings are open.
///
/// 提醒音效管的那几类（喝水等，按通知标识认）由应用自己播放所选的音色，
/// 不再叠一声系统默认提示音；勿扰、屏幕共享和短时间连着几条只响一声都在
/// `ReminderSoundPlayer` 里判断。应用没在运行时系统照通知里带的声音响。
final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// 启动时设成通知代理的那一个。代理是弱引用，放在这里一直留着。
    static let shared = BannerPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        guard let kind = ReminderSoundKind(notificationIdentifier: notification.request.identifier) else {
            return [.banner, .sound]
        }
        await MainActor.run { _ = ReminderSoundPlayer.shared.play(kind) }
        return [.banner, .list]
    }

    /// 点了通知本身：带着小组件 id 的（股票到价等，见 `NotificationRoute`）请扩展栏
    /// 打开那张小组件的面板。所有通知共用这一个代理类，谁先设成代理都一样处理，
    /// 喝水、久坐、播客这些不带 id 的照旧只把码头带到前台。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = NotificationRoute.widgetID(from: response.notification.request.content.userInfo)
        else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: ReminderPopupCenter.openPanelRequest, object: nil,
                                            userInfo: ["id": id.uuidString])
        }
    }
}
