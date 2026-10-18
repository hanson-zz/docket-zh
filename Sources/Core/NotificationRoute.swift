import Foundation

/// 系统通知点开以后去哪：通知的 `userInfo` 里带上小组件 id，点通知时由
/// `BannerPresenter`（应用里所有通知共用的那一个代理类）读出来，请扩展栏打开
/// 那张小组件的面板。没带 id 的通知（喝水、久坐、播客这些）照旧只是把码头带到前台。
public enum NotificationRoute {
    /// `userInfo` 里放小组件 id 的键。
    public static let widgetKey = "docketWidgetID"

    /// 发通知时放进 `UNMutableNotificationContent.userInfo` 的内容。
    public static func userInfo(widget: UUID) -> [String: String] {
        [widgetKey: widget.uuidString]
    }

    /// 点开的通知要打开哪张小组件。没带、带的不是 id 时是 nil。
    public static func widgetID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo[widgetKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
