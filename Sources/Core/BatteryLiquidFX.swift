import Foundation

/// 电池液态外观的三个动效的纯逻辑：插拔电源时水面晃一波、低电量时水面
/// 鼓起一个会呼吸的圆滴、水的颜色随电量从红经黄到绿平滑过渡。卡片只负责画。
///
/// 只属于液态外观（液态本身是 Pro，没解锁时退回经典，这里的东西一样不画）。
/// 卡片高约 58pt，幅度都很克制；打开“减少动态效果”时只换颜色，不晃、不溅、
/// 圆滴不呼吸。
public enum BatteryLiquidFX {

    // MARK: 插拔事件

    /// 电源插上还是拔掉。
    public enum PlugEvent: String, Equatable, Sendable {
        case plugged
        case unplugged
    }

    /// 两次读数之间有没有插拔：`previous` 是上一次读到的“接着电源”，
    /// 第一次读（nil）不算，免得一打开码头就晃一下。
    public static func plugEvent(previous: Bool?, current: Bool) -> PlugEvent? {
        guard let previous, previous != current else { return nil }
        return current ? .plugged : .unplugged
    }

    // MARK: 晃荡

    /// 插上电源晃多久，拔掉晃多久（拔掉只轻晃一下）。
    public static let plugSloshDuration: TimeInterval = 1.2
    public static let unplugSloshDuration: TimeInterval = 0.7

    public static func sloshDuration(_ event: PlugEvent) -> TimeInterval {
        event == .plugged ? plugSloshDuration : unplugSloshDuration
    }

    /// 水面最大倾斜（左右两端的高度差的一半），占水所在区域高度的比例。
    /// 插上 7%，拔掉是它的 40%。
    public static let plugTilt = 0.07
    public static let unplugTilt = plugTilt * 0.4

    /// 事件过去 `elapsed` 秒时水面的倾斜（-1...1 再乘最大倾斜）：一个衰减的
    /// 正弦，插上约晃两个来回，拔掉一个来回；时间到或还没开始都是 0。
    /// 正值是左高右低。
    public static func slosh(_ event: PlugEvent, elapsed: TimeInterval) -> Double {
        let duration = sloshDuration(event)
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return 0 }
        let p = elapsed / duration
        let cycles = event == .plugged ? 2.0 : 1.0
        // 指数衰减再乘一个收尾窗口，保证结束那一刻正好是 0，不会“啪”地跳平。
        let envelope = exp(-3 * p) * (1 - p)
        let peak = event == .plugged ? plugTilt : unplugTilt
        return peak * envelope * sin(2 * .pi * cycles * p)
    }

    /// 倾斜落到水面某一点上的高度（占区域高度的比例）：`x` 是 0...1 的
    /// 横向位置，中间不动，两端反向。
    public static func tiltLift(x: Double, slosh: Double) -> Double {
        let x = x.isFinite ? min(max(x, 0), 1) : 0.5
        return slosh * (1 - 2 * x)
    }

    /// 晃荡期间颜色从旧到新过渡的进度（0...1，先快后慢）。插上前的红变成
    /// 充电的颜色，不是一下子跳过去。
    public static func colorBlend(_ event: PlugEvent, elapsed: TimeInterval) -> Double {
        let duration = sloshDuration(event)
        guard elapsed.isFinite else { return 1 }
        guard elapsed > 0 else { return 0 }
        guard elapsed < duration else { return 1 }
        let p = elapsed / duration
        return 1 - pow(1 - p, 2.4)
    }

    // MARK: 水珠

    /// 插上电源时溅起的一颗水珠。`x` 是相对水面的横向位置（0...1），
    /// `height` 是离水面多高（占水上方空间的比例，0 在水面），`radius`
    /// 是半径占区域短边的比例，`opacity` 0...1。
    public struct Droplet: Equatable, Sendable {
        public var x: Double
        public var height: Double
        public var radius: Double
        public var opacity: Double
    }

    /// 水珠飞多久：起跳、到顶、落回水面。比晃荡短，落回时水面还在晃。
    public static let dropletFlight: TimeInterval = 0.75
    /// 溅起几颗。
    public static let dropletCount = 4

    /// `elapsed` 秒时还在空中的水珠（只在插上电源时有，拔掉不溅）。
    /// 每颗起跳时刻错开一点，抛物线飞起再落回；`origin` 是从水面哪里溅起
    /// （0...1），水珠散在它两边。
    public static func droplets(_ event: PlugEvent, elapsed: TimeInterval, origin: Double = 0.5,
                                count: Int = dropletCount) -> [Droplet] {
        guard event == .plugged, elapsed.isFinite, elapsed >= 0, count > 0 else { return [] }
        let origin = origin.isFinite ? min(max(origin, 0.1), 0.9) : 0.5
        var result: [Droplet] = []
        for index in 0..<min(count, 5) {
            let seed = Double(index)
            let delay = 0.04 * seed
            let flight = dropletFlight * (0.8 + 0.08 * seed)
            let t = elapsed - delay
            guard t >= 0, t < flight else { continue }
            let p = t / flight
            // 4p(1-p)：0 起跳、0.5 到顶、1 落回水面。
            let apex = 0.55 + 0.35 * (seed * 0.618_034).truncatingRemainder(dividingBy: 1)
            let height = apex * 4 * p * (1 - p)
            let side = index.isMultiple(of: 2) ? -1.0 : 1.0
            let spread = 0.05 + 0.04 * seed
            let x = min(max(origin + side * spread * p, 0), 1)
            let radius = 0.045 + 0.015 * (seed.truncatingRemainder(dividingBy: 2))
            // 起跳时淡入一点，快落回时淡出，落进水里就没了。
            let opacity = min(1, p / 0.12) * (p > 0.85 ? (1 - p) / 0.15 : 1)
            result.append(Droplet(x: x, height: height, radius: radius, opacity: opacity))
        }
        return result
    }

    // MARK: 低电量圆滴

    /// 低电量阈值：20% 及以下（按卡片上印的整数百分比算）。
    public static let lowPercent = 20

    /// 要不要画低电量的圆滴：连着、没在充电、20% 及以下。充电时不报警，
    /// 和电池格的颜色规则一样。
    public static func isLow(level: Double, charging: Bool, present: Bool) -> Bool {
        guard present, !charging, level.isFinite else { return false }
        return BatteryColorMap.percent(level) <= lowPercent
    }

    /// 圆滴呼吸一轮多久。
    public static let blobPeriod: TimeInterval = 3.2

    /// 圆滴在 `t` 秒时的大小倍数：0.82...1 慢慢一胀一缩。静止（减少动态
    /// 效果、看不见）时传 nil，固定在中间。
    public static func blobScale(t: TimeInterval?) -> Double {
        guard let t, t.isFinite else { return 0.91 }
        return 0.91 + 0.09 * sin(2 * .pi * t / blobPeriod)
    }

    /// 圆滴的半径，占水所在区域短边的比例。
    public static let blobRadius = 0.26

    // MARK: 颜色

    /// 水的颜色随电量走的几个点：20% 及以下红，30% 橙，50% 黄，65% 及以上
    /// 绿。红、橙和电池格的低电量色（#FF453A、#FF9F0A）一致，绿是
    /// `MetricColor.batteryPresent`（#34C759），黄是系统黄 #FFD60A。
    public static let red = BatteryRGB(1.0, 0x45 / 255.0, 0x3A / 255.0)
    public static let orange = BatteryRGB(1.0, 0x9F / 255.0, 0x0A / 255.0)
    public static let yellow = BatteryRGB(1.0, 0xD6 / 255.0, 0x0A / 255.0)
    public static let green = BatteryRGB(0x34 / 255.0, 0xC7 / 255.0, 0x59 / 255.0)

    public static let stops: [(level: Double, color: BatteryRGB)] = [
        (0.20, red), (0.30, orange), (0.50, yellow), (0.65, green),
    ]

    /// 电量对应的水色，相邻两点之间直线插值，所以电量一点点变，颜色也
    /// 一点点变。按卡片上印的整数百分比算，和数字同步。
    public static func gradientColor(level: Double) -> BatteryRGB {
        let value = Double(BatteryColorMap.percent(level.isFinite ? level : 0)) / 100
        guard let first = stops.first, let last = stops.last else { return green }
        if value <= first.level { return first.color }
        if value >= last.level { return last.color }
        for (a, b) in zip(stops, stops.dropFirst()) where value <= b.level {
            return a.color.mixed(with: b.color, (value - a.level) / (b.level - a.level))
        }
        return last.color
    }

    /// 横向/竖向电池格里水的颜色。现有的优先级不变：低电量模式是黄色
    /// （`BatteryColorMap.lowPowerYellow`，和系统一样），充电中是平时的电池绿
    /// （充电不报警），其余按电量渐变。
    public static func cellWaterColor(level: Double, charging: Bool, lowPower: Bool) -> BatteryRGB {
        if lowPower { return BatteryColorMap.lowPowerYellow }
        if charging { return green }
        return gradientColor(level: level)
    }

    /// 圆形液态仪表的水色：低电量模式照旧黄色，其余按电量渐变（圆形仪表
    /// 原来充电时也按电量上色，这里不改）。
    public static func gaugeWaterColor(level: Double, lowPower: Bool) -> BatteryRGB {
        lowPower ? BatteryColorMap.lowPowerYellow : gradientColor(level: level)
    }

    // MARK: 帧率

    /// 液态电池这一刻的帧率，nil 是一张静止的图：看不见或减少动态效果时
    /// 不动；晃荡、溅水珠时 30 帧；平时（含低电量圆滴的慢呼吸）10 帧。
    public static func framesPerSecond(visible: Bool, reduceMotion: Bool, sloshing: Bool) -> Double? {
        guard visible, !reduceMotion else { return nil }
        return sloshing ? BatteryMotion.maxFPS : BatteryMotion.idleFPS
    }

    /// 最近一次插拔离现在多久，还在晃的话返回事件和已过秒数，否则 nil。
    public static func activeSlosh(pluggedAt: Date?, unpluggedAt: Date?, now: Date)
        -> (event: PlugEvent, elapsed: TimeInterval)? {
        var latest: (PlugEvent, Date)?
        if let pluggedAt { latest = (.plugged, pluggedAt) }
        if let unpluggedAt, unpluggedAt > (latest?.1 ?? .distantPast) { latest = (.unplugged, unpluggedAt) }
        guard let latest else { return nil }
        let (event, at) = latest
        let elapsed = now.timeIntervalSince(at)
        guard elapsed >= 0, elapsed < sloshDuration(event) else { return nil }
        return (event, elapsed)
    }
}
