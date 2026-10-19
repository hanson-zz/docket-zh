import Foundation

/// 系统通知授权，以及哪些开关要在被关时提示「系统通知已关闭 · 去开启」。
///
/// 久坐、喝水、股票到价、播客新单集、GitHub、Codex 用量、电池、调休提醒原来都只
/// `try? requestAuthorization` 不看结果：用户在系统设置里把码头的通知关了，开关还
/// 开着却从不提醒。这里把授权状态归成三种，再说清楚哪些开关算“发通知的开关”，
/// 界面在开关旁边共用 `NotificationsOffNote` 一个视图。
public enum NotificationAccess: Equatable, Sendable {
    /// 还没读到，或者还没问过：都不提示，第一次真要发通知时系统自己会问。
    case unknown
    case allowed
    /// 用户关了（或者在授权框里点了不允许）。
    case denied

    /// `UNAuthorizationStatus` 的原始值：0 未决定、1 拒绝、2 允许、3 临时、4 短暂。
    /// 放在这里是为了不让 Core 依赖 UserNotifications。
    public init(authorizationStatus raw: Int) {
        switch raw {
        case 1: self = .denied
        case 2, 3, 4: self = .allowed
        default: self = .unknown
        }
    }

    /// 开关开着、通知却被关了，才提示。开关本来就关着的不用提。
    public func warns(switchOn: Bool) -> Bool { self == .denied && switchOn }

    /// 系统设置 ▸ 通知 ▸ 码头。带不上 id 时打开通知总页。
    public static func settingsURL(bundleID: String?) -> URL? {
        let base = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        guard let bundleID, !bundleID.isEmpty else { return URL(string: base) }
        return URL(string: "\(base)?id=\(bundleID)")
    }

    /// 设置 ▸ 小组件 里自动生成的布尔开关中，哪些是“发通知”的。
    /// 键是小组件种类的原始值。电子宠物、播客、喝水、股票的开关在各自面板里，另外接。
    public static let switches: [String: Set<String>] = [
        "posture": ["notify"],
        "podcast": ["notify"],
        "github": ["notify"],
        "ai-usage": ["notify", "notifyDone"],
        "lunar": ["workAlert"],
    ]

    public static func isNotificationSwitch(kind: String, key: String) -> Bool {
        switches[kind]?.contains(key) ?? false
    }

    /// 喝水：提醒间隔不是“关闭”、并且没交给到点弹出卡片时，才走系统通知。
    public static func waterUsesNotifications(every minutes: Int, popupShows: Bool) -> Bool {
        minutes > 0 && !popupShows
    }

    /// 股票：设了到价提醒才会发通知。
    public static func stockUsesNotifications(alertCount: Int) -> Bool { alertCount > 0 }

    /// 电池：充到、低于几档里勾了任意一档，或者蓝牙、充满、过热任意一个开着。
    public static func batteryUsesNotifications(levels: Int, extras: [Bool]) -> Bool {
        levels > 0 || extras.contains(true)
    }
}
