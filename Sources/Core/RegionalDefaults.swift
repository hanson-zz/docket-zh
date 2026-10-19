import Foundation

/// 新放的行情、摸鱼时钟这类小组件的默认值，按界面语言和地区给。
///
/// 原来不管什么界面都是中国的默认：加密货币人民币计价、红涨绿跌、黄金白银元/克、
/// 摸鱼时钟写死「¥」。中文界面照旧；英文界面看系统地区：中国大陆仍按人民币那一套，
/// 其他地区用美元计价、美元/盎司、当地货币符号；涨跌颜色在台湾、日本、韩国也是
/// 红涨，其余地区绿涨红跌。
///
/// 只决定新小组件写进配置的初始值（`WidgetCatalog.make` 会把默认值整份写进去），
/// 已经放好的小组件存着自己的值，一个都不改。
public struct RegionalDefaults: Equatable, Sendable {
    /// 加密货币计价，`cny` 或 `usd`（CoinGecko 只取这两种）。
    public var cryptoCurrency: String
    public var colors: ChangeColors
    public var metalUnit: PreciousMetal.DisplayUnit
    /// 摸鱼时钟“今天赚了”后面的货币符号。
    public var currencySymbol: String

    public static let chinese = RegionalDefaults(cryptoCurrency: "cny", colors: .redUp,
                                                 metalUnit: .cnyPerGram, currencySymbol: "¥")

    /// 红涨绿跌的地区：中国大陆、台湾、日本、韩国。香港和其他地区绿涨红跌。
    public static let redUpRegions: Set<String> = ["CN", "TW", "JP", "KR"]

    /// - Parameters:
    ///   - english: 界面是英文。中文界面一律按中国的默认。
    ///   - region: 系统地区代码（`US`、`CN`），不知道时为 nil。
    public static func resolve(english: Bool, region: String?) -> RegionalDefaults {
        guard english else { return .chinese }
        let code = region?.uppercased()
        if code == "CN" { return .chinese }
        return RegionalDefaults(cryptoCurrency: "usd",
                                colors: code.map { redUpRegions.contains($0) } == true ? .redUp : .greenUp,
                                metalUnit: .usdPerOunce,
                                currencySymbol: currencySymbol(region: code))
    }

    /// 地区的货币符号：美国 `$`、英国 `£`、德国 `€`、日本 `¥`。不知道地区时 `$`。
    public static func currencySymbol(region: String?) -> String {
        guard let region, !region.isEmpty else { return "$" }
        let locale = Locale(identifier: "en_\(region)")
        guard let symbol = locale.currencySymbol, !symbol.isEmpty, symbol != "¤" else { return "$" }
        // 有的地区给的是带国家前缀的写法（US$、CA$），卡片上只要最后的符号部分。
        if symbol.count > 1, let last = symbol.last, !last.isLetter,
           symbol.dropLast().allSatisfy(\.isLetter) {
            return String(last)
        }
        return symbol
    }

    /// 这台 Mac 现在的默认值。测试包里界面永远是中文，所以是 `.chinese`。
    public static var current: RegionalDefaults {
        resolve(english: L10n.isEnglish, region: Locale.current.region?.identifier)
    }
}
