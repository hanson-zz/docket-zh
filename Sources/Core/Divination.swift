import Foundation

// MARK: - 卜卦
//
// 卜卦小组件（免费）一个面板三页：每日一签、铜钱起卦、解忧书。规则、签库、六十四卦、
// 答案库、存法、尺寸和音效合成都在 Core，界面（扩展栏卡片、面板、桌面卡片）只调这里，
// 测试也只测这里。全部内置、离线，不联网。仅供娱乐。

// MARK: - 签

/// 签级。从好到平：上上、上吉、中吉、中平、下签。下签的白话也写得轻松正面。
public enum StickLevel: String, CaseIterable, Codable, Sendable {
    case best, great, good, fair, low

    /// 签级的字（签上的内容，英文界面也保持中文）。
    public var title: String {
        switch self {
        case .best: "上上签"
        case .great: "上吉签"
        case .good: "中吉签"
        case .fair: "中平签"
        case .low: "下签"
        }
    }

    /// 越小越好，排序和配色用。
    public var rank: Int { StickLevel.allCases.firstIndex(of: self) ?? 0 }

    /// 上上、上吉用喜庆红配金。
    public var isFestive: Bool { self == .best || self == .great }
}

/// 一支签：签级、四句签诗（原创七言）、今日宜、今日忌和一句白话。
public struct FortuneStick: Equatable, Sendable {
    public var level: StickLevel
    public var poem: [String]
    public var good: String
    public var avoid: String
    public var plain: String

    public init(level: StickLevel, poem: [String], good: String, avoid: String, plain: String) {
        self.level = level
        self.poem = poem
        self.good = good
        self.avoid = avoid
        self.plain = plain
    }

    /// 签诗四句，单句后加「，」、双句后加「。」，排成四行。
    public var poemLines: [String] {
        poem.enumerated().map { i, line in line + (i % 2 == 0 ? "，" : "。") }
    }
}

// MARK: - 八卦与六十四卦

/// 八卦。原始值按爻自下而上取位：初爻是第 0 位，阳为 1。
public enum Trigram: Int, CaseIterable, Sendable {
    case kun = 0, zhen = 1, kan = 2, dui = 3, gen = 4, li = 5, xun = 6, qian = 7

    public var name: String {
        switch self {
        case .qian: "乾"
        case .dui: "兑"
        case .li: "离"
        case .zhen: "震"
        case .xun: "巽"
        case .kan: "坎"
        case .gen: "艮"
        case .kun: "坤"
        }
    }

    /// 卦象：天泽火雷风水山地。
    public var image: String {
        switch self {
        case .qian: "天"
        case .dui: "泽"
        case .li: "火"
        case .zhen: "雷"
        case .xun: "风"
        case .kan: "水"
        case .gen: "山"
        case .kun: "地"
        }
    }

    /// 三爻自下而上，阳为 true。
    public var lines: [Bool] { (0..<3).map { rawValue >> $0 & 1 == 1 } }
}

/// 一卦。`lines` 是六个字符，自下而上，"1" 阳、"0" 阴。
public struct Hexagram: Equatable, Sendable {
    public var number: Int
    public var name: String
    public var lines: String
    /// 卦辞（通行本原文）。
    public var judgment: String
    /// 六条爻辞，初爻在前（通行本原文，带「初九：」这样的爻题）。
    public var lineTexts: [String]
    /// 乾的用九、坤的用六。
    public var extraText: String?
    /// 原创白话解读。
    public var plain: String

    public init(number: Int, name: String, lines: String, judgment: String, lineTexts: [String],
                extraText: String? = nil, plain: String) {
        self.number = number
        self.name = name
        self.lines = lines
        self.judgment = judgment
        self.lineTexts = lineTexts
        self.extraText = extraText
        self.plain = plain
    }

    /// 六爻自下而上，阳为 true。
    public var yang: [Bool] { lines.map { $0 == "1" } }

    /// 卦值：初爻第 0 位，阳为 1（0...63）。
    public var value: Int {
        yang.enumerated().reduce(0) { $0 | ($1.element ? 1 << $1.offset : 0) }
    }

    public var lower: Trigram { Trigram(rawValue: value & 7) ?? .kun }
    public var upper: Trigram { Trigram(rawValue: value >> 3 & 7) ?? .kun }

    /// 「乾为天」「水雷屯」：上下同卦写「某为某」，否则上卦象、下卦象加卦名。
    public var fullName: String {
        if lower == upper { return "\(upper.name)为\(upper.image)" }
        return upper.image + lower.image + name
    }

    /// Unicode 的卦符（U+4DC0 起按文王卦序）。
    public var symbol: String {
        guard let scalar = Unicode.Scalar(UInt32(0x4DC0 + number - 1)) else { return "" }
        return String(Character(scalar))
    }

    private static let byValue: [Int: Hexagram] = Dictionary(uniqueKeysWithValues: all.map { ($0.value, $0) })

    /// 按卦值找卦。
    public static func with(value: Int) -> Hexagram? { byValue[value & 63] }

    /// 按六爻（自下而上，阳为 true）找卦。
    public static func with(yang: [Bool]) -> Hexagram? {
        guard yang.count == 6 else { return nil }
        return with(value: yang.enumerated().reduce(0) { $0 | ($1.element ? 1 << $1.offset : 0) })
    }

    /// 第几卦（1...64）。
    public static func number(_ number: Int) -> Hexagram? {
        guard number >= 1, number <= all.count else { return nil }
        return all[number - 1]
    }
}

// MARK: - 铜钱起卦

/// 一爻的四种：老阴（变）、少阳、少阴、老阳（变）。原始值是传统的六七八九。
///
/// 对应关系按传统火珠林「少者为主」（本小组件一直用这一种）：三枚铜钱，背面是「背」、
/// 有字的一面是「字」，三背为老阳（变）、三字为老阴（变）、一背两字为少阳、两背一字为少阴。
/// 也就是三枚不一样时看少的那一面：背少为阳、字少为阴；三枚一样时为老、要变。
public enum LineKind: Int, CaseIterable, Codable, Sendable {
    case oldYin = 6, youngYang = 7, youngYin = 8, oldYang = 9

    /// 三枚铜钱里有几个背。
    public init(backs: Int) {
        switch backs {
        case 3: self = .oldYang
        case 2: self = .youngYin
        case 1: self = .youngYang
        default: self = .oldYin
        }
    }

    /// 三枚铜钱（true 是背）。
    public init(coins: [Bool]) {
        self.init(backs: coins.filter { $0 }.count)
    }

    public var isYang: Bool { self == .youngYang || self == .oldYang }
    public var isChanging: Bool { self == .oldYang || self == .oldYin }

    /// 变了以后是阴还是阳。
    public var changedYang: Bool { isChanging ? !isYang : isYang }

    public var name: String {
        switch self {
        case .oldYin: tr("老阴")
        case .youngYang: tr("少阳")
        case .youngYin: tr("少阴")
        case .oldYang: tr("老阳")
        }
    }
}

/// 一次起卦：想问的事、时间，和自下而上摇出的每一爻（每爻三枚铜钱，true 是背）。
public struct Casting: Equatable, Sendable {
    public static let lineCount = 6

    public var question: String
    /// 1970 起的秒。
    public var time: Double
    /// 每一爻的三枚铜钱，初爻在前。
    public private(set) var tosses: [[Bool]]

    public init(question: String = "", time: Double = 0, tosses: [[Bool]] = []) {
        self.question = String(question.prefix(Divination.questionLimit))
        self.time = time
        self.tosses = Array(tosses.filter { $0.count == 3 }.prefix(Self.lineCount))
    }

    public var lines: [LineKind] { tosses.map(LineKind.init(coins:)) }
    public var isComplete: Bool { tosses.count == Self.lineCount }
    public var count: Int { tosses.count }

    /// 摇一次：三枚铜钱各自正反，记成下一爻。摇满六爻后不再摇，返回 nil。
    @discardableResult
    public mutating func toss<G: RandomNumberGenerator>(using rng: inout G) -> [Bool]? {
        guard !isComplete else { return nil }
        let coins = (0..<3).map { _ in Bool.random(using: &rng) }
        tosses.append(coins)
        return coins
    }

    /// 一次起完：把剩下的几爻都摇完。
    public mutating func tossAll<G: RandomNumberGenerator>(using rng: inout G) {
        while toss(using: &rng) != nil {}
    }

    /// 变爻在第几爻（0 是初爻）。
    public var changingIndices: [Int] {
        lines.enumerated().filter { $0.element.isChanging }.map(\.offset)
    }

    /// 本卦（摇满六爻才有）。
    public var primary: Hexagram? {
        guard isComplete else { return nil }
        return Hexagram.with(yang: lines.map(\.isYang))
    }

    /// 之卦（有变爻才有）。
    public var changed: Hexagram? {
        guard isComplete, !changingIndices.isEmpty else { return nil }
        return Hexagram.with(yang: lines.map(\.changedYang))
    }

    /// 要看的爻辞：每个变爻一条；乾坤六爻全变时加上用九、用六。
    public var changingTexts: [String] {
        guard let primary else { return [] }
        var texts = changingIndices.map { primary.lineTexts[$0] }
        if changingIndices.count == Self.lineCount, let extra = primary.extraText { texts.append(extra) }
        return texts
    }
}

extension Casting: Codable {
    private enum CodingKeys: String, CodingKey { case question = "q", time = "t", tosses = "f" }

    /// 铜钱存成「110,000,...」：每爻三位，1 是背。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        let time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        let text = try c.decode(String.self, forKey: .tosses)
        let groups = text.split(separator: ",").map { group in group.map { $0 == "1" } }
        guard groups.allSatisfy({ $0.count == 3 }), groups.count <= Self.lineCount else {
            throw DecodingError.dataCorruptedError(forKey: .tosses, in: c, debugDescription: "bad tosses")
        }
        self.init(question: question, time: time, tosses: groups)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !question.isEmpty { try c.encode(question, forKey: .question) }
        try c.encode(time, forKey: .time)
        try c.encode(tosses.map { $0.map { $0 ? "1" : "0" }.joined() }.joined(separator: ","), forKey: .tosses)
    }
}

// MARK: - 解忧书

/// 解忧书：心里默想一个问题，翻一页给一句原创的短答案。
public enum WorryBook {
    /// 最近翻到的这么多页不会马上再出现（同一个问题连着翻也会换句）。
    public static let recentWindow = 40

    /// 在没翻过的页里随机挑一页（下标）。
    public static func pick<G: RandomNumberGenerator>(avoiding recent: [Int], using rng: inout G) -> Int {
        let count = answers.count
        let avoid = Set(recent.suffix(min(recentWindow, max(0, count - 1))))
        let pool = (0..<count).filter { !avoid.contains($0) }
        return pool.randomElement(using: &rng) ?? Int.random(in: 0..<count, using: &rng)
    }

    /// 按第一个「，」拆成两行（后半行用强调色）；没有逗号就一行。
    public static func split(_ answer: String) -> (first: String, second: String?) {
        guard let range = answer.range(of: "，") else { return (answer, nil) }
        let first = String(answer[..<range.lowerBound]) + "，"
        let second = String(answer[range.upperBound...])
        return second.isEmpty ? (answer, nil) : (first, second)
    }
}

// MARK: - 存进卡片配置

/// 面板停在哪一页。
public enum DivinationPage: String, CaseIterable, Sendable {
    case stick, coins, book

    public var title: String {
        switch self {
        case .stick: tr("每日一签")
        case .coins: tr("起卦")
        case .book: tr("解忧书")
        }
    }
}

/// 今天抽到的签、起卦记录、解忧书翻过的页、停在哪页和静音开关都在卡片配置里
/// （不在设置页列出：这些键不放进目录的默认值）。扩展栏卡片、面板和桌面卡片读写同一份。
public enum Divination {
    /// 抽签那天（本地日期 yyyy-MM-dd）。
    public static let stickDayKey = "stickDay"
    /// 那天抽到第几支（下标）。
    public static let stickKey = "stick"
    /// 最近几次起卦（紧凑 JSON 数组，新的在前）。
    public static let historyKey = "history"
    /// 正在摇、还没摇满六爻的那一卦。
    public static let castingKey = "casting"
    /// 解忧书最近翻到的页（逗号分隔的下标，旧的在前）。
    public static let bookRecentKey = "bookRecent"
    /// 面板停在哪页。
    public static let pageKey = "page"
    /// 音效开关（布尔，默认开）。
    public static let soundKey = "sound"

    /// 起卦记录留几次。
    public static let historyLimit = 5
    /// 想问的事最多几个字。
    public static let questionLimit = 40

    // MARK: 日期

    /// 本地日期 yyyy-MM-dd（按传入的日历和时区，第二天零点换签）。
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// FNV-1a 64 位：同一个字符串在哪台机器、哪次启动都一样（不用 Swift 的 hashValue）。
    public static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 某天、某张卡片该抽到的那支（下标）：日期加卡片自己的盐算种子，同一天同一张卡片
    /// 永远是同一支，换一天或换一张卡片就不同。
    public static func seededStick(day: String, salt: String) -> Int {
        var rng = MineRandom(seed: stableHash("\(day)|\(salt)"))
        return drawIndex(using: &rng)
    }

    /// 用给定的随机数抽一支（下标）。
    public static func drawIndex<G: RandomNumberGenerator>(using rng: inout G) -> Int {
        Int.random(in: 0..<FortuneStick.all.count, using: &rng)
    }

    // MARK: 每日一签

    /// 今天抽过就返回那支的下标，没抽过（或存的是别的日子）返回 nil。
    public static func todayStick(_ config: WidgetConfig, now: Date, calendar: Calendar = .current) -> Int? {
        guard config.string(stickDayKey) == dayKey(now, calendar: calendar) else { return nil }
        let index = config.int(stickKey, default: -1)
        return FortuneStick.all.indices.contains(index) ? index : nil
    }

    public struct Draw: Equatable, Sendable {
        /// 抽到的签（下标）。
        public var index: Int
        /// 是今天第一次抽（false 表示今天已经抽过，返回的是那一支）。
        public var isNew: Bool

        public var stick: FortuneStick { FortuneStick.all[index] }
    }

    /// 摇一摇：今天抽过就还是那支；没抽过用给定的随机数抽一支并记下今天。
    @discardableResult
    public static func drawStick<G: RandomNumberGenerator>(in config: inout WidgetConfig, now: Date,
                                                          calendar: Calendar = .current,
                                                          using rng: inout G) -> Draw {
        if let index = todayStick(config, now: now, calendar: calendar) { return Draw(index: index, isNew: false) }
        let index = drawIndex(using: &rng)
        config.set(stickDayKey, .string(dayKey(now, calendar: calendar)))
        config.set(stickKey, .number(Double(index)))
        return Draw(index: index, isNew: true)
    }

    /// 不传随机数时按日期加盐（卡片 id）定签。
    @discardableResult
    public static func drawStick(in config: inout WidgetConfig, now: Date, salt: String,
                                 calendar: Calendar = .current) -> Draw {
        var rng = MineRandom(seed: stableHash("\(dayKey(now, calendar: calendar))|\(salt)"))
        return drawStick(in: &config, now: now, calendar: calendar, using: &rng)
    }

    /// 「第三十七签」。
    public static func stickNumber(_ index: Int) -> String {
        "第\(chineseNumber(index + 1))签"
    }

    /// 「第37签」：放不下中文数字的窄处（扩展栏竖条）用。
    public static func shortStickNumber(_ index: Int) -> String {
        "第\(index + 1)签"
    }

    /// 1...99 的中文数字：一、十、十一、二十、三十七。
    public static func chineseNumber(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard n > 0, n < 100 else { return "\(n)" }
        if n < 10 { return digits[n] }
        let tens = n / 10, ones = n % 10
        return (tens == 1 ? "" : digits[tens]) + "十" + (ones == 0 ? "" : digits[ones])
    }

    // MARK: 起卦

    /// 正在摇的那一卦（没有就是空的一卦）。
    public static func casting(_ config: WidgetConfig) -> Casting {
        let raw = config.string(castingKey)
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let casting = try? JSONDecoder().decode(Casting.self, from: data) else { return Casting() }
        return casting
    }

    public static func storeCasting(_ casting: Casting, in config: inout WidgetConfig) {
        guard let data = try? JSONEncoder().encode(casting),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(castingKey, .string(text))
    }

    /// 最近几次起卦，新的在前。坏数据跳过。
    public static func history(_ config: WidgetConfig) -> [Casting] {
        let raw = config.string(historyKey)
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([Casting].self, from: data) else { return [] }
        return Array(list.filter(\.isComplete).prefix(historyLimit))
    }

    /// 记一次起好的卦：放最前面，只留最近 `historyLimit` 次。没摇满的不记。
    public static func record(_ casting: Casting, in config: inout WidgetConfig) {
        guard casting.isComplete else { return }
        let list = Array(([casting] + history(config)).prefix(historyLimit))
        guard let data = try? JSONEncoder().encode(list),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(historyKey, .string(text))
    }

    public static func clearHistory(in config: inout WidgetConfig) {
        config.set(historyKey, nil)
    }

    /// 摇一次（或一次起完）：没在摇或上一卦已经摇满就开新的一卦（带上想问的事），
    /// 摇满六爻时记进历史。返回摇完后的这一卦。
    @discardableResult
    public static func toss<G: RandomNumberGenerator>(in config: inout WidgetConfig, question: String,
                                                     all: Bool, now: Double, using rng: inout G) -> Casting {
        var current = casting(config)
        if current.isComplete || current.count == 0 {
            current = Casting(question: question.trimmingCharacters(in: .whitespacesAndNewlines), time: now)
        }
        if all { current.tossAll(using: &rng) } else { current.toss(using: &rng) }
        storeCasting(current, in: &config)
        if current.isComplete { record(current, in: &config) }
        return current
    }

    /// 重新起卦：丢掉没摇完的那一卦。
    public static func resetCasting(in config: inout WidgetConfig) {
        config.set(castingKey, nil)
    }

    /// 「六次摇钱 · 第三爻为变」这样的一行说明。
    public static func castingSummary(_ casting: Casting) -> String {
        guard casting.isComplete else {
            return casting.count == 0 ? tr("自下而上摇六次") : tr("已摇 \(casting.count) / 6 爻")
        }
        let changing = casting.changingIndices
        if changing.isEmpty { return tr("六次摇钱 · 没有变爻") }
        let names = changing.map { lineName($0) }.joined(separator: tr("、"))
        return tr("六次摇钱 · \(names)为变")
    }

    /// 第几爻的叫法：初爻、第二爻……上爻。
    public static func lineName(_ index: Int) -> String {
        switch index {
        case 0: tr("初爻")
        case 1: tr("第二爻")
        case 2: tr("第三爻")
        case 3: tr("第四爻")
        case 4: tr("第五爻")
        default: tr("上爻")
        }
    }

    // MARK: 解忧书

    public static func bookRecent(_ config: WidgetConfig) -> [Int] {
        config.string(bookRecentKey).split(separator: ",").compactMap { Int($0) }
            .filter { WorryBook.answers.indices.contains($0) }
    }

    /// 翻一页：避开最近翻过的，记下这页，返回下标。
    @discardableResult
    public static func turnPage<G: RandomNumberGenerator>(in config: inout WidgetConfig,
                                                         using rng: inout G) -> Int {
        let recent = bookRecent(config)
        let index = WorryBook.pick(avoiding: recent, using: &rng)
        let kept = Array((recent + [index]).suffix(WorryBook.recentWindow))
        config.set(bookRecentKey, .string(kept.map(String.init).joined(separator: ",")))
        return index
    }

    /// 最近一次翻到的页。
    public static func lastPage(_ config: WidgetConfig) -> Int? { bookRecent(config).last }

    // MARK: 页和音效

    public static func page(_ config: WidgetConfig) -> DivinationPage {
        DivinationPage(rawValue: config.string(pageKey)) ?? .stick
    }

    public static func setPage(_ page: DivinationPage, in config: inout WidgetConfig) {
        config.set(pageKey, .string(page.rawValue))
    }

    public static func soundOn(_ config: WidgetConfig) -> Bool { config.bool(soundKey, default: true) }

    public static func setSound(_ on: Bool, in config: inout WidgetConfig) { config.set(soundKey, .bool(on)) }

    // MARK: 颜色

    /// 主色喜庆红：浅色玻璃上用深红（白底约 6.9:1），深色玻璃上用亮珊瑚红。
    public static let redLightHex = "#B3261E"
    public static let redDarkHex = "#FF7B6B"
    /// 金色点缀（只做装饰线、铜钱和签筒，不做正文）。
    public static let goldHex = "#D4A63A"
    /// 金色当字用时：浅色压深（白底约 4.9:1），深色提亮。
    public static let goldTextLightHex = "#8A6414"
    public static let goldTextDarkHex = "#F0CB6A"

    // MARK: 尺寸

    /// 扩展栏横排卡片：小熊猫、今日签级和签号（和同组卡片一样高）。
    public static let tileWidth: Double = 188
    public static let tileHeight: Double = 62
    /// 左右两侧扩展栏的竖条高：76×120。
    public static let columnHeight: Double = 120
    /// 面板宽：和同组的扫雷、拔牙一样 340。
    public static let panelWidth: Double = 340
    public static let panelCardPadding: Double = 16
    public static let panelTailDepth: Double = 10
    /// 面板卡片里真正能放内容的宽（340 是 266）。所有内容按这个宽排，不会被裁。
    public static var panelContentWidth: Double {
        Double(DetailPanelWidth.content(panel: CGFloat(panelWidth), tailDepth: CGFloat(panelTailDepth),
                                        tailOnSide: true)) - panelCardPadding * 2
    }

    /// 最小字号（「仅供娱乐」法律小字例外，12pt）。
    public static let minimumFont: Double = 13
    public static let disclaimerFont: Double = 12
}

// MARK: - 桌面卡片

/// 钉在桌面：小号显示今日签、能直接摇；中号、大号左边签、右边（大号下面）起卦。
public enum DesktopCardsDivinationPlan {
    public static let kinds: Set<WidgetKind> = [.divination]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    public static func inset(_ size: DesktopPinSize) -> Double { size == .small ? 10 : 12 }
    /// 中号左边签那一列的宽。
    public static let mediumStickWidth: Double = 128
    public static let mediumSpacing: Double = 12

    /// 中号、大号能起卦。
    public static func canCast(_ size: DesktopPinSize) -> Bool { size != .small }
}

// MARK: - 音效合成

/// 卜卦的音效：全部代码现算（`WidgetSoundSynth.wav`），不带素材文件。
public enum DivinationSound: String, CaseIterable, Sendable {
    /// 摇签筒：竹签哗啦哗啦。
    case rattle
    /// 掉出一支签：「嗒」。
    case tick
    /// 龟壳里铜钱晃动：叮叮当当。
    case jingle
    /// 三枚铜钱先后落桌：清脆的三下。
    case clink
    /// 解忧书翻页：纸声。
    case page
}

public enum DivinationSoundSynth {
    public static let sampleRate = WidgetSoundSynth.sampleRate

    /// 三枚铜钱落桌错开的时间（秒）。
    public static let clinkOffsets: [Double] = [0, 0.11, 0.2]

    public static func render(_ sound: DivinationSound, sampleRate: Double = sampleRate) -> [Float] {
        switch sound {
        case .rattle: rattle(sampleRate: sampleRate)
        case .tick: tick(sampleRate: sampleRate)
        case .jingle: jingle(sampleRate: sampleRate)
        case .clink: clink(sampleRate: sampleRate)
        case .page: page(sampleRate: sampleRate)
        }
    }

    public static func wav(_ sound: DivinationSound) -> Data {
        WidgetSoundSynth.wav(render(sound), sampleRate: sampleRate)
    }

    /// 固定种子的白噪声，每次合成都一样。
    private struct Noise {
        var seed: UInt64
        mutating func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: seed >> 1) % 2_000_001) / 1_000_000 - 1
        }
    }

    /// 一下木头碰撞：带通噪声加一个很短的木质共鸣。
    private static func woodHit(into out: inout [Float], at start: Double, gain: Double, pitch: Double,
                                noise: inout Noise, sampleRate: Double) {
        let length = Int(0.05 * sampleRate)
        let begin = Int(start * sampleRate)
        var low = 0.0
        for i in 0..<length where begin + i < out.count {
            let t = Double(i) / sampleRate
            low += (noise.next() - low) * 0.35
            let body = sin(2 * .pi * pitch * t) * 0.6
            let env = exp(-t * 90)
            out[begin + i] += Float((low * 0.8 + body) * env * gain)
        }
    }

    /// 摇签筒：一阵一阵的竹签互碰，三次往返，每次十几下。
    private static func rattle(sampleRate: Double) -> [Float] {
        let duration = 0.9
        var out = [Float](repeating: 0, count: Int(duration * sampleRate))
        var noise = Noise(seed: 0xB00_5EED)
        for sweep in 0..<3 {
            let base = Double(sweep) * 0.3
            for k in 0..<14 {
                let jitter = (noise.next() + 1) * 0.008
                let at = base + Double(k) * 0.017 + jitter
                let gain = 0.25 * (1 - Double(k) / 18)
                woodHit(into: &out, at: at, gain: gain, pitch: 1400 + noise.next() * 300,
                        noise: &noise, sampleRate: sampleRate)
            }
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 掉签「嗒」：一下干脆的木头敲击，垫一点低音。
    private static func tick(sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(0.14 * sampleRate))
        var noise = Noise(seed: 0x71C4)
        woodHit(into: &out, at: 0, gain: 0.8, pitch: 900, noise: &noise, sampleRate: sampleRate)
        for i in 0..<out.count {
            let t = Double(i) / sampleRate
            out[i] += Float(sin(2 * .pi * 220 * t) * exp(-t * 40) * 0.25)
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 一下金属碰撞：几组不成整数倍的泛音，衰减不同，像铜钱。
    private static func ding(into out: inout [Float], at start: Double, gain: Double, base: Double,
                             decay: Double, sampleRate: Double) {
        let partials: [(Double, Double)] = [(1, 1), (2.76, 0.5), (5.4, 0.28), (8.93, 0.14)]
        let length = Int(0.35 * sampleRate)
        let begin = Int(start * sampleRate)
        for i in 0..<length where begin + i < out.count {
            let t = Double(i) / sampleRate
            var v = 0.0
            for (ratio, amp) in partials {
                v += sin(2 * .pi * base * ratio * t) * amp * exp(-t * decay * (0.6 + ratio * 0.25))
            }
            out[begin + i] += Float(v * min(1, t / 0.001) * gain)
        }
    }

    /// 龟壳里铜钱晃动：一串轻轻的叮当，闷在壳里（音量小、衰减快）。
    private static func jingle(sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(0.8 * sampleRate))
        var noise = Noise(seed: 0x5E11)
        for k in 0..<12 {
            let at = Double(k) * 0.055 + (noise.next() + 1) * 0.01
            ding(into: &out, at: at, gain: 0.12, base: 2300 + noise.next() * 400, decay: 30,
                 sampleRate: sampleRate)
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 三枚铜钱先后落桌：每枚一声清脆的叮，再一下小弹跳。
    private static func clink(sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(0.75 * sampleRate))
        let pitches = [2600.0, 2950.0, 2400.0]
        for (i, offset) in clinkOffsets.enumerated() {
            ding(into: &out, at: offset, gain: 0.32, base: pitches[i], decay: 14, sampleRate: sampleRate)
            ding(into: &out, at: offset + 0.07, gain: 0.12, base: pitches[i] * 1.01, decay: 20,
                 sampleRate: sampleRate)
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 翻页：一阵先升后落的沙沙噪声（高通），末尾一下轻轻的纸边拍。
    private static func page(sampleRate: Double) -> [Float] {
        let duration = 0.38
        var out = [Float](repeating: 0, count: Int(duration * sampleRate))
        var noise = Noise(seed: 0x9A6E)
        var high = 0.0, previous = 0.0
        for i in 0..<out.count {
            let t = Double(i) / sampleRate
            let white = noise.next()
            high = 0.9 * (high + white - previous)
            previous = white
            let swell = sin(.pi * min(1, t / 0.3))
            let flap = t > 0.3 ? exp(-(t - 0.3) * 60) * 0.8 : 0
            out[i] = Float(high * (swell * 0.22 + flap * 0.4))
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 限幅加 5 毫秒的尾巴渐弱，不会爆音、不会咔哒。
    private static func limited(_ samples: [Float], sampleRate: Double) -> [Float] {
        var out = samples.map { min(0.95, max(-0.95, $0)) }
        let tail = min(out.count, Int(0.005 * sampleRate))
        for j in 0..<tail {
            out[out.count - 1 - j] *= Float(j) / Float(max(1, tail))
        }
        return out
    }
}
