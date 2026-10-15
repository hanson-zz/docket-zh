import Foundation

/// 液态外观的共用规则：专注计时、时间进度、系统活动和摸鱼时钟都画同一种
/// 双层波浪水（波形借用 `BatteryMotion.surface`）。这里只管水位和帧率，
/// 卡片只负责画。
///
/// 省电：只有卡片真的在屏幕上时才动；平时 10 帧的慢波纹，闪金光时 30 帧；
/// 打开“减少动态效果”或调用方说水面静止时是一张静止的图。
public enum LiquidMotion {
    public static let idleFPS = 10.0
    public static let flourishFPS = 30.0

    public static func framesPerSecond(visible: Bool, reduceMotion: Bool,
                                       still: Bool = false, golden: Bool = false) -> Double? {
        guard visible, !reduceMotion, !still else { return nil }
        return golden ? flourishFPS : idleFPS
    }

    /// 0...1，非数字当 0。
    public static func level(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// 专注计时的水位：随专注时间慢慢涨，结束时满，没开始是空的。
    public static func timerLevel(remaining: Double, total: Double) -> Double {
        guard total > 0, remaining.isFinite else { return 0 }
        return level(1 - remaining / total)
    }

    /// 专注计时刚结束的一分钟里水面闪金光；`secondsSinceEnd` 是离到点过了
    /// 多少秒，没在计时（没有到点时间）时是 nil。
    public static let goldenSeconds = 60.0

    public static func timerGolden(secondsSinceEnd: Double?) -> Bool {
        guard let since = secondsSinceEnd, since.isFinite else { return false }
        return since >= 0 && since < goldenSeconds
    }

    /// 时间进度和系统活动的“液态”是一种 layout，和圆环、条形并列。
    public static let layout = "liquid"

    /// 专注计时没有 layout，用 `look` 键：ring（默认）或 liquid。
    public static let timerLookKey = "look"

    public enum TimerLook: String, CaseIterable, Sendable {
        case ring, liquid

        public var title: String {
            switch self {
            case .ring: "圆环"
            case .liquid: "液态"
            }
        }
    }

    public static func timerLook(_ config: WidgetConfig) -> TimerLook {
        TimerLook(rawValue: config.string(timerLookKey, default: TimerLook.ring.rawValue)) ?? .ring
    }

    /// 系统活动：占用越高水波越急（1 到 2.2 倍），过了 85% 变红提醒。
    public static func busySpeed(_ load: Double) -> Double {
        1 + 1.2 * level(load)
    }

    public static let hotThreshold = 0.85

    public static func isHot(_ load: Double) -> Bool { level(load) >= hotThreshold }
}
