import Foundation

// MARK: - 柴犬翻翻乐
//
// 柴犬翻翻乐小组件（免费，休闲游戏）的全部规则：一盘牌背面朝上，点一张翻开，再点一张比对，
// 图案一样就配上、一直翻着，不一样停约 0.8 秒再翻回去（这段时间里的点击不算，防连点）。
// 每翻第二张算一步，计时从第一次翻牌开始、全部配完时停。最佳纪录按最少步数比，步数一样比用时。
// 不限翻牌次数。进行中的盘、最佳纪录和音效开关都存在卡片配置里；界面（扩展栏卡片、面板、
// 桌面卡片）只调这里，测试也只测这里。
//
// 棋盘行列是参数（`ShibaBoardSpec`，默认 3 行 4 列、6 对），以后加中级 4×4（8 对）、
// 高级 4×5（10 对）只要多给一个规格，面板按规格排，不用重写。这一版界面不放难度切换。

/// 牌面图案。前 6 种是这一版 3×4 用的；后 4 种是以后 8 对、10 对时补上的备用图案。
/// 正式图由作者画（Resources/ShibaMatch/match-<rawValue>.png，可带 @2x），缺图时界面回退。
public enum ShibaFace: String, CaseIterable, Codable, Sendable {
    case shiba, paw, bone, house, ball, bowl
    case bell, leaf, star, heart

    /// 资源图名（不带扩展名）。
    public var imageName: String { "match-\(rawValue)" }

    /// 缺图时画的 emoji（系统自带的彩色字形，macOS 上一定有）。柴犬脸缺图时界面先用仓库里的
    /// 柴犬母版小头（`ShibaMatch.faceFallbackImage`），这个 emoji 是最后一道。
    public var emoji: String {
        switch self {
        case .shiba: "🐕"
        case .paw: "🐾"
        case .bone: "🦴"
        case .house: "🏠"
        case .ball: "🎾"
        case .bowl: "🥣"
        case .bell: "🔔"
        case .leaf: "🍃"
        case .star: "⭐️"
        case .heart: "💛"
        }
    }

    /// 读屏和配对结果里的名字。
    public var title: String {
        switch self {
        case .shiba: tr("柴犬")
        case .paw: tr("爪印")
        case .bone: tr("骨头")
        case .house: tr("狗窝")
        case .ball: tr("网球")
        case .bowl: tr("饭碗")
        case .bell: tr("铃铛")
        case .leaf: tr("树叶")
        case .star: tr("星星")
        case .heart: tr("爱心")
        }
    }
}

/// 棋盘规格：几行几列，配对数是格子数的一半。格子数必须是偶数、图案要够用。
public struct ShibaBoardSpec: Hashable, Codable, Sendable {
    public var rows: Int
    public var columns: Int

    public init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }

    /// 这一版唯一的规格：3 行 4 列、6 对。
    public static let standard = ShibaBoardSpec(rows: 3, columns: 4)
    /// 以后的中级、高级（这一版界面不放）。
    public static let medium = ShibaBoardSpec(rows: 4, columns: 4)
    public static let hard = ShibaBoardSpec(rows: 4, columns: 5)

    public var count: Int { rows * columns }
    public var pairs: Int { count / 2 }

    /// 行列都至少 2、格子数是偶数、图案够配。
    public var isValid: Bool {
        rows >= 2 && columns >= 2 && rows <= 8 && columns <= 8
            && count % 2 == 0 && pairs <= ShibaFace.allCases.count
    }

    /// 存档和纪录的键后缀：「3x4」。
    public var key: String { "\(rows)x\(columns)" }

    /// 这一盘用哪几种图案：按枚举顺序取前 `pairs` 种。
    public var faces: [ShibaFace] { Array(ShibaFace.allCases.prefix(pairs)) }
}

/// 一盘翻翻乐。牌按位置编号：从左上起一行一行数，`index = row * columns + column`。
public struct ShibaMatchGame: Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// 还没翻过牌（计时没开始）。
        case ready
        case playing
        /// 全部配完。
        case won
    }

    /// 点一张牌的结果。
    public enum FlipResult: Equatable, Sendable {
        /// 没翻：超出范围、已配对、已经翻着、正在等没配上的两张翻回去，或这盘已经完成。
        case ignored
        /// 翻开了这一轮的第一张。
        case first
        /// 第二张和第一张一样，配上了。
        case matched
        /// 第二张和第一张不一样，停一会儿再翻回去。
        case mismatched
        /// 配上了最后一对，完成。
        case won
    }

    /// 每张牌现在的样子。
    public enum CardState: Equatable, Sendable {
        case hidden
        /// 翻开着、还没比对完（这一轮的第一张）。
        case faceUp
        /// 翻开着、和另一张没配上，正等着翻回去。
        case wrong
        case matched
    }

    /// 没配上的两张停多久再翻回去（秒）。
    public static let mismatchDelay: Double = 0.8

    public private(set) var spec: ShibaBoardSpec
    /// 每个位置的图案。
    public private(set) var cards: [ShibaFace]
    public private(set) var matched: [Bool]
    /// 翻开着但还没配上的牌（最多两张，按翻开顺序）。
    public private(set) var faceUp: [Int]
    /// 步数：每翻第二张算一步。
    public private(set) var moves: Int
    /// 第一次翻牌的时间（1970 起的秒）。
    public private(set) var startedAt: Double?
    /// 配完最后一对的时间。
    public private(set) var endedAt: Double?
    /// 刚翻出没配上的两张的时间；翻回去后清掉。
    public private(set) var mismatchAt: Double?

    /// 新开一盘：用 `rng` 洗牌（测试注入固定种子）。规格不合法时按标准规格。
    public init<G: RandomNumberGenerator>(spec: ShibaBoardSpec = .standard, using rng: inout G) {
        let spec = spec.isValid ? spec : .standard
        var deck = spec.faces + spec.faces
        deck.shuffle(using: &rng)
        self.init(spec: spec, deck: deck)
    }

    /// 不传随机数时用系统随机。
    public init(spec: ShibaBoardSpec = .standard) {
        var rng = SystemRandomNumberGenerator()
        self.init(spec: spec, using: &rng)
    }

    private init(spec: ShibaBoardSpec, deck: [ShibaFace]) {
        self.spec = spec
        self.cards = deck
        self.matched = Array(repeating: false, count: deck.count)
        self.faceUp = []
        self.moves = 0
    }

    /// 测试用：直接摆好牌（必须正好是这个规格的每种图案各两张，否则 nil）。
    public static func fixed(spec: ShibaBoardSpec = .standard, cards: [ShibaFace]) -> ShibaMatchGame? {
        guard spec.isValid, ShibaMatchGame.isDeck(cards, for: spec) else { return nil }
        return ShibaMatchGame(spec: spec, deck: cards)
    }

    /// 这副牌是不是正好这个规格的每种图案各两张。
    static func isDeck(_ cards: [ShibaFace], for spec: ShibaBoardSpec) -> Bool {
        guard cards.count == spec.count else { return false }
        var counts: [ShibaFace: Int] = [:]
        for face in cards { counts[face, default: 0] += 1 }
        return counts.count == spec.pairs && counts.values.allSatisfy { $0 == 2 }
    }

    // MARK: 读

    public var status: Status {
        if endedAt != nil, matched.allSatisfy({ $0 }) { return .won }
        return startedAt == nil ? .ready : .playing
    }

    public var isWon: Bool { status == .won }
    /// 配上了几对。
    public var pairsFound: Int { matched.lazy.filter { $0 }.count / 2 }
    public var pairs: Int { spec.pairs }

    public func contains(_ index: Int) -> Bool { index >= 0 && index < cards.count }

    public func face(_ index: Int) -> ShibaFace? { contains(index) ? cards[index] : nil }

    public func state(_ index: Int) -> CardState {
        guard contains(index) else { return .hidden }
        if matched[index] { return .matched }
        if faceUp.contains(index) { return mismatchAt == nil ? .faceUp : .wrong }
        return .hidden
    }

    /// 这张牌正面朝上（翻开着或已配对）。
    public func isShowing(_ index: Int) -> Bool { state(index) != .hidden }

    /// 正在等没配上的两张翻回去：这段时间里点哪张都不算。时钟往回拨了（`now` 比记的时间还早）
    /// 按已经等够算，免得卡住。
    public func isWaiting(now: Double) -> Bool {
        guard let at = mismatchAt else { return false }
        return now >= at && now - at < Self.mismatchDelay
    }

    /// 用时（秒）：没开始是 0，完成后停在完成那一刻。
    public func elapsed(now: Double) -> Double {
        guard let start = startedAt else { return 0 }
        let end = endedAt ?? now
        return max(0, end - start)
    }

    // MARK: 改

    /// 点一张牌。
    @discardableResult
    public mutating func flip(_ index: Int, now: Double) -> FlipResult {
        guard status != .won, contains(index) else { return .ignored }
        if mismatchAt != nil {
            guard !isWaiting(now: now) else { return .ignored }
            settle(now: now)
        }
        guard !matched[index], !faceUp.contains(index) else { return .ignored }
        if startedAt == nil { startedAt = now }
        guard let first = faceUp.first else {
            faceUp = [index]
            return .first
        }
        moves += 1
        if cards[first] == cards[index] {
            matched[first] = true
            matched[index] = true
            faceUp = []
            if matched.allSatisfy({ $0 }) {
                endedAt = max(now, startedAt ?? now)
                return .won
            }
            return .matched
        }
        faceUp = [first, index]
        mismatchAt = now
        return .mismatched
    }

    /// 没配上的两张等够了就翻回去。翻回去了返回 true。
    @discardableResult
    public mutating func settle(now: Double) -> Bool {
        guard mismatchAt != nil, !isWaiting(now: now) else { return false }
        faceUp = []
        mismatchAt = nil
        return true
    }
}

// MARK: - 存进卡片配置

extension ShibaMatchGame: Codable {
    private enum CodingKeys: String, CodingKey {
        case rows = "r", columns = "c", cards = "k", matched = "m", faceUp = "u", moves = "n"
        case startedAt = "t0", endedAt = "t1", mismatchAt = "w"
    }

    /// 图案是一串用逗号隔开的名字，已配对是一串 0 / 1。读到任何对不上的地方都抛错，
    /// 由 `ShibaMatch.game` 回退成新的一盘。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func bad(_ key: CodingKeys, _ why: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: why)
        }
        let spec = ShibaBoardSpec(rows: try c.decode(Int.self, forKey: .rows),
                                  columns: try c.decode(Int.self, forKey: .columns))
        guard spec.isValid else { throw bad(.rows, "bad spec") }
        let names = try c.decode(String.self, forKey: .cards).split(separator: ",").map(String.init)
        let deck = names.compactMap(ShibaFace.init(rawValue:))
        guard deck.count == names.count, ShibaMatchGame.isDeck(deck, for: spec) else { throw bad(.cards, "bad cards") }
        self.init(spec: spec, deck: deck)

        let marks = try c.decode(String.self, forKey: .matched)
        guard marks.count == spec.count, marks.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            throw bad(.matched, "bad matched")
        }
        matched = marks.map { $0 == "1" }
        // 已配对必须成对：同一种图案的两张要么都配上、要么都没配上。
        for face in spec.faces {
            let flags = cards.indices.filter { cards[$0] == face }.map { matched[$0] }
            guard Set(flags).count == 1 else { throw bad(.matched, "half a pair") }
        }

        faceUp = try c.decodeIfPresent([Int].self, forKey: .faceUp) ?? []
        moves = try c.decodeIfPresent(Int.self, forKey: .moves) ?? 0
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt)
        mismatchAt = try c.decodeIfPresent(Double.self, forKey: .mismatchAt)

        guard moves >= 0, faceUp.count <= 2, Set(faceUp).count == faceUp.count,
              faceUp.allSatisfy({ contains($0) && !matched[$0] }) else { throw bad(.faceUp, "bad face up") }
        // 翻着两张就一定是没配上、在等翻回去；只翻着一张就不该在等。
        if faceUp.count == 2 {
            guard mismatchAt != nil, cards[faceUp[0]] != cards[faceUp[1]] else { throw bad(.faceUp, "bad pair") }
        } else if mismatchAt != nil {
            throw bad(.mismatchAt, "nothing to flip back")
        }
        let anyProgress = moves > 0 || !faceUp.isEmpty || matched.contains(true)
        if startedAt == nil, anyProgress || endedAt != nil { throw bad(.startedAt, "progress without start") }
        let allMatched = matched.allSatisfy { $0 }
        guard allMatched == (endedAt != nil) else { throw bad(.endedAt, "bad end") }
        // 配上一对至少要一步。
        guard moves >= pairsFound else { throw bad(.moves, "too few moves") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(spec.rows, forKey: .rows)
        try c.encode(spec.columns, forKey: .columns)
        try c.encode(cards.map(\.rawValue).joined(separator: ","), forKey: .cards)
        try c.encode(matched.map { $0 ? "1" : "0" }.joined(), forKey: .matched)
        if !faceUp.isEmpty { try c.encode(faceUp, forKey: .faceUp) }
        try c.encode(moves, forKey: .moves)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encodeIfPresent(mismatchAt, forKey: .mismatchAt)
    }
}

/// 一盘的成绩：步数少的好，步数一样用时短的好。
public struct ShibaRecord: Codable, Equatable, Sendable {
    public var moves: Int
    /// 用时，存到 0.1 秒。
    public var seconds: Double
    /// 完成的时间（那盘的 `endedAt`）：面板只在那一盘写「新纪录」。
    public var date: Double

    public init(moves: Int, seconds: Double, date: Double) {
        self.moves = moves
        self.seconds = seconds
        self.date = date
    }

    public func isBetter(than other: ShibaRecord?) -> Bool {
        guard let other else { return true }
        if moves != other.moves { return moves < other.moves }
        return seconds < other.seconds - 0.0001
    }
}

/// 音效：都用系统自带的短音（界面按名字播 NSSound），不带素材文件。
public enum ShibaSound: String, CaseIterable, Sendable {
    /// 翻开一张。
    case flip
    /// 配上一对。
    case match
    /// 全部配完。
    case win

    /// 系统音效名（/System/Library/Sounds）。
    public var systemName: String {
        switch self {
        case .flip: "Tink"
        case .match: "Pop"
        case .win: "Glass"
        }
    }
}

/// 进行中的盘、最佳纪录和音效开关都在卡片配置里（不在设置页列出：这些键不放进目录的默认值）。
/// 扩展栏卡片、面板和桌面卡片读写同一份。
public enum ShibaMatch {
    /// 音效开关（布尔，默认开，和扫雷一样）。
    public static let soundKey = "sound"

    /// 进行中的盘（紧凑 JSON），每种规格一份：「game.3x4」。
    public static func gameKey(_ spec: ShibaBoardSpec) -> String { "game.\(spec.key)" }
    /// 最佳纪录（JSON），每种规格一份：「best.3x4」。
    public static func bestKey(_ spec: ShibaBoardSpec) -> String { "best.\(spec.key)" }

    // MARK: 读写

    /// 存着的那盘；没有、坏了或规格对不上时是一盘新洗好的牌。
    public static func game<G: RandomNumberGenerator>(_ config: WidgetConfig, spec: ShibaBoardSpec = .standard,
                                                      using rng: inout G) -> ShibaMatchGame {
        if let stored = stored(config, spec: spec) { return stored }
        return ShibaMatchGame(spec: spec, using: &rng)
    }

    public static func game(_ config: WidgetConfig, spec: ShibaBoardSpec = .standard) -> ShibaMatchGame {
        var rng = SystemRandomNumberGenerator()
        return game(config, spec: spec, using: &rng)
    }

    /// 只读存着的，读不出来是 nil。
    public static func stored(_ config: WidgetConfig, spec: ShibaBoardSpec = .standard) -> ShibaMatchGame? {
        let raw = config.string(gameKey(spec), default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let game = try? JSONDecoder().decode(ShibaMatchGame.self, from: data),
              game.spec == spec else { return nil }
        return game
    }

    public static func store(_ game: ShibaMatchGame, in config: inout WidgetConfig) {
        guard let data = try? JSONEncoder().encode(game),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(gameKey(game.spec), .string(text))
    }

    public static func best(_ config: WidgetConfig, spec: ShibaBoardSpec = .standard) -> ShibaRecord? {
        let raw = config.string(bestKey(spec), default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let record = try? JSONDecoder().decode(ShibaRecord.self, from: data),
              record.moves > 0, record.seconds >= 0, record.seconds.isFinite else { return nil }
        return record
    }

    public static func storeBest(_ record: ShibaRecord, spec: ShibaBoardSpec, in config: inout WidgetConfig) {
        guard let data = try? JSONEncoder().encode(record),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(bestKey(spec), .string(text))
    }

    public static func soundOn(_ config: WidgetConfig) -> Bool {
        config.bool(soundKey, default: true)
    }

    public static func setSound(_ on: Bool, in config: inout WidgetConfig) {
        config.set(soundKey, .bool(on))
    }

    /// 这一盘是不是刚创下最佳纪录的那一盘（完成了，且纪录记的就是它）。
    public static func isRecord(_ game: ShibaMatchGame, in config: WidgetConfig) -> Bool {
        guard game.isWon, let ended = game.endedAt, let best = best(config, spec: game.spec) else { return false }
        return abs(best.date - ended) < 0.001 && best.moves == game.moves
    }

    public struct Outcome: Equatable, Sendable {
        public var result: ShibaMatchGame.FlipResult
        /// 刚完成而且是新的最佳纪录。
        public var newRecord: Bool

        /// 这一下该放的音效（静音时界面不放）。没配上不放声，免得吵。
        public var sound: ShibaSound? {
            switch result {
            case .ignored, .mismatched: nil
            case .first: .flip
            case .matched: .match
            case .won: .win
            }
        }

        /// 没配上：界面约 0.8 秒后调 `settle` 把两张翻回去。
        public var needsSettle: Bool { result == .mismatched }
    }

    /// 点一张牌，写回配置；完成时更新最佳纪录。
    @discardableResult
    public static func apply<G: RandomNumberGenerator>(flip index: Int, spec: ShibaBoardSpec = .standard,
                                                       to config: inout WidgetConfig, now: Double,
                                                       using rng: inout G) -> Outcome {
        var current = game(config, spec: spec, using: &rng)
        let result = current.flip(index, now: now)
        var outcome = Outcome(result: result, newRecord: false)
        guard result != .ignored else { return outcome }
        store(current, in: &config)
        if result == .won, let ended = current.endedAt {
            let seconds = (current.elapsed(now: now) * 10).rounded() / 10
            let record = ShibaRecord(moves: current.moves, seconds: seconds, date: ended)
            if record.isBetter(than: best(config, spec: spec)) {
                storeBest(record, spec: spec, in: &config)
                outcome.newRecord = true
            }
        }
        return outcome
    }

    @discardableResult
    public static func apply(flip index: Int, spec: ShibaBoardSpec = .standard,
                             to config: inout WidgetConfig, now: Double) -> Outcome {
        var rng = SystemRandomNumberGenerator()
        return apply(flip: index, spec: spec, to: &config, now: now, using: &rng)
    }

    /// 没配上的两张等够了就翻回去，写回配置。翻回去了返回 true。
    @discardableResult
    public static func settle(spec: ShibaBoardSpec = .standard, in config: inout WidgetConfig, now: Double) -> Bool {
        guard var current = stored(config, spec: spec), current.settle(now: now) else { return false }
        store(current, in: &config)
        return true
    }

    /// 重新开始：直接换一盘新洗的牌（纪录和音效开关不动）。
    public static func restart<G: RandomNumberGenerator>(spec: ShibaBoardSpec = .standard,
                                                         in config: inout WidgetConfig, using rng: inout G) {
        store(ShibaMatchGame(spec: spec, using: &rng), in: &config)
    }

    public static func restart(spec: ShibaBoardSpec = .standard, in config: inout WidgetConfig) {
        var rng = SystemRandomNumberGenerator()
        restart(spec: spec, in: &config, using: &rng)
    }

    /// 重新开始前要不要先确认一下：只有翻过牌、还没完成的那盘要（面板上第一下变成「再点一次」）。
    public static func restartNeedsConfirm(_ game: ShibaMatchGame) -> Bool {
        game.status == .playing
    }

    /// 确认状态留多久（秒），过了恢复成普通的重新开始键。
    public static let restartConfirmWindow: Double = 3

    // MARK: 文案

    public static var title: String { tr("柴犬翻翻乐") }

    /// 一个词的状态：未开始 / 进行中 / 完成。
    public static func statusWord(_ game: ShibaMatchGame) -> String {
        switch game.status {
        case .ready: tr("未开始")
        case .playing: tr("进行中")
        case .won: tr("完成")
        }
    }

    /// 「3/6」。
    public static func progressText(_ game: ShibaMatchGame) -> String {
        "\(game.pairsFound)/\(game.pairs)"
    }

    /// 一句状态（面板副标题、读屏）：「未开始」「进行中 · 已配对 3/6」「完成 · 14 步」。
    public static func statusLine(_ game: ShibaMatchGame) -> String {
        switch game.status {
        case .ready: return tr("未开始")
        case .playing: return tr("进行中 · 已配对 \(progressText(game))")
        case .won: return tr("完成 · \(game.moves) 步")
        }
    }

    /// 扩展栏卡片入口上的字：开始游戏 / 继续游戏 / 再来一盘。
    public static func entryTitle(_ game: ShibaMatchGame) -> String {
        switch game.status {
        case .ready: tr("开始游戏")
        case .playing: tr("继续游戏")
        case .won: tr("再来一盘")
        }
    }

    /// 竖排卡片放不下四个字，用两个字的：开始 / 继续 / 再来。
    public static func entryShortTitle(_ game: ShibaMatchGame) -> String {
        switch game.status {
        case .ready: tr("开始")
        case .playing: tr("继续")
        case .won: tr("再来")
        }
    }

    /// 「00:28」：分钟两位、秒两位；超过 99 分钟停在 99:59。
    public static func clockText(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(min(seconds, Double(99 * 60 + 59)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    public static func timeText(_ game: ShibaMatchGame, now: Double) -> String {
        tr("用时 \(clockText(seconds: game.elapsed(now: now)))")
    }

    public static func movesText(_ moves: Int) -> String {
        tr("步数 \(moves)")
    }

    /// 「最佳 14 步」，没有时「最佳 暂无」。
    public static func bestText(_ record: ShibaRecord?) -> String {
        guard let record else { return tr("最佳 暂无") }
        return tr("最佳 \(record.moves) 步")
    }

    /// 最佳纪录的悬停说明：「14 步 · 00:42」。
    public static func bestDetail(_ record: ShibaRecord?) -> String {
        guard let record else { return tr("还没有完成过") }
        return tr("\(record.moves) 步 · \(clockText(seconds: record.seconds))")
    }

    /// 完成结果卡的标题。
    public static func resultTitle(newRecord: Bool) -> String {
        newRecord ? tr("新纪录！") : tr("全部配对完成！")
    }

    /// 完成结果卡的一行：「14 步 · 用时 00:42」。
    public static func resultDetail(_ game: ShibaMatchGame) -> String {
        tr("\(game.moves) 步 · 用时 \(clockText(seconds: game.elapsed(now: game.endedAt ?? 0)))")
    }

    /// 每张牌的读屏名字：「第 2 行第 3 张，未翻开」「第 2 行第 3 张，骨头」「骨头，已配对」。
    public static func cardLabel(_ game: ShibaMatchGame, index: Int) -> String {
        guard game.contains(index), let face = game.face(index) else { return "" }
        let row = index / game.spec.columns + 1, column = index % game.spec.columns + 1
        switch game.state(index) {
        case .hidden: return tr("第 \(row) 行第 \(column) 张，未翻开")
        case .faceUp, .wrong: return tr("第 \(row) 行第 \(column) 张，\(face.title)")
        case .matched: return tr("\(face.title)，已配对")
        }
    }

    // MARK: 颜色

    /// 柴犬橙：入口胶囊、选中描边用（实心底上配深墨，见界面）。
    public static let accentHex = "#F0A04B"
    /// 字用的柴犬橙：浅色玻璃上压深、深色玻璃上提亮，两边都过 4.5:1。
    public static let accentLightHex = "#9A5208"
    public static let accentDarkHex = "#FFC27A"

    // MARK: 尺寸（扩展栏卡片、面板）

    /// 扩展栏横排卡片：柴犬、状态和入口。
    public static let tileWidth: Double = 176
    public static let tileHeight: Double = 62
    /// 左右两侧扩展栏的竖条高（76 宽）：柴犬在上，进度和入口在下。
    public static let columnHeight: Double = 120

    /// 面板宽 340（和同组的扫雷一样）。
    public static let panelWidth: Double = 340
    /// 面板卡片（DetailCard）自己的内边距。
    public static let panelCardPadding: Double = 16
    /// 尾巴在侧边时让出的深度（PanelShape.arrowDepth）。
    public static let panelTailDepth: Double = 10
    /// 面板卡片里真正能放内容的宽：340 是 266。
    public static var panelContentWidth: Double {
        Double(DetailPanelWidth.content(panel: CGFloat(panelWidth), tailDepth: CGFloat(panelTailDepth),
                                        tailOnSide: true)) - panelCardPadding * 2
    }

    /// 面板里的棋盘布局（按内容宽排，规格变了跟着变）。
    public static func panelLayout(_ spec: ShibaBoardSpec = .standard) -> ShibaBoardLayout {
        ShibaBoardLayout(spec: spec, width: panelContentWidth, maxHeight: 300, gap: 8)
    }

    /// 底部趴着的柴犬占的宽高（不挡牌、不拦点击）。
    public static let panelLyingShibaHeight: Double = 58
    public static let panelLyingShibaWidth: Double = 64

    /// 牌的点击区最窄不小于这个。
    public static let minimumHitSide: Double = 24

    /// 柴犬脸缺 match-shiba 图时先用的仓库柴犬母版小头。
    public static let faceFallbackImage = "notch-shiba-peek"
}

/// 柴犬素材：只用仓库里已有的柴犬母版（橙白毛绒、红色爪印领巾），不另画。
public enum ShibaMatchArt {
    /// 面板头像：刘海探头的小脑袋。
    public static let avatar = "notch-shiba-peek"
    /// 面板左下趴着的：桌面伙伴扒边探头那张（下巴搁在前爪上）。
    public static let lying = "desk-shiba-peek"
    /// 完成结果卡上举爪欢呼的（刘海「完成」那张，带 @2x，放大不糊）。
    public static let cheer = "notch-shiba-done"

    /// 扩展栏卡片和桌面卡片上的柴犬：未开始在打盹，进行中睁眼看着，完成举爪。
    public static func tile(_ status: ShibaMatchGame.Status) -> String {
        switch status {
        case .ready: "notch-shiba-sleep"
        case .playing: "notch-shiba-focus"
        case .won: "notch-shiba-done"
        }
    }
}

/// 一块棋盘怎么排：给定可用宽和最高高度，算每张牌多大（宽高比 1 : 1.08，放不下就按高缩）、
/// 每张牌的位置和点到哪一张。面板、桌面卡片都用它，测试保证不出框、点击区不小于 24pt。
public struct ShibaBoardLayout: Equatable, Sendable {
    public var spec: ShibaBoardSpec
    public var cardWidth: Double
    public var cardHeight: Double
    public var gap: Double

    /// 牌的高宽比。
    public static let aspect: Double = 1.08

    public init(spec: ShibaBoardSpec, width: Double, maxHeight: Double, gap: Double) {
        self.spec = spec
        self.gap = gap
        let columns = Double(max(1, spec.columns)), rows = Double(max(1, spec.rows))
        let byWidth = ((width - gap * (columns - 1)) / columns).rounded(.down)
        let byHeight = (((maxHeight - gap * (rows - 1)) / rows) / Self.aspect).rounded(.down)
        let w = max(1, min(byWidth, byHeight))
        cardWidth = w
        cardHeight = (w * Self.aspect).rounded(.down)
    }

    public var width: Double { Double(spec.columns) * cardWidth + Double(max(0, spec.columns - 1)) * gap }
    public var height: Double { Double(spec.rows) * cardHeight + Double(max(0, spec.rows - 1)) * gap }

    /// 第 `index` 张牌的左上角（棋盘坐标，左上为原点）。
    public func origin(_ index: Int) -> (x: Double, y: Double) {
        let row = index / max(1, spec.columns), column = index % max(1, spec.columns)
        return (Double(column) * (cardWidth + gap), Double(row) * (cardHeight + gap))
    }

    /// 点到哪一张；点在缝里或棋盘外是 nil。
    public func hitIndex(x: Double, y: Double) -> Int? {
        guard x >= 0, y >= 0 else { return nil }
        let column = Int(x / (cardWidth + gap)), row = Int(y / (cardHeight + gap))
        guard row < spec.rows, column < spec.columns else { return nil }
        let localX = x - Double(column) * (cardWidth + gap), localY = y - Double(row) * (cardHeight + gap)
        guard localX <= cardWidth, localY <= cardHeight else { return nil }
        return row * spec.columns + column
    }

    /// 键盘方向键移动焦点：到边就停。
    public func move(_ index: Int, row dr: Int, column dc: Int) -> Int {
        let columns = max(1, spec.columns)
        let row = min(max(0, index / columns + dr), spec.rows - 1)
        let column = min(max(0, index % columns + dc), columns - 1)
        return row * columns + column
    }
}

/// 钉在桌面：小号只显示状态（柴犬、进度、步数），中号、大号能直接玩。卡片边距、读数行高和
/// 每档棋盘多大放这里，测试保证牌放得下、点击区不小于 24pt。
public enum DesktopCardsShibaPlan {
    public static let kinds: Set<WidgetKind> = [.shibaMatch]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 这一档能不能直接玩。
    public static func isPlayable(_ size: DesktopPinSize) -> Bool { size != .small }

    public static func inset(_ size: DesktopPinSize) -> Double { size == .small ? 10 : 12 }
    /// 大号顶上读数一行的高。
    public static let headerHeight: Double = 30
    public static let headerSpacing: Double = 8
    /// 中号右边读数一列的宽。
    public static let mediumSideWidth: Double = 104
    public static let mediumSpacing: Double = 12

    /// 能玩的那两档的棋盘布局；小号是 nil。
    public static func layout(for size: DesktopPinSize, spec: ShibaBoardSpec = .standard) -> ShibaBoardLayout? {
        let inset = inset(size)
        switch size {
        case .small:
            return nil
        case .medium:
            return ShibaBoardLayout(spec: spec, width: size.width - inset * 2 - mediumSideWidth - mediumSpacing,
                                    maxHeight: size.height - inset * 2, gap: 6)
        case .large:
            return ShibaBoardLayout(spec: spec, width: size.width - inset * 2,
                                    maxHeight: size.height - inset * 2 - headerHeight - headerSpacing, gap: 8)
        }
    }
}
