import Foundation

/// 天气「多城市」样式的城市列表（存在 `cities`）：面板「编辑」里增删、排序。
///
/// 卡片一条放不下第 4 个城市（见 `WeatherLayout.maxCities`），所以卡片只显示
/// 前 3 个；面板里列出全部，最多 `maxCount` 个，排在前 3 的就是卡片上的。
/// 名字去掉首尾空白，重复的（不分大小写）只留第一个，至少留 1 个；一个能用的
/// 都没有时退回默认的北京、上海、广州，卡片永远不空。
public enum WeatherCityList {
    public static let key = "cities"
    /// 面板里最多几个城市。
    public static let maxCount = 8
    /// 卡片上显示前几个。
    public static var tileCount: Int { WeatherLayout.maxCities }

    /// 整理过的列表：去空白、去重、最多 `maxCount` 个，空了退回默认。
    public static func list(_ raw: [String]) -> [String] {
        let clean = deduped(raw)
        return clean.isEmpty ? WeatherLayout.defaultCities : clean
    }

    /// 存着的列表；没存过就是默认。
    public static func list(_ config: WidgetConfig) -> [String] {
        list(config.strings(key, default: WeatherLayout.defaultCities))
    }

    /// 写回 `cities`。空列表不写（编辑到一半的空表不是要一张空卡片）。
    public static func write(_ list: [String], to config: inout WidgetConfig) {
        let clean = deduped(list)
        guard !clean.isEmpty else { return }
        config.set(key, .list(clean.map { .string($0) }))
    }

    /// 排在第 `index` 个的城市在不在卡片上。
    public static func isOnTile(_ index: Int) -> Bool {
        index >= 0 && index < tileCount
    }

    public static func contains(_ city: String, in list: [String]) -> Bool {
        let key = normalized(city).lowercased()
        return list.contains { normalized($0).lowercased() == key }
    }

    /// 能不能再加：名字不空、没满、不重复。
    public static func canAdd(_ city: String, to list: [String]) -> Bool {
        let name = normalized(city)
        return !name.isEmpty && list.count < maxCount && !contains(name, in: list)
    }

    /// 加到最后。空名字、重复或满了原样返回。
    public static func adding(_ city: String, to list: [String]) -> [String] {
        let name = normalized(city)
        guard canAdd(name, to: list) else { return list }
        return list + [name]
    }

    /// 第 `index` 个能不能删：至少留 1 个。
    public static func canRemove(at index: Int, in list: [String]) -> Bool {
        list.count > 1 && list.indices.contains(index)
    }

    /// 删掉第 `index` 个，至少留 1 个。
    public static func removing(at index: Int, from list: [String]) -> [String] {
        guard canRemove(at: index, in: list) else { return list }
        var copy = list
        copy.remove(at: index)
        return copy
    }

    /// 把第 `from` 个挪到第 `to` 个，越界的夹到两端。
    public static func moving(from: Int, to: Int, in list: [String]) -> [String] {
        WeatherPlaces.moving(from: from, to: to, in: list)
    }

    /// 拖动松手时落在第几格：位移按行高四舍五入。
    public static func dropIndex(from: Int, translation: Double, rowHeight: Double, count: Int) -> Int {
        WeatherPlaces.dropIndex(from: from, translation: translation, rowHeight: rowHeight, count: count)
    }

    private static func normalized(_ city: String) -> String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduped(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in raw {
            let trimmed = normalized(name)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
            if out.count == maxCount { break }
        }
        return out
    }
}
