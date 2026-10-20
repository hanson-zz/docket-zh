import Foundation

/// 加密货币面板里能直接改的部分：币种列表的增删排、币种的中文名和搜索、
/// 到价提醒（Pro）。界面在 `CryptoDetail`，判断都在这里，测试不联网。
///
/// 存法都在小组件自己的设置里：
/// - `coins`：币种列表，常见币写代码（`BTC`），其余写 CoinGecko id（`solo-coin`），
///   和设置页手填的写法一样，见 `CryptoMarket.coinIDs`。
/// - `alerts`：到价提醒，一条一个字符串 `bitcoin>800000@cny`（高于）、
///   `bitcoin<720000@cny`（低于），关掉的前面加 `~`。每个币每个方向一条。
///   不放进 WidgetCatalog 的默认值，所以不出现在设置页，只在面板里改。
/// - `alertHits`：到过价、还没打开面板看过的币（CoinGecko id），卡片上这几个变色，
///   打开面板就清掉。
public struct CryptoAlert: Equatable, Hashable, Sendable {
    /// CoinGecko id，`bitcoin`。
    public var coin: String
    /// 高于（涨到或超过）还是低于（跌到或低于）。
    public var above: Bool
    public var price: Double
    /// 设提醒时的计价，`cny` 或 `usd`。切换计价不改它：提醒价按设的那种比。
    public var currency: String
    /// 开着才判断。提醒一次后自动关掉，价格留着，再打开就是同一条。
    public var on: Bool

    public init(coin: String, above: Bool, price: Double, currency: String, on: Bool = true) {
        self.coin = coin
        self.above = above
        self.price = price
        self.currency = currency == "usd" ? "usd" : "cny"
        self.on = on
    }

    /// 存进设置的写法。
    public var text: String {
        (on ? "" : "~") + coin + (above ? ">" : "<") + CryptoWatch.plainNumber(price) + "@" + currency
    }

    /// 读一条；`BTC>800000@cny`、` ~bitcoin < 0.5 @usd ` 都认，读不出来是 nil。
    /// 没写计价的按人民币。
    public static func parse(_ raw: String) -> CryptoAlert? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var on = true
        if text.hasPrefix("~") {
            on = false
            text.removeFirst()
        }
        let above: Bool
        if text.contains(">") { above = true } else if text.contains("<") { above = false } else { return nil }
        let parts = text.split(separator: above ? ">" : "<", omittingEmptySubsequences: false)
        guard parts.count == 2, let coin = CryptoMarket.coinID(String(parts[0])) else { return nil }
        let right = parts[1].split(separator: "@", omittingEmptySubsequences: false)
        guard right.count <= 2 else { return nil }
        let number = right[0].trimmingCharacters(in: .whitespaces)
        guard let price = Double(number), price.isFinite, price > 0 else { return nil }
        let currency = right.count == 2 ? right[1].trimmingCharacters(in: .whitespaces).lowercased() : "cny"
        guard currency == "cny" || currency == "usd" else { return nil }
        return CryptoAlert(coin: coin, above: above, price: price, currency: currency, on: on)
    }

    /// 现价到了没有：高于的涨到或超过，低于的跌到或低于。
    public func isReached(by price: Double?) -> Bool {
        guard let price, price.isFinite, price > 0 else { return false }
        return above ? price >= self.price : price <= self.price
    }

    /// 同一个币同一个方向算同一条。
    public func sameSlot(_ other: CryptoAlert) -> Bool {
        coin == other.coin && above == other.above
    }
}

/// 搜索结果的一条。
public struct CryptoSearchHit: Equatable, Sendable, Identifiable {
    public var id: String
    public var symbol: String
    public var name: String

    public init(id: String, symbol: String, name: String) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.name = name
    }
}

public enum CryptoWatch {
    public static let alertsKey = "alerts"
    public static let hitsKey = "alertHits"

    // MARK: 币种列表

    /// 写进 `coins` 的写法：常见币写代码，其余写 id。
    public static func token(for id: String) -> String {
        CryptoMarket.knownIDs.first { $0.value == id }?.key ?? id
    }

    public static func writeCoins(_ ids: [String], into config: inout WidgetConfig) {
        config.set("coins", .list(ids.map { .string(token(for: $0)) }))
    }

    /// 是否还能再加：最多 `CryptoMarket.maxCoins` 个。
    public static func canAdd(count: Int) -> Bool { count < CryptoMarket.maxCoins }

    /// 加一个币到末尾。已经有了或满了返回 nil。
    public static func adding(_ id: String, to ids: [String]) -> [String]? {
        guard let id = CryptoMarket.coinID(id), !ids.contains(id), canAdd(count: ids.count) else { return nil }
        return ids + [id]
    }

    /// 至少留一个：列表空了 `coinIDs` 会退回默认的三个，删掉最后一个反而多出三个。
    public static func canRemove(count: Int) -> Bool { count > 1 }

    public static func removing(_ id: String, from ids: [String]) -> [String] {
        guard canRemove(count: ids.count) else { return ids }
        return ids.filter { $0 != id }
    }

    /// 把第 `from` 个挪到第 `to` 个的位置，越界的夹到两头。
    public static func moving(_ ids: [String], from: Int, to: Int) -> [String] {
        guard ids.indices.contains(from) else { return ids }
        var list = ids
        let item = list.remove(at: from)
        list.insert(item, at: min(max(to, 0), list.count))
        return list
    }

    /// 拖动排序：拖了多远换算成落到第几个。`step` 是一行的高度加行距。
    public static func dropIndex(from: Int, offset: Double, step: Double, count: Int) -> Int {
        guard count > 0, step > 0, offset.isFinite else { return max(0, min(from, count - 1)) }
        let moved = Int((offset / step).rounded())
        return min(max(from + moved, 0), count - 1)
    }

    // MARK: 名字

    /// 常见币，按大概的市值排，搜索时排在前面。中文名是国内行情软件常见的叫法。
    public static let catalog: [(id: String, symbol: String, zh: String, en: String)] = [
        ("bitcoin", "BTC", "比特币", "Bitcoin"),
        ("ethereum", "ETH", "以太坊", "Ethereum"),
        ("tether", "USDT", "泰达币", "Tether"),
        ("ripple", "XRP", "瑞波币", "XRP"),
        ("binancecoin", "BNB", "币安币", "BNB"),
        ("solana", "SOL", "索拉纳", "Solana"),
        ("usd-coin", "USDC", "USDC", "USDC"),
        ("dogecoin", "DOGE", "狗狗币", "Dogecoin"),
        ("tron", "TRX", "波场", "TRON"),
        ("cardano", "ADA", "艾达币", "Cardano"),
        ("chainlink", "LINK", "Chainlink", "Chainlink"),
        ("stellar", "XLM", "恒星币", "Stellar"),
        ("sui", "SUI", "Sui", "Sui"),
        ("bitcoin-cash", "BCH", "比特币现金", "Bitcoin Cash"),
        ("avalanche-2", "AVAX", "雪崩", "Avalanche"),
        ("the-open-network", "TON", "TON 币", "Toncoin"),
        ("litecoin", "LTC", "莱特币", "Litecoin"),
        ("shiba-inu", "SHIB", "柴犬币", "Shiba Inu"),
        ("polkadot", "DOT", "波卡", "Polkadot"),
        ("uniswap", "UNI", "Uniswap", "Uniswap"),
        ("pepe", "PEPE", "佩佩币", "Pepe"),
        ("near", "NEAR", "NEAR", "NEAR Protocol"),
        ("aptos", "APT", "Aptos", "Aptos"),
        ("ethereum-classic", "ETC", "以太经典", "Ethereum Classic"),
        ("filecoin", "FIL", "文件币", "Filecoin"),
        ("arbitrum", "ARB", "Arbitrum", "Arbitrum"),
        ("optimism", "OP", "Optimism", "Optimism"),
    ]

    /// 面板上显示的名字：常见币中文界面用中文名，英文界面用英文名；其余用
    /// CoinGecko 给的名字（搜索时记下的或行情里的），都没有就写代码。
    static func displayName(id: String, fallback: String?, english: Bool = L10n.isEnglish) -> String {
        if let known = catalog.first(where: { $0.id == id }) { return english ? known.en : known.zh }
        if let fallback, !fallback.isEmpty { return fallback }
        return CryptoMarket.label(id: id, quote: nil)
    }

    // MARK: 搜索

    /// 本地先搜常见币：代码开头、中文名、英文名或 id 里有这个词。代码完全一样的排最前。
    public static func localSearch(_ query: String) -> [CryptoSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matched = catalog.filter { coin in
            coin.symbol.lowercased().hasPrefix(q) || coin.zh.lowercased().contains(q)
                || coin.en.lowercased().contains(q) || coin.id.hasPrefix(q)
        }
        let exact = matched.filter { $0.symbol.lowercased() == q }
        let rest = matched.filter { $0.symbol.lowercased() != q }
        return (exact + rest).map { CryptoSearchHit(id: $0.id, symbol: $0.symbol, name: $0.en) }
    }

    /// 至少两个字（或一个汉字）才去 CoinGecko 搜，免得一个字母就发请求。
    public static func wantsRemoteSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        // CoinGecko 只认英文，中文名只在本地表里搜。
        if q.unicodeScalars.contains(where: { $0.value >= 0x3400 }) { return false }
        return q.count >= 2
    }

    public static func searchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/search")
        components?.queryItems = [URLQueryItem(name: "query", value: query.trimmingCharacters(in: .whitespacesAndNewlines))]
        return components?.url
    }

    /// `/search` 的 `coins` 数组，按 CoinGecko 自己的排序，id 不合规矩的丢掉。
    /// 错误对象或别的东西是 nil。
    public static func parseSearch(_ data: Data, limit: Int = 8) -> [CryptoSearchHit]? {
        struct Wire: Decodable {
            struct Coin: Decodable { var id: String?; var symbol: String?; var name: String? }
            var coins: [Coin]?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), let coins = wire.coins else { return nil }
        var hits: [CryptoSearchHit] = []
        for coin in coins {
            guard let raw = coin.id, let id = CryptoMarket.coinID(raw), id == raw,
                  !hits.contains(where: { $0.id == id }) else { continue }
            hits.append(CryptoSearchHit(id: id, symbol: coin.symbol ?? id, name: coin.name ?? id))
            if hits.count == limit { break }
        }
        return hits
    }

    /// 本地的在前，联网的补在后面，同一个 id 只留一条。
    public static func mergedResults(local: [CryptoSearchHit], remote: [CryptoSearchHit], limit: Int = 6) -> [CryptoSearchHit] {
        var result: [CryptoSearchHit] = []
        for hit in local + remote where !result.contains(where: { $0.id == hit.id }) {
            result.append(hit)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: 到价提醒

    /// 设置里的提醒，读不出来的丢掉，同一个币同一个方向只留第一条，不在列表里的币也丢掉
    /// （`coins` 传 nil 时不按币过滤）。
    public static func alerts(_ config: WidgetConfig, coins: [String]? = nil) -> [CryptoAlert] {
        var result: [CryptoAlert] = []
        for raw in config.strings(alertsKey, default: []) {
            guard let alert = CryptoAlert.parse(raw), !result.contains(where: { $0.sameSlot(alert) }) else { continue }
            if let coins, !coins.contains(alert.coin) { continue }
            result.append(alert)
        }
        return result
    }

    public static func writeAlerts(_ alerts: [CryptoAlert], into config: inout WidgetConfig) {
        config.set(alertsKey, .list(alerts.map { .string($0.text) }))
    }

    public static func alert(_ alerts: [CryptoAlert], coin: String, above: Bool) -> CryptoAlert? {
        alerts.first { $0.coin == coin && $0.above == above }
    }

    /// 放进一条：同一个币同一个方向的换掉，没有就加在后面。
    public static func setting(_ alert: CryptoAlert, in alerts: [CryptoAlert]) -> [CryptoAlert] {
        if let index = alerts.firstIndex(where: { $0.sameSlot(alert) }) {
            var list = alerts
            list[index] = alert
            return list
        }
        return alerts + [alert]
    }

    public static func removing(coin: String, above: Bool, from alerts: [CryptoAlert]) -> [CryptoAlert] {
        alerts.filter { !($0.coin == coin && $0.above == above) }
    }

    /// 删掉一个币时它的提醒一起删。
    public static func removing(coin: String, from alerts: [CryptoAlert]) -> [CryptoAlert] {
        alerts.filter { $0.coin != coin }
    }

    /// 开着提醒的币，铃铛标在这几个上。
    public static func watchedCoins(_ alerts: [CryptoAlert]) -> Set<String> {
        Set(alerts.filter(\.on).map(\.coin))
    }

    /// 所有加密货币卡片现在要取价的币，按计价分：卡片自己的币按卡片的计价，
    /// 开着的提醒（`alertsOn` 时）按提醒设的计价。删掉的币、删掉的卡片、
    /// 换掉的计价都不在里面，取价时直接跳过。
    public static func inUse(_ configs: [WidgetConfig], alertsOn: Bool) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for config in configs {
            let coins = CryptoMarket.coinIDs(config)
            result[CryptoMarket.currency(config), default: []].formUnion(coins)
            guard alertsOn else { continue }
            for alert in alerts(config, coins: coins) where alert.on {
                result[alert.currency, default: []].insert(alert.coin)
            }
        }
        return result
    }

    /// 已经登记要取价的，只留还在用的。
    public static func pruned(_ tracked: [String: Set<String>], inUse: [String: Set<String>]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for (currency, ids) in tracked {
            let kept = ids.intersection(inUse[currency] ?? [])
            if !kept.isEmpty { result[currency] = kept }
        }
        return result
    }

    /// 开着的提醒用到的计价：和卡片当前计价不同的也要去取价。
    public static func currencies(_ alerts: [CryptoAlert]) -> Set<String> {
        Set(alerts.filter(\.on).map(\.currency))
    }

    /// 这次到价的：开着、而且现价到了。`price` 给出某个币在某种计价下的现价，
    /// 没有（还没取到、断网）就是 nil，不算到。
    public static func due(_ alerts: [CryptoAlert], price: (_ coin: String, _ currency: String) -> Double?) -> [CryptoAlert] {
        alerts.filter { $0.on && $0.isReached(by: price($0.coin, $0.currency)) }
    }

    /// 提醒过的自动关掉，价格留着。
    public static func firing(_ fired: [CryptoAlert], in alerts: [CryptoAlert]) -> [CryptoAlert] {
        alerts.map { alert in
            guard fired.contains(where: { $0.sameSlot(alert) && $0.price == alert.price }) else { return alert }
            var off = alert
            off.on = false
            return off
        }
    }

    /// 面板“到价提醒”一行写哪一条：按币种顺序第一个开着的，高于在低于前。
    public static func featured(_ alerts: [CryptoAlert], order: [String]) -> CryptoAlert? {
        let live = alerts.filter(\.on)
        for coin in order {
            if let hit = live.first(where: { $0.coin == coin && $0.above }) ?? live.first(where: { $0.coin == coin }) {
                return hit
            }
        }
        return nil
    }

    /// `比特币高于 ¥800,000`。
    public static func title(_ alert: CryptoAlert, name: String) -> String {
        let price = CryptoMarket.priceText(alert.price, currency: alert.currency)
        return alert.above ? tr("\(name)高于 \(price)") : tr("\(name)低于 \(price)")
    }

    /// 面板涨跌色块上的字：`+2.4%`、`-0.8%`、`0.0%`，没有是 `-`。
    public static func chipText(_ change: Double?) -> String {
        guard let change, change.isFinite else { return "-" }
        let rounded = (change * 10).rounded() / 10
        if rounded == 0 { return "0.0%" }
        return (rounded > 0 ? "+" : "") + String(format: "%.1f%%", rounded)
    }

    // MARK: 到价的币（卡片变色）

    public static func hits(_ config: WidgetConfig) -> [String] {
        config.strings(hitsKey, default: [])
    }

    public static func addingHits(_ coins: [String], to config: inout WidgetConfig) {
        var list = hits(config)
        for coin in coins where !list.contains(coin) { list.append(coin) }
        config.set(hitsKey, .list(list.map { .string($0) }))
    }

    // MARK: 提醒价的输入

    /// 输入框里的价：`¥800,000`、`800000`、`80万`、`0.18`、全角逗号都认。
    /// 不是正数就是 nil。
    public static func parsePrice(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["¥", "￥", "$", "＄", ",", "，", " ", "_"] { t = t.replacingOccurrences(of: junk, with: "") }
        t = t.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".")
        var scale = 1.0
        if t.hasSuffix("万") { scale = 10_000; t.removeLast() } else if t.hasSuffix("亿") { scale = 100_000_000; t.removeLast() }
        guard !t.isEmpty, let value = Double(t), value.isFinite else { return nil }
        let result = value * scale
        return result > 0 && result.isFinite ? result : nil
    }

    /// 打开一条还没写价的提醒时先填的价：高于是现价往上 5%、低于往下 5%，
    /// 取两位有效数字，高于的往上取、低于的往下取，保证在现价两边。
    public static func suggested(current: Double?, above: Bool) -> Double? {
        guard let current, current.isFinite, current > 0 else { return nil }
        let target = current * (above ? 1.05 : 0.95)
        let unit = pow(10, floor(log10(target)) - 1)
        let rounded = (above ? ceil(target / unit) : floor(target / unit)) * unit
        // 浮点的 0.1 这类尾巴去掉。
        let cleaned = Double(String(format: "%.10g", rounded)) ?? rounded
        return cleaned > 0 ? cleaned : nil
    }

    /// 输入框里显示的价：和行情一样带千分位，不带货币符号（符号在框外）。
    public static func inputText(_ price: Double, currency: String) -> String {
        String(CryptoMarket.priceText(price, currency: currency).dropFirst())
    }

    /// 存进设置的数字：整数不带小数点，其余用最短的写法（`0.00001234` 可能写成 `1.234e-05`，读回来一样）。
    static func plainNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }
}
