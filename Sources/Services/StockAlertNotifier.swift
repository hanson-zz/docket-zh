import Foundation
@preconcurrency import UserNotifications

/// 股票到价提醒的系统通知。每条提醒只发一次：发没发过记在小组件自己的设置
/// `alertsFired` 里，由股票卡片判断（见 `StockBoard.newlyReached`），这里只管发。
/// 第一次发的时候才请求通知权限。点开通知打开这张股票卡片的面板：`userInfo`
/// 带小组件 id，由 `BannerPresenter` 处理（见 `NotificationRoute`）。
@MainActor
final class StockAlertNotifier {
    static let shared = StockAlertNotifier()

    private var asked = false
    private let presenter = BannerPresenter()

    private init() {}

    /// `AAPL 到 237.00 了`，正文写现价和是涨到还是跌到。
    func post(_ alert: StockBoard.Alert, name: String, price: Double, widget: UUID) {
        let title = tr("\(name) 到 \(StockBoard.priceText(alert.price)) 了")
        let body = alert.above
            ? tr("现价 \(StockBoard.priceText(price))，已涨到你设的提醒价。")
            : tr("现价 \(StockBoard.priceText(price))，已跌到你设的提醒价。")
        let identifier = "docket.stock.\(alert.text)"
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
