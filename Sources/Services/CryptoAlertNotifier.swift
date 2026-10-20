import Foundation
@preconcurrency import UserNotifications

/// 加密货币到价提醒（Pro）的系统通知。到没到价、提醒后自动关掉由加密货币卡片判断
/// （见 `CryptoWatch.due`、`CryptoWatch.firing`），这里只管发。第一次发的时候才请求
/// 通知权限；点开通知打开这张卡片的面板（`userInfo` 带小组件 id，见 `NotificationRoute`）。
@MainActor
final class CryptoAlertNotifier {
    static let shared = CryptoAlertNotifier()

    private var asked = false
    private let presenter = BannerPresenter()

    private init() {}

    /// `比特币高于 ¥800,000 了`，正文写现价，并说这条已经关掉。
    func post(_ alert: CryptoAlert, name: String, price: Double, widget: UUID) {
        let title = tr("\(CryptoWatch.title(alert, name: name)) 了")
        let now = CryptoMarket.priceText(price, currency: alert.currency)
        let body = tr("现价 \(now)。这条提醒已自动关掉，可以在面板里再打开。")
        let identifier = "docket.crypto.\(widget.uuidString).\(alert.coin)\(alert.above ? ">" : "<")"
        let info = NotificationRoute.userInfo(widget: widget)
        Task { await send(title: title, body: body, identifier: identifier, info: info) }
    }

    private func send(title: String, body: String, identifier: String, info: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = info
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }
}
