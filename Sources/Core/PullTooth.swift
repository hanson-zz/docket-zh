import Foundation

// MARK: - 拔牙
//
// 拔牙小组件（免费）的全部规则：一只张着大嘴的小熊猫「圆圆」，上下两排一共 12 颗牙，
// 每局随机一颗是疼牙。一颗一颗点着拔，拔到疼牙小熊猫「啊呜」一下合嘴，这局结束；
// 其余 11 颗都拔光算赢。记最高一局拔了几颗（最高连拔）和赢了几局。进行中的局、
// 纪录和静音开关都存在卡片配置里；界面（扩展栏卡片、面板、桌面卡片）只调这里，
// 测试也只测这里。小熊猫是用户画的素材（张嘴没牙的待机图、被咬、胜利三张），
// 牙用代码画在嘴里，音效代码合成。

/// 一局拔牙。牙按位置编号：上排从左到右 0...5，下排从左到右 6...11。
public struct ToothGame: Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// 还没拔第一颗：疼牙还没定（第一下才定，和扫雷的首击一样，存着的局里看不到）。
        case ready
        case playing
        /// 拔到疼牙，小熊猫合嘴了。
        case bitten
        /// 其余的牙都拔光了。
        case won
    }

    /// 拔一下的结果。
    public enum PullResult: Equatable, Sendable {
        /// 没拔：已经拔过、超出范围或这局已经结束。
        case ignored
        /// 拔下来了，接着拔。
        case pulled
        /// 拔到疼牙。
        case bitten
        /// 拔下最后一颗好牙，赢了。
        case won
    }

    /// 默认一共 12 颗：上下各 6。
    public static let defaultCount = 12

    public private(set) var count: Int
    /// 哪颗是疼牙；第一下之前是 nil。
    public private(set) var sore: Int?
    public private(set) var pulled: [Bool]
    public private(set) var status: Status
    /// 拔第一颗的时间（1970 起的秒）。
    public private(set) var startedAt: Double?
    /// 合嘴或赢的时间。
    public private(set) var endedAt: Double?

    public init(count: Int = ToothGame.defaultCount) {
        let count = min(max(2, count), 64)
        self.count = count
        self.sore = nil
        self.pulled = Array(repeating: false, count: count)
        self.status = .ready
    }

    public var isOver: Bool { status == .bitten || status == .won }
    /// 这局拔下了几颗（不算疼牙）。
    public var pulledCount: Int { pulled.lazy.filter { $0 }.count }
    /// 还要拔几颗好牙才赢。
    public var remaining: Int { max(0, count - 1 - pulledCount) }
    /// 一局最多能拔几颗（除了疼牙都拔）。
    public var maxPulls: Int { count - 1 }

    public func contains(_ index: Int) -> Bool { index >= 0 && index < count }

    /// 这颗还在嘴里。
    public func isInMouth(_ index: Int) -> Bool { contains(index) && !pulled[index] }

    /// 结束后亮出疼牙；没结束不告诉。
    public var revealedSore: Int? { isOver ? sore : nil }

    /// 拔一颗。第一下先随机定疼牙（12 颗里任一颗，包括这一颗）。
    @discardableResult
    public mutating func pull<G: RandomNumberGenerator>(_ index: Int, now: Double,
                                                        using rng: inout G) -> PullResult {
        guard contains(index), !isOver, !pulled[index] else { return .ignored }
        if status == .ready || sore == nil {
            sore = Int.random(in: 0..<count, using: &rng)
            status = .playing
            startedAt = now
        }
        if index == sore {
            status = .bitten
            endedAt = now
            return .bitten
        }
        pulled[index] = true
        if remaining == 0 {
            status = .won
            endedAt = now
            return .won
        }
        return .pulled
    }

    /// 不传随机数时用系统随机。
    @discardableResult
    public mutating func pull(_ index: Int, now: Double) -> PullResult {
        var rng = SystemRandomNumberGenerator()
        return pull(index, now: now, using: &rng)
    }

    /// 测试用：直接指定疼牙（已开局）。
    public static func fixed(count: Int = ToothGame.defaultCount, sore: Int, startedAt: Double = 0) -> ToothGame {
        var game = ToothGame(count: count)
        game.sore = min(max(0, sore), game.count - 1)
        game.status = .playing
        game.startedAt = startedAt
        return game
    }
}

// MARK: - 存进卡片配置

extension ToothGame: Codable {
    private enum CodingKeys: String, CodingKey {
        case count = "n", sore = "s", pulled = "p", status = "st", startedAt = "t0", endedAt = "t1"
    }

    /// 拔过的牙是一串 0 / 1。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = try c.decode(Int.self, forKey: .count)
        guard count >= 2, count <= 64 else {
            throw DecodingError.dataCorruptedError(forKey: .count, in: c, debugDescription: "bad count")
        }
        self.init(count: count)
        let text = try c.decode(String.self, forKey: .pulled)
        guard text.count == count else {
            throw DecodingError.dataCorruptedError(forKey: .pulled, in: c, debugDescription: "bad pulled")
        }
        pulled = text.map { $0 == "1" }
        status = try c.decode(Status.self, forKey: .status)
        if let sore = try c.decodeIfPresent(Int.self, forKey: .sore), contains(sore) {
            self.sore = sore
            // 疼牙不可能被拔下来：坏数据按没拔读。
            pulled[sore] = false
        }
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt)
        // 没定疼牙就不可能开局，按还没开始读。
        if sore == nil, status != .ready {
            status = .ready
            pulled = Array(repeating: false, count: count)
            startedAt = nil
            endedAt = nil
        }
        // 写的是赢了但牙没拔光，按进行中读。
        if status == .won, remaining > 0 { status = .playing; endedAt = nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(count, forKey: .count)
        try c.encodeIfPresent(sore, forKey: .sore)
        try c.encode(pulled.map { $0 ? "1" : "0" }.joined(), forKey: .pulled)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
    }
}

/// 拔牙的音效：代码合成的短 WAV（`WidgetSoundSynth.wav`），不带素材文件。
public enum ToothSound: String, CaseIterable, Sendable {
    /// 拔下一颗：「啵」。
    case pop
    /// 小熊猫合嘴：「咔嚓」。
    case snap
    /// 赢了：三个上行的音。
    case win
}

/// 进行中的局、纪录和静音开关都在卡片配置里（不在设置页列出：这些键不放进目录的
/// 默认值）。扩展栏卡片、面板和桌面卡片读写同一份。
public enum PullTooth {
    /// 进行中的局（紧凑 JSON）。
    public static let gameKey = "game"
    /// 最高连拔：一局里最多拔下几颗。
    public static let bestKey = "best"
    /// 创下最高连拔的那一局结束的时间（那局的 `endedAt`）：面板只在那一局写「新纪录」。
    public static let bestAtKey = "bestAt"
    /// 赢了几局。
    public static let winsKey = "wins"
    /// 音效开关（布尔，默认开）。
    public static let soundKey = "sound"

    /// 一排几颗、一共几颗。
    public static let perRow = 6
    public static let toothCount = perRow * 2

    // MARK: 读写

    public static func game(_ config: WidgetConfig) -> ToothGame {
        let raw = config.string(gameKey, default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let game = try? JSONDecoder().decode(ToothGame.self, from: data),
              game.count == toothCount else { return ToothGame(count: toothCount) }
        return game
    }

    public static func store(_ game: ToothGame, in config: inout WidgetConfig) {
        guard let data = try? JSONEncoder().encode(game),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(gameKey, .string(text))
    }

    public static func best(_ config: WidgetConfig) -> Int {
        max(0, config.int(bestKey, default: 0))
    }

    public static func wins(_ config: WidgetConfig) -> Int {
        max(0, config.int(winsKey, default: 0))
    }

    public static func soundOn(_ config: WidgetConfig) -> Bool {
        config.bool(soundKey, default: true)
    }

    public static func setSound(_ on: Bool, in config: inout WidgetConfig) {
        config.set(soundKey, .bool(on))
    }

    /// 这一局是不是刚创下最高连拔的那一局（结束了，且 `bestAt` 记的就是它）。
    public static func isRecord(_ game: ToothGame, in config: WidgetConfig) -> Bool {
        guard game.isOver, let ended = game.endedAt, game.pulledCount > 0,
              game.pulledCount == best(config) else { return false }
        return abs(config.double(bestAtKey, default: -1) - ended) < 0.001
    }

    public struct Outcome: Equatable, Sendable {
        public var result: ToothGame.PullResult
        /// 刚结束而且是新的最高连拔。
        public var newRecord: Bool

        /// 这一下该放的音效（静音时界面不放）。
        public var sound: ToothSound? {
            switch result {
            case .ignored: nil
            case .pulled: .pop
            case .bitten: .snap
            case .won: .win
            }
        }
    }

    /// 拔一颗，写回配置；结束时更新最高连拔、胜场。
    @discardableResult
    public static func apply<G: RandomNumberGenerator>(pull index: Int, to config: inout WidgetConfig,
                                                       now: Double, using rng: inout G) -> Outcome {
        var current = game(config)
        let result = current.pull(index, now: now, using: &rng)
        var outcome = Outcome(result: result, newRecord: false)
        guard result != .ignored else { return outcome }
        store(current, in: &config)
        if current.isOver {
            if current.status == .won { config.set(winsKey, .number(Double(wins(config) + 1))) }
            let count = current.pulledCount
            if count > best(config) {
                config.set(bestKey, .number(Double(count)))
                if let ended = current.endedAt { config.set(bestAtKey, .number(ended)) }
                outcome.newRecord = true
            }
        }
        return outcome
    }

    /// 用系统随机。
    @discardableResult
    public static func apply(pull index: Int, to config: inout WidgetConfig, now: Double) -> Outcome {
        var rng = SystemRandomNumberGenerator()
        return apply(pull: index, to: &config, now: now, using: &rng)
    }

    /// 重开：一局新的、疼牙还没定的。
    public static func restart(in config: inout WidgetConfig) {
        store(ToothGame(count: toothCount), in: &config)
    }

    // MARK: 文案

    /// 主角的名字。
    public static var animalName: String { tr("小熊猫圆圆") }

    /// 一句状态。
    public static func statusLine(_ game: ToothGame) -> String {
        switch game.status {
        case .ready: return tr("张大嘴了，点一颗牙拔下来")
        case .playing: return tr("还剩 \(game.remaining) 颗好牙，哪颗是疼牙？")
        case .bitten: return tr("啊呜！拔到疼牙了")
        case .won: return tr("好牙全拔光了，你赢了")
        }
    }

    /// 「最高 9 颗 · 赢 2 局」。
    public static func recordLine(best: Int, wins: Int) -> String {
        tr("最高 \(best) 颗 · 赢 \(wins) 局")
    }

    /// 面板头部的副标题：还没开局时是玩法，开局后是当前状态。
    public static func subtitle(_ game: ToothGame) -> String {
        game.status == .ready ? tr("点一颗牙拔下来，找到疼牙就合嘴！") : statusLine(game)
    }

    /// 面板信息卡右边「最高纪录」下面那行：「9 颗 · 赢 2 局」。
    public static func recordValue(best: Int, wins: Int) -> String {
        tr("\(best) 颗 · 赢 \(wins) 局")
    }

    /// 底部提示条左边：还没开局时「点一颗牙，试试手气！」，开局后剩几颗好牙；结束后面板换成「再来一局」，
    /// 这里给读屏用的状态。
    public static func hintLine(_ game: ToothGame) -> String {
        switch game.status {
        case .ready: return tr("点一颗牙，试试手气！")
        case .playing: return tr("还剩 \(game.remaining) 颗好牙")
        case .bitten, .won: return statusLine(game)
        }
    }

    /// 底部提示条右边：「12 颗牙中有 1 颗疼牙」。
    public static func ruleLine(count: Int = toothCount) -> String {
        tr("\(count) 颗牙中有 1 颗疼牙")
    }

    // MARK: 颜色

    /// 大数字的强调色（糖果粉，效果图那种偏洋红的粉）：浅色玻璃上用压深的那份（白底、近白玻璃和
    /// 浅紫雾上都过 4.5:1），深色玻璃上用提亮的那份。
    public static let accentHex = "#E0559A"
    public static let accentLightHex = "#B8267A"
    public static let accentDarkHex = "#FF8CC6"

    // MARK: 尺寸（扩展栏卡片、面板、桌面卡片）

    /// 扩展栏横排卡片宽：小熊猫缩略图、两行读数、重开键。
    public static let tileWidth: Double = 188
    public static let tileHeight: Double = 62
    /// 左右两侧扩展栏的竖条高：缩略图在上，两行读数在下。
    public static let columnHeight: Double = 120
    /// 面板宽 380（比同组的扫雷宽 40）：效果图里小熊猫占满面板宽，嘴要宽到一排 6 颗牙每颗
    /// 点击区至少 24pt，340 宽放不下。
    public static let panelWidth: Double = 380
    /// 面板卡片（DetailCard）自己的内边距。
    public static let panelCardPadding: Double = 16
    /// 尾巴在侧边时让出的深度（PanelShape.arrowDepth）。
    public static let panelTailDepth: Double = 10
    /// 面板卡片里真正能放内容的宽：面板宽减面板内容区两侧边距（DetailPanelWidth.padding），
    /// 按尾巴在侧边的最窄情况再减尾巴，最后减卡片自己的内边距。380 宽是 306。
    public static var panelContentWidth: Double {
        Double(DetailPanelWidth.content(panel: CGFloat(panelWidth), tailDepth: CGFloat(panelTailDepth),
                                        tailOnSide: true)) - panelCardPadding * 2
    }

    /// 面板里小熊猫画多宽：就是内容宽，一点不多。
    public static var panelArtWidth: Double { panelContentWidth }

    /// 面板里的小熊猫：只画脸（`.face`），牙够大。
    public static var panelArtLayout: ToothLayout { ToothLayout(width: panelArtWidth, crop: .face) }

    /// 牙的点击区最窄不小于这个（面板、桌面三档都按它测）。
    public static let minimumHitSide: Double = 24

    /// 扩展栏横排、竖排的小熊猫缩略图宽（只看，不能点）。
    public static let tileArtWidth: Double = 52
    public static let columnArtWidth: Double = 60
}

// MARK: - 小熊猫和牙的位置

/// 小熊猫是用户画的素材（Resources/Pet/sprites/tooth-panda-open.png，正方形，张大嘴、嘴里没有牙，
/// 双爪捧脸），牙用代码画在嘴里。下面的比例都按整张素材的边长算（0…1，x 从左、y 从上），
/// 按这张图的嘴标定：嘴里最宽约 0.33…0.72，上唇内沿正中约 0.496、两角往下弯，下唇内沿
/// 正中约 0.747、两角往上翘，所以两排牙的牙根顺着嘴形各弯一点（中间两颗最贴唇）。
/// `crop` 是这次画素材的哪一块：面板和扩展栏缩略图画脸（`.face`），大号桌面卡片画半身（`.bust`），
/// 中号画嘴（`.mouth`），小号只画嘴里那一块（`.closeUp`），牙才够大、点得准。画在宽 `width`、
/// 高 `width × crop 高宽比` 的框里，牙的位置和点击区也在这里算，测试保证点击区不重叠、
/// 不出框、每颗至少 `PullTooth.minimumHitSide`。
public struct ToothLayout: Equatable, Sendable {
    public struct Box: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }

        public func intersects(_ other: Box) -> Bool {
            x < other.maxX - 0.001 && other.x < maxX - 0.001 && y < other.maxY - 0.001 && other.y < maxY - 0.001
        }

        public func contains(_ other: Box) -> Bool {
            other.x >= x - 0.001 && other.maxX <= maxX + 0.001 && other.y >= y - 0.001 && other.maxY <= maxY + 0.001
        }
    }

    /// 画素材的哪一块（素材边长的比例）。
    public enum Crop: CaseIterable, Equatable, Sendable {
        /// 整张。
        case full
        /// 脸：耳朵尖和爪子外侧裁掉一点（面板、扩展栏缩略图）。
        case face
        /// 半身：眼睛到爪子（大号桌面卡片）。
        case bust
        /// 嘴和嘴唇（中号桌面卡片）。
        case mouth
        /// 只有嘴里两排牙那一块（小号桌面卡片）。
        case closeUp

        public var rect: Box {
            switch self {
            case .full: Box(x: 0, y: 0, width: 1, height: 1)
            case .face: Box(x: 0.17, y: 0.09, width: 0.71, height: 0.69)
            case .bust: Box(x: 0.225, y: 0.22, width: 0.60, height: 0.58)
            case .mouth: Box(x: 0.335, y: 0.47, width: 0.38, height: 0.30)
            case .closeUp: Box(x: 0.355, y: 0.475, width: 0.34, height: 0.294)
            }
        }
    }

    public var width: Double
    public var crop: Crop
    /// 高是宽的几倍。
    public var aspect: Double { crop.rect.height / crop.rect.width }
    public var height: Double { width * aspect }

    public init(width: Double, crop: Crop = .full) {
        self.width = max(1, width)
        self.crop = crop
    }

    /// 能放进 `maxWidth × maxHeight` 的最大的一块。
    public static func fitting(maxWidth: Double, maxHeight: Double, crop: Crop = .full) -> ToothLayout {
        let aspect = crop.rect.height / crop.rect.width
        return ToothLayout(width: min(maxWidth, maxHeight / aspect).rounded(.down), crop: crop)
    }

    // 以下都是素材边长的比例。
    /// 两排牙的左右边（上下排一样宽，正对嘴里最宽的那段）。
    static let span = (0.355, 0.695)
    /// 上牙根：正中两颗贴着上唇内沿，往两边顺着嘴角往下弯。
    static let upperRoot = 0.496
    static let upperArc = 0.018
    /// 下牙根（下唇内沿）：正中最低，往两边往上翘。
    static let lowerRoot = 0.745
    static let lowerArc = 0.030
    /// 牙高。
    static let toothHeight = 0.065
    /// 牙宽占一格的比例。
    static let toothFill = 0.8
    /// 点击区上沿（上唇里）和下沿（下唇里）。
    static let hitTop = 0.48
    static let hitBottom = 0.762
    /// 拔掉的牙往外飞的距离。
    static let closeTravel = 0.06

    /// 一个比例在框里多少点（只缩放，不平移）。
    public func value(_ fraction: Double) -> Double { fraction / crop.rect.width * width }
    /// 素材里的横坐标在框里的位置。
    public func x(_ fraction: Double) -> Double { value(fraction - crop.rect.x) }
    /// 素材里的纵坐标在框里的位置。
    public func y(_ fraction: Double) -> Double { value(fraction - crop.rect.y) }

    /// 整张素材画多大、从哪儿开始（框外的被裁掉）。
    public var artSide: Double { value(1) }
    public var artOrigin: (x: Double, y: Double) { (x(0), y(0)) }

    /// 第几列离正中多远（0 是正中两颗附近，1 是最边上），按平方走，嘴角弯得快。
    static func bend(_ column: Int) -> Double {
        let offset = (Double(column) - Double(PullTooth.perRow - 1) / 2) / (Double(PullTooth.perRow - 1) / 2)
        return offset * offset
    }

    /// 这一列的牙根（素材比例）。
    static func root(column: Int, upper: Bool) -> Double {
        upper ? upperRoot + upperArc * bend(column) : lowerRoot - lowerArc * bend(column)
    }

    /// 上下两排的分界：上排最低的牙尖和下排最高的牙尖的正中间。
    static var split: Double {
        let upperTip = (0..<PullTooth.perRow).map { root(column: $0, upper: true) + toothHeight }.max() ?? 0
        let lowerTip = (0..<PullTooth.perRow).map { root(column: $0, upper: false) - toothHeight }.min() ?? 1
        return (upperTip + lowerTip) / 2
    }

    public var hitSplit: Double { y(Self.split) }

    public var closeTravel: Double { value(Self.closeTravel) }

    /// 一格多宽（上下排一样）。
    public func pitch(upper: Bool = true) -> Double {
        value(Self.span.1 - Self.span.0) / Double(PullTooth.perRow)
    }

    /// 张嘴时这颗牙画在哪。
    public func tooth(_ index: Int) -> Box {
        let upper = index < PullTooth.perRow
        let column = index % PullTooth.perRow
        let pitch = pitch(upper: upper)
        let w = pitch * Self.toothFill
        let h = value(Self.toothHeight)
        let left = x(Self.span.0) + Double(column) * pitch + (pitch - w) / 2
        let root = y(Self.root(column: column, upper: upper))
        return Box(x: left, y: upper ? root : root - h, width: w, height: h)
    }

    /// 这颗牙的点击区：整格宽，上排从上唇里到分界线，下排从分界线到下唇里。
    public func hit(_ index: Int) -> Box {
        let upper = index < PullTooth.perRow
        let column = Double(index % PullTooth.perRow)
        let pitch = pitch(upper: upper)
        let left = x(Self.span.0) + column * pitch
        let top = upper ? y(Self.hitTop) : hitSplit
        let bottom = upper ? hitSplit : y(Self.hitBottom)
        return Box(x: left, y: top, width: pitch, height: bottom - top)
    }

    /// 点击区最窄的一边。
    public var smallestHitSide: Double {
        (0..<PullTooth.toothCount).map { min(hit($0).width, hit($0).height) }.min() ?? 0
    }

    /// 在框里点到哪颗牙（点击区外是 nil）。
    public func hitIndex(x: Double, y: Double) -> Int? {
        (0..<PullTooth.toothCount).first { i in
            let box = hit(i)
            return x >= box.x && x < box.maxX && y >= box.y && y < box.maxY
        }
    }

    /// 结束后（被咬、赢了）换成整张的表情图，按比例完整放进框里、底边对齐：
    /// 返回图画多大、左上角在哪。
    public var wholeArt: Box {
        let side = min(width, height)
        return Box(x: (width - side) / 2, y: height - side, width: side, height: side)
    }
}

/// 钉在桌面：拔牙小 / 中 / 大三档都能直接玩，小熊猫按卡片大小缩放、裁到嘴附近。卡片边距、
/// 读数行高放这里，测试保证小熊猫放得下、点击区不小于 `minimumHitSide`。
public enum DesktopCardsToothPlan {
    public static let kinds: Set<WidgetKind> = [.pullTooth]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 牙的点击区最窄不小于这个（和面板一样 24pt）。
    public static let minimumHitSide: Double = PullTooth.minimumHitSide

    public static func inset(_ size: DesktopPinSize) -> Double { size == .small ? 6 : 12 }
    /// 顶上读数一行的高（小号、大号在小熊猫上面；中号读数在右边一列）。
    public static func headerHeight(_ size: DesktopPinSize) -> Double { size == .small ? 18 : 30 }
    public static func headerSpacing(_ size: DesktopPinSize) -> Double { size == .small ? 2 : 6 }
    /// 中号右边读数一列的宽。
    public static let mediumSideWidth: Double = 128
    public static let mediumSpacing: Double = 12

    /// 每一档画小熊猫的哪一块。
    public static func crop(for size: DesktopPinSize) -> ToothLayout.Crop {
        switch size {
        case .small: .closeUp
        case .medium: .mouth
        case .large: .bust
        }
    }

    /// 这一档小熊猫画多大。
    public static func layout(for size: DesktopPinSize) -> ToothLayout {
        let inset = inset(size)
        switch size {
        case .medium:
            return .fitting(maxWidth: size.width - inset * 2 - mediumSideWidth - mediumSpacing,
                            maxHeight: size.height - inset * 2, crop: crop(for: size))
        case .small, .large:
            return .fitting(maxWidth: size.width - inset * 2,
                            maxHeight: size.height - inset * 2 - headerHeight(size) - headerSpacing(size),
                            crop: crop(for: size))
        }
    }
}

// MARK: - 音效合成

/// 三个短音效，全部现算：没有素材文件，版权干净，可商用。
public enum ToothSoundSynth {
    public static let sampleRate = WidgetSoundSynth.sampleRate

    public static func render(_ sound: ToothSound, sampleRate: Double = sampleRate) -> [Float] {
        switch sound {
        case .pop: pop(sampleRate: sampleRate)
        case .snap: snap(sampleRate: sampleRate)
        case .win: win(sampleRate: sampleRate)
        }
    }

    public static func wav(_ sound: ToothSound) -> Data {
        WidgetSoundSynth.wav(render(sound), sampleRate: sampleRate)
    }

    /// 「啵」：从低滑到高的圆润正弦，起得快、收得快，像拔出瓶塞。
    private static func pop(sampleRate: Double) -> [Float] {
        let duration = 0.09
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let frequency = 380 + 900 * min(1, t / 0.05)
            phase += 2 * .pi * frequency / sampleRate
            let attack = min(1, t / 0.003)
            let decay = exp(-t * 45)
            out[i] = Float((sin(phase) + 0.2 * sin(phase * 2)) * attack * decay * 0.6)
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 「咔嚓」：两下很短的噪声咔哒（上下牙碰上），垫一个往下掉的低音。
    private static func snap(sampleRate: Double) -> [Float] {
        let duration = 0.24
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var seed: UInt64 = 0xC0FF_EE11
        var phase = 0.0
        var high = 0.0, previous = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(Int64(bitPattern: seed >> 1) % 2_000_001) / 1_000_000 - 1
            // 一阶高通：只留脆的那部分。
            high = 0.85 * (high + white - previous)
            previous = white
            let click1 = exp(-t * 160)
            let click2 = t >= 0.045 ? exp(-(t - 0.045) * 120) * 0.8 : 0
            phase += 2 * .pi * (180 - 100 * min(1, t / duration)) / sampleRate
            let thump = sin(phase) * exp(-t * 22) * 0.5
            out[i] = Float(high * (click1 + click2) * 0.7 + thump * min(1, t / 0.004))
        }
        return limited(out, sampleRate: sampleRate)
    }

    /// 胜利：C、E、G 三个上行的短音，最后一个长一点。
    private static func win(sampleRate: Double) -> [Float] {
        let notes: [(Double, Double)] = [(523.25, 0.10), (659.25, 0.10), (783.99, 0.26)]
        var out: [Float] = []
        for (frequency, length) in notes {
            let count = Int(length * sampleRate)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let phase = 2 * .pi * frequency * t
                let attack = min(1, t / 0.006)
                let decay = exp(-t * (length > 0.2 ? 9 : 18))
                let tone = sin(phase) + 0.3 * sin(phase * 2) + 0.12 * sin(phase * 3)
                out.append(Float(tone * attack * decay * 0.4))
            }
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
