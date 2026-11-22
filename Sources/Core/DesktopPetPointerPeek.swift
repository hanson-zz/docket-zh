import Foundation

// MARK: - 指针旁探头
//
// 桌面伙伴的第一步：鼠标停着不动约 20 秒，所选吉祥物在指针左下方「扒着一条看不见的水平边」探出头：
// 只露头、耳朵、两只前爪和一点胸口，爪子压在那条边上；鼠标一动、按键、点按就收起。正在打字、
// 麦克风在用（通话、开会讲解）时不出来；人走开约 3 分钟也收起。静止时只是一张图，不开显示刷新。
// 这里只有纯逻辑，窗口在 App 的 `DesktopPetPointerPeekController`。
//
// 图用 desk-<吉祥物>-peek（@2x 高 192 像素），六只都是趴姿，底边就在前爪下面。真机上早先的问题是
// 这条截平的底边浮在空中、没有东西挡着，看着像被切掉一块。现在把遮罩边（那条看不见的边）放在每只
// 前爪压边的那条线上（`cut`），图底下参差的那几行藏到边后面，边上画一道极淡的接触阴影，
// 整体朝指针歪一点，出场时从边后面升起、停一下、轻轻回弹。可见高度六只统一（`visibleHeight`）。

public enum DesktopPetPointerPeek {
    /// 鼠标停多久出来。
    public static let appearAfter: TimeInterval = 20
    /// 鼠标和键盘都没动这么久，算人走开了，收起。
    public static let leaveAfter: TimeInterval = 180
    /// 最近这么久内按过键，算正在打字，不出来。
    public static let typingQuiet: TimeInterval = 5
    /// 指针挪动超过这么多点才算动了（手碰一下桌子的抖动不算）。
    public static let moveSlop: Double = 4
    /// 露在边上面那一截的高度（点），六只统一，再乘桌宠的大小。中号 40 点高（原来整张 64 点）。
    public static let visibleHeight: Double = 40
    /// 图离指针的距离（点）。
    public static let gap: Double = 10
    /// 整体朝指针歪几度（3 到 5 度之间）。
    public static let tiltDegrees: Double = 4
    /// 接触阴影：沿遮罩边一道很淡的影子，宽度是可见宽度的多少、多不透明、多糊。
    public static let contactShadowWidth: Double = 0.78
    public static let contactShadowOpacity: Double = 0.16
    public static let contactShadowRadius: Double = 2
    /// 窗口四周给歪斜、回弹和接触阴影留的透明边（点）。
    public static let margin: Double = 6

    /// 一张探头图怎么裁：都是占图高的比例（从图顶往下量）。
    /// `top` 是头顶（耳朵尖）那一行，`chin` 是下巴（头的下沿），`edge` 是前爪压边的那条线，
    /// 遮罩边就放在这里，再往下（图底参差的几行）藏到边后面。
    public struct Cut: Equatable, Sendable {
        public var top: Double
        public var chin: Double
        public var edge: Double

        public init(top: Double, chin: Double, edge: Double) {
            self.top = top
            self.chin = chin
            self.edge = edge
        }

        /// 头占露出来那一截的多少。
        public var headShare: Double { (chin - top) / (edge - top) }
    }

    /// 六只探头图各自的裁法（按 @2x 192 像素高的图量出来的行号）。前爪下沿往下那几行只剩零碎的
    /// 毛边（不透明的不到一半），遮罩边放在它上面一点。
    public static func cut(_ mascot: FocusMascot) -> Cut {
        func rows(_ top: Double, _ chin: Double, _ edge: Double) -> Cut {
            Cut(top: top / 192, chin: chin / 192, edge: edge / 192)
        }
        switch mascot {
        case .cat: return rows(1, 132, 186)
        case .octopus: return rows(0, 146, 184)
        case .otter: return rows(0, 148, 185)
        case .panda: return rows(0, 128, 185)
        case .penguin: return rows(1, 122, 183)
        case .shiba: return rows(1, 128, 181)
        }
    }

    /// 缺探头图、退到整张坐姿时不裁：整张都露出来，边就在脚底。
    public static let uncut = Cut(top: 0, chin: 0.7, edge: 1)

    /// 探头摆好的样子（点，原点在遮罩边左端，y 向上）。
    public struct Layout: Equatable, Sendable {
        /// 露在边上面那一截（宽 × 高），也是遮罩的范围。
        public var visible: CGSize
        /// 整张图画在哪：底下一截在 y < 0，被边挡住。
        public var image: CGRect
        /// 整个窗口内容的大小（露出来那截加四周的 `margin`）。
        public var panel: CGSize
    }

    /// 按图的宽高（任意单位，只看比例）、裁法和桌宠大小算出摆法。
    public static func layout(imageSize: CGSize, cut: Cut, scale: Double) -> Layout {
        let h = Double(imageSize.height), w = Double(imageSize.width)
        guard h > 0, w > 0, cut.edge > cut.top else {
            let side = visibleHeight * scale
            return Layout(visible: CGSize(width: side, height: side),
                          image: CGRect(x: 0, y: 0, width: side, height: side),
                          panel: CGSize(width: side + margin * 2, height: side + margin * 2))
        }
        let shown = visibleHeight * scale
        let drawnHeight = shown / (cut.edge - cut.top)
        let drawnWidth = drawnHeight * w / h
        let below = drawnHeight * (1 - cut.edge)
        let visible = CGSize(width: drawnWidth, height: shown)
        return Layout(visible: visible,
                      image: CGRect(x: 0, y: -below, width: drawnWidth, height: drawnHeight),
                      panel: CGSize(width: drawnWidth + margin * 2, height: shown + margin * 2))
    }

    /// 朝指针歪多少度：正数是往右歪（顶部偏右，顺时针）。图在指针左边就往右歪，在右边就往左歪。
    public static func lean(pointerOnRight: Bool) -> Double {
        pointerOnRight ? tiltDegrees : -tiltDegrees
    }

    // MARK: 出场

    /// 出场动画的一帧：`time` 是 0...1 的进度，`rise` 是相对最终位置往上多少点（负数在边下面），
    /// `squash` 是竖直方向的缩放（以遮罩边为基准，小于 1 是压一下，近似眨眼、耳朵动一下）。
    public struct Keyframe: Equatable, Sendable {
        public var time: Double
        public var rise: Double
        public var squash: Double
    }

    /// 从边下面多深的地方升起来（点，6 到 10 之间）。
    public static let riseDistance: Double = 8
    /// 回弹往上多冒多少（点）。
    public static let reboundHeight: Double = 1.5
    /// 整段出场多长（秒）。
    public static let entranceDuration: TimeInterval = 1.0

    /// 三段：慢慢升起（0 到 0.45）、停住并轻轻压一下像眨眼（到 0.75）、轻微回弹落定（到 1）。
    /// 减弱动态效果时没有帧，直接出现。
    public static func entrance(reduceMotion: Bool) -> [Keyframe] {
        guard !reduceMotion else { return [] }
        return [
            Keyframe(time: 0, rise: -riseDistance, squash: 1),
            Keyframe(time: 0.45, rise: 0, squash: 1),
            Keyframe(time: 0.55, rise: 0, squash: 0.96),
            Keyframe(time: 0.65, rise: 0, squash: 1),
            Keyframe(time: 0.75, rise: 0, squash: 1),
            Keyframe(time: 0.87, rise: reboundHeight, squash: 1.01),
            Keyframe(time: 1, rise: 0, squash: 1),
        ]
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

    /// 图的名字（不带扩展名），按顺序试：先是扒边探头的 `desk-<吉祥物>-peek`（按 `cut` 裁），
    /// 缺图时退到桌宠整张坐姿 `pet-sprite-<吉祥物>-sit`（小熊猫是 `pet-sprite-front-sit-1`，不裁）。
    public static func imageCandidates(_ mascot: FocusMascot) -> [String] {
        let sit = mascot == .panda ? "pet-sprite-front-sit-1" : "pet-sprite-\(mascot.rawValue)-sit"
        return ["desk-\(mascot.rawValue)-peek", sit]
    }

    /// 这张图怎么裁：探头图按各自的 `cut`，其余（坐姿）不裁。
    public static func cut(forImage name: String, mascot: FocusMascot) -> Cut {
        name.hasSuffix("-peek") ? cut(mascot) : uncut
    }
}
