import Foundation
import Observation

/// One symbol's last known state. `history` is the intraday close series the
/// dithered chart draws; `stale` means the last refresh failed and these
/// numbers are the previous good ones rather than fresh.
struct StockQuote: Sendable {
    var symbol, name: String
    var price, change, changePercent: Double
    var currency: String
    var history: [Double]
    var stale: Bool
    /// When each point of `history` was, seconds since 1970, one per point;
    /// empty when the endpoint sent no timestamps.
    var times: [Double] = []
    /// The volume traded in each point's interval, one per point.
    var volumes: [Double] = []
    /// Yesterday's close: the dashed line the day is read against.
    var previousClose: Double?
    /// Today's regular session, so the chart spans the whole day and a
    /// morning's trading fills only the morning.
    var sessionStart: Date?
    var sessionEnd: Date?
    /// The day's volume so far.
    var volume: Double?
    /// 这份报价是什么时候成功取到的：刷新失败（`stale`）时卡片写「离线 · 10:32 的价」。
    var fetchedAt: Date?
}

/// Quotes and intraday history for the Stock and Watchlist widgets.
///
/// Backed by Yahoo's chart endpoint, which needs no key:
/// `https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m`
///
/// **That endpoint is undocumented.** It is not a contract: fields come and go
/// and it 403s a non-browser User-Agent. Every field is therefore optional and
/// every failure path returns `nil`, which leaves the cached quote in place and
/// only flips `stale`. Nothing here ever traps, and nothing ever writes a zero
/// that would read as a real price.
@MainActor @Observable
final class StockService {
    static let shared = StockService()

    /// Permanent on-screen widgets, not a page load: one poll per five
    /// minutes is plenty for a shelf, and stays far under anything Yahoo
    /// throttles.
    private static let interval: TimeInterval = 300

    private(set) var quotes: [String: StockQuote] = [:]

    @ObservationIgnored private var tracked: Set<String> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshing = false

    private init() {}

    // MARK: Public surface

    func quote(_ symbol: String) -> StockQuote? { quotes[Self.normalised(symbol)] }

    /// Registers the symbols a widget is showing. Nothing is fetched until the
    /// first widget asks, so a shelf with no stock widgets never touches the
    /// network.
    ///
    // ponytail: the tracked set only grows for the life of the process - a
    // removed widget costs one extra request per five minutes. Add a refcount
    // if someone actually churns watchlists.
    func track(_ symbols: [String]) {
        let wanted = Set(symbols.map(Self.normalised)).subtracting([""])
        let added = wanted.subtracting(tracked)
        guard !added.isEmpty else { return }
        tracked.formUnion(added)
        startTimer()
        // Only the newcomers: a widget appearing must not re-pull the symbols
        // already on screen, nor wait out the cadence for its own.
        Task { await load(added) }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await load(tracked)
    }

    private func load(_ symbols: Set<String>) async {
        guard !symbols.isEmpty else { return }
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in symbols {
                group.addTask { (symbol, await Self.fetch(symbol)) }
            }
            for await (symbol, fresh) in group {
                if var fresh {
                    fresh.fetchedAt = .now
                    quotes[symbol] = fresh
                } else if var last = quotes[symbol] {
                    // Keep the last good numbers; only admit they are old.
                    last.stale = true
                    quotes[symbol] = last
                }
            }
        }
    }

    // MARK: Cadence

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        // Generous: nothing here needs to land on a particular second, and
        // slack lets the system coalesce the wakeup.
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated static func normalised(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: Network

    /// Safari's own User-Agent. The endpoint rejects an empty or SDK one.
    nonisolated private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    nonisolated private static func fetch(_ symbol: String) async -> StockQuote? {
        guard let path = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              !path.isEmpty,
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/"
                            + path + "?range=1d&interval=5m")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return decode(data, symbol: symbol)
        } catch {
            return nil
        }
    }

    /// 面板里「输入代码或名称」：Yahoo 的搜索接口，和行情同一个来源、同一个
    /// User-Agent。失败（断网、限流、格式变了）是空的，面板照样有本地名表和
    /// 照代码猜的结果。
    nonisolated static func search(_ text: String) async -> [StockSearch.Hit] {
        guard let url = StockSearch.url(text) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            return StockSearch.parse(data)
        } catch {
            return []
        }
    }

    /// Mirrors only the handful of fields we read, all optional - a shape
    /// change drops us to `nil`, never a trap.
    private struct Payload: Decodable {
        struct Period: Decodable { var start: Double?; var end: Double? }
        struct Periods: Decodable { var regular: Period? }
        struct Meta: Decodable {
            var currency: String?
            var regularMarketVolume: Double?
            var currentTradingPeriod: Periods?
            var shortName: String?
            var longName: String?
            var regularMarketPrice: Double?
            var chartPreviousClose: Double?
            var previousClose: Double?
        }
        struct Series: Decodable { var close: [Double?]?; var volume: [Double?]? }
        struct Indicators: Decodable { var quote: [Series]? }
        struct Result: Decodable {
            var meta: Meta?
            var timestamp: [Double]?
            var indicators: Indicators?
        }
        struct Chart: Decodable { var result: [Result]? }
        var chart: Chart?
    }

    nonisolated private static func decode(_ data: Data, symbol: String) -> StockQuote? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let result = payload.chart?.result?.first,
              let meta = result.meta
        else { return nil }

        // Gaps in the series are nulls, not zeros - dropping them keeps the
        // chart honest instead of drawing a cliff to the x-axis. A point's
        // time and volume go with it, so the three stay in step.
        let rawCloses = result.indicators?.quote?.first?.close ?? []
        let rawVolumes = result.indicators?.quote?.first?.volume ?? []
        let rawTimes = result.timestamp ?? []
        let timed = rawTimes.count == rawCloses.count
        var closes: [Double] = []
        var times: [Double] = []
        var volumes: [Double] = []
        for index in rawCloses.indices {
            guard let close = rawCloses[index], close.isFinite else { continue }
            closes.append(close)
            if timed { times.append(rawTimes[index]) }
            let volume = index < rawVolumes.count ? rawVolumes[index] ?? 0 : 0
            volumes.append(volume.isFinite ? volume : 0)
        }

        guard let price = meta.regularMarketPrice ?? closes.last, price.isFinite else { return nil }

        var change = 0.0
        var percent = 0.0
        let previous = meta.chartPreviousClose ?? meta.previousClose ?? closes.first
        if let previous, previous.isFinite, previous > 0 {
            change = price - previous
            percent = change / previous * 100
        }
        let period = meta.currentTradingPeriod?.regular
        let tradedVolume = meta.regularMarketVolume ?? volumes.reduce(0, +)

        return StockQuote(
            symbol: symbol,
            name: meta.shortName ?? meta.longName ?? symbol,
            price: price,
            change: change,
            changePercent: percent,
            currency: meta.currency ?? "USD",
            history: Array(closes.suffix(160)),
            stale: false,
            times: Array(times.suffix(160)),
            volumes: Array(volumes.suffix(160)),
            previousClose: previous.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            sessionStart: period?.start.map { Date(timeIntervalSince1970: $0) },
            sessionEnd: period?.end.map { Date(timeIntervalSince1970: $0) },
            volume: tradedVolume > 0 ? tradedVolume : nil
        )
    }
}

// MARK: - Presentation

extension StockQuote {
    var rising: Bool { changePercent >= 0 }

    /// The same quote with every price multiplied by `factor`: a metal's
    /// dollars an ounce shown as yuan a gram. Percentages and volumes do not
    /// change with the unit.
    func scaled(by factor: Double) -> StockQuote {
        guard factor != 1, factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.price *= factor
        copy.change *= factor
        copy.history = history.map { $0 * factor }
        copy.previousClose = previousClose.map { $0 * factor }
        return copy
    }

    /// The user's own locale decides the decimal separator, so the shipped
    /// render's "333,08" and an en_US "333.08" are the same call.
    var priceText: String { price.formatted(.number.precision(.fractionLength(2))) }

    var percentText: String {
        (changePercent / 100).formatted(
            .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: true))
        )
    }
}

// MARK: - Library previews

extension StockQuote {
    /// Representative values for the widget library, which has no live data.
    /// These are the numbers in the reference art.
    static func preview(_ symbol: String) -> StockQuote {
        let key = StockService.normalised(symbol)
        let known: [String: (price: Double, percent: Double, name: String)] = [
            "AAPL": (232.18, 2.41, "Apple Inc."),
            "MSFT": (428.55, 1.05, "Microsoft Corporation"),
            "NVDA": (142.86, 4.82, "NVIDIA Corporation"),
            "TSLA": (251.30, 3.10, "Tesla, Inc."),
            "GOOGL": (171.20, 0.38, "Alphabet Inc."),
            "AMZN": (186.42, -0.62, "Amazon.com, Inc."),
            "600519.SS": (1486.20, -1.51, "KWEICHOW MOUTAI"),
            "GC=F": (2412.50, 0.64, "Gold"),
            "SI=F": (30.85, -0.42, "Silver"),
            PreciousMetal.exchangeSymbol: (7.12, 0.02, "USD/CNY"),
        ]
        let sample = known[key] ?? (128.40, 0.86, key)
        let previous = sample.price / (1 + sample.percent / 100)
        // The walk is a shape; pinned to run from yesterday's close to today's
        // price so the dashed line and the last point agree with the figures.
        let walk = sampleHistory(seed: key, rising: sample.percent >= 0)
        let low = walk.min() ?? 0, high = walk.max() ?? 1
        let first = walk.first ?? 0, last = walk.last ?? 1
        let history = walk.enumerated().map { index, value -> Double in
            let t = Double(index) / Double(max(walk.count - 1, 1))
            let line = previous + (sample.price - previous) * t
            let wiggle = (value - (first + (last - first) * t)) / max(high - low, 0.001)
            return line + wiggle * abs(sample.price - previous) * 0.8 + wiggle * sample.price * 0.002
        }
        // A session of 6.5 hours, three-quarters gone.
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let step = 300.0
        let times = history.indices.map { start.timeIntervalSince1970 + Double($0) * step }
        var state = key.unicodeScalars.reduce(UInt64(0x51ED_270B)) { $0 &* 33 &+ UInt64($1.value) }
        let volumes: [Double] = history.indices.map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double((state >> 33) % 1000) / 1000
            let edge = index < 6 || index > history.count - 6 ? 2.2 : 1
            return (40_000 + noise * 90_000) * edge
        }
        return StockQuote(
            symbol: key.isEmpty ? "AAPL" : key,
            name: sample.name,
            price: sample.price,
            change: sample.price - previous,
            changePercent: sample.percent,
            currency: key == "600519.SS" ? "CNY" : "USD",
            history: history,
            stale: false,
            times: times,
            volumes: volumes,
            previousClose: previous,
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(step * Double(history.count) * 4 / 3),
            volume: volumes.reduce(0, +)
        )
    }

    /// A deterministic random walk - same symbol, same squiggle every launch,
    /// so the library card does not shimmer as it redraws.
    private static func sampleHistory(seed: String, rising: Bool) -> [Double] {
        var state = seed.unicodeScalars.reduce(UInt64(0x9E37_79B9)) { $0 &* 31 &+ UInt64($1.value) }
        var value = 0.0
        return (0..<78).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double((state >> 33) % 1000) / 1000 - 0.5
            value += noise * 0.9 + (rising ? 0.07 : -0.07)
            return value
        }
    }
}
