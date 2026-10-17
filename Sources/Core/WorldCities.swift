import Foundation

/// 世界时钟“选择城市”用的城市表：常用城市的中文名对应 IANA 时区，另外
/// 可以直接搜系统认识的全部时区标识。选中后写回小组件的 `zone` 和 `city`。
///
/// 一张卡片一个城市，和原来一样。
public struct WorldCity: Equatable, Hashable, Sendable, Identifiable {
    /// 卡片上显示的名字，写进 `city`。
    public var name: String
    /// IANA 时区标识，写进 `zone`。
    public var zone: String
    /// 英文名和拼音，搜索时也认。
    public var aliases: [String]
    /// 国家或地区，列表里小字显示。
    public var region: String

    public var id: String { "\(zone)|\(name)" }

    public init(name: String, zone: String, aliases: [String] = [], region: String = "") {
        self.name = name
        self.zone = zone
        self.aliases = aliases
        self.region = region
    }
}

public enum WorldCities {
    /// 内置的常用城市，按大致的使用频率排。
    public static let all: [WorldCity] = [
        WorldCity(name: tr("北京"), zone: "Asia/Shanghai", aliases: ["Beijing", "beijing", "bj"], region: tr("中国")),
        WorldCity(name: tr("上海"), zone: "Asia/Shanghai", aliases: ["Shanghai", "shanghai", "sh"], region: tr("中国")),
        WorldCity(name: tr("香港"), zone: "Asia/Hong_Kong", aliases: ["Hong Kong", "xianggang", "hk"], region: tr("中国香港")),
        WorldCity(name: tr("澳门"), zone: "Asia/Macau", aliases: ["Macau", "aomen"], region: tr("中国澳门")),
        WorldCity(name: tr("台北"), zone: "Asia/Taipei", aliases: ["Taipei", "taibei"], region: tr("中国台湾")),
        WorldCity(name: tr("乌鲁木齐"), zone: "Asia/Urumqi", aliases: ["Urumqi", "wulumuqi"], region: tr("中国")),
        WorldCity(name: tr("东京"), zone: "Asia/Tokyo", aliases: ["Tokyo", "dongjing"], region: tr("日本")),
        WorldCity(name: tr("首尔"), zone: "Asia/Seoul", aliases: ["Seoul", "shouer"], region: tr("韩国")),
        WorldCity(name: tr("新加坡"), zone: "Asia/Singapore", aliases: ["Singapore", "xinjiapo"], region: tr("新加坡")),
        WorldCity(name: tr("吉隆坡"), zone: "Asia/Kuala_Lumpur", aliases: ["Kuala Lumpur", "jilongpo"], region: tr("马来西亚")),
        WorldCity(name: tr("曼谷"), zone: "Asia/Bangkok", aliases: ["Bangkok", "mangu"], region: tr("泰国")),
        WorldCity(name: tr("胡志明市"), zone: "Asia/Ho_Chi_Minh", aliases: ["Ho Chi Minh", "Saigon", "huzhiming"], region: tr("越南")),
        WorldCity(name: tr("雅加达"), zone: "Asia/Jakarta", aliases: ["Jakarta", "yajiada"], region: tr("印度尼西亚")),
        WorldCity(name: tr("马尼拉"), zone: "Asia/Manila", aliases: ["Manila", "manila"], region: tr("菲律宾")),
        WorldCity(name: tr("新德里"), zone: "Asia/Kolkata", aliases: ["New Delhi", "Delhi", "xindeli"], region: tr("印度")),
        WorldCity(name: tr("孟买"), zone: "Asia/Kolkata", aliases: ["Mumbai", "mengmai"], region: tr("印度")),
        WorldCity(name: tr("迪拜"), zone: "Asia/Dubai", aliases: ["Dubai", "dibai"], region: tr("阿联酋")),
        WorldCity(name: tr("利雅得"), zone: "Asia/Riyadh", aliases: ["Riyadh", "liyade"], region: tr("沙特阿拉伯")),
        WorldCity(name: tr("伊斯坦布尔"), zone: "Europe/Istanbul", aliases: ["Istanbul", "yisitanbuer"], region: tr("土耳其")),
        WorldCity(name: tr("莫斯科"), zone: "Europe/Moscow", aliases: ["Moscow", "mosike"], region: tr("俄罗斯")),
        WorldCity(name: tr("伦敦"), zone: "Europe/London", aliases: ["London", "lundun"], region: tr("英国")),
        WorldCity(name: tr("都柏林"), zone: "Europe/Dublin", aliases: ["Dublin", "dubolin"], region: tr("爱尔兰")),
        WorldCity(name: tr("巴黎"), zone: "Europe/Paris", aliases: ["Paris", "bali"], region: tr("法国")),
        WorldCity(name: tr("柏林"), zone: "Europe/Berlin", aliases: ["Berlin", "bolin"], region: tr("德国")),
        WorldCity(name: tr("法兰克福"), zone: "Europe/Berlin", aliases: ["Frankfurt", "falankefu"], region: tr("德国")),
        WorldCity(name: tr("阿姆斯特丹"), zone: "Europe/Amsterdam", aliases: ["Amsterdam", "amusitedan"], region: tr("荷兰")),
        WorldCity(name: tr("苏黎世"), zone: "Europe/Zurich", aliases: ["Zurich", "suliShi", "sulishi"], region: tr("瑞士")),
        WorldCity(name: tr("罗马"), zone: "Europe/Rome", aliases: ["Rome", "luoma"], region: tr("意大利")),
        WorldCity(name: tr("马德里"), zone: "Europe/Madrid", aliases: ["Madrid", "madeli"], region: tr("西班牙")),
        WorldCity(name: tr("斯德哥尔摩"), zone: "Europe/Stockholm", aliases: ["Stockholm", "sidegeermo"], region: tr("瑞典")),
        WorldCity(name: tr("开罗"), zone: "Africa/Cairo", aliases: ["Cairo", "kailuo"], region: tr("埃及")),
        WorldCity(name: tr("约翰内斯堡"), zone: "Africa/Johannesburg", aliases: ["Johannesburg", "yuehanneisibao"], region: tr("南非")),
        WorldCity(name: tr("纽约"), zone: "America/New_York", aliases: ["New York", "NYC", "niuyue"], region: tr("美国")),
        WorldCity(name: tr("华盛顿"), zone: "America/New_York", aliases: ["Washington", "huashengdun"], region: tr("美国")),
        WorldCity(name: tr("波士顿"), zone: "America/New_York", aliases: ["Boston", "boshidun"], region: tr("美国")),
        WorldCity(name: tr("芝加哥"), zone: "America/Chicago", aliases: ["Chicago", "zhijiage"], region: tr("美国")),
        WorldCity(name: tr("丹佛"), zone: "America/Denver", aliases: ["Denver", "danfo"], region: tr("美国")),
        WorldCity(name: tr("洛杉矶"), zone: "America/Los_Angeles", aliases: ["Los Angeles", "LA", "luoshanji"], region: tr("美国")),
        WorldCity(name: tr("旧金山"), zone: "America/Los_Angeles", aliases: ["San Francisco", "SF", "jiujinshan"], region: tr("美国")),
        WorldCity(name: tr("西雅图"), zone: "America/Los_Angeles", aliases: ["Seattle", "xiyatu"], region: tr("美国")),
        WorldCity(name: tr("檀香山"), zone: "Pacific/Honolulu", aliases: ["Honolulu", "Hawaii", "tanxiangshan"], region: tr("美国")),
        WorldCity(name: tr("多伦多"), zone: "America/Toronto", aliases: ["Toronto", "duolunduo"], region: tr("加拿大")),
        WorldCity(name: tr("温哥华"), zone: "America/Vancouver", aliases: ["Vancouver", "wengehua"], region: tr("加拿大")),
        WorldCity(name: tr("墨西哥城"), zone: "America/Mexico_City", aliases: ["Mexico City", "moxigecheng"], region: tr("墨西哥")),
        WorldCity(name: tr("圣保罗"), zone: "America/Sao_Paulo", aliases: ["Sao Paulo", "shengbaoluo"], region: tr("巴西")),
        WorldCity(name: tr("布宜诺斯艾利斯"), zone: "America/Argentina/Buenos_Aires", aliases: ["Buenos Aires", "buyinuosiailisi"], region: tr("阿根廷")),
        WorldCity(name: tr("悉尼"), zone: "Australia/Sydney", aliases: ["Sydney", "xini"], region: tr("澳大利亚")),
        WorldCity(name: tr("墨尔本"), zone: "Australia/Melbourne", aliases: ["Melbourne", "moerben"], region: tr("澳大利亚")),
        WorldCity(name: tr("珀斯"), zone: "Australia/Perth", aliases: ["Perth", "posi"], region: tr("澳大利亚")),
        WorldCity(name: tr("奥克兰"), zone: "Pacific/Auckland", aliases: ["Auckland", "aokelan"], region: tr("新西兰")),
    ]

    /// 搜索：先是内置城市（中文名、英文名、拼音、国家、时区标识都认，
    /// 名字开头对上的排前面），再是系统时区里标识对得上、内置表没有的。
    /// 空查询返回全部内置城市。
    public static func search(_ query: String,
                              systemZones: [String] = TimeZone.knownTimeZoneIdentifiers) -> [WorldCity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let compact = q.replacingOccurrences(of: " ", with: "")

        func matches(_ text: String) -> Bool {
            let t = text.lowercased()
            return t.contains(q) || t.replacingOccurrences(of: " ", with: "").contains(compact)
        }

        let builtIn = all.filter { city in
            matches(city.name) || matches(city.region) || matches(city.zone)
                || city.aliases.contains(where: matches)
        }
        let ranked = builtIn.sorted { a, b in
            let aStarts = a.name.lowercased().hasPrefix(q) || a.aliases.contains { $0.lowercased().hasPrefix(q) }
            let bStarts = b.name.lowercased().hasPrefix(q) || b.aliases.contains { $0.lowercased().hasPrefix(q) }
            if aStarts != bStarts { return aStarts }
            return false
        }

        let covered = Set(all.map(\.zone))
        let extra = systemZones
            .filter { !covered.contains($0) }
            .filter { matches($0) || matches(displayName(zone: $0)) }
            .sorted()
            .map { WorldCity(name: displayName(zone: $0), zone: $0, region: tr("系统时区")) }
        return ranked + extra
    }

    /// 系统时区标识的显示名：取最后一段，下划线换成空格。
    /// `America/Argentina/Buenos_Aires` 是 “Buenos Aires”。
    public static func displayName(zone: String) -> String {
        let last = zone.split(separator: "/").last.map(String.init) ?? zone
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// 已经存着的 `zone` 和 `city` 对应的内置城市；对不上时 nil。
    public static func city(zone: String, name: String) -> WorldCity? {
        all.first { $0.zone == zone && $0.name == name }
    }
}
