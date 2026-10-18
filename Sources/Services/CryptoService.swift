import Foundation
import Observation

/// Coin prices for the 加密货币行情 widget, from CoinGecko's free public API.
///
/// One request per quote currency covers every coin every widget on the
/// shelf is showing, at most every five minutes (`CryptoMarket.shouldFetch`).
/// The last good table is kept in memory and written to Caches, so the widget
/// opens with numbers after a relaunch and keeps them through a failed fetch,
/// marked stale rather than blanked. Nothing is fetched until a crypto widget
/// asks.
@MainActor @Observable
final class CryptoService {
    static let shared = CryptoService()

    private(set) var snapshots: [String: CryptoSnapshot] = [:]
    /// Currencies whose last fetch failed; their table is the previous one.
    private(set) var failed: Set<String> = []

    @ObservationIgnored private var tracked: [String: Set<String>] = [:]
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var timer: Timer?

    private init() {
        for currency in ["cny", "usd"] {
            if let cached = Self.readCache(currency) { snapshots[currency] = cached }
        }
    }

    // MARK: Public surface

    func quote(_ id: String, currency: String) -> CryptoQuote? {
        snapshots[currency]?.quotes[id]
    }

    func updated(_ currency: String) -> Date? { snapshots[currency]?.fetched }

    func isStale(_ currency: String) -> Bool { failed.contains(currency) }

    /// Registers what a widget is showing and fetches if the gate allows.
    func track(_ ids: [String], currency: String) {
        let wanted = Set(ids)
        guard !wanted.isEmpty else { return }
        tracked[currency, default: []].formUnion(wanted)
        startTimer()
        tick()
    }

    // MARK: Cadence

    private func startTimer() {
        guard timer == nil else { return }
        // A minute is only how often the gate is asked; the gate itself keeps
        // the requests five minutes apart.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date.now
        for (currency, ids) in tracked where !ids.isEmpty && !inFlight.contains(currency) {
            let have = snapshots[currency]?.quotes ?? [:]
            let missing = ids.contains { have[$0] == nil }
            guard CryptoMarket.shouldFetch(lastAttempt: lastAttempt[currency], now: now, missing: missing)
            else { continue }
            lastAttempt[currency] = now
            inFlight.insert(currency)
            let list = ids.sorted()
            Task {
                let fresh = await Self.fetch(ids: list, currency: currency)
                inFlight.remove(currency)
                if let fresh, !fresh.isEmpty {
                    let merged = CryptoMarket.merged(snapshots[currency], fresh: fresh,
                                                     currency: currency, at: .now)
                    snapshots[currency] = merged
                    failed.remove(currency)
                    Self.writeCache(merged)
                } else {
                    failed.insert(currency)
                }
            }
        }
    }

    // MARK: Network

    nonisolated private static func fetch(ids: [String], currency: String) async -> [String: CryptoQuote]? {
        guard let url = CryptoMarket.marketsURL(ids: ids, currency: currency) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Docket (macOS dock widget; https://github.com/hanson-zz/docket-zh)",
                         forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return nil }
            return CryptoMarket.parse(data)
        } catch {
            return nil
        }
    }

    // MARK: Cache

    private static func cacheURL(_ currency: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("crypto-\(currency).json")
    }

    private static func readCache(_ currency: String) -> CryptoSnapshot? {
        guard let url = cacheURL(currency), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(CryptoSnapshot.self, from: data)
    }

    private static func writeCache(_ snapshot: CryptoSnapshot) {
        guard let url = cacheURL(snapshot.currency) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Library previews

extension CryptoQuote {
    /// Representative values for the library and the screenshots, which have
    /// no live data. A deterministic walk per coin so the card holds still.
    static func preview(_ id: String, currency: String) -> CryptoQuote {
        let usd: [String: (symbol: String, name: String, price: Double, change: Double)] = [
            "bitcoin": ("BTC", "Bitcoin", 78_420, 1.09),
            "ethereum": ("ETH", "Ethereum", 3_046.5, -2.31),
            "solana": ("SOL", "Solana", 182.37, 4.62),
            "binancecoin": ("BNB", "BNB", 612.4, 0.35),
            "dogecoin": ("DOGE", "Dogecoin", 0.1834, -1.2),
        ]
        let sample = usd[id] ?? (symbol: CryptoMarket.label(id: id, quote: nil), name: id, price: 12.5, change: 0.8)
        let rate = currency == "usd" ? 1 : 7.12
        var state = id.unicodeScalars.reduce(UInt64(0x9E37_79B9)) { $0 &* 31 &+ UInt64($1.value) }
        var value = 100.0
        let walk: [Double] = (0..<CryptoMarket.sparklinePoints).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double((state >> 33) % 1000) / 1000 - 0.5
            value += noise * 1.2 + sample.change * 0.04
            return value
        }
        return CryptoQuote(id: id, symbol: sample.symbol, name: sample.name,
                           price: sample.price * rate, change24h: sample.change, sparkline: walk,
                           change7d: CryptoMarket.weekChange(walk))
    }
}
