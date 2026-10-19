import Foundation

/// 行情断网时卡片底行那句「离线 · 10:32 的价」。
///
/// 股票、自选股、加密货币刷新失败时留着上次的数，原来只把透明度降到 55%，
/// 不说为什么。这里给出那句话：时间是上次成功取到的时刻，今天的只写时分，
/// 不是今天的带上月日；一组里有好几只过期时取最早的那个，宁可说旧不说新。
public enum OfflineQuote {
    /// 过期时卡片的透明度：有了文字说明，不用再淡到 55% 那么看不清。
    public static let staleOpacity = 0.7

    /// 一组报价里最早的那次成功时间；都不知道就是 nil。
    public static func oldest(_ times: [Date?]) -> Date? {
        times.compactMap { $0 }.min()
    }

    /// 「10:32」，不是今天时「10/18 10:32」。固定 24 小时制，中英一样。
    public static func timeText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    /// 卡片底行：「离线 · 10:32 的价」；不知道是几点的价时只写「离线」。
    public static func label(fetched: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let fetched else { return tr("离线") }
        return tr("离线 · \(timeText(fetched, now: now, calendar: calendar)) 的价")
    }
}
