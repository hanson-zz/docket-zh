import Foundation

// MARK: - 指针旁探头
//
// 桌面伙伴的第一步：鼠标停着不动约 20 秒，所选吉祥物在指针左下方探出头（图里它朝右上看，正好看着指针）；鼠标一动、
// 按键、点按就收起。正在打字、麦克风在用（通话、开会讲解）时不出来；人走开约 3 分钟也收起。
// 静止时只是一张图，不开显示刷新。这里只有纯逻辑，窗口在 App 的 `DesktopPetPointerPeekController`。

public enum DesktopPetPointerPeek {
    /// 鼠标停多久出来。
    public static let appearAfter: TimeInterval = 20
    /// 鼠标和键盘都没动这么久，算人走开了，收起。
    public static let leaveAfter: TimeInterval = 180
    /// 最近这么久内按过键，算正在打字，不出来。
    public static let typingQuiet: TimeInterval = 5
    /// 指针挪动超过这么多点才算动了（手碰一下桌子的抖动不算）。
    public static let moveSlop: Double = 4
    /// 探头图的高度（点），再乘桌宠的大小。
    public static let baseHeight: Double = 64
    /// 图离指针的距离（点）。
    public static let gap: Double = 14

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

    /// 探头图的名字（不带扩展名），按顺序试：先是桌面伙伴专用的 `desk-<吉祥物>-peek`，
    /// 还没有时用专注面板那套站姿图（专注中用 focus，否则 idle），六只都有。
    public static func imageCandidates(_ mascot: FocusMascot, focusing: Bool) -> [String] {
        let still = focusing ? "focus" : "idle"
        return ["desk-\(mascot.rawValue)-peek", "focus-mascot-\(mascot.rawValue)-\(still)"]
    }
}
