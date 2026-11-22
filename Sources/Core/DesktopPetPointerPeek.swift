import Foundation

// MARK: - 指针旁探头
//
// 桌面伙伴的第一步：鼠标停着不动约 20 秒，所选吉祥物以完整的小坐姿出现在指针左下方（图里朝右，正好看着指针）；鼠标一动、
// 按键、点按就收起。正在打字、麦克风在用（通话、开会讲解）时不出来；人走开约 3 分钟也收起。
// 静止时只是一张图，不开显示刷新。这里只有纯逻辑，窗口在 App 的 `DesktopPetPointerPeekController`。
//
// 早先用的是「趴着探头」那套图（desk-<吉祥物>-peek，身体在爪子下面截平），贴在边上才像探头；
// 浮在指针旁、底下没有东西挡着时，真机看像被切掉一块。所以指针旁一律用完整的坐姿，尺寸也收小。

public enum DesktopPetPointerPeek {
    /// 鼠标停多久出来。
    public static let appearAfter: TimeInterval = 20
    /// 鼠标和键盘都没动这么久，算人走开了，收起。
    public static let leaveAfter: TimeInterval = 180
    /// 最近这么久内按过键，算正在打字，不出来。
    public static let typingQuiet: TimeInterval = 5
    /// 指针挪动超过这么多点才算动了（手碰一下桌子的抖动不算）。
    public static let moveSlop: Double = 4
    /// 图的高度（点），再乘桌宠的大小。中号 40 点高，柴犬约 31 点宽，约是 Finder 大图标的一半以下。
    public static let baseHeight: Double = 40
    /// 图离指针的距离（点）。
    public static let gap: Double = 10
    /// 出现时从下面冒上来的距离（点）；减弱动态效果时为 0，只淡入。
    public static func rise(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 6 }

    /// 按图的原始宽高比和桌宠大小算出显示尺寸。
    public static func size(imageSize: CGSize, scale: Double) -> CGSize {
        let height = baseHeight * scale
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 1
        return CGSize(width: height * aspect, height: height)
    }

    /// 现在该不该露出来。
    /// - Parameters:
    ///   - pointerIdle: 鼠标多少秒没动。
    ///   - keyIdle: 多少秒没按键。
    ///   - quiet: 麦克风在用等要安静的时候。
    ///   - pressed: 鼠标键按着。
    public static func wanted(pointerIdle: TimeInterval, keyIdle: TimeInterval,
                              quiet: Bool, pressed: Bool) -> Bool {
        guard !quiet, !pressed, keyIdle >= typingQuiet else { return false }
        guard pointerIdle >= appearAfter else { return false }
        return min(pointerIdle, keyIdle) < leaveAfter
    }

    /// 露着时指针从 `from` 挪到 `to`，算不算动了。
    public static func moved(from: CGPoint, to: CGPoint) -> Bool {
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        return dx * dx + dy * dy > moveSlop * moveSlop
    }

    /// 图放哪（AppKit 坐标，原点左下）：默认在指针左下方，左边放不下翻到右边，下面放不下翻到上面，
    /// 最后夹进屏幕可用范围里。
    public static func frame(pointer: CGPoint, size: CGSize, bounds: CGRect) -> CGRect {
        let g = CGFloat(gap)
        var x = pointer.x - g - size.width
        var y = pointer.y - g - size.height
        if x < bounds.minX { x = pointer.x + g }
        if y < bounds.minY { y = pointer.y + g }
        x = min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        y = min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// 图的名字（不带扩展名），按顺序试，都是从头到脚完整的一只：
    /// 平时用桌宠的坐姿 `pet-sprite-<吉祥物>-sit`（小熊猫是正面坐 `pet-sprite-front-sit-1`），
    /// 专注中用专注面板闭眼打坐的 `focus-mascot-<吉祥物>-focus`；缺图时退到专注面板的站姿 idle。
    public static func imageCandidates(_ mascot: FocusMascot, focusing: Bool) -> [String] {
        let sit = mascot == .panda ? "pet-sprite-front-sit-1" : "pet-sprite-\(mascot.rawValue)-sit"
        let idle = "focus-mascot-\(mascot.rawValue)-idle"
        if focusing { return ["focus-mascot-\(mascot.rawValue)-focus", sit, idle] }
        return [sit, idle]
    }
}
