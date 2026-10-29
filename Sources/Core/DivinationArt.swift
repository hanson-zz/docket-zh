import Foundation

// MARK: - 卜卦 · 小熊猫姿势图和动画节奏
//
// 三种玩法的小熊猫都是整身 3D 毛绒姿势图（Resources/Divination，@2x、高 480 像素、256 色 PNG），
// 每个动作一张，动画就是在这些姿势之间交叉淡入、加上整张图的摇摆、起跳和落地挤压。
// 签筒、龟甲、书都画在姿势图里；只有铜钱、飞出来的签条、签纸和书页上的字是单独一层。
// 每种玩法按用户给的分解图分成几拍（`DivinationBeat`），每拍一张姿势、停一下再换下一拍。
// 这里放素材名、尺寸、对齐点和每一拍的时间，界面只照着画。

/// 一张整身姿势图。
public enum DivinationPose: String, CaseIterable, Sendable {
    /// 每日一签：① 抱签筒摇一摇（筒口朝上）、② 签蹦出来时抱着签筒仰头看、③ 双手捧着展开的签纸
    /// （纸上的字由代码写）。
    case qianShake = "div-qian-1-shake"
    case qianLook = "div-qian-2-look"
    case qianRead = "div-qian-3-read"
    /// 起卦：① 双手捧古龟甲（② 摇几下也用这张，整张图左右摆）、③ 跳起举过头顶、③ 往地上一摔
    /// （蹲着双爪按住扣在地上的龟甲，壳口朝前，铜钱从这里蹦出来）、④ 把龟甲抱回来。
    case castHold = "div-cast-1-hold"
    case castRaise = "div-cast-3-raise"
    case castSlam = "div-cast-3-slam"
    case castPickup = "div-cast-4-pickup"
    /// 解忧书：① 合掌默想、② 双手捧着刚翻开的书（书页朝外、页上空白，中间几页还翘着，眯眼笑）、
    /// ③ 书页正对着看答案（睁眼，页上泛金光、写字）。浅色朱红封面、深色藏蓝封面。②③ 两张图
    /// 书的位置和小熊猫身子一样大、对在同一处，换图时只看见书页翻平、亮起来。
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
        case .qianLook: (361, 480)
        case .qianRead: (393, 480)
        case .castHold: (354, 480)
        case .castRaise: (313, 480)
        case .castSlam: (427, 480)
        case .castPickup: (351, 480)
        case .bookWish: (329, 480)
        case .bookOpenRed, .bookOpenNavy: (355, 480)
        case .bookAnswerRed, .bookAnswerNavy: (355, 480)
        }
    }

    /// 宽 / 高。
    public var aspect: Double { Double(pixelSize.width) / Double(pixelSize.height) }

    /// 同一玩法里各张图的显示高度比例：图里道具占的地方不一样，按这个缩放后小熊猫个头一致
    /// （一摔那张是蹲着的，头和别的图一样大时整张图略矮）。
    public var heightScale: Double {
        switch self {
        case .castHold: 0.95
        case .castSlam: 0.96
        case .castPickup: 0.96
        case .bookWish: 0.966
        default: 1
        }
    }

    /// 小熊猫身子（脚）在图里的横向位置（占图宽的比例）。姿势层把这一点对在场景中线上，
    /// 换图时脚底不左右跳：尾巴、龟甲、书伸出去的那边不算。
    public var anchorX: Double {
        switch self {
        case .castHold: 0.6
        case .castRaise: 0.47
        case .castSlam: 0.45
        case .castPickup: 0.44
        case .bookWish: 0.6
        case .bookOpenRed, .bookOpenNavy, .bookAnswerRed, .bookAnswerNavy: 0.51
        default: 0.5
        }
    }

    /// 按 `poseHeight` 画时这张图的显示宽高。
    public func displaySize(poseHeight: Double) -> (width: Double, height: Double) {
        let h = poseHeight * heightScale
        return (h * aspect, h)
    }

    /// 图上按比例的一点（fx、fy 从左上角算）换成场景坐标：图的 `anchorX` 对在 `centerX`、底边贴着 `bottom`。
    public func scenePoint(_ fx: Double, _ fy: Double, poseHeight: Double, centerX: Double,
                           bottom: Double) -> (x: Double, y: Double) {
        let size = displaySize(poseHeight: poseHeight)
        return (centerX + (fx - anchorX) * size.width, bottom - (1 - fy) * size.height)
    }

    /// 图中心相对场景中线的横向偏移（`anchorX` 对齐后）。
    public func centerOffset(poseHeight: Double) -> Double {
        (0.5 - anchorX) * displaySize(poseHeight: poseHeight).width
    }

    /// 解忧书捧书翻开、答案两张图按外观选封面：深色藏蓝、浅色朱红。
    public static func bookOpen(dark: Bool) -> DivinationPose { dark ? .bookOpenNavy : .bookOpenRed }
    public static func bookAnswer(dark: Bool) -> DivinationPose { dark ? .bookAnswerNavy : .bookAnswerRed }
}

/// 动画的一拍：这一拍显示哪张姿势、从第几秒开始、停多久（照分解图一拍一张，拍与拍之间
/// 交叉淡入 0.18 秒）。
public struct DivinationBeat: Equatable, Sendable {
    public var pose: DivinationPose
    public var start: Double
    public var duration: Double
    public var end: Double { start + duration }

    public init(pose: DivinationPose, start: Double, duration: Double) {
        self.pose = pose
        self.start = start
        self.duration = duration
    }
}

/// 姿势图以外的几层素材，以及姿势图上代码要对齐的位置。
public enum DivinationArt {
    /// 姿势之间交叉淡入的时长（减少动态效果时 0.15）。
    public static let crossFade: Double = 0.18

    /// 铜钱正反面：默认铜色，银币、古铜绿锈是按亮度着色好的两套（Pro 皮肤）。
    public static func coin(back: Bool, skin: CoinSkin) -> String {
        let side = back ? "div-coin-back" : "div-coin-front"
        switch skin {
        case .classic: return side
        case .silver: return side + "-silver"
        case .verdigris: return side + "-verdigris"
        }
    }

    /// 签筒皮肤：盖在抱签筒那两张图（摇一摇、仰头看签）上的筒身着色层（和姿势图同尺寸）；
    /// 默认竹签筒不用盖，别的姿势没有签筒。
    public static func tubeOverlay(_ skin: TubeSkin, pose: DivinationPose = .qianShake) -> String? {
        let prefix: String
        switch pose {
        case .qianShake: prefix = "div-qian-1-tube-"
        case .qianLook: prefix = "div-qian-2-tube-"
        default: return nil
        }
        switch skin {
        case .bamboo: return nil
        case .lacquer: return prefix + "lacquer"
        case .jade: return prefix + "jade"
        }
    }

    /// 带签筒的姿势（着色层要和它们同尺寸）。
    public static let tubePoses: [DivinationPose] = [.qianShake, .qianLook]

    /// 打进包里的每一张图（测试逐个确认文件在、尺寸对）。
    public static var allImageNames: [String] {
        var names = DivinationPose.allCases.map(\.imageName)
        for skin in CoinSkin.allCases {
            names.append(coin(back: false, skin: skin))
            names.append(coin(back: true, skin: skin))
        }
        for pose in tubePoses {
            names += TubeSkin.allCases.compactMap { tubeOverlay($0, pose: pose) }
        }
        return names
    }

    /// 「展签看」图上那张空白签纸能写字的地方（按图宽高的比例，x、y 是左上角）。
    public static let slipRect = (x: 0.17, y: 0.475, width: 0.67, height: 0.19)
    /// 「展签看」图上小熊猫的脸（眼睛到嘴，按图宽高的比例）：签条落进手里时不从这里过。
    public static let readFaceRect = (x: 0.22, y: 0.15, width: 0.56, height: 0.29)
    /// 「仰头看」图上签筒口（蹦出来的签从这里出发）。
    public static let tubeMouth = (x: 0.8, y: 0.3)
    /// 签蹦出来以后停在半空的位置（按「仰头看」图算，在小熊猫头的右上方，它仰头看着）。
    /// 场景太小时界面再把签条收进场景里。
    public static let slipHover = (x: 1.08, y: 0.1)
    /// 飞出来的签条高度：按姿势高度取，最小 24。
    public static func flyingSlipHeight(poseHeight: Double) -> Double { max(24, poseHeight * 0.26) }
    /// 签条宽 / 高。
    public static let flyingSlipAspect: Double = 0.34

    /// 签条停在半空的中心：按 `slipHover` 算，再收进场景（四边留 2pt），不会被裁。
    public static func hoverCenter(sceneWidth: Double, sceneHeight: Double, poseHeight: Double) -> (x: Double, y: Double) {
        let bottom = sceneHeight - 4
        let p = DivinationPose.qianLook.scenePoint(slipHover.x, slipHover.y, poseHeight: poseHeight,
                                                   centerX: sceneWidth / 2, bottom: bottom)
        let h = flyingSlipHeight(poseHeight: poseHeight), w = h * flyingSlipAspect
        let x = min(max(p.x, w / 2 + 2), sceneWidth - w / 2 - 2)
        let y = min(max(p.y, h / 2 + 2), sceneHeight - h / 2 - 2)
        return (x, y)
    }

    /// 「一摔」图上壳口（铜钱从这里蹦出来）和龟甲着地的中点（扬土从这里散开）。
    public static let slamMouth = (x: 0.8, y: 0.88)
    public static let slamContactX: Double = 0.68
    /// 「一摔」图上龟甲的宽（占图宽）。
    public static let slamShellWidth: Double = 0.62

    /// 「答案」图上两页书能写字的地方（按图宽高的比例，x、y 是左上角）和书脊的横向位置。
    public static let bookPageRect = (x: 0.19, y: 0.47, width: 0.67, height: 0.26)
    public static let bookSpineX: Double = 0.525
    /// 书页上淡淡的墨字（竖排几列短笔画）每页几列。
    public static let bookInkColumns = 4

    /// 金色四角星光点：每颗相对中心的方向（单位圆上，y 向下）、大小（pt）和起始延迟（按进度算）。
    public static let sparkleStars: [(x: Double, y: Double, size: Double, delay: Double)] = [
        (-1, -0.55, 9, 0), (0.95, -0.7, 11, 0.08), (1.1, 0.35, 7, 0.16), (-1.05, 0.45, 8, 0.12), (0.15, -1.1, 7, 0.22),
    ]

    /// 光点半径：先取 `preferred`，放不下时缩到每颗星（连同大小）都在 `width`×`height` 的场景里，不被裁。
    public static func sparkleRadius(center: (x: Double, y: Double), preferred: Double,
                                     width: Double, height: Double) -> Double {
        var r = preferred
        for star in sparkleStars {
            let half = star.size / 2
            if star.x < 0 { r = min(r, (center.x - half) / -star.x) }
            if star.x > 0 { r = min(r, (width - center.x - half) / star.x) }
            if star.y < 0 { r = min(r, (center.y - half) / -star.y) }
            if star.y > 0 { r = min(r, (height - center.y - half) / star.y) }
        }
        return max(0, r)
    }

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

/// 照分解图三拍：① 抱签筒摇一摇（整张图 ±8° 摆）→ ② 换「仰头看」图，一支签从筒口蹦出来、
/// 飞到小熊猫头的右上方停在半空，小熊猫仰头看着 → ③ 换「展签」图，签条落进它手里、展开成
/// 那张签纸，签级写在纸上，冒几颗金色光点。时间都是从按下起算的秒数，合计和原来一样
/// （摇签筒、「嗒」的声音按这里的时间放）。减少动态效果时不走这套，直接出结果。
public struct StickShake: Equatable, Sendable {
    public var shake: Double
    public var fly: Double
    public var reveal: Double

    public static let normal = StickShake(shake: 0.5, fly: 0.42, reveal: 0.37)

    /// 第二拍里签条从筒口蹦到半空用掉的比例，后面停在半空。
    public static let popFraction: Double = 0.45
    /// 第三拍开头签条从半空落进手里、展开成签纸的时长（换图的交叉淡入也在这段里）。
    /// 改成先往下落再横着滑进手里以后路线长一点，0.14 改 0.18（还在第三拍的一半以内）。
    public static let catchDuration: Double = 0.18
    /// 落进手里那段里，前面这一截在小熊猫右边竖着往下落（大小不变），后面横着滑进手里、展开。
    public static let dropFraction: Double = 0.45

    /// 签蹦出（这时写进今天的签、「嗒」）、换展签图、全部结束。
    public var flyStart: Double { shake }
    public var readStart: Double { shake + fly }
    public var total: Double { shake + fly + reveal }
    /// 签条落定在手里、纸上的字开始出来。
    public var caught: Double { readStart + Self.catchDuration }

    public enum Phase: Equatable, Sendable { case shake, fly, read, rest }

    public func phase(at t: Double) -> Phase {
        if t < 0 || t >= total { return .rest }
        if t < flyStart { return .shake }
        if t < readStart { return .fly }
        return .read
    }

    /// 三拍：摇一摇、仰头看签、展签。
    public var beats: [DivinationBeat] {
        [DivinationBeat(pose: .qianShake, start: 0, duration: shake),
         DivinationBeat(pose: .qianLook, start: flyStart, duration: fly),
         DivinationBeat(pose: .qianRead, start: readStart, duration: reveal)]
    }

    /// 这一刻该显示的姿势；`rest` 时看今天抽没抽过。
    public func pose(at t: Double, drawn: Bool) -> DivinationPose {
        switch phase(at: t) {
        case .shake: .qianShake
        case .fly: .qianLook
        case .read: .qianRead
        case .rest: drawn ? .qianRead : .qianShake
        }
    }

    /// 签条此刻在哪一段：蹦出（0…1）、停在半空（0…1）、落进手里展开（0…1）；不在飞时 nil。
    public enum SlipStage: Equatable, Sendable {
        case pop(Double)
        case hover(Double)
        case land(Double)
    }

    public func slipStage(at t: Double) -> SlipStage? {
        guard t >= flyStart, t < caught else { return nil }
        if t >= readStart { return .land((t - readStart) / Self.catchDuration) }
        let p = (t - flyStart) / fly
        if p < Self.popFraction { return .pop(p / Self.popFraction) }
        return .hover((p - Self.popFraction) / (1 - Self.popFraction))
    }

    /// 签条的位置和大小（中心点、宽高，场景坐标）。
    public struct SlipFrame: Equatable, Sendable {
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

        public var minX: Double { x - width / 2 }
        public var maxX: Double { x + width / 2 }
        public var minY: Double { y - height / 2 }
        public var maxY: Double { y + height / 2 }
    }

    /// 签纸在场景里落定的位置（「展签」图上那张签纸）。
    public static func caughtFrame(sceneWidth: Double, sceneHeight: Double, poseHeight: Double) -> SlipFrame {
        let s = DivinationArt.slipRect
        let a = DivinationPose.qianRead.scenePoint(s.x, s.y, poseHeight: poseHeight, centerX: sceneWidth / 2,
                                                   bottom: sceneHeight - 4)
        let z = DivinationPose.qianRead.scenePoint(s.x + s.width, s.y + s.height, poseHeight: poseHeight,
                                                   centerX: sceneWidth / 2, bottom: sceneHeight - 4)
        return SlipFrame(x: (a.x + z.x) / 2, y: (a.y + z.y) / 2, width: z.x - a.x, height: z.y - a.y)
    }

    /// 「展签」图上小熊猫的脸在场景里的范围（minX、minY、maxX、maxY）。
    public static func faceBox(sceneWidth: Double, sceneHeight: Double,
                               poseHeight: Double) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let f = DivinationArt.readFaceRect
        let a = DivinationPose.qianRead.scenePoint(f.x, f.y, poseHeight: poseHeight, centerX: sceneWidth / 2,
                                                   bottom: sceneHeight - 4)
        let z = DivinationPose.qianRead.scenePoint(f.x + f.width, f.y + f.height, poseHeight: poseHeight,
                                                   centerX: sceneWidth / 2, bottom: sceneHeight - 4)
        return (a.x, a.y, z.x, z.y)
    }

    /// 第三拍签条落进手里（`q` 0…1）：原来从头右上方的半空斜着直线落到胸前，半路签条已经展开一半，
    /// 正好从脸前面过。现在走低路线：先在小熊猫右边竖着往下落（越落越快、大小不变），落到脸下面
    /// 那么低，再横着滑进手里、同时展开成签纸（位置和大小同一个缓动，先快后慢）；签条顶边一路
    /// 都在脸的下面，也都在场景里。
    public static func landFrame(_ q: Double, sceneWidth: Double, sceneHeight: Double,
                                 poseHeight: Double) -> SlipFrame {
        let hover = DivinationArt.hoverCenter(sceneWidth: sceneWidth, sceneHeight: sceneHeight, poseHeight: poseHeight)
        let h = DivinationArt.flyingSlipHeight(poseHeight: poseHeight)
        let w = h * DivinationArt.flyingSlipAspect
        let target = caughtFrame(sceneWidth: sceneWidth, sceneHeight: sceneHeight, poseHeight: poseHeight)
        let face = faceBox(sceneWidth: sceneWidth, sceneHeight: sceneHeight, poseHeight: poseHeight)
        let low = min(max(target.y, face.maxY + h / 2 + 2, hover.y), sceneHeight - h / 2 - 2)
        let q = min(1, max(0, q))
        if q < dropFraction {
            let p = q / dropFraction
            return SlipFrame(x: hover.x, y: hover.y + (low - hover.y) * p * p, width: w, height: h)
        }
        let p = (q - dropFraction) / (1 - dropFraction)
        let e = 1 - (1 - p) * (1 - p)
        return SlipFrame(x: hover.x + (target.x - hover.x) * e, y: low + (target.y - low) * e,
                         width: w + (target.width - w) * e, height: h + (target.height - h) * e)
    }

    /// 签纸上的字此刻的不透明度：签条落定后 0.15 秒淡入；不在动时 1。
    public func slipTextOpacity(at t: Double) -> Double {
        if t < 0 || t >= total { return 1 }
        return min(1, max(0, (t - caught) / 0.15))
    }

    /// 摇一摇的摆角（度）：-8、8、-6、6、0，每段一样长。
    public static let swayAngles: [Double] = [-8, 8, -6, 6, 0]
}

// MARK: - 起卦：每一拍换哪张图

extension ShellToss {
    public enum Phase: Equatable, Sendable {
        /// ① 双手捧着龟甲（轻轻往上一托）。
        case hold
        /// ② 捧着龟甲摇几下（姿势图整张左右摆，铜钱叮当）。
        case shake
        /// ③ 举过头顶（先蹲一下再跳起来，在最高处停一下）。
        case raise
        /// ③ 一摔：换「一摔」图，小熊猫落地蹲着把龟甲扣在面前地上，铜钱从壳口蹦出来、落在前面地上。
        case slam
        /// ④ 把龟甲抱回来，铜钱留在地上显示这一爻。
        case pickup
        case rest
    }

    public func phase(at t: Double) -> Phase {
        if t < 0 || t >= total { return .rest }
        if t < shakeStart { return .hold }
        if t < liftStart { return .shake }
        if t < fallStart { return .raise }
        if t < pickupStart { return .slam }
        return .pickup
    }

    /// 五拍：捧、摇、举高、一摔（铜钱蹦出落地）、捡回。
    public var beats: [DivinationBeat] {
        [DivinationBeat(pose: .castHold, start: 0, duration: hold),
         DivinationBeat(pose: .castHold, start: shakeStart, duration: shake),
         DivinationBeat(pose: .castRaise, start: liftStart, duration: lift),
         DivinationBeat(pose: .castSlam, start: fallStart, duration: pickupStart - fallStart),
         DivinationBeat(pose: .castPickup, start: pickupStart, duration: pickup)]
    }

    /// 这一刻该显示的姿势。`rest` 时起过卦抱着龟甲笑，没起过双手捧着。
    public func pose(at t: Double, tossed: Bool) -> DivinationPose {
        switch phase(at: t) {
        case .hold, .shake: .castHold
        case .raise: .castRaise
        case .slam: .castSlam
        case .pickup: .castPickup
        case .rest: tossed ? .castPickup : .castHold
        }
    }

    /// 起跳前蹲的时长、往上跳的时长（举高那拍的前一截，剩下的在最高处停着）。
    public var crouch: Double { min(0.08, lift * 0.4) }
    public var rise: Double { min(0.14, lift - crouch) }

    /// 场景里的位置：小熊猫身子（脚）在 `pandaX`、脚底在 `footY`。面板（内容宽 266）小熊猫在中线上，
    /// 铜钱落在它前面的一排（`coinRowY` 是铜钱中心），和脚隔开，不压在脚上；桌面卡片地方小，
    /// 小熊猫靠左，铜钱在它右边脚底那条线上排成一排（`coinsInRow`），小一号。起跳、托一下、
    /// 铜钱抛高和扬土都按小熊猫高度跟面板（136）的比例缩。
    public struct Layout: Equatable, Sendable {
        public var sceneWidth: Double
        public var sceneHeight: Double
        public var poseHeight: Double
        public var footY: Double
        public var coin: Double
        public var coinRowY: Double
        public var pandaX: Double
        public var coinsInRow: Bool
        /// 排成一排时铜钱之间、铜钱和小熊猫之间留的缝。
        public var coinGap: Double

        public init(sceneWidth: Double, sceneHeight: Double, poseHeight: Double, footY: Double, coin: Double,
                    coinRowY: Double, pandaX: Double? = nil, coinsInRow: Bool = false, coinGap: Double = 2) {
            self.sceneWidth = sceneWidth
            self.sceneHeight = sceneHeight
            self.poseHeight = poseHeight
            self.footY = footY
            self.coin = coin
            self.coinRowY = coinRowY
            self.pandaX = pandaX ?? sceneWidth / 2
            self.coinsInRow = coinsInRow
            self.coinGap = coinGap
        }

        /// 和面板小熊猫（136）的比例。
        public var scale: Double { poseHeight / 136 }
        /// 跳起来的高度、① 往上一托的高度。
        public var jumpHeight: Double { 14 * scale }
        public var holdLift: Double { 4 * scale }
        /// 第 i 枚铜钱从壳口蹦出来的抛高。
        public func coinArc(_ i: Int) -> Double { (40 + 8 * Double(i)) * scale }
        /// 三枚铜钱出壳口时左右错开的距离。
        public var mouthSpread: Double { 5 * scale }
        /// 一摔触地压扁时图最多横着胖多少（铜钱排在旁边时要让开）。
        public static let squashWidth: Double = 1.06

        /// 第 i 枚铜钱停下的中心（场景坐标）。
        public func landing(_ i: Int) -> (x: Double, y: Double) {
            if coinsInRow {
                let slam = DivinationPose.castSlam
                let right = slam.displaySize(poseHeight: poseHeight).width * (1 - slam.anchorX) * Self.squashWidth
                let first = pandaX + right + coinGap + coin / 2
                return (first + Double(i) * (coin + coinGap), coinRowY)
            }
            let spot = ShellToss.landings[i]
            return (pandaX + spot.x * coin, coinRowY + spot.y * coin)
        }

        /// 三枚铜钱停下的中间（光点从这里散开）。
        public var coinsCenter: (x: Double, y: Double) {
            let spots = (0..<3).map { landing($0) }
            return (spots.map(\.x).reduce(0, +) / 3, spots.map(\.y).reduce(0, +) / 3)
        }
    }

    public static let panelLayout = Layout(sceneWidth: Divination.panelContentWidth, sceneHeight: 198,
                                           poseHeight: 136, footY: 152, coin: 30, coinRowY: 176)
}

// MARK: - 解忧书：默想 → 捧书翻开 → 答案

extension WorryBook {
    /// ① 合掌默想停一下、② 捧书翻开（这时翻页纸声），③ 换答案图：书页泛金光、页上淡淡出字，
    /// 书下的答案逐行淡入（每行 `lineFade`）。合计和原来一样。
    public static let wishHold: Double = 0.36
    public static let openHold: Double = 0.4
    public static let lineFade: Double = 0.21

    public enum Phase: Equatable, Sendable { case wish, open, answer, rest }

    public static func phase(at t: Double) -> Phase {
        if t < 0 || t >= flipDuration { return .rest }
        if t < wishHold { return .wish }
        if t < flipSwap { return .open }
        return .answer
    }

    /// 三拍：默想、翻开、答案。
    public static func beats(dark: Bool) -> [DivinationBeat] {
        [DivinationBeat(pose: .bookWish, start: 0, duration: wishHold),
         DivinationBeat(pose: DivinationPose.bookOpen(dark: dark), start: wishHold, duration: openHold),
         DivinationBeat(pose: DivinationPose.bookAnswer(dark: dark), start: flipSwap, duration: flipDuration - flipSwap)]
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

    /// 书页上第 `column` 列淡墨字此刻的不透明度：从右页最右一列往左依次出来（竖排从右往左读），
    /// 和书下的答案一起写完；`rest` 时都是 1。
    public static func inkOpacity(_ column: Int, of count: Int, at t: Double) -> Double {
        if t < 0 || t >= flipDuration { return 1 }
        let span = flipDuration - flipSwap - 0.05
        let step = span / Double(max(1, count))
        let order = count - 1 - column
        let start = flipSwap + 0.05 + Double(order) * step * 0.8
        return min(1, max(0, (t - start) / max(0.05, step)))
    }
}
