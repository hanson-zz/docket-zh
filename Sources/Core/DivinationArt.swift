import Foundation

// MARK: - 卜卦 · 小熊猫姿势图和动画节奏
//
// 三种玩法的小熊猫都是整身 3D 毛绒姿势图（Resources/Divination，@2x、高 480 像素、256 色 PNG），
// 每个动作一张，动画就是在这些姿势之间交叉淡入、加上整张图的摇摆、起跳和落地挤压。
// 签筒、龟甲、书都画在姿势图里；只有扣在地上的龟甲、铜钱、飞出来的签条和签纸上的字是单独一层。
// 这里放素材名、尺寸和每种玩法「什么时候换哪张图」，界面只照着画。

/// 一张整身姿势图。
public enum DivinationPose: String, CaseIterable, Sendable {
    /// 每日一签：抱签筒摇一摇、举起抽出的一支签、双手展开签纸看（纸上的字由代码写）。
    case qianShake = "div-qian-1-shake"
    case qianDraw = "div-qian-2-draw"
    case qianRead = "div-qian-3-read"
    /// 起卦：双手捧古龟甲（摇几下也用这张，整张图左右摆）、举过头顶、摔完把龟甲抱回来。
    case castHold = "div-cast-1-hold"
    case castRaise = "div-cast-3-raise"
    case castPickup = "div-cast-4-pickup"
    /// 解忧书：合掌默想、捧书翻开、书页正对着看答案（浅色朱红封面、深色藏蓝封面）。
    case bookWish = "div-book-1-wish"
    case bookOpenRed = "div-book-2-open-red"
    case bookOpenNavy = "div-book-2-open-navy"
    case bookAnswerRed = "div-book-3-answer-red"
    case bookAnswerNavy = "div-book-3-answer-navy"

    public var imageName: String { rawValue }

    /// 图的像素宽高（@2x）。
    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .qianShake: (360, 480)
        case .qianDraw: (392, 480)
        case .qianRead: (393, 480)
        case .castHold: (354, 480)
        case .castRaise: (313, 480)
        case .castPickup: (351, 480)
        case .bookWish: (329, 480)
        case .bookOpenRed, .bookOpenNavy: (362, 480)
        case .bookAnswerRed, .bookAnswerNavy: (355, 480)
        }
    }

    /// 宽 / 高。
    public var aspect: Double { Double(pixelSize.width) / Double(pixelSize.height) }

    /// 同一玩法里各张图的显示高度比例：图里道具占的地方不一样，按这个缩放后小熊猫个头一致。
    public var heightScale: Double {
        switch self {
        case .castHold: 0.95
        case .castPickup: 0.96
        case .bookWish: 0.966
        default: 1
        }
    }

    /// 解忧书捧书翻开、答案两张图按外观选封面：深色藏蓝、浅色朱红。
    public static func bookOpen(dark: Bool) -> DivinationPose { dark ? .bookOpenNavy : .bookOpenRed }
    public static func bookAnswer(dark: Bool) -> DivinationPose { dark ? .bookAnswerNavy : .bookAnswerRed }
}

/// 姿势图以外的几层素材，以及姿势图上代码要对齐的位置。
public enum DivinationArt {
    /// 扣在地上的古龟甲（一摔那一下，熊猫不出现，只有它）：宽 / 高。
    public static let shellDome = "div-shell-dome"
    public static let shellDomeAspect: Double = 359.0 / 200.0

    /// 铜钱正反面：默认铜色，银币、古铜绿锈是按亮度着色好的两套（Pro 皮肤）。
    public static func coin(back: Bool, skin: CoinSkin) -> String {
        let side = back ? "div-coin-back" : "div-coin-front"
        switch skin {
        case .classic: return side
        case .silver: return side + "-silver"
        case .verdigris: return side + "-verdigris"
        }
    }

    /// 签筒皮肤：盖在「摇一摇」那张图上的筒身着色层（和姿势图同尺寸）；默认竹签筒不用盖。
    public static func tubeOverlay(_ skin: TubeSkin) -> String? {
        switch skin {
        case .bamboo: nil
        case .lacquer: "div-qian-1-tube-lacquer"
        case .jade: "div-qian-1-tube-jade"
        }
    }

    /// 打进包里的每一张图（测试逐个确认文件在、尺寸对）。
    public static var allImageNames: [String] {
        var names = DivinationPose.allCases.map(\.imageName)
        names.append(shellDome)
        for skin in CoinSkin.allCases {
            names.append(coin(back: false, skin: skin))
            names.append(coin(back: true, skin: skin))
        }
        names += TubeSkin.allCases.compactMap(tubeOverlay)
        return names
    }

    /// 「展签看」图上那张空白签纸能写字的地方（按图宽高的比例，x、y 是左上角）。
    public static let slipRect = (x: 0.17, y: 0.475, width: 0.67, height: 0.19)
    /// 「摇一摇」图上签筒口（飞出来的签从这里出发）。
    public static let tubeMouth = (x: 0.74, y: 0.3)
    /// 「举过头顶」图上龟甲底边（摔下去的龟甲从这里开始落）。
    public static let raisedShellBottom: Double = 0.3
    /// 签纸上写签级的字号：按纸高取，最大 22pt；算出来不到 13pt（桌面小卡片、扩展栏那么小）
    /// 时返回 nil，纸上不写字，签级照样写在图外面。
    public static func slipFont(slipHeight: Double) -> Double? {
        let font = min(22, (slipHeight * 0.62).rounded(.down))
        return font >= Divination.minimumFont ? font : nil
    }

    /// 签纸（米白，浅色深色外观里都是同一张图）和写在上面的字色：签级用朱红，签号用深褐，
    /// 都过 4.5:1（测试守着）。
    public static let slipPaperHex = "#D6CFB8"
    public static let slipLevelInkHex = "#8E1C16"
    public static let slipNumberInkHex = "#3E2F22"
}

// MARK: - 每日一签的节奏

/// 摇一摇（抱签筒左右摆 ±8°）→ 换「举签」图、一支签从筒口沿弧线飞出 → 换「展签」图、签级写在纸上。
/// 时间都是从按下起算的秒数；减少动态效果时不走这套，直接出结果。
public struct StickShake: Equatable, Sendable {
    public var shake: Double
    public var fly: Double
    public var reveal: Double

    public static let normal = StickShake(shake: 0.54, fly: 0.45, reveal: 0.3)

    /// 签飞出（这时写进今天的签）、换展签图、全部结束。
    public var flyStart: Double { shake }
    public var readStart: Double { shake + fly }
    public var total: Double { shake + fly + reveal }

    public enum Phase: Equatable, Sendable { case shake, fly, read, rest }

    public func phase(at t: Double) -> Phase {
        if t < 0 || t >= total { return .rest }
        if t < flyStart { return .shake }
        if t < readStart { return .fly }
        return .read
    }

    /// 这一刻该显示的姿势；`rest` 时看今天抽没抽过。
    public func pose(at t: Double, drawn: Bool) -> DivinationPose {
        switch phase(at: t) {
        case .shake: .qianShake
        case .fly: .qianDraw
        case .read: .qianRead
        case .rest: drawn ? .qianRead : .qianShake
        }
    }

    /// 摇一摇的摆角（度）：-8、8、-6、6、0，每段一样长。
    public static let swayAngles: [Double] = [-8, 8, -6, 6, 0]
}

// MARK: - 起卦：每一刻换哪张图

extension ShellToss {
    public enum Phase: Equatable, Sendable {
        /// 捧着龟甲摇（姿势图整张左右摆）。
        case shake
        /// 举过头顶（先蹲一下再跳起来）。
        case raise
        /// 一摔：熊猫不出现，龟甲从高处落下扣在地上，铜钱从壳口蹦出来。
        case thrown
        /// 把龟甲抱回来。
        case pickup
        case rest
    }

    public func phase(at t: Double) -> Phase {
        if t < 0 || t >= total { return .rest }
        if t < liftStart { return .shake }
        if t < fallStart { return .raise }
        if t < pickupStart { return .thrown }
        return .pickup
    }

    /// 这一刻该显示的姿势；一摔那段是 nil（只有扣地龟甲）。`rest` 时起过卦抱着龟甲笑，没起过双手捧着。
    public func pose(at t: Double, tossed: Bool) -> DivinationPose? {
        switch phase(at: t) {
        case .shake: .castHold
        case .raise: .castRaise
        case .thrown: nil
        case .pickup: .castPickup
        case .rest: tossed ? .castPickup : .castHold
        }
    }

    /// 起跳前蹲的时长（举高那段的前一截）。
    public var crouch: Double { min(0.08, lift * 0.4) }
}

// MARK: - 解忧书：默想 → 捧书翻开 → 答案

extension WorryBook {
    /// 合掌默想停一下、捧书翻开，然后换答案图、答案逐行淡入（每行 `lineFade`）。
    public static let wishHold: Double = 0.28
    public static let openHold: Double = 0.4
    public static let lineFade: Double = 0.25

    public enum Phase: Equatable, Sendable { case wish, open, answer, rest }

    public static func phase(at t: Double) -> Phase {
        if t < 0 || t >= flipDuration { return .rest }
        if t < wishHold { return .wish }
        if t < flipSwap { return .open }
        return .answer
    }

    /// 这一刻该显示的姿势；`rest` 时翻过就是答案图，没翻过合掌默想。
    public static func pose(at t: Double, answered: Bool, dark: Bool) -> DivinationPose {
        switch phase(at: t) {
        case .wish: .bookWish
        case .open: DivinationPose.bookOpen(dark: dark)
        case .answer: DivinationPose.bookAnswer(dark: dark)
        case .rest: answered ? DivinationPose.bookAnswer(dark: dark) : .bookWish
        }
    }

    /// 第 `line` 行答案此刻的不透明度（翻到答案后逐行淡入；`rest` 时都是 1）。
    public static func lineOpacity(_ line: Int, at t: Double) -> Double {
        if t < 0 || t >= flipDuration { return 1 }
        let start = flipSwap + 0.05 + Double(line) * lineFade
        return min(1, max(0, (t - start) / lineFade))
    }
}
