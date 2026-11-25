import Foundation

/// 沿边流光：一道细细的彗星状光沿着卡片、输入框或圆环的边缘绕圈，表示
/// “正在进行”（AI 生成中、输入框聚焦、专注计时进行中）。这里只放纯计算：
/// 开关、动还是静、绕到哪、彗尾怎么切段、浅色深色各用多亮。画法在
/// `Sources/Widgets/EdgeBeamView.swift`。
///
/// 思路参考 border-beam-ios（MIT，Copyright (c) ismnoiet，
/// https://github.com/ismnoiet/border-beam-ios），代码是码头自己写的精简版：
/// 不用 Metal 着色器，按路径比例截出几段描边，头亮尾淡。
public enum EdgeBeam {
    /// 设置 ▸ 小组件 ▸「沿边流光」，默认开。
    public static let enabledKey = "edgeBeam.enabled"
    public static let defaultEnabled = true

    /// 绕一圈几秒。慢一点，像呼吸而不是转圈的加载动画。
    public static let lapDuration: Double = 3.6
    /// 出现、消失的淡入淡出时长。
    public static let fadeDuration: Double = 0.45
    /// 彗尾占整圈周长的多少。
    public static let tailLength: Double = 0.24
    /// 彗尾切成几段，越靠头越亮。
    public static let segmentCount = 10
    /// 静止时光停在哪（周长比例）。
    public static let stillHead: Double = 0.18
    /// 动的时候最多每秒画几帧：细线流光 30 帧已经顺，省一半电。
    public static let frameRate: Double = 30

    /// 光沿着什么形状走。
    public enum Outline: Equatable, Sendable {
        case rounded(Double)
        case capsule
        case circle
    }

    /// 此刻怎么画。
    public enum Motion: Equatable, Sendable {
        /// 不画（开关关了，或者不在进行中）。
        case off
        /// 画一道静止的光：减弱动态效果、低电量模式。
        case still
        /// 绕圈流动。
        case moving
    }

    /// 开关关了或不在进行中不画；减弱动态效果、低电量时只画静止的光，不开时间线。
    public static func motion(enabled: Bool, active: Bool, reduceMotion: Bool, lowPower: Bool) -> Motion {
        guard enabled, active else { return .off }
        return reduceMotion || lowPower ? .still : .moving
    }

    /// 走过 `elapsed` 秒后光头在周长上的位置，0..<1。
    public static func phase(elapsed: TimeInterval, lap: Double = lapDuration) -> Double {
        guard lap > 0, elapsed.isFinite else { return 0 }
        let value = (elapsed / lap).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    /// 彗尾的一段：路径上 `from`...`to`（0...1，from < to），亮度系数 `strength`（0...1）。
    public struct Segment: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public var strength: Double

        public init(from: Double, to: Double, strength: Double) {
            self.from = from
            self.to = to
            self.strength = strength
        }
    }

    /// 光头在 `head` 时的各段，从尾到头。跨过路径起点的那段拆成两段，
    /// 两段亮度一样，所以接缝看不出来。
    public static func segments(head: Double, length: Double = tailLength, count: Int = segmentCount) -> [Segment] {
        guard count > 0, length > 0 else { return [] }
        let head = phase(elapsed: head, lap: 1)
        let span = min(1, length)
        let piece = span / Double(count)
        var result: [Segment] = []
        for index in 0..<count {
            let strength = pow(Double(index + 1) / Double(count), 2)
            let end = head - span + piece * Double(index + 1)
            let start = end - piece
            let from = phase(elapsed: start, lap: 1)
            let to = phase(elapsed: end, lap: 1)
            if to == 0 {
                result.append(Segment(from: from, to: 1, strength: strength))
            } else if from < to {
                result.append(Segment(from: from, to: to, strength: strength))
            } else {
                result.append(Segment(from: from, to: 1, strength: strength))
                if to > 0 { result.append(Segment(from: 0, to: to, strength: strength)) }
            }
        }
        return result
    }

    /// 浅色、深色各一套亮度：细线、低亮度，柔光更淡更窄，不做大面积发光。
    public struct Look: Equatable, Sendable {
        /// 主线宽（点）。
        public var lineWidth: Double
        /// 主线光头处的不透明度。
        public var lineOpacity: Double
        /// 柔光线宽（点）。
        public var glowWidth: Double
        /// 柔光模糊半径（点）。
        public var glowBlur: Double
        /// 柔光光头处的不透明度。
        public var glowOpacity: Double
    }

    /// 深色底上光亮一些也不刺眼；浅色底上光会发灰，主线稍实、柔光更淡。
    public static func look(dark: Bool) -> Look {
        dark
            ? Look(lineWidth: 1.2, lineOpacity: 0.7, glowWidth: 3, glowBlur: 3, glowOpacity: 0.22)
            : Look(lineWidth: 1.2, lineOpacity: 0.62, glowWidth: 3, glowBlur: 2.5, glowOpacity: 0.14)
    }

    /// 没选过颜色（单色）时的中性光：深色是柔和的白，浅色是中灰，sRGB 0...1。
    public static func neutral(dark: Bool) -> (red: Double, green: Double, blue: Double) {
        dark ? (0.92, 0.93, 0.95) : (0.42, 0.43, 0.46)
    }

    /// 线画在形状里面：往里收半个线宽，圆角跟着收，不会被外层裁掉。
    public static func inset(dark: Bool) -> Double { look(dark: dark).lineWidth / 2 }
}
