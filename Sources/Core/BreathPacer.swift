import Foundation

/// 环境音面板里的呼吸引导：圆圈吸气时变大、屏息时停住、呼气时缩小。
///
/// 纯函数，只按“开始了多少秒”算出当前在哪一步、这一步走了多少、圆圈该多大，
/// 测试可以拨到任意时刻。
public enum BreathPacer {

    public enum Phase: String, Sendable, Equatable {
        case inhale, holdIn, exhale, holdOut

        public var title: String {
            switch self {
            case .inhale: "吸气"
            case .holdIn: "屏息"
            case .exhale: "呼气"
            case .holdOut: "停一下"
            }
        }
    }

    /// 几种常见的节奏，每步的秒数。屏息为 0 的步骤直接跳过。
    public enum Pattern: String, CaseIterable, Identifiable, Sendable {
        case calm, box, relax

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .calm: "舒缓 4-6"
            case .box: "方块 4-4-4-4"
            case .relax: "助眠 4-7-8"
            }
        }

        /// 吸气、屏息、呼气、停一下，各几秒。
        public var seconds: [Double] {
            switch self {
            case .calm: [4, 0, 6, 0]
            case .box: [4, 4, 4, 4]
            case .relax: [4, 7, 8, 0]
            }
        }

        public var cycleLength: Double { seconds.reduce(0, +) }

        public static func parse(_ raw: String) -> Pattern { Pattern(rawValue: raw) ?? .calm }
    }

    public struct State: Equatable, Sendable {
        public var phase: Phase
        /// 这一步走了多少，0...1。
        public var progress: Double
        /// 这一步还剩几秒，向上取整，显示用。
        public var secondsLeft: Int
        /// 圆圈大小，0 是最小（呼完），1 是最大（吸满）。
        public var fullness: Double
        /// 第几轮，从 0 起。
        public var cycle: Int
    }

    static let phases: [Phase] = [.inhale, .holdIn, .exhale, .holdOut]

    /// 开始 `elapsed` 秒后的状态。负数按 0 算。
    public static func state(elapsed: Double, pattern: Pattern) -> State {
        let length = pattern.cycleLength
        let t = max(elapsed, 0)
        let cycle = Int(t / length)
        var inCycle = t - Double(cycle) * length
        for (index, duration) in pattern.seconds.enumerated() where duration > 0 {
            if inCycle < duration {
                let progress = inCycle / duration
                let phase = phases[index]
                return State(phase: phase,
                             progress: progress,
                             secondsLeft: max(1, Int((duration - inCycle).rounded(.up))),
                             fullness: fullness(phase: phase, progress: progress),
                             cycle: cycle)
            }
            inCycle -= duration
        }
        // 浮点误差落在一轮的最末尾：当作下一轮刚开始吸气。
        return State(phase: .inhale, progress: 0,
                     secondsLeft: Int(pattern.seconds[0].rounded(.up)),
                     fullness: 0, cycle: cycle + 1)
    }

    /// 吸气和呼气用缓入缓出，看起来像真的在呼吸，而不是匀速放气。
    public static func fullness(phase: Phase, progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        let eased = 0.5 - 0.5 * cos(p * .pi)
        switch phase {
        case .inhale: return eased
        case .holdIn: return 1
        case .exhale: return 1 - eased
        case .holdOut: return 0
        }
    }

    /// 帧率：只在开着引导、面板看得见、没开减少动态效果时连续动画；
    /// 否则每秒刷新一次文字就够了。
    public static func framesPerSecond(running: Bool, reduceMotion: Bool) -> Double {
        running && !reduceMotion ? 30 : 1
    }
}
