import Foundation

// MARK: - 刘海小岛跟随所选吉祥物
//
// 刘海上的专注计时按当前生效的吉祥物（`FocusMascot.of(state, unlocked:)`，没解锁 Pro 时只能是
// 小熊猫）取图：`notch-<吉祥物>-<样子>.png`，放在 Resources/NotchMascots（可带 @2x）。
// 样子有四种：peek（收起时刘海边上的小头）、focus（展开后专注中）、sleep（暂停）、done（刚完成和休息）。
// 某张图还没有时回退到现有的倒挂小熊猫（Resources/NotchPanda 的 `notch-panda-*`），focus 回退成
// hang，眨眼那一帧只在回退到小熊猫时用。小熊猫自己的 peek、sleep、done 就是现有那几张。

/// 刘海上吉祥物的样子。
public enum NotchMascotPose: String, CaseIterable, Sendable {
    case peek, focus, sleep, done

    /// 展开时吉祥物状态换成样子：专注中是 focus，暂停（等开始）是 sleep，刚完成和休息是 done。
    public static func of(_ state: FocusMascotState) -> NotchMascotPose {
        switch state {
        case .focus: .focus
        case .idle: .sleep
        case .done, .break: .done
        }
    }
}

/// 收起时左边那颗小头从哪来。
public enum NotchMascotPeek: Equatable, Sendable {
    /// 资源里的这张图。
    case image(String)
    /// 没有刘海专用小头：用专注面板那套状态图（`focus-mascot-<吉祥物>-<状态>`），和以前一样。
    case panelStill
}

public enum NotchMascotArt {
    /// 新素材放的资源目录（打包时平铺进 Bundle，按名字查）。
    public static let folder = "NotchMascots"

    /// 这只吉祥物这个样子的图名（不带扩展名）。
    public static func imageName(_ mascot: FocusMascot, _ pose: NotchMascotPose) -> String {
        "notch-\(mascot.rawValue)-\(pose.rawValue)"
    }

    /// 回退用的现有倒挂小熊猫图名。focus 是 hang，`blinking` 时是眨眼那一帧。
    public static func pandaFallback(_ pose: NotchMascotPose, blinking: Bool = false) -> String {
        switch pose {
        case .peek: NotchHangingPanda.peekImageName
        case .focus: (blinking ? NotchHangingPanda.Pose.blink : .hang).imageName
        case .sleep: NotchHangingPanda.Pose.sleep.imageName
        case .done: NotchHangingPanda.Pose.done.imageName
        }
    }

    /// 按顺序试的图名：先是这只自己的，再是小熊猫回退（去重）。
    public static func candidates(_ mascot: FocusMascot, _ pose: NotchMascotPose, blinking: Bool = false) -> [String] {
        let own = imageName(mascot, pose)
        let fallback = pandaFallback(pose, blinking: blinking)
        return own == fallback ? [own] : [own, fallback]
    }

    /// 展开时用哪张图：有自己的就用自己的（不眨眼），没有就回退小熊猫（眨眼只在这时生效）。
    /// `exists` 判断资源里有没有这张图；都没有时是 nil。
    public static func resolve(_ mascot: FocusMascot, _ pose: NotchMascotPose, blinking: Bool = false,
                               exists: (String) -> Bool) -> String? {
        candidates(mascot, pose, blinking: blinking).first(where: exists)
    }

    /// 这个样子会不会落到小熊猫回退（用来决定眨眼循环要不要跑）。
    public static func usesPandaFallback(_ mascot: FocusMascot, _ pose: NotchMascotPose,
                                         exists: (String) -> Bool) -> Bool {
        let own = imageName(mascot, pose)
        if exists(own) { return own == pandaFallback(pose) }
        return exists(pandaFallback(pose))
    }

    /// 收起时的小头：自己的 peek 图优先；别的吉祥物没有时用面板状态图（以前就是这样）；
    /// 小熊猫用现有的 `notch-panda-peek`，它也缺时用面板状态图。
    public static func peek(_ mascot: FocusMascot, exists: (String) -> Bool) -> NotchMascotPeek {
        let own = imageName(mascot, .peek)
        if exists(own) { return .image(own) }
        if mascot == .panda, exists(NotchHangingPanda.peekImageName) {
            return .image(NotchHangingPanda.peekImageName)
        }
        return .panelStill
    }
}

// MARK: - 专注面板的吉祥物道具

/// 专注面板进度环旁边、每只吉祥物的道具（Resources/FocusProps/`prop-<吉祥物>.png`），放在小熊猫
/// 竹竿那一侧（右边，左下角是吉祥物）。小熊猫用现有的竹竿，没有道具图；缺图时不画也不占位。
public enum FocusMascotProp {
    public static let folder = "FocusProps"
    /// 道具图显示多高（点）。
    public static let height: Double = 64
    /// 专注进行中轻轻上下浮动：振幅（点）和周期（秒）。
    public static let bobAmplitude: Double = 2
    public static let bobPeriod: Double = 3

    /// 道具图名；小熊猫没有（它有竹竿）。
    public static func imageName(_ mascot: FocusMascot) -> String? {
        mascot.climbsBamboo ? nil : "prop-\(mascot.rawValue)"
    }

    /// 画哪张：小熊猫不画，缺图不画。
    public static func resolve(_ mascot: FocusMascot, exists: (String) -> Bool) -> String? {
        guard let name = imageName(mascot), exists(name) else { return nil }
        return name
    }

    /// 浮动的位移（点，向上为负）：只在专注进行中浮，减弱动态效果时不动。
    public static func bob(at time: TimeInterval, running: Bool, reduceMotion: Bool) -> Double {
        guard running, !reduceMotion else { return 0 }
        return -bobAmplitude * sin(time * 2 * .pi / bobPeriod)
    }
}
