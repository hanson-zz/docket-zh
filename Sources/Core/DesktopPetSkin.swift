import Foundation

// MARK: - 桌宠换成所选吉祥物
//
// 小熊猫有整套逐帧动作（`DesktopPetStrip`）。其余五只各只有 6 张图：
// Resources/Pet/sprites/pet-sprite-<吉祥物>-<peek|sit|walk1|walk2|sleep|cheer>.png（@2x，坐姿高 130 像素，
// 脚底在图片底边、都朝右）。大脑照旧按小熊猫算动作，画之前把小熊猫的帧名换成最接近的那张：
// 走、跑、叼东西是 walk1、walk2 交替加一点颠，睡觉、趴着团起来是 sleep，欢呼、挥手是 cheer，
// 趴着探头是 peek，其余（坐、眨眼、伸懒腰、跳、吊着、贴边等）都是 sit。

public enum DesktopPetSkinAction: String, CaseIterable, Sendable {
    case peek, sit, walk1, walk2, sleep, cheer
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
        case .sleep, .fallAsleep, .lie, .hangSleep, .hugSleep, .hugSleepR, .frontSleep, .frontLie:
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
        return skinned
    }
}
