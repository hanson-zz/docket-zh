import Foundation
import Observation

/// 找台的网络请求：流派多 tag 一页、国家台数。都只在收音机面板开着时由面板发起，
/// 面板关掉时面板取消自己的 Task，URLSession 的请求跟着取消。
enum RadioBrowseService {
    /// 一页结果：几个 tag 各查一次（并发），合并去重排好接在 `shown` 后面。
    /// 全部镜像都没回答时是 nil；被取消时也是 nil。
    nonisolated static func page(_ search: RadioSearch, page: Int, shown: [RadioListing],
                                 limit: Int = RadioBrowse.pageSize) async -> (listings: [RadioListing], more: Bool)? {
        let offset = RadioBrowse.offset(page: page, size: limit)
        let tagCount = max(1, search.genre?.tags.count ?? 1)
        let answers = await withTaskGroup(of: (Int, [RadioListing], Int)?.self) { group in
            for index in 0..<tagCount {
                group.addTask {
                    for host in RadioBrowser.hosts {
                        if Task.isCancelled { return nil }
                        let urls = search.urls(offset: offset, limit: limit, host: host)
                        guard urls.indices.contains(index),
                              let data = await get(urls[index]),
                              let parsed = RadioBrowser.parseListings(data) else { continue }
                        return (index, parsed.listings, parsed.rows)
                    }
                    return nil
                }
            }
            var collected: [(Int, [RadioListing], Int)] = []
            for await answer in group { if let answer { collected.append(answer) } }
            return collected.sorted { $0.0 < $1.0 }
        }
        guard !Task.isCancelled, !answers.isEmpty else { return nil }
        let merged = RadioBrowse.merge(shown, batches: answers.map(\.1))
        return (merged, RadioBrowse.hasMore(rowsPerTag: answers.map(\.2), size: limit))
    }

    /// 国家和台数，nil 是都没回答。
    nonisolated static func countries() async -> [RadioCountry]? {
        for host in RadioBrowser.hosts {
            if Task.isCancelled { return nil }
            guard let url = RadioCountries.countriesURL(host: host), let data = await get(url),
                  let list = RadioCountries.parse(data), !list.isEmpty else { continue }
            return list
        }
        return nil
    }

    nonisolated private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RadioBrowser.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data
    }
}

/// 国家台数（缓存一天，存在 UserDefaults）和点阵地图资源，几个收音机面板共用。
@MainActor @Observable
final class RadioWorldStore {
    static let shared = RadioWorldStore()

    private static let cacheKey = "radio.countries.cache"
    private static let cacheDateKey = "radio.countries.savedAt"

    private(set) var countries: [RadioCountry] = []
    private(set) var loading = false
    private(set) var failed = false
    /// 点阵地图；资源读不出来时是 nil，世界页只给列表。
    let map: RadioWorldMap?

    @ObservationIgnored private var savedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 每发一次加一，取消后才回来的旧回答不动新的状态。
    @ObservationIgnored private var generation = 0

    private init() {
        let defaults = UserDefaults.standard
        countries = RadioCountries.decode(defaults.string(forKey: Self.cacheKey) ?? "")
        savedAt = defaults.object(forKey: Self.cacheDateKey) as? Date
        if let url = Bundle.main.url(forResource: "radio-world-dots", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            map = RadioWorldMap(data: data)
        } else {
            map = nil
        }
    }

    var counts: [String: Int] {
        Dictionary(countries.map { ($0.code, $0.count) }, uniquingKeysWith: +)
    }

    /// 缓存过期（或没有）时取一次；面板打开世界页或搜索页时调用。
    func refreshIfStale(now: Date = .now) {
        guard task == nil, countries.isEmpty || !RadioCountries.isFresh(savedAt: savedAt, now: now) else { return }
        loading = true
        failed = false
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            let list = await RadioBrowseService.countries()
            guard let self, mine == self.generation else { return }
            self.task = nil
            self.loading = false
            guard !Task.isCancelled else { return }
            if let list {
                self.countries = list
                self.savedAt = .now
                UserDefaults.standard.set(RadioCountries.encode(list), forKey: Self.cacheKey)
                UserDefaults.standard.set(self.savedAt, forKey: Self.cacheDateKey)
            } else {
                self.failed = self.countries.isEmpty
            }
        }
    }

    /// 面板关掉时取消还没回来的请求。
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        loading = false
    }
}
