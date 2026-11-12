import Foundation

/// 小熊猫身边的草丛：屏幕下边缘平时藏在草里只露耳朵，点一下冒头挥爪，久了趴进草里；
/// 程序坞上待着时脚边一小丛。走、跑、跳、叼着的时候没有草。
/// 草分前后两层：`back` 在小熊猫身后，`front` 挡在身前。素材是用户画的毛绒草（768 画布，草根在脚线），
/// 和小熊猫帧同一缩放裁成 @2x，草根贴图底，横向以小熊猫为中。
public enum DesktopPetGrass: Equatable, Sendable {
    /// 藏身：高草挡住大半个身子，只露耳朵。
    case tall
    /// 冒出来、趴着：前景压矮（只挡脚和肚子），后面几根高草。
    case low
    /// 程序坞上：脚边一小丛，没有后层。
    case mini

    /// 前景草摇摆一轮多久（秒），四拍：正、左、正、右。
    public static let swayPeriod: Double = 2.4
    /// 藏身时往草里沉多少（点，乘大小设置）：耳朵尖刚好露出前景草。
    public static let hiddenSink: Double = 18
    /// 冒头挥爪时还沉多少：脚和尾巴根留在草里。
    public static let peekSink: Double = 7
    /// 从藏着到冒出来、缩回去用多久。
    public static let riseDuration: TimeInterval = 0.28

    /// 前景草这一刻用哪张：tall 和 low 各 3 张轮着摆，mini 一张。
    public func frontImage(time: Double) -> String {
        switch self {
        case .mini: return "pet-sprite-grass-mini"
        case .tall, .low:
            let beat = Int((time / (Self.swayPeriod / 4)).rounded(.down))
            let index = [1, 2, 1, 3][((beat % 4) + 4) % 4]
            return "pet-sprite-grass-\(self == .tall ? "front" : "low")-\(index)"
        }
    }

    /// 后层，mini 没有。
    public var backImage: String? { self == .mini ? nil : "pet-sprite-grass-back" }

    /// 所有用到的图（测试核对素材在不在）。
    public static let allImages: [String] = ["pet-sprite-grass-back", "pet-sprite-grass-mini"]
        + (1...3).map { "pet-sprite-grass-front-\($0)" } + (1...3).map { "pet-sprite-grass-low-\($0)" }
}

extension DesktopPetBrain {
    /// 屏幕下边缘（蜷着那种）在草里：歇着藏身只露耳朵（耳朵偶尔抖），被点、来了事冒头挥爪，
    /// 坐着、哈欠、伸懒腰时冒出来压矮草，睡着趴进草里；走、跳等有方向的动作没有草，按侧面画。
    static func grassPose(_ state: DesktopPetState, now: Date, scale: Double) -> DesktopPetPose {
        let elapsed = max(0, now.timeIntervalSince(state.since))
        let time = now.timeIntervalSinceReferenceDate
        var hidden: DesktopPetPose
        switch state.activity {
        case .curl:
            // 藏着：坐姿沉进草里。刚趴回去的那一下从冒头的高度沉下去。
            hidden = DesktopPetPose(image: DesktopPetStrip.frontSit.imageName(DesktopPetHug.idleFrame(time: time)))
            let t = min(1, elapsed / DesktopPetGrass.riseDuration)
            hidden.lift = -(DesktopPetGrass.peekSink + (DesktopPetGrass.hiddenSink - DesktopPetGrass.peekSink) * t)
            hidden.grass = t < 0.5 ? .low : .tall
            return hidden
        case .peek, .jump, .cheer, .celebrate:
            hidden = DesktopPetPose(image: DesktopPetStrip.frontWave.imageName(Int(elapsed * 3)))
            let t = min(1, elapsed / DesktopPetGrass.riseDuration)
            hidden.lift = -(DesktopPetGrass.hiddenSink - (DesktopPetGrass.hiddenSink - DesktopPetGrass.peekSink) * t)
            hidden.grass = t < 0.5 ? .tall : .low
            return hidden
        case .droop:
            hidden = DesktopPetPose(image: DesktopPetStrip.frontLie.imageName(DesktopPetHug.idleFrame(time: time)))
            hidden.grass = .low
            return hidden
        default:
            break
        }
        if var front = frontPose(state, now: now) {
            front.grass = .low
            if case .sleep = state.activity {} else if front.image.hasPrefix("pet-sprite-front-sit") {
                front.lift = -DesktopPetGrass.peekSink
            }
            return front
        }
        return pose(state, now: now, scale: scale)
    }
}
