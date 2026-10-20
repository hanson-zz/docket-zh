import Foundation
import Observation

/// 法定节假日安排：内置一年，之后的年份从 holiday-cn 获取并缓存。
///
/// NateScarlet/holiday-cn (MIT) turns each State Council notice into one
/// JSON file per year within a day of publication. It is read through
/// jsDelivr, which is reachable from mainland China, with GitHub's raw host
/// as the fallback. A year that is not announced yet comes back empty and is
/// simply tried again later; until then the widget shows the festival days
/// themselves and says the schedule is not out.
@MainActor @Observable
final class HolidayService {
    static let shared = HolidayService()

    static let attribution = tr("放假安排来自国务院办公厅通知，经 holiday-cn 整理")

    private(set) var known: [Int: [HolidayDay]] = HolidaySchedule.bundled

    @ObservationIgnored private var lastAttempt: Date = .distantPast
    @ObservationIgnored private var fetching = false

    private init() {
        for (year, days) in Self.readCache() where days.count > 0 {
            known[year] = days
        }
        // 法定工作日闹钟在 Core 里查同一份安排。
        AlarmHolidays.update(known)
    }

    /// The breaks of this year and the next, official where announced.
    func breaks(now: Date) -> [HolidayBreak] {
        let year = ChineseCalendar.gregorian.component(.year, from: now)
        return HolidaySchedule.breaks(years: year...(year + 1), known: known)
    }

    /// Fetches the years still missing, at most every six hours.
    func refresh(now: Date = .now) {
        let year = ChineseCalendar.gregorian.component(.year, from: now)
        let missing = [year, year + 1].filter { known[$0] == nil }
        guard !missing.isEmpty, !fetching, now.timeIntervalSince(lastAttempt) > 6 * 3_600 else { return }
        fetching = true
        lastAttempt = now
        Task {
            defer { fetching = false }
            for wanted in missing {
                guard let days = await Self.fetch(year: wanted) else { continue }
                known[wanted] = days
            }
            AlarmHolidays.update(known)
            Self.writeCache(known.filter { HolidaySchedule.bundled[$0.key] == nil })
        }
    }

    private static func fetch(year: Int) async -> [HolidayDay]? {
        let sources = [
            "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json",
            "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json",
        ]
        for source in sources {
            guard let url = URL(string: source) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Dockling (macOS dock widget; https://github.com/hanson-zz/docket-zh)",
                             forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            // An empty file means the notice is not out: not an error, and
            // no reason to ask the other host.
            return HolidaySchedule.parse(data)
        }
        return nil
    }

    // MARK: Cache

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("holidays-cn.json")
    }

    private static func readCache() -> [Int: [HolidayDay]] {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: [HolidayDay]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, days in Int(key).map { ($0, days) } })
    }

    private static func writeCache(_ years: [Int: [HolidayDay]]) {
        guard let url = cacheURL else { return }
        let stored = Dictionary(uniqueKeysWithValues: years.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
