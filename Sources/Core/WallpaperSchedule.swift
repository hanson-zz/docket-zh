import Foundation

/// 壁纸：收藏，和按早中晚自动换（Pro）。
///
/// 收藏存在 `favorites`（图片路径）。自动换的设置都放在卡片配置里：
/// - `autoChange`：开没开。没解锁 Pro 时不换，配置照旧存着，解锁后自动恢复。
/// - `morningAt`、`noonAt`、`eveningAt`：三个时刻，“HH:mm”。
/// - `morningPicture`、`noonPicture`、`eveningPicture`：到点放的那张（固定这张时用）。
/// - `autoSource`：`fixed` 固定这张，`favorites` 从收藏随机。
/// - `followSun`：早上跟日出、晚上跟日落（中午仍按设的时刻）。
///
/// 哪一段由 `slot(at:)` 算：今天已经过了的最后一个时刻那段；今天第一个时刻
/// 之前算昨天晚上那段。每一段有一个 `occurrence` 键（日期加段名），换过就记下，
/// 同一段不再换第二次；重启后键没变也不重换。
public enum WallpaperSchedule {

    public static let favoritesKey = "favorites"
    public static let autoChangeKey = "autoChange"
    public static let autoSourceKey = "autoSource"
    public static let followSunKey = "followSun"
    public static let maxFavorites = 200

    public enum Slot: String, CaseIterable, Sendable {
        case morning, noon, evening

        public var title: String {
            switch self {
            case .morning: tr("早上")
            case .noon: tr("中午")
            case .evening: tr("晚上")
            }
        }

        public var timeKey: String { "\(rawValue)At" }
        public var pictureKey: String { "\(rawValue)Picture" }

        /// 默认 06:00、12:00、19:00，分钟数。
        public var defaultMinutes: Int {
            switch self {
            case .morning: 6 * 60
            case .noon: 12 * 60
            case .evening: 19 * 60
            }
        }
    }

    public enum Source: String, CaseIterable, Sendable {
        case fixed, favorites

        public var title: String {
            switch self {
            case .fixed: tr("固定这张")
            case .favorites: tr("从收藏随机")
            }
        }
    }

    // MARK: 收藏

    public static func favorites(_ config: WidgetConfig) -> [String] {
        config.strings(favoritesKey)
    }

    public static func isFavorite(_ path: String, _ config: WidgetConfig) -> Bool {
        favorites(config).contains(path)
    }

    /// 点星星：没收藏的加进来，收藏了的去掉。满了不加，返回 false。
    @discardableResult
    public static func toggleFavorite(_ path: String, in config: inout WidgetConfig) -> Bool {
        var list = favorites(config)
        if let index = list.firstIndex(of: path) {
            list.remove(at: index)
        } else {
            guard list.count < maxFavorites else { return false }
            list.append(path)
        }
        config.set(favoritesKey, .list(list.map { .string($0) }))
        return true
    }

    // MARK: 时刻

    /// “06:00” → 360；认不出是 nil。
    public static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func text(_ minutes: Int) -> String {
        let value = ((minutes % 1_440) + 1_440) % 1_440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// 存着的三个时刻，没存或认不出的用默认值。
    public static func storedMinutes(_ config: WidgetConfig) -> [Slot: Int] {
        var result: [Slot: Int] = [:]
        for slot in Slot.allCases {
            result[slot] = minutes(config.string(slot.timeKey)) ?? slot.defaultMinutes
        }
        return result
    }

    /// 实际用的三个时刻：跟日出日落时早上、晚上换成那天的日出、日落（给了才换）。
    public static func effectiveMinutes(_ config: WidgetConfig, sunrise: Int?, sunset: Int?) -> [Slot: Int] {
        var result = storedMinutes(config)
        if config.bool(followSunKey) {
            if let sunrise { result[.morning] = sunrise }
            if let sunset { result[.evening] = sunset }
        }
        return result
    }

    public static func source(_ config: WidgetConfig) -> Source {
        Source(rawValue: config.string(autoSourceKey)) ?? .fixed
    }

    // MARK: 现在是哪段

    public struct Occurrence: Equatable, Sendable {
        public var slot: Slot
        /// 这段开始的时刻。
        public var start: Date
        /// “2026-10-20 morning”，同一段只换一次。
        public var key: String
    }

    /// `date` 落在哪一段。三个时刻按先后排；相同的时刻后面的段算数。
    public static func slot(at date: Date, minutes: [Slot: Int], calendar: Calendar = .current) -> Occurrence? {
        let day = calendar.startOfDay(for: date)
        let sorted = Slot.allCases
            .map { ($0, min(max(minutes[$0] ?? $0.defaultMinutes, 0), 1_439)) }
            .sorted { $0.1 == $1.1 ? index($0.0) < index($1.0) : $0.1 < $1.1 }
        func at(_ minute: Int, on day: Date) -> Date? {
            calendar.date(byAdding: .minute, value: minute, to: day)
        }
        var found: (Slot, Date)?
        for (slot, minute) in sorted {
            guard let start = at(minute, on: day), start <= date else { continue }
            found = (slot, start)
        }
        if found == nil, let last = sorted.last,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
           let start = at(last.1, on: yesterday) {
            found = (last.0, start)
        }
        guard let found else { return nil }
        let (slot, start) = found
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let key = "\(stamp) \(slot.rawValue)"
        return Occurrence(slot: slot, start: start, key: key)
    }

    private static func index(_ slot: Slot) -> Int {
        Slot.allCases.firstIndex(of: slot) ?? 0
    }

    /// 到点放哪张。固定这张：这段设的那张（没设就不换）；从收藏随机：收藏里
    /// 挑一张，尽量不和现在这张一样（只剩这一张时就是它）。`roll` 在 0..<1。
    /// `available` 是还找得到的图片路径，找不到的跳过。
    public static func pick(_ slot: Slot, config: WidgetConfig, current: String?,
                            available: Set<String>?, roll: Double) -> String? {
        switch source(config) {
        case .fixed:
            let path = config.string(slot.pictureKey)
            guard !path.isEmpty else { return nil }
            if let available, !available.contains(path) { return nil }
            return path
        case .favorites:
            var list = favorites(config)
            if let available { list = list.filter { available.contains($0) } }
            guard !list.isEmpty else { return nil }
            let others = list.filter { $0 != current }
            let pool = others.isEmpty ? list : others
            let clamped = min(max(roll.isFinite ? roll : 0, 0), 0.999_999)
            return pool[Int(clamped * Double(pool.count))]
        }
    }

    /// 日出日落换成当天的分钟数（按 `calendar` 的时区）。
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
