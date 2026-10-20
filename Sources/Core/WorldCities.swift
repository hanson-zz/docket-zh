import Foundation

/// 城市卡右上角画哪个地标。按城市映射，不按时区：北京和上海同在
/// Asia/Shanghai，一个是天坛，一个是东方明珠。没有专属地标的城市画通用天际线。
/// 线稿本身在 Widgets/Landmarks/CityLandmarks.swift。
public enum CityLandmark: String, CaseIterable, Sendable {
    case templeOfHeaven, orientalPearl, bigBen, empireState, tokyoTower,
         eiffelTower, sydneyOpera, burjKhalifa, marinaBaySands, skyline
}

/// 世界时钟里的一个城市：显示名、IANA 时区，以及内置表里的英文名、国家、
/// 拼音别名、地标。存进配置时编码成 "时区|名字"（`storageKey`），世界时钟
/// 的 `cities` 和时钟面板的 `clockCities` 用的是同一套。
public struct WorldCity: Equatable, Hashable, Sendable, Identifiable {
    /// 稳定的标识：内置城市是 "paris" 这种，表外的（系统时区、手改的配置）
    /// 是 "时区|名字"。判断“已添加”看它。
    public var id: String
    /// 界面上显示的名字（内置城市是当前界面语言的名字），写进 `city`。
    public var name: String
    /// IANA 时区标识，写进 `zone`。
    public var zone: String
    /// 拼音和其他别名，搜索时也认。
    public var aliases: [String]
    /// 国家或地区，列表里小字显示。
    public var region: String
    /// 英文名，添加城市时名字后面的小字，搜索也认。
    public var english: String
    /// 内置表里的中文原名（本地化的键），表外的城市为空。存着的名字是
    /// 别的界面语言写的也能认回来。
    public var key: String
    public var landmark: CityLandmark

    /// 表外的城市：系统时区或者旧配置里的名字。
    public init(name: String, zone: String, aliases: [String] = [], region: String = "") {
        self.id = "\(zone)|\(name)"
        self.name = name
        self.zone = zone
        self.aliases = aliases
        self.region = region
        self.english = ""
        self.key = ""
        self.landmark = .skyline
    }

    public init(id: String, name: String, key: String, english: String, region: String, zone: String,
                aliases: [String], landmark: CityLandmark = .skyline) {
        self.id = id
        self.name = name
        self.zone = zone
        self.aliases = aliases
        self.region = region
        self.english = english
        self.key = key
        self.landmark = landmark
    }

    /// 内置表里的城市（有英文名、国家、地标）。
    public var isBuiltIn: Bool { !key.isEmpty }

    /// 存进配置的样子："Europe/London|伦敦"。
    public var storageKey: String { "\(zone)|\(name)" }

    /// 从 "时区|名字" 读回来。时区不存在或格式不对是 nil；名字是内置城市
    /// （任一语言的名字）时换成内置城市本身，带上地标和国家；没写名字时
    /// 用时区标识的最后一段。
    public init?(storage raw: String) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let zone = parts.first?.trimmingCharacters(in: .whitespaces), !zone.isEmpty,
              TimeZone(identifier: zone) != nil else { return nil }
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        if name.isEmpty {
            self.init(name: WorldCities.displayName(zone: zone), zone: zone)
        } else if let known = WorldCities.city(zone: zone, name: name) {
            self = known
        } else {
            self.init(name: name, zone: zone)
        }
    }

    public var timeZone: TimeZone? { TimeZone(identifier: zone) }
}

public enum WorldCities {
    private static func c(_ id: String, _ name: String, _ key: String, _ english: String, _ region: String,
                          _ zone: String, _ aliases: [String], landmark: CityLandmark = .skyline) -> WorldCity {
        WorldCity(id: id, name: name, key: key, english: english, region: region, zone: zone,
                  aliases: aliases, landmark: landmark)
    }

    /// 内置城市，大致按地区、再按使用频率排。中文名和国家走 `tr()`，
    /// 英文界面显示英文。数据随 App 内置，不联网。
    public static let all: [WorldCity] = [
        c("beijing", tr("北京"), "北京", "Beijing", tr("中国"), "Asia/Shanghai", ["beijing", "bj", "Peking"], landmark: .templeOfHeaven),
        c("shanghai", tr("上海"), "上海", "Shanghai", tr("中国"), "Asia/Shanghai", ["shanghai", "sh"], landmark: .orientalPearl),
        c("guangzhou", tr("广州"), "广州", "Guangzhou", tr("中国"), "Asia/Shanghai", ["guangzhou", "Canton", "gz"]),
        c("shenzhen", tr("深圳"), "深圳", "Shenzhen", tr("中国"), "Asia/Shanghai", ["shenzhen", "sz"]),
        c("hangzhou", tr("杭州"), "杭州", "Hangzhou", tr("中国"), "Asia/Shanghai", ["hangzhou"]),
        c("chengdu", tr("成都"), "成都", "Chengdu", tr("中国"), "Asia/Shanghai", ["chengdu"]),
        c("chongqing", tr("重庆"), "重庆", "Chongqing", tr("中国"), "Asia/Shanghai", ["chongqing"]),
        c("wuhan", tr("武汉"), "武汉", "Wuhan", tr("中国"), "Asia/Shanghai", ["wuhan"]),
        c("xian", tr("西安"), "西安", "Xi'an", tr("中国"), "Asia/Shanghai", ["xian"]),
        c("nanjing", tr("南京"), "南京", "Nanjing", tr("中国"), "Asia/Shanghai", ["nanjing"]),
        c("tianjin", tr("天津"), "天津", "Tianjin", tr("中国"), "Asia/Shanghai", ["tianjin"]),
        c("suzhou", tr("苏州"), "苏州", "Suzhou", tr("中国"), "Asia/Shanghai", ["suzhou"]),
        c("xiamen", tr("厦门"), "厦门", "Xiamen", tr("中国"), "Asia/Shanghai", ["xiamen"]),
        c("qingdao", tr("青岛"), "青岛", "Qingdao", tr("中国"), "Asia/Shanghai", ["qingdao"]),
        c("harbin", tr("哈尔滨"), "哈尔滨", "Harbin", tr("中国"), "Asia/Shanghai", ["haerbin"]),
        c("kunming", tr("昆明"), "昆明", "Kunming", tr("中国"), "Asia/Shanghai", ["kunming"]),
        c("lhasa", tr("拉萨"), "拉萨", "Lhasa", tr("中国"), "Asia/Shanghai", ["lasa"]),
        c("urumqi", tr("乌鲁木齐"), "乌鲁木齐", "Urumqi", tr("中国"), "Asia/Urumqi", ["wulumuqi"]),
        c("hongkong", tr("香港"), "香港", "Hong Kong", tr("中国香港"), "Asia/Hong_Kong", ["xianggang", "hk"]),
        c("macau", tr("澳门"), "澳门", "Macau", tr("中国澳门"), "Asia/Macau", ["aomen", "Macao"]),
        c("taipei", tr("台北"), "台北", "Taipei", tr("中国台湾"), "Asia/Taipei", ["taibei"]),
        c("kaohsiung", tr("高雄"), "高雄", "Kaohsiung", tr("中国台湾"), "Asia/Taipei", ["gaoxiong"]),
        c("tokyo", tr("东京"), "东京", "Tokyo", tr("日本"), "Asia/Tokyo", ["dongjing"], landmark: .tokyoTower),
        c("osaka", tr("大阪"), "大阪", "Osaka", tr("日本"), "Asia/Tokyo", ["daban"]),
        c("kyoto", tr("京都"), "京都", "Kyoto", tr("日本"), "Asia/Tokyo", ["jingdu"]),
        c("sapporo", tr("札幌"), "札幌", "Sapporo", tr("日本"), "Asia/Tokyo", ["zhahuang"]),
        c("fukuoka", tr("福冈"), "福冈", "Fukuoka", tr("日本"), "Asia/Tokyo", ["fugang"]),
        c("okinawa", tr("冲绳"), "冲绳", "Okinawa", tr("日本"), "Asia/Tokyo", ["chongsheng", "Naha"]),
        c("seoul", tr("首尔"), "首尔", "Seoul", tr("韩国"), "Asia/Seoul", ["shouer"]),
        c("busan", tr("釜山"), "釜山", "Busan", tr("韩国"), "Asia/Seoul", ["fushan"]),
        c("pyongyang", tr("平壤"), "平壤", "Pyongyang", tr("朝鲜"), "Asia/Pyongyang", ["pingrang"]),
        c("ulaanbaatar", tr("乌兰巴托"), "乌兰巴托", "Ulaanbaatar", tr("蒙古"), "Asia/Ulaanbaatar", ["wulanbatuo"]),
        c("singapore", tr("新加坡"), "新加坡", "Singapore", tr("新加坡"), "Asia/Singapore", ["xinjiapo"], landmark: .marinaBaySands),
        c("kualalumpur", tr("吉隆坡"), "吉隆坡", "Kuala Lumpur", tr("马来西亚"), "Asia/Kuala_Lumpur", ["jilongpo", "KL"]),
        c("bangkok", tr("曼谷"), "曼谷", "Bangkok", tr("泰国"), "Asia/Bangkok", ["mangu"]),
        c("phuket", tr("普吉岛"), "普吉岛", "Phuket", tr("泰国"), "Asia/Bangkok", ["pujidao"]),
        c("chiangmai", tr("清迈"), "清迈", "Chiang Mai", tr("泰国"), "Asia/Bangkok", ["qingmai"]),
        c("hochiminh", tr("胡志明市"), "胡志明市", "Ho Chi Minh City", tr("越南"), "Asia/Ho_Chi_Minh", ["huzhimingshi", "Saigon"]),
        c("hanoi", tr("河内"), "河内", "Hanoi", tr("越南"), "Asia/Ho_Chi_Minh", ["henei"]),
        c("jakarta", tr("雅加达"), "雅加达", "Jakarta", tr("印度尼西亚"), "Asia/Jakarta", ["yajiada"]),
        c("bali", tr("巴厘岛"), "巴厘岛", "Bali", tr("印度尼西亚"), "Asia/Makassar", ["balidao", "Denpasar"]),
        c("manila", tr("马尼拉"), "马尼拉", "Manila", tr("菲律宾"), "Asia/Manila", ["manila"]),
        c("phnompenh", tr("金边"), "金边", "Phnom Penh", tr("柬埔寨"), "Asia/Phnom_Penh", ["jinbian"]),
        c("yangon", tr("仰光"), "仰光", "Yangon", tr("缅甸"), "Asia/Yangon", ["yangguang", "Rangoon"]),
        c("vientiane", tr("万象"), "万象", "Vientiane", tr("老挝"), "Asia/Vientiane", ["wanxiang"]),
        c("newdelhi", tr("新德里"), "新德里", "New Delhi", tr("印度"), "Asia/Kolkata", ["xindeli", "Delhi"]),
        c("mumbai", tr("孟买"), "孟买", "Mumbai", tr("印度"), "Asia/Kolkata", ["mengmai", "Bombay"]),
        c("bengaluru", tr("班加罗尔"), "班加罗尔", "Bengaluru", tr("印度"), "Asia/Kolkata", ["banjialuoer", "Bangalore"]),
        c("karachi", tr("卡拉奇"), "卡拉奇", "Karachi", tr("巴基斯坦"), "Asia/Karachi", ["kalaqi"]),
        c("islamabad", tr("伊斯兰堡"), "伊斯兰堡", "Islamabad", tr("巴基斯坦"), "Asia/Karachi", ["yisilanbao"]),
        c("dhaka", tr("达卡"), "达卡", "Dhaka", tr("孟加拉国"), "Asia/Dhaka", ["daka"]),
        c("kathmandu", tr("加德满都"), "加德满都", "Kathmandu", tr("尼泊尔"), "Asia/Kathmandu", ["jiademandou"]),
        c("colombo", tr("科伦坡"), "科伦坡", "Colombo", tr("斯里兰卡"), "Asia/Colombo", ["kelunpo"]),
        c("male", tr("马累"), "马累", "Malé", tr("马尔代夫"), "Indian/Maldives", ["malei", "Male", "Maldives"]),
        c("kabul", tr("喀布尔"), "喀布尔", "Kabul", tr("阿富汗"), "Asia/Kabul", ["kabuer"]),
        c("tashkent", tr("塔什干"), "塔什干", "Tashkent", tr("乌兹别克斯坦"), "Asia/Tashkent", ["tashigan"]),
        c("almaty", tr("阿拉木图"), "阿拉木图", "Almaty", tr("哈萨克斯坦"), "Asia/Almaty", ["alamutu"]),
        c("astana", tr("阿斯塔纳"), "阿斯塔纳", "Astana", tr("哈萨克斯坦"), "Asia/Almaty", ["asitana"]),
        c("dubai", tr("迪拜"), "迪拜", "Dubai", tr("阿联酋"), "Asia/Dubai", ["dibai", "UAE"], landmark: .burjKhalifa),
        c("abudhabi", tr("阿布扎比"), "阿布扎比", "Abu Dhabi", tr("阿联酋"), "Asia/Dubai", ["abuzhabi"]),
        c("doha", tr("多哈"), "多哈", "Doha", tr("卡塔尔"), "Asia/Qatar", ["duoha"]),
        c("riyadh", tr("利雅得"), "利雅得", "Riyadh", tr("沙特阿拉伯"), "Asia/Riyadh", ["liyade"]),
        c("jeddah", tr("吉达"), "吉达", "Jeddah", tr("沙特阿拉伯"), "Asia/Riyadh", ["jida"]),
        c("kuwait", tr("科威特城"), "科威特城", "Kuwait City", tr("科威特"), "Asia/Kuwait", ["keweitecheng"]),
        c("muscat", tr("马斯喀特"), "马斯喀特", "Muscat", tr("阿曼"), "Asia/Muscat", ["masikate"]),
        c("tehran", tr("德黑兰"), "德黑兰", "Tehran", tr("伊朗"), "Asia/Tehran", ["deheilan"]),
        c("baghdad", tr("巴格达"), "巴格达", "Baghdad", tr("伊拉克"), "Asia/Baghdad", ["bageda"]),
        c("baku", tr("巴库"), "巴库", "Baku", tr("阿塞拜疆"), "Asia/Baku", ["baku"]),
        c("tbilisi", tr("第比利斯"), "第比利斯", "Tbilisi", tr("格鲁吉亚"), "Asia/Tbilisi", ["dibilisi"]),
        c("yerevan", tr("埃里温"), "埃里温", "Yerevan", tr("亚美尼亚"), "Asia/Yerevan", ["ailiwen"]),
        c("telaviv", tr("特拉维夫"), "特拉维夫", "Tel Aviv", tr("以色列"), "Asia/Jerusalem", ["telaweifu"]),
        c("jerusalem", tr("耶路撒冷"), "耶路撒冷", "Jerusalem", tr("以色列"), "Asia/Jerusalem", ["yelusaleng"]),
        c("amman", tr("安曼"), "安曼", "Amman", tr("约旦"), "Asia/Amman", ["anman"]),
        c("beirut", tr("贝鲁特"), "贝鲁特", "Beirut", tr("黎巴嫩"), "Asia/Beirut", ["beilute"]),
        c("istanbul", tr("伊斯坦布尔"), "伊斯坦布尔", "Istanbul", tr("土耳其"), "Europe/Istanbul", ["yisitanbuer"]),
        c("ankara", tr("安卡拉"), "安卡拉", "Ankara", tr("土耳其"), "Europe/Istanbul", ["ankala"]),
        c("london", tr("伦敦"), "伦敦", "London", tr("英国"), "Europe/London", ["lundun", "UK"], landmark: .bigBen),
        c("manchester", tr("曼彻斯特"), "曼彻斯特", "Manchester", tr("英国"), "Europe/London", ["manchesite"]),
        c("edinburgh", tr("爱丁堡"), "爱丁堡", "Edinburgh", tr("英国"), "Europe/London", ["aidingbao"]),
        c("dublin", tr("都柏林"), "都柏林", "Dublin", tr("爱尔兰"), "Europe/Dublin", ["dubolin"]),
        c("paris", tr("巴黎"), "巴黎", "Paris", tr("法国"), "Europe/Paris", ["bali"], landmark: .eiffelTower),
        c("nice", tr("尼斯"), "尼斯", "Nice", tr("法国"), "Europe/Paris", ["nisi"]),
        c("berlin", tr("柏林"), "柏林", "Berlin", tr("德国"), "Europe/Berlin", ["bolin"]),
        c("frankfurt", tr("法兰克福"), "法兰克福", "Frankfurt", tr("德国"), "Europe/Berlin", ["falankefu"]),
        c("munich", tr("慕尼黑"), "慕尼黑", "Munich", tr("德国"), "Europe/Berlin", ["munihei", "München"]),
        c("hamburg", tr("汉堡"), "汉堡", "Hamburg", tr("德国"), "Europe/Berlin", ["hanbao"]),
        c("amsterdam", tr("阿姆斯特丹"), "阿姆斯特丹", "Amsterdam", tr("荷兰"), "Europe/Amsterdam", ["amusitedan"]),
        c("brussels", tr("布鲁塞尔"), "布鲁塞尔", "Brussels", tr("比利时"), "Europe/Brussels", ["bulusaier"]),
        c("luxembourg", tr("卢森堡"), "卢森堡", "Luxembourg", tr("卢森堡"), "Europe/Luxembourg", ["lusenbao"]),
        c("zurich", tr("苏黎世"), "苏黎世", "Zurich", tr("瑞士"), "Europe/Zurich", ["sulishi", "Zürich"]),
        c("geneva", tr("日内瓦"), "日内瓦", "Geneva", tr("瑞士"), "Europe/Zurich", ["rineiwa"]),
        c("vienna", tr("维也纳"), "维也纳", "Vienna", tr("奥地利"), "Europe/Vienna", ["weiyena", "Wien"]),
        c("rome", tr("罗马"), "罗马", "Rome", tr("意大利"), "Europe/Rome", ["luoma", "Roma"]),
        c("milan", tr("米兰"), "米兰", "Milan", tr("意大利"), "Europe/Rome", ["milan", "Milano"]),
        c("venice", tr("威尼斯"), "威尼斯", "Venice", tr("意大利"), "Europe/Rome", ["weinisi"]),
        c("madrid", tr("马德里"), "马德里", "Madrid", tr("西班牙"), "Europe/Madrid", ["madeli"]),
        c("barcelona", tr("巴塞罗那"), "巴塞罗那", "Barcelona", tr("西班牙"), "Europe/Madrid", ["basailuona"]),
        c("lisbon", tr("里斯本"), "里斯本", "Lisbon", tr("葡萄牙"), "Europe/Lisbon", ["lisiben", "Lisboa"]),
        c("athens", tr("雅典"), "雅典", "Athens", tr("希腊"), "Europe/Athens", ["yadian"]),
        c("stockholm", tr("斯德哥尔摩"), "斯德哥尔摩", "Stockholm", tr("瑞典"), "Europe/Stockholm", ["sidegeermo"]),
        c("oslo", tr("奥斯陆"), "奥斯陆", "Oslo", tr("挪威"), "Europe/Oslo", ["aosilu"]),
        c("copenhagen", tr("哥本哈根"), "哥本哈根", "Copenhagen", tr("丹麦"), "Europe/Copenhagen", ["gebenhagen"]),
        c("helsinki", tr("赫尔辛基"), "赫尔辛基", "Helsinki", tr("芬兰"), "Europe/Helsinki", ["heerxinji"]),
        c("reykjavik", tr("雷克雅未克"), "雷克雅未克", "Reykjavik", tr("冰岛"), "Atlantic/Reykjavik", ["leikeyaweike"]),
        c("warsaw", tr("华沙"), "华沙", "Warsaw", tr("波兰"), "Europe/Warsaw", ["huasha"]),
        c("prague", tr("布拉格"), "布拉格", "Prague", tr("捷克"), "Europe/Prague", ["bulage"]),
        c("budapest", tr("布达佩斯"), "布达佩斯", "Budapest", tr("匈牙利"), "Europe/Budapest", ["budapeisi"]),
        c("bucharest", tr("布加勒斯特"), "布加勒斯特", "Bucharest", tr("罗马尼亚"), "Europe/Bucharest", ["bujialeisite"]),
        c("sofia", tr("索非亚"), "索非亚", "Sofia", tr("保加利亚"), "Europe/Sofia", ["suofeiya"]),
        c("belgrade", tr("贝尔格莱德"), "贝尔格莱德", "Belgrade", tr("塞尔维亚"), "Europe/Belgrade", ["beiergelaide"]),
        c("kyiv", tr("基辅"), "基辅", "Kyiv", tr("乌克兰"), "Europe/Kyiv", ["jifu", "Kiev"]),
        c("minsk", tr("明斯克"), "明斯克", "Minsk", tr("白俄罗斯"), "Europe/Minsk", ["mingsike"]),
        c("moscow", tr("莫斯科"), "莫斯科", "Moscow", tr("俄罗斯"), "Europe/Moscow", ["mosike"]),
        c("stpetersburg", tr("圣彼得堡"), "圣彼得堡", "Saint Petersburg", tr("俄罗斯"), "Europe/Moscow", ["shengbidebao", "St Petersburg"]),
        c("novosibirsk", tr("新西伯利亚"), "新西伯利亚", "Novosibirsk", tr("俄罗斯"), "Asia/Novosibirsk", ["xinxiboliya"]),
        c("vladivostok", tr("符拉迪沃斯托克"), "符拉迪沃斯托克", "Vladivostok", tr("俄罗斯"), "Asia/Vladivostok", ["fuladiwosituoke", "haishenwei", "海参崴"]),
        c("cairo", tr("开罗"), "开罗", "Cairo", tr("埃及"), "Africa/Cairo", ["kailuo"]),
        c("casablanca", tr("卡萨布兰卡"), "卡萨布兰卡", "Casablanca", tr("摩洛哥"), "Africa/Casablanca", ["kasabulanka"]),
        c("algiers", tr("阿尔及尔"), "阿尔及尔", "Algiers", tr("阿尔及利亚"), "Africa/Algiers", ["aerjier"]),
        c("tunis", tr("突尼斯"), "突尼斯", "Tunis", tr("突尼斯"), "Africa/Tunis", ["tunisi"]),
        c("lagos", tr("拉各斯"), "拉各斯", "Lagos", tr("尼日利亚"), "Africa/Lagos", ["lagesi"]),
        c("accra", tr("阿克拉"), "阿克拉", "Accra", tr("加纳"), "Africa/Accra", ["akela"]),
        c("dakar", tr("达喀尔"), "达喀尔", "Dakar", tr("塞内加尔"), "Africa/Dakar", ["dakaer"]),
        c("nairobi", tr("内罗毕"), "内罗毕", "Nairobi", tr("肯尼亚"), "Africa/Nairobi", ["neiluobi"]),
        c("addisababa", tr("亚的斯亚贝巴"), "亚的斯亚贝巴", "Addis Ababa", tr("埃塞俄比亚"), "Africa/Addis_Ababa", ["yadisiyabeiba"]),
        c("daressalaam", tr("达累斯萨拉姆"), "达累斯萨拉姆", "Dar es Salaam", tr("坦桑尼亚"), "Africa/Dar_es_Salaam", ["daleisisalamu"]),
        c("johannesburg", tr("约翰内斯堡"), "约翰内斯堡", "Johannesburg", tr("南非"), "Africa/Johannesburg", ["yuehanneisibao"]),
        c("capetown", tr("开普敦"), "开普敦", "Cape Town", tr("南非"), "Africa/Johannesburg", ["kaipudun"]),
        c("mauritius", tr("毛里求斯"), "毛里求斯", "Mauritius", tr("毛里求斯"), "Indian/Mauritius", ["maoliqiusi", "Port Louis"]),
        c("newyork", tr("纽约"), "纽约", "New York", tr("美国"), "America/New_York", ["niuyue", "NYC", "USA"], landmark: .empireState),
        c("washington", tr("华盛顿"), "华盛顿", "Washington, D.C.", tr("美国"), "America/New_York", ["huashengdun", "Washington DC"]),
        c("boston", tr("波士顿"), "波士顿", "Boston", tr("美国"), "America/New_York", ["boshidun"]),
        c("philadelphia", tr("费城"), "费城", "Philadelphia", tr("美国"), "America/New_York", ["feicheng"]),
        c("atlanta", tr("亚特兰大"), "亚特兰大", "Atlanta", tr("美国"), "America/New_York", ["yatelanda"]),
        c("miami", tr("迈阿密"), "迈阿密", "Miami", tr("美国"), "America/New_York", ["maiami"]),
        c("detroit", tr("底特律"), "底特律", "Detroit", tr("美国"), "America/Detroit", ["ditelv"]),
        c("chicago", tr("芝加哥"), "芝加哥", "Chicago", tr("美国"), "America/Chicago", ["zhijiage"]),
        c("houston", tr("休斯敦"), "休斯敦", "Houston", tr("美国"), "America/Chicago", ["xiusidun"]),
        c("dallas", tr("达拉斯"), "达拉斯", "Dallas", tr("美国"), "America/Chicago", ["dalasi"]),
        c("austin", tr("奥斯汀"), "奥斯汀", "Austin", tr("美国"), "America/Chicago", ["aositing"]),
        c("neworleans", tr("新奥尔良"), "新奥尔良", "New Orleans", tr("美国"), "America/Chicago", ["xinaoerliang"]),
        c("denver", tr("丹佛"), "丹佛", "Denver", tr("美国"), "America/Denver", ["danfo"]),
        c("phoenix", tr("凤凰城"), "凤凰城", "Phoenix", tr("美国"), "America/Phoenix", ["fenghuangcheng"]),
        c("saltlakecity", tr("盐湖城"), "盐湖城", "Salt Lake City", tr("美国"), "America/Denver", ["yanhucheng"]),
        c("losangeles", tr("洛杉矶"), "洛杉矶", "Los Angeles", tr("美国"), "America/Los_Angeles", ["luoshanji", "LA"]),
        c("lasvegas", tr("拉斯维加斯"), "拉斯维加斯", "Las Vegas", tr("美国"), "America/Los_Angeles", ["lasiweijiasi"]),
        c("sanfrancisco", tr("旧金山"), "旧金山", "San Francisco", tr("美国"), "America/Los_Angeles", ["jiujinshan", "SF", "sanfanshi", "三藩市"]),
        c("sanjose", tr("圣何塞"), "圣何塞", "San Jose", tr("美国"), "America/Los_Angeles", ["shenghesai", "Silicon Valley", "硅谷"]),
        c("seattle", tr("西雅图"), "西雅图", "Seattle", tr("美国"), "America/Los_Angeles", ["xiyatu"]),
        c("anchorage", tr("安克雷奇"), "安克雷奇", "Anchorage", tr("美国"), "America/Anchorage", ["ankeleiqi", "Alaska"]),
        c("honolulu", tr("檀香山"), "檀香山", "Honolulu", tr("美国"), "Pacific/Honolulu", ["tanxiangshan", "Hawaii", "夏威夷"]),
        c("toronto", tr("多伦多"), "多伦多", "Toronto", tr("加拿大"), "America/Toronto", ["duolunduo"]),
        c("montreal", tr("蒙特利尔"), "蒙特利尔", "Montreal", tr("加拿大"), "America/Toronto", ["mengtelier"]),
        c("ottawa", tr("渥太华"), "渥太华", "Ottawa", tr("加拿大"), "America/Toronto", ["wotaihua"]),
        c("vancouver", tr("温哥华"), "温哥华", "Vancouver", tr("加拿大"), "America/Vancouver", ["wengehua"]),
        c("calgary", tr("卡尔加里"), "卡尔加里", "Calgary", tr("加拿大"), "America/Edmonton", ["kaerjiali"]),
        c("halifax", tr("哈利法克斯"), "哈利法克斯", "Halifax", tr("加拿大"), "America/Halifax", ["halifakesi"]),
        c("stjohns", tr("圣约翰斯"), "圣约翰斯", "St. John's", tr("加拿大"), "America/St_Johns", ["shengyuehansi", "Newfoundland"]),
        c("mexicocity", tr("墨西哥城"), "墨西哥城", "Mexico City", tr("墨西哥"), "America/Mexico_City", ["moxigecheng"]),
        c("cancun", tr("坎昆"), "坎昆", "Cancún", tr("墨西哥"), "America/Cancun", ["kankun", "Cancun"]),
        c("havana", tr("哈瓦那"), "哈瓦那", "Havana", tr("古巴"), "America/Havana", ["hawana"]),
        c("panama", tr("巴拿马城"), "巴拿马城", "Panama City", tr("巴拿马"), "America/Panama", ["banamacheng"]),
        c("sanjuan", tr("圣胡安"), "圣胡安", "San Juan", tr("波多黎各"), "America/Puerto_Rico", ["shenghuan"]),
        c("bogota", tr("波哥大"), "波哥大", "Bogotá", tr("哥伦比亚"), "America/Bogota", ["bogeda", "Bogota"]),
        c("lima", tr("利马"), "利马", "Lima", tr("秘鲁"), "America/Lima", ["lima"]),
        c("quito", tr("基多"), "基多", "Quito", tr("厄瓜多尔"), "America/Guayaquil", ["jiduo"]),
        c("caracas", tr("加拉加斯"), "加拉加斯", "Caracas", tr("委内瑞拉"), "America/Caracas", ["jialajiasi"]),
        c("santiago", tr("圣地亚哥"), "圣地亚哥", "Santiago", tr("智利"), "America/Santiago", ["shengdiyage"]),
        c("buenosaires", tr("布宜诺斯艾利斯"), "布宜诺斯艾利斯", "Buenos Aires", tr("阿根廷"), "America/Argentina/Buenos_Aires", ["buyinuosiailisi"]),
        c("saopaulo", tr("圣保罗"), "圣保罗", "São Paulo", tr("巴西"), "America/Sao_Paulo", ["shengbaoluo", "Sao Paulo"]),
        c("riodejaneiro", tr("里约热内卢"), "里约热内卢", "Rio de Janeiro", tr("巴西"), "America/Sao_Paulo", ["liyuereneilu", "Rio"]),
        c("brasilia", tr("巴西利亚"), "巴西利亚", "Brasília", tr("巴西"), "America/Sao_Paulo", ["baxiliya", "Brasilia"]),
        c("montevideo", tr("蒙得维的亚"), "蒙得维的亚", "Montevideo", tr("乌拉圭"), "America/Montevideo", ["mengdeweidiya"]),
        c("sydney", tr("悉尼"), "悉尼", "Sydney", tr("澳大利亚"), "Australia/Sydney", ["xini"], landmark: .sydneyOpera),
        c("melbourne", tr("墨尔本"), "墨尔本", "Melbourne", tr("澳大利亚"), "Australia/Melbourne", ["moerben"]),
        c("brisbane", tr("布里斯班"), "布里斯班", "Brisbane", tr("澳大利亚"), "Australia/Brisbane", ["bulisiban"]),
        c("perth", tr("珀斯"), "珀斯", "Perth", tr("澳大利亚"), "Australia/Perth", ["posi"]),
        c("adelaide", tr("阿德莱德"), "阿德莱德", "Adelaide", tr("澳大利亚"), "Australia/Adelaide", ["adelaide"]),
        c("darwin", tr("达尔文"), "达尔文", "Darwin", tr("澳大利亚"), "Australia/Darwin", ["daerwen"]),
        c("canberra", tr("堪培拉"), "堪培拉", "Canberra", tr("澳大利亚"), "Australia/Sydney", ["kanpeila"]),
        c("auckland", tr("奥克兰"), "奥克兰", "Auckland", tr("新西兰"), "Pacific/Auckland", ["aokelan"]),
        c("wellington", tr("惠灵顿"), "惠灵顿", "Wellington", tr("新西兰"), "Pacific/Auckland", ["huilingdun"]),
        c("fiji", tr("苏瓦"), "苏瓦", "Suva", tr("斐济"), "Pacific/Fiji", ["suwa", "Fiji"]),
        c("guam", tr("关岛"), "关岛", "Guam", tr("关岛"), "Pacific/Guam", ["guandao", "Hagatna"]),
        c("tahiti", tr("帕皮提"), "帕皮提", "Papeete", tr("法属波利尼西亚"), "Pacific/Tahiti", ["papiti", "Tahiti"]),
    ]

    /// 添加城市时的“常用城市”，只列还没添加的。
    public static let commonIDs = ["beijing", "shanghai", "hongkong", "singapore", "seoul", "dubai",
                                   "losangeles", "sanfrancisco", "london", "newyork", "tokyo", "paris",
                                   "berlin", "moscow", "bangkok", "sydney"]

    public static var common: [WorldCity] {
        commonIDs.compactMap { id in all.first { $0.id == id } }
    }

    public static func city(id: String) -> WorldCity? {
        all.first { $0.id == id }
    }

    /// 搜索：先是内置城市（中文名、英文名、拼音、国家、时区标识都认，
    /// 名字开头对上的排前面），再是系统时区里标识对得上、内置表没有的。
    /// 空查询返回全部内置城市。
    public static func search(_ query: String,
                              systemZones: [String] = TimeZone.knownTimeZoneIdentifiers) -> [WorldCity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let compact = q.replacingOccurrences(of: " ", with: "")

        func matches(_ text: String) -> Bool {
            guard !text.isEmpty else { return false }
            let t = text.lowercased()
            return t.contains(q) || t.replacingOccurrences(of: " ", with: "").contains(compact)
        }

        func names(_ city: WorldCity) -> [String] { [city.name, city.key, city.english] + city.aliases }

        let builtIn = all.filter { city in
            names(city).contains(where: matches) || matches(city.region) || matches(city.zone)
        }
        func starts(_ city: WorldCity) -> Bool {
            names(city).contains { name in
                let t = name.lowercased()
                return !t.isEmpty && (t.hasPrefix(q) || t.replacingOccurrences(of: " ", with: "").hasPrefix(compact))
            }
        }
        // 稳定排序：开头对上的在前，其余保持表里的顺序。
        let ranked = builtIn.filter(starts) + builtIn.filter { !starts($0) }

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

    /// 已经存着的 `zone` 和 `city` 对应的内置城市；对不上时 nil。名字按
    /// 当前界面语言、中文原名、英文名都认。
    public static func city(zone: String, name: String) -> WorldCity? {
        all.first { $0.zone == zone && ($0.name == name || $0.key == name || $0.english == name) }
    }

    /// 时差的参照城市：本地时区在内置表里的第一个城市（Asia/Shanghai 是北京）。
    /// 表里没有本地时区时 nil，文案写“本地”。
    public static func reference(here: TimeZone = .current) -> WorldCity? {
        all.first { $0.zone == here.identifier }
    }

    /// 参照城市的名字，找不到是“本地”。
    public static func referenceName(here: TimeZone = .current) -> String {
        reference(here: here)?.name ?? tr("本地")
    }
}
