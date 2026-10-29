import Foundation

// MARK: - 卜卦 · 每日一签的附加功能
//
// 免费：星座 / 属相（定签的种子、徽章、今日幸运色和幸运数字）、本周寄语。
// Pro：签历（抽过的签按日期自动记下，月历回顾、收藏）、签卡分享图、签筒和铜钱皮肤。
// 签历和皮肤的设置都存在卡片配置里；没解锁时照常记、照常存，只是看不到、用不上，
// 解锁或试用后原样回来（见 `ProLicenseGate` 的卜卦部分）。

// MARK: - 星座和属相

/// 每日一签可选的星座（12 个）或属相（12 个）。选了以后定签用「日期 + 星座 / 属相」，
/// 同一天同一个星座在哪张卡片上都是同一支；不选时照旧用「日期 + 卡片 id」。
public enum DivinationSign: String, CaseIterable, Sendable {
    case aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius, capricorn, aquarius, pisces
    case rat, ox, tiger, rabbit, dragon, snake, horse, goat, monkey, rooster, dog, pig

    /// 设置里的三选一：不选、星座、属相。
    public enum Kind: String, CaseIterable, Sendable {
        case none, star, animal

        public var title: String {
            switch self {
            case .none: tr("不选")
            case .star: tr("星座")
            case .animal: tr("属相")
            }
        }

        public var signs: [DivinationSign] {
            switch self {
            case .none: []
            case .star: Array(DivinationSign.allCases.prefix(12))
            case .animal: Array(DivinationSign.allCases.suffix(12))
            }
        }
    }

    public var kind: Kind {
        (DivinationSign.allCases.firstIndex(of: self) ?? 0) < 12 ? .star : .animal
    }

    /// 「狮子座」「属龙」。
    public var name: String {
        switch self {
        case .aries: tr("白羊座")
        case .taurus: tr("金牛座")
        case .gemini: tr("双子座")
        case .cancer: tr("巨蟹座")
        case .leo: tr("狮子座")
        case .virgo: tr("处女座")
        case .libra: tr("天秤座")
        case .scorpio: tr("天蝎座")
        case .sagittarius: tr("射手座")
        case .capricorn: tr("摩羯座")
        case .aquarius: tr("水瓶座")
        case .pisces: tr("双鱼座")
        case .rat: tr("属鼠")
        case .ox: tr("属牛")
        case .tiger: tr("属虎")
        case .rabbit: tr("属兔")
        case .dragon: tr("属龙")
        case .snake: tr("属蛇")
        case .horse: tr("属马")
        case .goat: tr("属羊")
        case .monkey: tr("属猴")
        case .rooster: tr("属鸡")
        case .dog: tr("属狗")
        case .pig: tr("属猪")
        }
    }

    /// 徽章上的小符号：星座用符号字形（加 U+FE0E 按文字画，不变成彩色表情），属相用一个字。
    public var symbol: String {
        switch self {
        case .aries: "\u{2648}\u{FE0E}"
        case .taurus: "\u{2649}\u{FE0E}"
        case .gemini: "\u{264A}\u{FE0E}"
        case .cancer: "\u{264B}\u{FE0E}"
        case .leo: "\u{264C}\u{FE0E}"
        case .virgo: "\u{264D}\u{FE0E}"
        case .libra: "\u{264E}\u{FE0E}"
        case .scorpio: "\u{264F}\u{FE0E}"
        case .sagittarius: "\u{2650}\u{FE0E}"
        case .capricorn: "\u{2651}\u{FE0E}"
        case .aquarius: "\u{2652}\u{FE0E}"
        case .pisces: "\u{2653}\u{FE0E}"
        case .rat: "鼠"
        case .ox: "牛"
        case .tiger: "虎"
        case .rabbit: "兔"
        case .dragon: "龙"
        case .snake: "蛇"
        case .horse: "马"
        case .goat: "羊"
        case .monkey: "猴"
        case .rooster: "鸡"
        case .dog: "狗"
        case .pig: "猪"
        }
    }
}

/// 今日幸运色：名字加一个色块的颜色（色块另有描边，浅色深色玻璃上都看得见）。
public struct LuckyColor: Equatable, Sendable {
    public var name: String
    public var hex: String
}

/// 某天某个星座 / 属相的幸运色和幸运数字（只是轻松好玩，确定性随机）。
public struct DailyLuck: Equatable, Sendable {
    public var color: LuckyColor
    public var number: Int
}

public extension Divination {
    /// 选的星座或属相（原始值；空字符串是不选）。
    static let signKey = "sign"
    /// 签历：抽过的签，`yyyy-MM-dd=下标`，按日期从旧到新，逗号分隔。
    static let stickLogKey = "stickLog"
    /// 收藏的日子（`yyyy-MM-dd`，逗号分隔）。
    static let stickFavoritesKey = "stickFavs"
    /// 签筒皮肤、铜钱皮肤（Pro）。
    static let tubeSkinKey = "tubeSkin"
    static let coinSkinKey = "coinSkin"

    /// 签历至少留这么多天（一年多一点）；收藏的那几天一直留着。
    static let stickLogRetentionDays = 400

    // MARK: 星座和属相

    static func sign(_ config: WidgetConfig) -> DivinationSign? {
        DivinationSign(rawValue: config.string(signKey))
    }

    /// 定签用的盐：选了星座 / 属相时是它，否则是卡片自己的盐（卡片 id）。
    static func stickSalt(_ config: WidgetConfig, cardSalt: String) -> String {
        if let sign = sign(config) { return "sign:\(sign.rawValue)" }
        return cardSalt
    }

    /// 改星座 / 属相（nil 是不选）。今天已经抽过时按新的种子换成对应的那支，签历里今天这条一起改，
    /// 这样同一天同一个星座永远是同一支。
    static func setSign(_ sign: DivinationSign?, in config: inout WidgetConfig, now: Date, cardSalt: String,
                        calendar: Calendar = .current) {
        config.set(signKey, sign.map { .string($0.rawValue) })
        guard todayStick(config, now: now, calendar: calendar) != nil else { return }
        let day = dayKey(now, calendar: calendar)
        let index = seededStick(day: day, salt: stickSalt(config, cardSalt: cardSalt))
        config.set(stickKey, .number(Double(index)))
        recordStick(index, day: day, in: &config, now: now, calendar: calendar)
    }

    /// 今日幸运色可选的颜色（原创取名，都是好听的颜色）。
    static let luckyColors: [LuckyColor] = [
        LuckyColor(name: tr("朱红"), hex: "#D2402F"),
        LuckyColor(name: tr("杏黄"), hex: "#F2B33D"),
        LuckyColor(name: tr("竹青"), hex: "#5E9B5A"),
        LuckyColor(name: tr("天青"), hex: "#6FA8DC"),
        LuckyColor(name: tr("藕荷"), hex: "#B784A7"),
        LuckyColor(name: tr("月白"), hex: "#D6E4EE"),
        LuckyColor(name: tr("琥珀"), hex: "#C98A2B"),
        LuckyColor(name: tr("松绿"), hex: "#2E8B74"),
        LuckyColor(name: tr("海棠红"), hex: "#E05A6D"),
        LuckyColor(name: tr("黛紫"), hex: "#5B4B8A"),
        LuckyColor(name: tr("珊瑚橙"), hex: "#F07F5A"),
        LuckyColor(name: tr("象牙白"), hex: "#F4EEDC"),
        LuckyColor(name: tr("湖蓝"), hex: "#2F7FB6"),
        LuckyColor(name: tr("桃粉"), hex: "#F2A7B4"),
    ]

    /// 幸运数字的范围。
    static let luckyNumbers = 1...9

    /// 某天某个星座 / 属相的幸运色和幸运数字：同一天同一个总是一样，换一天大多会换。
    static func luck(day: String, sign: DivinationSign) -> DailyLuck {
        var rng = MineRandom(seed: stableHash("luck|\(day)|\(sign.rawValue)"))
        let color = luckyColors[Int.random(in: 0..<luckyColors.count, using: &rng)]
        let number = Int.random(in: luckyNumbers, using: &rng)
        return DailyLuck(color: color, number: number)
    }

    // MARK: 签历

    /// 一天的签：日期、第几支（下标）、收藏没有。
    struct StickRecord: Equatable, Sendable, Identifiable {
        public var day: String
        public var index: Int
        public var favorite: Bool
        public var id: String { day }
        public var stick: FortuneStick { FortuneStick.all[index] }

        public init(day: String, index: Int, favorite: Bool) {
            self.day = day
            self.index = index
            self.favorite = favorite
        }
    }

    /// 签历：日期到下标。坏数据（日期格式不对、下标超界）跳过。
    static func stickLog(_ config: WidgetConfig) -> [String: Int] {
        var result: [String: Int] = [:]
        for item in config.string(stickLogKey).split(separator: ",") {
            let parts = item.split(separator: "=")
            guard parts.count == 2, isDayKey(String(parts[0])), let index = Int(parts[1]),
                  FortuneStick.all.indices.contains(index) else { continue }
            result[String(parts[0])] = index
        }
        return result
    }

    static func favoriteDays(_ config: WidgetConfig) -> Set<String> {
        Set(config.string(stickFavoritesKey).split(separator: ",").map(String.init).filter(isDayKey))
    }

    /// 那天的签（没抽过是 nil）。
    static func record(day: String, in config: WidgetConfig) -> StickRecord? {
        guard let index = stickLog(config)[day] else { return nil }
        return StickRecord(day: day, index: index, favorite: favoriteDays(config).contains(day))
    }

    /// 全部签历，新的在前。
    static func records(_ config: WidgetConfig) -> [StickRecord] {
        let favorites = favoriteDays(config)
        return stickLog(config).sorted { $0.key > $1.key }
            .map { StickRecord(day: $0.key, index: $0.value, favorite: favorites.contains($0.key)) }
    }

    /// 收藏的签，新的在前。
    static func favorites(_ config: WidgetConfig) -> [StickRecord] {
        records(config).filter(\.favorite)
    }

    /// 记下某天抽到的签（同一天再记就改成新的），顺手清掉 `stickLogRetentionDays` 天以前、没收藏的。
    static func recordStick(_ index: Int, day: String, in config: inout WidgetConfig, now: Date,
                            calendar: Calendar = .current) {
        guard FortuneStick.all.indices.contains(index), isDayKey(day) else { return }
        var log = stickLog(config)
        log[day] = index
        let favorites = favoriteDays(config)
        let cutoff = calendar.date(byAdding: .day, value: -stickLogRetentionDays, to: now).map {
            dayKey($0, calendar: calendar)
        } ?? ""
        log = log.filter { $0.key >= cutoff || favorites.contains($0.key) }
        let text = log.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        config.set(stickLogKey, .string(text))
    }

    /// 收藏 / 取消收藏某天的签；那天没抽过签时不动，返回 false。返回收藏后的状态。
    @discardableResult
    static func toggleFavorite(day: String, in config: inout WidgetConfig) -> Bool {
        guard stickLog(config)[day] != nil else { return false }
        var days = favoriteDays(config)
        let on = !days.contains(day)
        if on { days.insert(day) } else { days.remove(day) }
        config.set(stickFavoritesKey, days.isEmpty ? nil : .string(days.sorted().joined(separator: ",")))
        return on
    }

    /// `yyyy-MM-dd` 这样的字符串。
    static func isDayKey(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isASCII) && Int($0) != nil }
    }

    /// 日期字符串转回那天零点（按传入的日历）。
    static func date(fromDay day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard isDayKey(day), parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 签历这一个月里每天的签级（月历的小圆点用）：日期到签级。
    static func monthLevels(_ config: WidgetConfig, month: Date, calendar: Calendar = .current) -> [String: StickLevel] {
        let prefix = String(dayKey(month, calendar: calendar).prefix(7))
        var result: [String: StickLevel] = [:]
        for (day, index) in stickLog(config) where day.hasPrefix(prefix) {
            result[day] = FortuneStick.all[index].level
        }
        return result
    }

    // MARK: 皮肤

    /// 现在该画哪款签筒：没解锁时总是默认竹签筒（选的那款照旧存着）。
    static func tubeSkin(_ config: WidgetConfig, unlocked: Bool) -> TubeSkin {
        guard unlocked else { return .bamboo }
        return TubeSkin(rawValue: config.string(tubeSkinKey)) ?? .bamboo
    }

    /// 现在该画哪款铜钱：没解锁时总是默认铜钱。
    static func coinSkin(_ config: WidgetConfig, unlocked: Bool) -> CoinSkin {
        guard unlocked else { return .classic }
        return CoinSkin(rawValue: config.string(coinSkinKey)) ?? .classic
    }

    /// 存着的选择（不看解锁），设置页显示用。
    static func storedTubeSkin(_ config: WidgetConfig) -> TubeSkin {
        TubeSkin(rawValue: config.string(tubeSkinKey)) ?? .bamboo
    }

    static func storedCoinSkin(_ config: WidgetConfig) -> CoinSkin {
        CoinSkin(rawValue: config.string(coinSkinKey)) ?? .classic
    }
}

// MARK: - 签筒和铜钱皮肤（Pro）

/// 签筒皮肤：默认竹（免费）、朱漆、青玉。全是代码画，只换颜色。
public enum TubeSkin: String, CaseIterable, Sendable {
    case bamboo, lacquer, jade

    public var title: String {
        switch self {
        case .bamboo: tr("竹签筒")
        case .lacquer: tr("朱漆签筒")
        case .jade: tr("青玉签筒")
        }
    }

    public var isPro: Bool { self != .bamboo }

    /// 筒身、两侧暗部、筒口和箍、签牌、签牌上的字。
    public var bodyHex: String {
        switch self {
        case .bamboo: "#C98A3A"
        case .lacquer: "#B8322A"
        case .jade: "#7DB5A0"
        }
    }

    public var shadeHex: String {
        switch self {
        case .bamboo: "#A86E28"
        case .lacquer: "#8E241E"
        case .jade: "#578F7B"
        }
    }

    public var bandHex: String {
        switch self {
        case .bamboo: "#8A5418"
        case .lacquer: "#D4A63A"
        case .jade: "#2F6B5A"
        }
    }

    public var labelHex: String {
        switch self {
        case .bamboo: "#C8382E"
        case .lacquer: "#2A1D18"
        case .jade: "#C8382E"
        }
    }

    public var labelInkHex: String {
        switch self {
        case .bamboo: "#F3D684"
        case .lacquer: "#F3D684"
        case .jade: "#F7EBC8"
        }
    }
}

/// 铜钱皮肤：默认铜钱（免费）、银币、古铜绿锈。起卦页、桌面卡片都从同一个颜色入口读。
public enum CoinSkin: String, CaseIterable, Sendable {
    case classic, silver, verdigris

    public var title: String {
        switch self {
        case .classic: tr("铜钱")
        case .silver: tr("银币")
        case .verdigris: tr("古铜绿锈")
        }
    }

    public var isPro: Bool { self != .classic }

    /// 钱面、外框和钱文、方孔内框的亮边。
    public var faceHex: String {
        switch self {
        case .classic: Divination.goldHex
        case .silver: "#C7CDD6"
        case .verdigris: "#7FA58C"
        }
    }

    public var deepHex: String {
        switch self {
        case .classic: "#A87A1E"
        case .silver: "#6F7886"
        case .verdigris: "#6B4F2A"
        }
    }

    public var lightHex: String {
        switch self {
        case .classic: "#F3D684"
        case .silver: "#F4F6F9"
        case .verdigris: "#C9E2CF"
        }
    }
}

// MARK: - 签卡分享图（Pro）

/// 当天签渲染成的竖版图片：尺寸、文件名、日期写法。画法在界面那边（ImageRenderer）。
public enum DivinationShareCard {
    /// 逻辑尺寸（点），按 `scale` 倍出图：1080×1920 像素，9:16 竖版。
    public static let width: Double = 360
    public static let height: Double = 640
    public static let scale: Double = 3

    public static var pixelSize: (width: Int, height: Int) {
        (Int(width * scale), Int(height * scale))
    }

    /// 保存时的默认文件名：「码头每日一签-2026-10-29-浅色.png」。
    public static func fileName(day: String, dark: Bool) -> String {
        "\(tr("码头每日一签"))-\(day)-\(dark ? tr("深色") : tr("浅色")).png"
    }

    /// 卡片上的日期：「2026 年 10 月 29 日 · 星期四」（按界面语言）。
    /// `locale` 不传时按界面语言。
    public static func dateText(day: String, calendar: Calendar = .current, locale: Locale? = nil) -> String {
        guard let date = Divination.date(fromDay: day, calendar: calendar) else { return day }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale ?? L10n.interfaceLocale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdEEEE")
        return formatter.string(from: date)
    }

    /// 两款配色：浅色宣纸底、深色墨底。
    public static let lightBackgroundHex = "#FBF6EA"
    public static let lightInkHex = "#2A1D18"
    public static let lightSubInkHex = "#6B5A4A"
    public static let darkBackgroundHex = "#1E1714"
    public static let darkInkHex = "#F6EDDC"
    public static let darkSubInkHex = "#C9B8A0"
}

// MARK: - 本周寄语

/// 每周一换一句温暖鼓励的话（按本地 ISO 周，周一开头）。只是寄语，不说运势、不做预测。
public enum DivinationWeekly {
    /// 某天所在的 ISO 周：年和第几周。
    public static func week(_ date: Date, calendar: Calendar = .current) -> (year: Int, week: Int) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 1)
    }

    /// 那周的那一句（下标）：一年里每周都不一样（句子比 53 周多）。
    public static func index(_ date: Date, calendar: Calendar = .current) -> Int {
        let w = week(date, calendar: calendar)
        let raw = w.year * 53 + (w.week - 1)
        return ((raw % lines.count) + lines.count) % lines.count
    }

    public static func line(_ date: Date, calendar: Calendar = .current) -> String {
        lines[index(date, calendar: calendar)]
    }

    /// 原创寄语（英文界面也保持中文，和签诗、解忧书一样）。
    public static let lines: [String] = [
        "这一周，慢一点也没关系，你一直在往前走。",
        "把今天过好，就是对自己最好的交代。",
        "累了就歇一歇，喝口热水，再出发。",
        "你比自己以为的更能扛，也更值得被温柔对待。",
        "做完一件小事，就给自己点个赞。",
        "别急着和别人比，你有自己的节奏。",
        "把心放宽一点，路自然就宽了。",
        "今天的认真，会在某天悄悄回报你。",
        "允许自己有不完美的一天。",
        "多晒晒太阳，多笑一笑，日子会亮起来。",
        "你已经做得很好了，记得也夸夸自己。",
        "遇到难处，先深呼吸三次，再一步一步来。",
        "给在乎的人发一句问候，温暖是会传递的。",
        "早点睡，好好吃饭，身体是最好的伙伴。",
        "不必事事周全，尽力就好。",
        "每一个普通的日子，都值得好好过。",
        "想做的事，从最小的一步开始。",
        "对自己说一声辛苦了，你值得。",
        "心里有光的人，走到哪里都不会太暗。",
        "这周试着少想一点如果，多做一点现在。",
        "把房间收拾干净，心也会跟着清爽。",
        "别怕慢，只怕停；别怕小，只怕不开始。",
        "你的善意，别人都记得。",
        "偶尔放空，是为了更好地装满。",
        "今天也请好好爱自己。",
        "有些答案，走着走着就明白了。",
        "身边的小美好，值得停下来看一看。",
        "做自己喜欢的事，时间都会变得柔软。",
        "把烦恼写下来，它就没那么重了。",
        "你不是一个人在努力，大家都在悄悄加油。",
        "笑一笑，这一周就有了好的开头。",
        "认真工作，也认真休息。",
        "不舒服的时候，可以说不。",
        "给自己留一点独处的时间，听听心里的声音。",
        "保持好奇，世界会一直有趣。",
        "昨天的遗憾，就交给昨天吧。",
        "走出门去散散步，风会帮你理清思绪。",
        "你值得被好好对待，包括被你自己。",
        "把复杂的事拆小，一件一件做完。",
        "感谢一下这周帮过你的人。",
        "不用一下子变好，一点一点就够了。",
        "专注眼前这一件，心就会安定下来。",
        "愿你这周吃得香、睡得稳、笑得多。",
        "和喜欢的人一起吃顿饭，比什么都好。",
        "允许自己慢慢来，花也不是一夜开的。",
        "你的坚持，正在悄悄长成力量。",
        "给生活留一点空白，惊喜才有地方落脚。",
        "多喝水，多走路，少熬夜。",
        "哪怕只前进一小步，也是在前进。",
        "对别人温柔，也别忘了对自己温柔。",
        "这周，试着把手机放下一会儿，看看窗外。",
        "你本来的样子，就已经很好。",
        "把想说的谢谢说出口，把想见的人约出来。",
        "心情不好的时候，就去做一件让自己开心的小事。",
        "愿你被这个世界温柔以待，也温柔地对待世界。",
        "新的一周，新的开始，你一定可以。",
    ]
}
