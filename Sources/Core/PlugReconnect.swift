import Foundation

/// 断网状态的插头小动画（天气和 GitHub 面板共用）。
///
/// 没连上时插头拔在插座外面，电线跟着轻轻晃；点“重新连接”或服务正在重试时，
/// 插头推回插座，插口冒一点电光。纯函数，测试可以拨到任意时刻。
public enum PlugReconnect {
    public enum Phase: Equatable, Sendable {
        /// 拔着，等人点重试。
        case unplugged
        /// 插回去了，正在等结果。
        case reconnecting
    }

    /// 晃动只要很慢的帧率。
    public static let swayFPS = 10.0

    /// 点了重试以后，插头至少插着这么久再决定拔不拔出来，
    /// 免得请求被节流立刻返回时动画一闪而过。
    public static let minimumHold: TimeInterval = 1.2

    /// 现在是哪个阶段：服务在读，或者刚点过重试还在最短停留时间里，就算插着。
    public static func phase(loading: Bool, holding: Bool) -> Phase {
        loading || holding ? .reconnecting : .unplugged
    }

    /// 插头离插座有多远，0 是插好，1 是拔到最远。
    /// 拔着的时候在 0.82 到 1 之间来回晃，减少动态效果时停在 1。
    public static func gap(_ phase: Phase, t: Double, reduceMotion: Bool) -> Double {
        switch phase {
        case .reconnecting:
            return 0
        case .unplugged:
            guard !reduceMotion else { return 1 }
            return 0.91 + 0.09 * sin(t * 1.7)
        }
    }

    /// 电线下垂的程度，0...1：插头越远线绷得越直，晃的时候也跟着起伏。
    public static func sag(gap: Double, t: Double, reduceMotion: Bool) -> Double {
        let base = 1 - 0.45 * min(max(gap, 0), 1)
        guard !reduceMotion else { return base }
        return min(max(base + 0.08 * sin(t * 1.7 + 0.9), 0), 1)
    }

    /// 帧率：只有拔着、并且没开减少动态效果时才晃。插着时是静止的图。
    public static func framesPerSecond(_ phase: Phase, reduceMotion: Bool) -> Double? {
        phase == .unplugged && !reduceMotion ? swayFPS : nil
    }
}
