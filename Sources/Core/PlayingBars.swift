import Foundation

/// 正在播放的跳动小竖条（音乐、小宇宙、浏览器视频都用）。
///
/// 每根条是几条不同频率的正弦叠在一起，看起来像在跟着节奏跳，不读真实
/// 音频（读音频要录音权限，不值得）。纯函数，测试可以拨到任意时刻。
public enum PlayingBars {
    public static let count = 4
    public static let fps = 12.0
    /// 最矮也留一点，暂停时整排停在这个高度。
    public static let rest = 0.28

    /// 第 `index` 根条在时间 `t` 的高度，0...1。
    public static func height(index: Int, t: Double) -> Double {
        let seed = Double(index) * 1.37 + 0.5
        let a = sin(t * (5.1 + seed) + seed * 2.1)
        let b = sin(t * (8.3 + seed * 0.7) + seed * 4.7)
        let c = sin(t * (2.9 + seed * 1.3) + seed)
        let raw = 0.5 + 0.22 * a + 0.16 * b + 0.12 * c
        return min(max(raw, rest), 1)
    }

    /// 暂停或减少动态效果：一排矮矮的静止条，高低错落一点。
    public static func stillHeight(index: Int) -> Double {
        [0.45, 0.7, 0.35, 0.55][((index % 4) + 4) % 4]
    }

    /// 帧率：只在播放、卡片看得见并且没开减少动态效果时跳。
    public static func framesPerSecond(playing: Bool, visible: Bool, reduceMotion: Bool) -> Double? {
        playing && visible && !reduceMotion ? fps : nil
    }
}
