import Foundation

// MARK: - 桌宠换成所选吉祥物
//
// 小熊猫有整套逐帧动作（`DesktopPetStrip`）。其余五只各只有 6 张图：
// Resources/Pet/sprites/pet-sprite-<吉祥物>-<peek|sit|walk1|walk2|sleep|cheer>.png（@2x，坐姿高 130 像素，
// 脚底在图片底边、都朝右）。大脑照旧按小熊猫算动作，画之前把小熊猫的帧名换成最接近的那张：
// 走、跑、叼东西是 walk1、walk2 交替加一点颠，睡觉、趴着团起来是 sleep，欢呼、挥手是 cheer，
// 趴着探头是 peek，吊在上边是 hang / hang-sleep（前爪在图顶），抱左右边是 hug / hug-r（贴边那侧在图边），
// 被拎起来是 drag，其余（坐、眨眼、伸懒腰、跳等）都是 sit。
// 只有一张坐姿的动作用变换补出样子（`gesture`）：伸懒腰往上拉长、打哈欠往后仰、抬头看微微后仰、
// 蔫了压矮一点、起跳和落地那几帧蹲一下。呼吸、张望、小跳等另见 `DesktopPetLively`。

public enum DesktopPetSkinAction: String, CaseIterable, Sendable {
    case peek, sit, walk1, walk2, sleep, cheer
    case hang, hangSleep = "hang-sleep", hug, hugR = "hug-r", drag
}

public enum DesktopPetSkin {
    /// 走路时 walk2 那一帧抬高多少点，像一颠一颠。
    public static let walkBob: Double = 1.5

    public static func imageName(_ mascot: FocusMascot, _ action: DesktopPetSkinAction) -> String {
        "pet-sprite-\(mascot.rawValue)-\(action.rawValue)"
    }

    /// 小熊猫帧名（pet-sprite-<动作>-<n>）拆成动作和第几帧（从 0 数）；不是动作帧时返回 nil。
    static func parse(_ image: String) -> (strip: DesktopPetStrip, frame: Int)? {
        let prefix = "pet-sprite-"
        guard image.hasPrefix(prefix), let dash = image.lastIndex(of: "-") else { return nil }
        let stem = String(image[image.index(image.startIndex, offsetBy: prefix.count)..<dash])
        guard let strip = DesktopPetStrip(rawValue: stem),
              let number = Int(image[image.index(after: dash)...]) else { return nil }
        return (strip, number - 1)
    }

    /// 小熊猫这一帧换成哪张。
    public static func action(forPandaImage image: String) -> DesktopPetSkinAction {
        guard let parsed = parse(image) else {
            return image.contains("cheer") ? .cheer : .sit
        }
        let frame = parsed.frame
        switch parsed.strip {
        case .walk:
            return (frame / 8) % 2 == 0 ? .walk1 : .walk2
        case .run, .carry:
            return (frame / 2) % 2 == 0 ? .walk1 : .walk2
        case .hang, .drop:
            return .hang
        case .hangSleep:
            return .hangSleep
        case .hug, .hugOut, .hugSleep, .hugClimb:
            return .hug
        case .hugR, .hugOutR, .hugSleepR, .hugClimbR:
            return .hugR
        case .drag:
            return .drag
        case .sleep, .fallAsleep, .lie, .frontSleep, .frontLie:
            return .sleep
        case .cheer, .frontWave:
            return .cheer
        case .peek:
            return .peek
        default:
            return .sit
        }
    }

    /// 把按小熊猫算好的样子换成别的吉祥物。小熊猫原样返回。
    public static func apply(_ pose: DesktopPetPose, mascot: FocusMascot) -> DesktopPetPose {
        guard mascot != .panda else { return pose }
        var skinned = pose
        let action = action(forPandaImage: pose.image)
        skinned.image = imageName(mascot, action)
        skinned.height = nil
        if action == .walk2 { skinned.lift += walkBob }
        gesture(forPandaImage: pose.image, into: &skinned)
        return skinned
    }

    /// 伸懒腰最多拉长多少、打哈欠最多后仰几度、抬头看后仰几度、蔫了压矮多少。
    public static let stretchLift: Double = 0.09
    public static let yawnLean: Double = 5
    public static let lookLean: Double = 3
    public static let droopSink: Double = 0.07

    /// 小熊猫这一帧在它那套动作里走到了多深（0…1…0）：顺着播的按正弦弧，来回播的（正面 4 帧、抬头）按帧号。
    static func depth(strip: DesktopPetStrip, frame: Int) -> Double {
        let count = max(1, strip.frameCount)
        let index = min(count - 1, max(0, frame))
        switch strip {
        case .frontStretch, .frontYawn, .lookup:
            return count > 1 ? Double(index) / Double(count - 1) : 1
        default:
            return sin(.pi * (Double(index) + 0.5) / Double(count))
        }
    }

    /// 别的吉祥物没有专门帧的动作，用缩放、转动在坐姿上做出来。`pose` 已经换成那只的图。
    static func gesture(forPandaImage image: String, into pose: inout DesktopPetPose) {
        guard let parsed = parse(image) else { return }
        let back: Double = pose.facingLeft ? 1 : -1
        let k = depth(strip: parsed.strip, frame: parsed.frame)
        switch parsed.strip {
        case .stretch, .frontStretch:
            pose.scaleY *= 1 + stretchLift * k
            pose.scaleX *= 1 - stretchLift * 0.45 * k
        case .yawn, .frontYawn:
            pose.wobble += back * yawnLean * k
            pose.scaleY *= 1 + 0.03 * k
        case .lookup:
            pose.wobble += back * lookLean * k
        case .droop:
            pose.scaleY *= 1 - droopSink
        case .jump:
            // 8 帧：蹲（1、2）、起跳落地蹲（5）压扁一点。
            if [1, 2, 5].contains(parsed.frame) {
                pose.scaleY *= 0.92
                pose.scaleX *= 1.04
            }
        default:
            break
        }
    }
}
