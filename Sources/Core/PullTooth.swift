import Foundation

// MARK: - 拔牙
//
// 拔牙小组件（免费）的全部规则：一只张着大嘴的小河马「圆圆」，上下两排一共 12 颗牙，
// 每局随机一颗是疼牙。一颗一颗点着拔，拔到疼牙河马「啊呜」一下合嘴，这局结束；
// 其余 11 颗都拔光算赢。记最高一局拔了几颗（最高连拔）和赢了几局。进行中的局、
// 纪录和静音开关都存在卡片配置里；界面（扩展栏卡片、面板、桌面卡片）只调这里，
// 测试也只测这里。河马、牙齿和音效都是原创的，用代码画、代码合成。

/// 一局拔牙。牙按位置编号：上排从左到右 0...5，下排从左到右 6...11。
public struct ToothGame: Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// 还没拔第一颗：疼牙还没定（第一下才定，和扫雷的首击一样，存着的局里看不到）。
        case ready
        case playing
        /// 拔到疼牙，河马合嘴了。
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
    /// 河马合嘴：「咔嚓」。
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

    /// 河马的名字。
    public static var animalName: String { tr("河马圆圆") }

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

    // MARK: 颜色

    /// 大数字的强调色（树莓粉）：浅色玻璃上用压深的那份（过 4.5:1），深色玻璃上用提亮的那份。
    public static let accentHex = "#E5487A"
    public static let accentLightHex = "#C42A58"
    public static let accentDarkHex = "#FF8FB0"

    // MARK: 尺寸（扩展栏卡片、面板、桌面卡片）

    /// 扩展栏横排卡片宽：河马缩略图、两行读数、重开键。
    public static let tileWidth: Double = 188
    public static let tileHeight: Double = 62
    /// 左右两侧扩展栏的竖条高：缩略图在上，两行读数在下。
    public static let columnHeight: Double = 120
    /// 面板宽：和同组的扫雷一样 340。
    public static let panelWidth: Double = 340
    /// 面板卡片（DetailCard）自己的内边距。
    public static let panelCardPadding: Double = 16
    /// 尾巴在侧边时让出的深度（PanelShape.arrowDepth）。
    public static let panelTailDepth: Double = 10
    /// 面板卡片里真正能放内容的宽：面板宽减面板内容区两侧边距（DetailPanelWidth.padding），
    /// 按尾巴在侧边的最窄情况再减尾巴，最后减卡片自己的内边距。340 宽是 266。
    public static var panelContentWidth: Double {
        Double(DetailPanelWidth.content(panel: CGFloat(panelWidth), tailDepth: CGFloat(panelTailDepth),
                                        tailOnSide: true)) - panelCardPadding * 2
    }

    /// 面板里河马画多宽：就是内容宽，一点不多。
    public static var panelArtWidth: Double { panelContentWidth }
}

// MARK: - 河马和牙的位置

/// 河马画在一个宽 `width`、高 `width × aspect` 的框里，所有部件按宽的比例摆。牙的位置
/// 和点击区也在这里算，界面照着画、照着放按钮，测试保证点击区不重叠、不出框、够大。
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

        public func intersects(_ other: Box) -> Bool {
            x < other.maxX - 0.001 && other.x < maxX - 0.001 && y < other.maxY - 0.001 && other.y < maxY - 0.001
        }
    }

    /// 高是宽的几倍。
    public static let aspect = 0.82

    public var width: Double
    public var height: Double { width * Self.aspect }

    public init(width: Double) { self.width = max(1, width) }

    /// 能放进 `maxWidth × maxHeight` 的最大的河马。
    public static func fitting(maxWidth: Double, maxHeight: Double) -> ToothLayout {
        ToothLayout(width: min(maxWidth, maxHeight / aspect).rounded(.down))
    }

    // 以下都是宽的比例（y 也按宽算）。
    /// 上牙根（上牙床下沿）。
    static let upperRoot = 0.43
    /// 下牙根（下牙床上沿）。
    static let lowerRoot = 0.70
    /// 牙高。
    static let toothHeight = 0.11
    /// 上排左右边。
    static let upperSpan = (0.19, 0.81)
    /// 下排左右边（远一点，窄一点）。
    static let lowerSpan = (0.22, 0.78)
    /// 牙宽占一格的比例。
    static let toothFill = 0.82
    /// 合嘴时上半边往下移多少。
    static let closeTravel = 0.16
    /// 点击区上沿（上牙床里）和下沿（下牙床里）。
    static let hitTop = 0.37
    static let hitBottom = 0.75

    public func value(_ fraction: Double) -> Double { fraction * width }

    /// 上下两排的分界：两排牙尖的正中间。
    public var hitSplit: Double {
        value((Self.upperRoot + Self.toothHeight + Self.lowerRoot - Self.toothHeight) / 2)
    }

    /// 合嘴时上半边（头、上牙床、上牙）往下移多少。
    public var closeTravel: Double { value(Self.closeTravel) }

    private func span(upper: Bool) -> (Double, Double) {
        upper ? Self.upperSpan : Self.lowerSpan
    }

    /// 一格多宽（上排或下排）。
    public func pitch(upper: Bool) -> Double {
        let (left, right) = span(upper: upper)
        return value(right - left) / Double(PullTooth.perRow)
    }

    /// 张嘴时这颗牙画在哪。
    public func tooth(_ index: Int) -> Box {
        let upper = index < PullTooth.perRow
        let column = Double(index % PullTooth.perRow)
        let pitch = pitch(upper: upper)
        let w = pitch * Self.toothFill
        let h = value(Self.toothHeight)
        let x = value(span(upper: upper).0) + column * pitch + (pitch - w) / 2
        let y = upper ? value(Self.upperRoot) : value(Self.lowerRoot) - h
        return Box(x: x, y: y, width: w, height: h)
    }

    /// 这颗牙的点击区：整格宽，上排从上牙床到分界线，下排从分界线到下牙床。
    public func hit(_ index: Int) -> Box {
        let upper = index < PullTooth.perRow
        let column = Double(index % PullTooth.perRow)
        let pitch = pitch(upper: upper)
        let x = value(span(upper: upper).0) + column * pitch
        let top = upper ? value(Self.hitTop) : hitSplit
        let bottom = upper ? hitSplit : value(Self.hitBottom)
        return Box(x: x, y: top, width: pitch, height: bottom - top)
    }

    /// 点击区最窄的一边（下排更窄）。
    public var smallestHitSide: Double {
        (0..<PullTooth.toothCount).map { min(hit($0).width, hit($0).height) }.min() ?? 0
    }

    /// 在河马框里点到哪颗牙（点击区外是 nil）。
    public func hitIndex(x: Double, y: Double) -> Int? {
        (0..<PullTooth.toothCount).first { i in
            let box = hit(i)
            return x >= box.x && x < box.maxX && y >= box.y && y < box.maxY
        }
    }
}

/// 钉在桌面：拔牙小 / 中 / 大三档都能直接玩，河马按卡片大小缩放。卡片边距、读数行高放
/// 这里，测试保证河马整只放得下、点击区不小于 `minimumHitSide`。
public enum DesktopCardsToothPlan {
    public static let kinds: Set<WidgetKind> = [.pullTooth]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 牙的点击区最窄不小于这个（小号下排约 14pt 宽、26pt 高）。
    public static let minimumHitSide: Double = 13

    public static func inset(_ size: DesktopPinSize) -> Double { size == .small ? 6 : 12 }
    /// 顶上读数一行的高（小号、大号在河马上面；中号读数在右边一列）。
    public static func headerHeight(_ size: DesktopPinSize) -> Double { size == .small ? 18 : 30 }
    public static func headerSpacing(_ size: DesktopPinSize) -> Double { size == .small ? 2 : 6 }
    /// 中号右边读数一列的宽。
    public static let mediumSideWidth: Double = 128
    public static let mediumSpacing: Double = 12

    /// 这一档河马画多大。
    public static func layout(for size: DesktopPinSize) -> ToothLayout {
        let inset = inset(size)
        switch size {
        case .medium:
            return .fitting(maxWidth: size.width - inset * 2 - mediumSideWidth - mediumSpacing,
                            maxHeight: size.height - inset * 2)
        case .small, .large:
            return .fitting(maxWidth: size.width - inset * 2,
                            maxHeight: size.height - inset * 2 - headerHeight(size) - headerSpacing(size))
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
