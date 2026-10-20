import Foundation

// 股票、自选股面板里的「编辑」：搜索添加、删除、拖动排序、每行填持仓。
// 写回的还是原来的那几个设置键（`symbols`、`groups`、`holdings`），设置页的
// 文本框照旧能粘贴，两边改的是同一份。

extension StockBoard {
    // MARK: 持仓（股数和可选的成本价）

    /// 一只的持仓：股数，和可选的成本价（每股）。
    public struct Holding: Equatable, Sendable {
        public var shares: Double
        public var cost: Double?

        public init(shares: Double, cost: Double? = nil) {
            self.shares = shares
            self.cost = cost
        }
    }

    /// 持仓的每一条：`NVDA 100`、`AAPL:50`、`600519.SS=200`（老格式，只有股数），
    /// 以及 `NVDA 100 238`、`NVDA 100 @238`（带成本价）。股数为 0、写不成数字的
    /// 整条不算；成本价写了但不是正数的整条也不算，免得把错的成本当真。
    public static func holdingEntries(_ config: WidgetConfig) -> [String: Holding] {
        var result: [String: Holding] = [:]
        for raw in config.strings("holdings", default: []) {
            guard let found = holdingEntry(raw) else { continue }
            result[found.0] = found.1
        }
        return result
    }

    static func holdingEntry(_ raw: String) -> (String, Holding)? {
        let parts = raw.split(whereSeparator: { " :=：＝\t@".contains($0) }).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let symbol = normalised(parts[0])
        guard !symbol.isEmpty, let shares = number(parts[1]), shares != 0 else { return nil }
        var cost: Double?
        if parts.count == 3 {
            guard let value = number(parts[2]), value > 0 else { return nil }
            cost = value
        }
        return (symbol, Holding(shares: shares, cost: cost))
    }

    /// 面板输入框里的数：去掉空白和千分位逗号；不是有限的数是 nil。
    public static func number(_ text: String) -> Double? {
        let cleaned = text.filter { !" ,，\t".contains($0) }
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// 填回输入框的数：`100`、`238.5`，去掉多余的零。
    public static func numberText(_ value: Double) -> String { trimmed(value) }

    /// 写回设置的一条：`NVDA 100`，有成本时 `NVDA 100 238.5`。
    public static func holdingText(_ symbol: String, _ holding: Holding) -> String {
        var text = normalised(symbol) + " " + trimmed(holding.shares)
        if let cost = holding.cost { text += " " + trimmed(cost) }
        return text
    }

    /// 面板里改一只的持仓之后的 `holdings` 列表。`holding` 为 nil（或股数是 0）是清掉
    /// 这只。别的条目原样保留（包括写坏了读不出来的，那是用户自己的字）；这只原来
    /// 在哪一行，新的就写在哪一行。
    public static func settingHolding(_ symbol: String, _ holding: Holding?,
                                      in config: WidgetConfig) -> [String] {
        let key = normalised(symbol)
        let replacement = holding.flatMap { $0.shares != 0 && $0.shares.isFinite ? holdingText(key, $0) : nil }
        var result: [String] = []
        var placed = false
        for raw in config.strings("holdings", default: []) {
            let parts = raw.split(whereSeparator: { " :=：＝\t@".contains($0) })
            if let first = parts.first, normalised(String(first)) == key {
                if !placed, let replacement { result.append(replacement) }
                placed = true
                continue
            }
            result.append(raw)
        }
        if !placed, let replacement { result.append(replacement) }
        return result
    }

    /// 持仓按钮上的字：`100 股`；带成本时 `100 股 @238`。
    public static func holdingLabel(_ holding: Holding?) -> String {
        guard let holding else { return tr("持仓") }
        let shares = tr("\(trimmed(holding.shares)) 股")
        guard let cost = holding.cost else { return shares }
        return shares + " @" + trimmed(cost)
    }

    /// 持仓盈亏：(现价 - 成本) × 股数，一种货币一笔，百分比按成本算。
    /// 没填成本的不算；按金额绝对值从大到小排。
    public static func holdingProfit(_ positions: [Position], holdings: [String: Holding]) -> [Profit] {
        var amount: [String: Double] = [:]
        var base: [String: Double] = [:]
        for position in positions {
            guard let holding = holdings[position.symbol], let cost = holding.cost, position.price.isFinite
            else { continue }
            amount[position.currency, default: 0] += (position.price - cost) * holding.shares
            base[position.currency, default: 0] += cost * abs(holding.shares)
        }
        return amount.map { currency, value in
            let start = base[currency] ?? 0
            return Profit(currency: currency, amount: value, percent: start > 0 ? value / start * 100 : nil)
        }
        .sorted { abs($0.amount) == abs($1.amount) ? $0.currency < $1.currency : abs($0.amount) > abs($1.amount) }
    }

    // MARK: 代码列表

    /// 面板编辑里一个列表最多几只。
    public static let editorLimit = 30

    /// 面板编辑的是哪串代码：自选股是正在看的分组（没有分组时是整串 `symbols`），
    /// 股票是轮播的那几只。
    public static func editingSymbols(_ config: WidgetConfig, watchlist: Bool) -> [String] {
        watchlist ? currentGroup(config).symbols : rotation(config)
    }

    /// 删到只剩一只就不让再删：空列表会退回默认的几只（自选股）或 AAPL（股票），
    /// 删光反而冒出没要过的股票。
    public static func canRemove(count: Int) -> Bool { count > 1 }

    /// 把编辑后的代码写回去。空的不写（见 `canRemove`）。自选股有分组时写进正在看的
    /// 分组，名字不变；股票正在显示的那只被删了就换成第一只。
    public static func settingSymbols(_ symbols: [String], in config: WidgetConfig,
                                      watchlist: Bool) -> WidgetConfig {
        let list = Array(unique(symbols).prefix(editorLimit))
        guard !list.isEmpty else { return config }
        var result = config
        if watchlist, !config.strings("groups", default: []).compactMap(Group.parse).isEmpty {
            var group = currentGroup(config)
            group.symbols = list
            result.set("groups", .list(saving(group, in: config).map { .string($0) }))
            result.set("group", .string(group.name))
            return result
        }
        result.set("symbols", .list(list.map { .string($0) }))
        if !watchlist, !list.contains(normalised(config.string("symbol", default: ""))) {
            result.set("symbol", .string(list[0]))
        }
        return result
    }

    /// 面板里加一只：已经有了、满了或代码是空的时是 nil。
    public static func addingSymbol(_ symbol: String, to config: WidgetConfig,
                                    watchlist: Bool) -> WidgetConfig? {
        let key = normalised(symbol)
        let current = editingSymbols(config, watchlist: watchlist)
        guard !key.isEmpty, !current.contains(key), current.count < editorLimit else { return nil }
        return settingSymbols(current + [key], in: config, watchlist: watchlist)
    }

    /// 挪一只：`from` 挪到 `to`（挪完以后它在的位置），越界的夹回来。
    public static func moved(_ list: [String], from: Int, to: Int) -> [String] {
        guard list.indices.contains(from) else { return list }
        var result = list
        let item = result.remove(at: from)
        result.insert(item, at: min(max(0, to), result.count))
        return result
    }

    /// 拖柄拖了 `offset` 点之后应该落在第几行。
    public static func dragTarget(from index: Int, offset: Double, rowHeight: Double, count: Int) -> Int {
        guard count > 0, rowHeight > 0, offset.isFinite else { return index }
        let steps = Int((offset / rowHeight).rounded())
        return min(max(0, index + steps), count - 1)
    }
}

/// 面板里「输入代码或名称」的搜索。
///
/// 行情一直用的是 Yahoo 的接口，搜索也用 Yahoo 的 `v1/finance/search`（不要 key）。
/// 它不认中文名，所以先查本地的中文名表（`StockBoard.knownNames`），再把看起来像
/// 代码的输入直接换成 Yahoo 的写法：`600519` 是 600519.SS，`000001` 是 000001.SZ，
/// `700` 或 `00700` 是 0700.HK。
public enum StockSearch {
    public struct Hit: Equatable, Sendable {
        public var symbol: String
        public var name: String
        public var exchange: String

        public init(symbol: String, name: String, exchange: String = "") {
            self.symbol = StockBoard.normalised(symbol)
            self.name = name
            self.exchange = exchange
        }
    }

    public static let limit = 5

    /// 去掉首尾空白，太长的不搜。
    public static func query(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        return trimmed
    }

    /// 输入本身就是代码时，它在 Yahoo 上的写法；不像代码时是 nil。
    public static func guess(_ text: String) -> String? {
        guard let raw = query(text) else { return nil }
        if raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber) {
            if raw.count == 6 {
                switch raw.first {
                case "6", "9": return raw + ".SS"
                case "0", "2", "3": return raw + ".SZ"
                default: return nil
                }
            }
            guard raw.count <= 5 else { return nil }
            let digits = String(raw.drop { $0 == "0" })
            guard !digits.isEmpty, digits.count <= 4 else { return nil }
            return String(repeating: "0", count: 4 - digits.count) + digits + ".HK"
        }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.^=-")
        guard raw.count <= 15, raw.allSatisfy({ allowed.contains($0) }),
              raw.contains(where: { $0.isLetter || $0 == "^" }) else { return nil }
        return StockBoard.normalised(raw)
    }

    /// 本地中文名表里能对上的：名字（中文或英文界面里的名字）包含输入，或代码以输入开头。
    public static func local(_ text: String) -> [Hit] {
        guard let raw = query(text) else { return [] }
        let needle = raw.lowercased()
        let upper = StockBoard.normalised(raw)
        return StockBoard.knownNames
            .filter { symbol, name in
                name.lowercased().contains(needle) || trKey(name).lowercased().contains(needle)
                    || symbol.hasPrefix(upper)
            }
            .map { Hit(symbol: $0.key, name: StockBoard.displayName($0.key, fallback: nil)) }
            .sorted { $0.symbol < $1.symbol }
    }

    /// Yahoo 搜索接口的地址。
    public static func url(_ text: String) -> URL? {
        guard let raw = query(text) else { return nil }
        var parts = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: raw),
                             URLQueryItem(name: "quotesCount", value: "8"),
                             URLQueryItem(name: "newsCount", value: "0"),
                             URLQueryItem(name: "listsCount", value: "0")]
        return parts?.url
    }

    private struct Payload: Decodable {
        struct Quote: Decodable {
            var symbol: String?
            var shortname: String?
            var longname: String?
            var exchDisp: String?
            var quoteType: String?
        }
        var quotes: [Quote]?
    }

    /// 解析 Yahoo 搜索的结果。期权不要；接口变了、坏了都是空的，不出错。
    public static func parse(_ data: Data) -> [Hit] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return (payload.quotes ?? []).compactMap { quote in
            guard let symbol = quote.symbol, !symbol.isEmpty, quote.quoteType?.uppercased() != "OPTION"
            else { return nil }
            let name = quote.longname ?? quote.shortname ?? ""
            return Hit(symbol: symbol, name: StockBoard.displayName(symbol, fallback: name),
                       exchange: quote.exchDisp ?? "")
        }
    }

    /// 合在一起给面板：本地表、接口结果、照代码猜的，按这个先后去重，最多 `limit` 条。
    public static func merged(local: [Hit], remote: [Hit], guess: String?) -> [Hit] {
        var result: [Hit] = []
        var all = local + remote
        if let guess { all.append(Hit(symbol: guess, name: StockBoard.displayName(guess, fallback: nil))) }
        for hit in all where !hit.symbol.isEmpty && !result.contains(where: { $0.symbol == hit.symbol }) {
            result.append(hit)
            if result.count == limit { break }
        }
        return result
    }
}
