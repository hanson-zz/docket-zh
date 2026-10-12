import Foundation
import Observation

/// Exchange rates from a free, keyless provider, cached on disk.
///
/// open.er-api.com publishes the day's rates against any base without an API
/// key; its terms ask for attribution, shown wherever the rates are. One
/// fetch with CNY as the base covers every pair, and the last good table is
/// written to Caches so the widget keeps working offline, with its date shown
/// so nobody mistakes yesterday's rate for today's.
@MainActor @Observable
final class CurrencyService {
    static let shared = CurrencyService()

    static let attribution = "汇率数据来自 ExchangeRate-API（open.er-api.com），每日更新"
    static let attributionURL = URL(string: "https://www.exchangerate-api.com")!
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/CNY")!

    private(set) var rates: CurrencyRates?
    private(set) var loading = false
    /// Set when the last fetch failed; the cached table stays in use.
    private(set) var failed = false

    @ObservationIgnored private var lastAttempt: Date = .distantPast
    @ObservationIgnored private var started = false

    private init() {
        rates = Self.readCache()
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    /// Fetches when the table is stale, at most once every ten minutes.
    func refresh(force: Bool = false) {
        let now = Date.now
        if !force, let rates, !rates.isStale(now: now) { return }
        guard !loading, force || now.timeIntervalSince(lastAttempt) > 600 else { return }
        loading = true
        lastAttempt = now
        Task {
            defer { loading = false }
            var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
            request.setValue("Dockling (macOS dock widget; https://github.com/hanson-zz/docket-zh)",
                             forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let parsed = CurrencyRates.parse(data) else {
                    failed = true
                    return
                }
                rates = parsed
                failed = false
                Self.writeCache(parsed)
            } catch {
                failed = true
            }
        }
    }

    // MARK: Cache

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("currency-rates.json")
    }

    private static func readCache() -> CurrencyRates? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(CurrencyRates.self, from: data)
    }

    private static func writeCache(_ rates: CurrencyRates) {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(rates) { try? data.write(to: url, options: .atomic) }
    }
}
