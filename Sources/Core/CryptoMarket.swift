import Foundation

/// One coin's last known market state, as fetched from CoinGecko and as cached.
public struct CryptoQuote: Codable, Equatable, Sendable {
    /// CoinGecko's id, `bitcoin`.
    public var id: String
    /// Ticker in capitals, `BTC`.
    public var symbol: String
    public var name: String
    public var price: Double
    /// Percent over the last 24 hours; nil when CoinGecko has none.
    public var change24h: Double?
    /// Roughly the last 24 hours, hourly, oldest first. Shape only: see
    /// `CryptoMarket.parse` for why it is not drawn against `price`.
    public var sparkline: [Double]

    public init(id: String, symbol: String, name: String, price: Double,
                change24h: Double?, sparkline: [Double] = []) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.price = price
        self.change24h = change24h
        self.sparkline = sparkline
    }
}

/// The last good table for one quote currency, written to disk as is.
public struct CryptoSnapshot: Codable, Equatable, Sendable {
    /// `cny` or `usd`.
    public var currency: String
    public var quotes: [String: CryptoQuote]
    public var fetched: Date

    public init(currency: String, quotes: [String: CryptoQuote], fetched: Date) {
        self.currency = currency
        self.quotes = quotes
        self.fetched = fetched
    }
}

/// How rises and falls are coloured. 红涨绿跌 is how every quote screen in
/// mainland China, Hong Kong and Taiwan reads; 绿涨红跌 is the Western one.
public enum ChangeColors: String, CaseIterable, Sendable {
    case redUp
    case greenUp

    public var title: String {
        switch self {
        case .redUp: tr("红涨绿跌")
        case .greenUp: tr("绿涨红跌")
        }
    }

    public static func from(_ config: WidgetConfig) -> ChangeColors {
        ChangeColors(rawValue: config.string("colors", default: ChangeColors.redUp.rawValue)) ?? .redUp
    }
}

/// Which way a change reads, and so which ink it gets.
public enum ChangeTone: Equatable, Sendable {
    case red, green, neutral
}

/// 加密货币行情: the pure half. Which coins a widget means, the CoinGecko
/// request for them, parsing the answer, the refresh gate and the formatting
/// are all here so they are tested with sample JSON and no network.
///
/// Data from CoinGecko's free public API (no key), credited in the panel and
/// in NOTICE.md as its terms ask.
public enum CryptoMarket {
    public static let attribution = tr("数据来自 CoinGecko")
    public static let attributionURL = URL(string: "https://www.coingecko.com")!

    public static let defaultCoins = ["BTC", "ETH", "SOL"]
    /// What the shelf tile can show side by side; the panel lists them all.
    public static let tileCoins = 4
    /// What one request asks for. CoinGecko's free tier is generous per call
    /// and stingy per minute, so a long list is one call, not several.
    public static let maxCoins = 12

    /// The free tier allows a handful of calls a minute shared by everyone on
    /// an address; a shelf has no business asking more than every five.
    public static let refreshInterval: TimeInterval = 300
    /// A coin just added to the list may be fetched sooner, but never in a
    /// burst while someone is typing a list in Settings.
    public static let addedCoinInterval: TimeInterval = 60

    /// Tickers people type, to CoinGecko ids. Anything else is taken to be a
    /// CoinGecko id already (`the-open-network`), which is what the settings
    /// prompt says to use for a coin not listed here.
    public static let knownIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "BNB": "binancecoin",
        "XRP": "ripple", "DOGE": "dogecoin", "ADA": "cardano", "TRX": "tron",
        "TON": "the-open-network", "LTC": "litecoin", "DOT": "polkadot",
        "AVAX": "avalanche-2", "LINK": "chainlink", "USDT": "tether", "USDC": "usd-coin",
        "SHIB": "shiba-inu", "BCH": "bitcoin-cash", "XLM": "stellar", "SUI": "sui",
        "ETC": "ethereum-classic", "UNI": "uniswap", "NEAR": "near", "APT": "aptos",
        "ARB": "arbitrum", "OP": "optimism", "PEPE": "pepe", "FIL": "filecoin",
    ]

    /// The coins a widget shows, as CoinGecko ids, in the order configured,
    /// deduplicated, never empty.
    public static func coinIDs(_ config: WidgetConfig) -> [String] {
        let raw = config.strings("coins", default: defaultCoins)
        var seen: [String] = []
        for entry in raw {
            guard let id = coinID(entry), !seen.contains(id) else { continue }
            seen.append(id)
            if seen.count == maxCoins { break }
        }
        return seen.isEmpty ? defaultCoins.compactMap(coinID) : seen
    }

    /// `btc`, ` BTC ` and `bitcoin` all mean bitcoin. Nil for anything that
    /// cannot be an id, so a stray character never becomes a request.
    public static func coinID(_ entry: String) -> String? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let known = knownIDs[trimmed.uppercased()] { return known }
        let id = trimmed.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return id
    }

    /// `cny` or `usd`.
    public static func currency(_ config: WidgetConfig) -> String {
        config.string("currency", default: "cny") == "usd" ? "usd" : "cny"
    }

    /// `/coins/markets` answers price, 24h change and a seven-day hourly
    /// sparkline for every coin in one call.
    public static func marketsURL(ids: [String], currency: String) -> URL? {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")
        components?.queryItems = [
            URLQueryItem(name: "vs_currency", value: currency),
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "24h"),
        ]
        return components?.url
    }

    /// The `/coins/markets` array, keyed by id. Nil for an error object (the
    /// rate limit answers `{"status":{"error_code":429,…}}`) or anything that
    /// is not the array, so a bad answer never replaces a good table.
    ///
    /// The sparkline CoinGecko returns is priced in US dollars whatever
    /// `vs_currency` says, so it is kept as a shape only: the last 24 hourly
    /// points, drawn against their own range, never against `price`.
    public static func parse(_ data: Data) -> [String: CryptoQuote]? {
        struct Wire: Decodable {
            struct Spark: Decodable { var price: [Double?]? }
            var id: String?
            var symbol: String?
            var name: String?
            var current_price: Double?
            var price_change_percentage_24h: Double?
            var price_change_percentage_24h_in_currency: Double?
            var sparkline_in_7d: Spark?
        }
        guard let rows = try? JSONDecoder().decode([Wire].self, from: data) else { return nil }
        var result: [String: CryptoQuote] = [:]
        for row in rows {
            guard let id = row.id, !id.isEmpty, let price = row.current_price,
                  price.isFinite, price >= 0 else { continue }
            let change = row.price_change_percentage_24h_in_currency ?? row.price_change_percentage_24h
            let points = (row.sparkline_in_7d?.price ?? []).compactMap { $0 }.filter(\.isFinite)
            result[id] = CryptoQuote(
                id: id,
                symbol: (row.symbol ?? id).uppercased(),
                name: row.name ?? id,
                price: price,
                change24h: change.flatMap { $0.isFinite ? $0 : nil },
                sparkline: Array(points.suffix(25)))
        }
        return result
    }

    /// Whether a fetch may start: never more than every five minutes, or
    /// every minute when a coin on show has no price at all yet.
    public static func shouldFetch(lastAttempt: Date?, now: Date, missing: Bool) -> Bool {
        guard let lastAttempt else { return true }
        let since = now.timeIntervalSince(lastAttempt)
        return since >= (missing ? addedCoinInterval : refreshInterval)
    }

    /// A good table merged into the last one: coins in the fresh answer win,
    /// coins it left out keep their last good price rather than vanishing.
    public static func merged(_ old: CryptoSnapshot?, fresh: [String: CryptoQuote],
                              currency: String, at now: Date) -> CryptoSnapshot {
        var quotes = old?.currency == currency ? old?.quotes ?? [:] : [:]
        for (id, quote) in fresh { quotes[id] = quote }
        return CryptoSnapshot(currency: currency, quotes: quotes, fetched: now)
    }

    // MARK: Reading a change

    public static func tone(_ change: Double?, colors: ChangeColors) -> ChangeTone {
        guard let change, change.isFinite, abs(change) >= 0.005 else { return .neutral }
        let up = change > 0
        switch colors {
        case .redUp: return up ? .red : .green
        case .greenUp: return up ? .green : .red
        }
    }

    // MARK: Formatting

    /// `¥558,865`, `$1.23`, `¥0.000123`: whole units once a coin is worth a
    /// thousand, cents above one, and enough digits below that to see it move.
    public static func priceText(_ price: Double, currency: String) -> String {
        guard price.isFinite else { return "-" }
        let symbol = currency == "usd" ? "$" : "¥"
        let digits: Int
        switch abs(price) {
        case 1_000...: digits = 0
        case 1...: digits = 2
        case 0.01...: digits = 4
        case 0: digits = 2
        default: digits = 8
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let number = formatter.string(from: NSNumber(value: price)) ?? String(format: "%.\(digits)f", price)
        return symbol + number
    }

    /// `+1.09%`, `-0.42%`, `0.00%`, or `-` when there is no figure.
    public static func changeText(_ change: Double?) -> String {
        guard let change, change.isFinite else { return "-" }
        let rounded = (change * 100).rounded() / 100
        let sign = rounded > 0 ? "+" : ""
        return sign + String(format: "%.2f%%", rounded == 0 ? 0 : rounded)
    }

    /// `BTC` from the quote when there is one, otherwise the configured entry
    /// in capitals, so the tile says which coin is loading.
    public static func label(id: String, quote: CryptoQuote?) -> String {
        if let quote { return quote.symbol }
        return knownIDs.first { $0.value == id }?.key ?? id.uppercased()
    }

    // MARK: Sizing

    /// One column per coin on the shelf, up to `tileCoins`.
    public static func tileWidth(count: Int) -> Double {
        let shown = min(max(count, 1), tileCoins)
        return Double(shown * 76 + 20)
    }

    /// A row per coin in the 76pt column: ticker and change over the price,
    /// and the sparkline under them when the chart is on.
    public static func columnHeight(count: Int, chart: Bool) -> Double {
        let shown = min(max(count, 1), tileCoins)
        return max(62, Double(shown * (chart ? 44 : 32) + 10))
    }
}
