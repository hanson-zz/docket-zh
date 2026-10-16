import Foundation

/// 折叠翻页数字的纯逻辑：时钟的“折叠翻页”样式和倒计时的“折叠翻页”外观共用。
///
/// 每个数字一张上下两半的卡片，数字变化时上半张带着旧数字往下折，
/// 折过去以后下半张带着新数字落下来。画法在 FoldFlipDigits.swift，
/// 这里只放哪些字要翻、倒计时选的是哪种外观。
public enum FoldFlip {
    /// 时钟样式里的 layout 值。
    public static let clockLayout = "fold"

    /// 倒计时没有 layout，用 `look` 键：plain（默认，原来的数字）或 fold。
    public static let countdownLookKey = "look"

    public enum CountdownLook: String, CaseIterable, Sendable {
        case plain, fold

        public var title: String {
            switch self {
            case .plain: "普通数字"
            case .fold: "折叠翻页"
            }
        }
    }

    public static func countdownLook(_ config: WidgetConfig) -> CountdownLook {
        CountdownLook(rawValue: config.string(countdownLookKey, default: CountdownLook.plain.rawValue)) ?? .plain
    }

    /// 读数里的一格：数字是一张会翻的卡片，冒号这类分隔符原样画、不翻。
    public struct Cell: Equatable, Sendable {
        public var text: String
        public var flips: Bool
    }

    /// 一串读数拆成格子，顺序不变。
    public static func cells(_ text: String) -> [Cell] {
        text.map { Cell(text: String($0), flips: $0.isNumber) }
    }

    /// 从右往左数的位置，个位永远是 0。
    ///
    /// 卡片按这个认身份：倒计时从 10:00 走到 9:59 少了一位时，
    /// 分钟和秒的个位还是原来那张卡片，接着翻，而不是整排重新出现。
    public static func slot(_ index: Int, count: Int) -> Int {
        max(0, count - 1 - index)
    }
}

/// 超过目标的圆环：满一圈以后不再停住，而是在上面再画第二圈。
///
/// 喝水的圆环和圆环仪表都用它。第二圈满了就停（最多两圈），
/// 喝到三倍目标也只是两圈满，免得一圈圈叠得看不出来。
public enum RingLap {
    public static let maxLaps: Double = 2

    /// 不封顶到 1 的进度，0 到 `maxLaps`。目标是 0 或没喝时是 0。
    public static func progress(total: Int, goal: Int) -> Double {
        guard goal > 0, total > 0 else { return 0 }
        return clamp(Double(total) / Double(goal))
    }

    /// 拆成底下的第一圈和叠在上面的第二圈，各自 0 到 1。
    public static func split(_ progress: Double) -> (first: Double, second: Double) {
        let value = clamp(progress)
        return (min(value, 1), max(0, value - 1))
    }

    /// 是否已经开始画第二圈。
    public static func isLapping(_ progress: Double) -> Bool {
        split(progress).second > 0
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maxLaps)
    }
}
