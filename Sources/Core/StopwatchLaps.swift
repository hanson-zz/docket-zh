import Foundation

/// 秒表只往上数：横向大数字带两位小数，加计次。和倒计时相反，它不管还剩多少。
///
/// 配置里的键：`started`（这一段开始的 epoch，0 是停着）、`elapsed`（之前几段
/// 攒下的秒数），以及 `laps`：每次计次那一圈的秒数，按先后排，存成文字。
public enum StopwatchLaps {
    public static let lapsKey = "laps"
    /// 最多记这么多圈，再多丢掉最早的。
    public static let maxLaps = 99

    public struct Lap: Equatable, Sendable {
        /// 第几圈，从 1 数。
        public var number: Int
        public var seconds: TimeInterval
        /// 是不是最快的那圈（至少两圈时才标）。
        public var fastest: Bool
    }

    public static func elapsed(_ config: WidgetConfig, now: Date) -> TimeInterval {
        let started = config.double("started")
        let banked = config.double("elapsed")
        guard started > 0 else { return max(0, banked) }
        return max(0, banked + now.timeIntervalSince1970 - started)
    }

    public static func isRunning(_ config: WidgetConfig) -> Bool { config.double("started") > 0 }

    public static func laps(_ config: WidgetConfig) -> [TimeInterval] {
        config.strings(lapsKey).compactMap { Double($0) }.filter { $0 >= 0 && $0.isFinite }
    }

    /// 按一下“计次”后的整组：这一圈 = 现在的总时长减去前面各圈之和。
    public static func addingLap(to laps: [TimeInterval], elapsed: TimeInterval) -> [TimeInterval] {
        let lap = max(0, elapsed - laps.reduce(0, +))
        return Array((laps + [lap]).suffix(maxLaps))
    }

    public static func store(_ laps: [TimeInterval], in config: inout WidgetConfig) {
        config.set(lapsKey, .list(laps.map { .string(String(format: "%.2f", $0)) }))
    }

    /// 最快那圈的下标；不到两圈时没有。并列时取先跑出来的那圈。
    public static func fastestIndex(_ laps: [TimeInterval]) -> Int? {
        guard laps.count >= 2 else { return nil }
        var best = 0
        for (index, lap) in laps.enumerated() where lap < laps[best] { best = index }
        return best
    }

    /// 最近几圈，新的在上；最快那圈（在所有圈里比）标出来。
    public static func recent(_ laps: [TimeInterval], count: Int = 3) -> [Lap] {
        let fastest = fastestIndex(laps)
        return laps.enumerated().reversed().prefix(max(0, count)).map {
            Lap(number: $0.offset + 1, seconds: $0.element, fastest: $0.offset == fastest)
        }
    }

    // MARK: 文字

    /// 大数字：“01:23”，过了一小时是“1:01:23”。
    public static func main(_ elapsed: TimeInterval) -> String {
        let total = Int(max(0, elapsed).rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 大数字后面的两位小数：“.45”。
    public static func hundredths(_ elapsed: TimeInterval) -> String {
        // 加一点点，免得 28.1 × 100 算成 2809.999… 少了一位。
        let value = Int((max(0, elapsed) * 100 + 1e-6).rounded(.down)) % 100
        return String(format: ".%02d", value)
    }

    /// 计次一行：“0:28.10”，过了一小时是“1:00:28.10”。
    public static func lapText(_ seconds: TimeInterval) -> String {
        let hundredths = Int((max(0, seconds) * 100 + 1e-6).rounded(.down))
        let total = hundredths / 100
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return base + String(format: ".%02d", hundredths % 100)
    }

    /// 窄卡片和暂停时的说明：“已暂停 · 3 次计次”。
    public static func caption(running: Bool, elapsed: TimeInterval, lapCount: Int) -> String {
        let state = running ? tr("正在计时") : (elapsed > 0 ? tr("已暂停") : tr("就绪"))
        return lapCount > 0 ? tr("\(state) · \(lapCount) 次计次") : state
    }
}
