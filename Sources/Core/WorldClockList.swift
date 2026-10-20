import Foundation

/// 世界时钟的城市列表：存储、增删排序，和城市卡上的几行文案。纯计算，
/// 不碰界面，方便测试。
///
/// 存在配置的 `cities` 键里，每项 "时区|名字"（`WorldCity.storageKey`），
/// 1 到 12 个，顺序就是面板和卡片的显示顺序。没有 `cities` 的旧卡片由
/// `zone` 和 `city` 生成第一项；写入时第一项同步回 `zone` 和 `city`，
/// 旧版本和截图工具读这两个键照样对。
public enum WorldClockList {
    public static let key = "cities"
    public static let zoneKey = "zone"
    public static let cityKey = "city"
    public static let maxCount = 12
    /// 卡片最多显示几个（横排三列、竖排三行）。
    public static let tileLimit = 3

    public static let defaultZone = "Europe/London"
    public static var defaultName: String { tr("伦敦") }

    /// 旧键 `zone` + `city` 表示的城市；时区认不出时是伦敦。
    public static func legacyCity(_ config: WidgetConfig) -> WorldCity {
        let zone = config.string(zoneKey, default: defaultZone)
        let name = config.string(cityKey, default: defaultName)
        if let city = WorldCity(storage: "\(zone)|\(name)") { return city }
        return WorldCity(storage: "\(defaultZone)|\(defaultName)") ?? WorldCity(name: defaultName, zone: defaultZone)
    }

    /// 面板和卡片上的城市，至少 1 个，最多 12 个。认不出的项跳过，重复的只留第一个。
    public static func cities(_ config: WidgetConfig) -> [WorldCity] {
        var result: [WorldCity] = []
        for raw in config.strings(key) {
            guard let city = WorldCity(storage: raw), !contains(city, in: result) else { continue }
            result.append(city)
            if result.count == maxCount { break }
        }
        return result.isEmpty ? [legacyCity(config)] : result
    }

    /// 写回列表：裁到 1 到 12 个，去重，第一项同步到 `zone` 和 `city`。
    /// 传空列表什么也不改（至少留 1 个）。
    public static func write(_ cities: [WorldCity], to config: inout WidgetConfig) {
        var list: [WorldCity] = []
        for city in cities where !contains(city, in: list) && list.count < maxCount {
            list.append(city)
        }
        guard let first = list.first else { return }
        config.set(key, .list(list.map { .string($0.storageKey) }))
        config.set(zoneKey, .string(first.zone))
        config.set(cityKey, .string(first.name))
    }

    /// 同一个城市：内置城市看 id，表外的看时区和名字。
    public static func contains(_ city: WorldCity, in list: [WorldCity]) -> Bool {
        list.contains { $0.id == city.id }
    }

    public static func canAdd(_ city: WorldCity, to list: [WorldCity]) -> Bool {
        list.count < maxCount && !contains(city, in: list)
    }

    /// 加到最后；已经有了或满 12 个时原样返回。
    public static func adding(_ city: WorldCity, to list: [WorldCity]) -> [WorldCity] {
        canAdd(city, to: list) ? list + [city] : list
    }

    /// 删掉第 `index` 个；只剩 1 个时不删。
    public static func removing(at index: Int, from list: [WorldCity]) -> [WorldCity] {
        guard list.count > 1, list.indices.contains(index) else { return list }
        var copy = list
        copy.remove(at: index)
        return copy
    }

    /// 把第 `from` 个挪到第 `to` 个的位置（挪完之后的下标）。
    public static func moving(from: Int, to: Int, in list: [WorldCity]) -> [WorldCity] {
        guard list.indices.contains(from) else { return list }
        let target = min(max(0, to), list.count - 1)
        guard target != from else { return list }
        var copy = list
        let item = copy.remove(at: from)
        copy.insert(item, at: target)
        return copy
    }

    /// 拖动把手时，按位移算落到哪一格：每过半行换一格。
    public static func dropIndex(from: Int, translation: Double, rowHeight: Double, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return from }
        let steps = Int((translation / rowHeight).rounded())
        return min(max(0, from + steps), count - 1)
    }

    /// 卡片上显示的城市：列表前 3 个（横排 168×58 和竖排都一样）。
    public static func tileCities(_ config: WidgetConfig) -> [WorldCity] {
        Array(cities(config).prefix(tileLimit))
    }

    /// 竖排时卡片的高度：1 个城市保持原来的 76，多个时每个城市一行。
    public static func verticalHeight(_ config: WidgetConfig) -> Double {
        let count = tileCities(config).count
        return count <= 1 ? 76 : Double(count * 52 + 8)
    }
}

/// 城市卡上的文案：时差、几点钟的说法、星期或昨天明天。
public enum WorldClockText {

    /// 当地比此处快多少秒（慢是负数），按这一刻各自的规则算，夏令时自动对。
    public static func offsetSeconds(_ zone: TimeZone, now: Date, here: TimeZone = .current) -> Int {
        zone.secondsFromGMT(for: now) - here.secondsFromGMT(for: now)
    }

    /// “7 小时”“5 小时 30 分”“45 分”。
    public static func duration(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return tr("\(m) 分") }
        if m == 0 { return tr("\(h) 小时") }
        return tr("\(h) 小时 \(m) 分")
    }

    /// “比北京晚 7 小时”“比北京早 5 小时 30 分”“与北京相同”。
    public static func difference(_ seconds: Int, reference: String) -> String {
        guard seconds != 0 else { return tr("与\(reference)相同") }
        let amount = duration(seconds)
        return seconds > 0 ? tr("比\(reference)早 \(amount)") : tr("比\(reference)晚 \(amount)")
    }

    /// 城市卡名字下面那行。这座城市就是参照城市时写“此处”；参照名取本地
    /// 时区在内置表里的第一个城市，找不到写“本地”。
    public static func offsetLine(_ city: WorldCity, now: Date, here: TimeZone = .current) -> String {
        let reference = WorldCities.reference(here: here)
        if let reference, reference.id == city.id { return tr("此处") }
        let zone = city.timeZone ?? here
        return difference(offsetSeconds(zone, now: now, here: here),
                          reference: reference?.name ?? tr("本地"))
    }

    /// 几点钟的说法：凌晨、清晨、上午、中午、下午、傍晚、晚上。
    public static func dayPart(hour: Int) -> String {
        switch hour {
        case ..<5: tr("凌晨")
        case 5..<8: tr("清晨")
        case 8..<11: tr("上午")
        case 11..<13: tr("中午")
        case 13..<17: tr("下午")
        case 17..<19: tr("傍晚")
        default: tr("晚上")
        }
    }

    /// 星期几，“周二”。`weekday` 按公历 1 是周日。
    public static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: tr("周日")
        case 2: tr("周一")
        case 3: tr("周二")
        case 4: tr("周三")
        case 5: tr("周四")
        case 6: tr("周五")
        default: tr("周六")
        }
    }

    /// 时间大字下面那行：同一天是“周二 · 凌晨”，不是同一天是“昨天 · 晚上”
    /// 或“明天 · 上午”。
    public static func dayLine(_ zone: TimeZone, now: Date, here: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .weekday], from: now)
        let part = dayPart(hour: parts.hour ?? 0)
        let day: String
        switch ClockPanelData.dayOffset(now, zone: zone, here: here) {
        case ..<0: day = tr("昨天")
        case 1...: day = tr("明天")
        default: day = weekdayName(parts.weekday ?? 1)
        }
        return "\(day) · \(part)"
    }

    /// 当地 6 点到 18 点算白天（按钟点，不按日出），和时钟面板一样。
    public static func isDaytime(_ zone: TimeZone, now: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return ClockPanelData.isDaytime(hour: calendar.component(.hour, from: now))
    }

    /// 面板头上那行：“此处 北京 10:18 · 6 个城市”。`time` 由界面按系统
    /// 12/24 小时制格式化好传进来。
    public static func header(time: String, count: Int, here: TimeZone = .current) -> String {
        tr("此处 \(WorldCities.referenceName(here: here)) \(time) · \(count) 个城市")
    }
}
