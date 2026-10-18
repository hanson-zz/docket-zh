import Foundation

/// 三个“圆环撞脸”拆开后的纯逻辑：圆只留给圆环仪表，电池画成电池形状，
/// 系统活动的“竖条”是一格一格亮起来的竖条。放在 Core 里是为了能测。
///
/// 存的值都不变：电池的“电池格”仍是 `layout` 为 gauge（Pro 照旧），
/// 系统活动的“竖条”仍是 `layout` 为 rings，所以已经放好的卡片读出来
/// 直接换成新画法，配置不用改。
public enum ShapeMeters {

    // MARK: 系统活动 · 竖条

    /// 竖条一共几格。
    public static let segments = 8

    /// 亮几格：占用按格数四舍五入；只要不是 0 就至少亮一格，免得 3% 的
    /// CPU 看起来像没在读。
    public static func litSegments(_ value: Double, segments: Int = segments) -> Int {
        guard segments > 0, value.isFinite else { return 0 }
        let clamped = min(max(value, 0), 1)
        guard clamped > 0.005 else { return 0 }
        return min(segments, max(1, Int((clamped * Double(segments)).rounded())))
    }

    /// 系统活动的 `layout` 值和添加面板里的名字。rings 是存的值，名字改成“竖条”。
    public static let systemSegmentsLayout = "rings"

    // MARK: 电池 · 电池格

    /// 电池格怎么画：只有一台设备时是一块横向电池，旁边写百分比；
    /// 多台设备时每台一块竖电池。
    public enum CellAxis: Equatable, Sendable {
        case horizontal
        case vertical
    }

    public static func cellAxis(deviceCount: Int) -> CellAxis {
        deviceCount <= 1 ? .horizontal : .vertical
    }

    /// 电池格用哪种外观画电池形状：经典是实心的一截，液态是一截水；像素电池、
    /// 能量粒子、小熊猫抱电池照旧画它们自己的。认不出的值按经典。
    public static func drawsCell(look raw: String) -> Bool {
        switch BatteryLook(rawValue: raw) ?? .classic {
        case .classic, .liquid: true
        case .pixel, .particles, .panda: false
        }
    }

    /// 电池里填多少：没连上的设备是空的，绝不编一个电量出来。
    public static func cellFill(level: Double, present: Bool) -> Double {
        guard present, level.isFinite else { return 0 }
        return min(max(level, 0), 1)
    }

    /// 电池格的颜色：平时不上色，低于 20% 变橙，10% 变红；充电中或没连上
    /// 不报警。
    public enum CellTone: Equatable, Sendable {
        case normal
        case low
        case critical
        case absent
    }

    public static func cellTone(level: Double, charging: Bool, present: Bool) -> CellTone {
        guard present else { return .absent }
        guard !charging else { return .normal }
        if level <= 0.10 { return .critical }
        if level <= 0.20 { return .low }
        return .normal
    }

    // MARK: 合并成开关的样式

    /// 系统活动的“数字”和“数字 + 图表”、网络活动的“仅数字”和“带图表”
    /// 合并成一个样式加“显示图表”开关。旧卡片本来就把有没有图表存在
    /// `chart` 里，这里把一份旧配置读成新样式（只看 `layout`）加开关的值，
    /// 外观和原来一样。认不出的旧值按“不显示图表”。
    public static let chartKey = "chart"

    public static func chartOption(_ config: WidgetConfig) -> Bool {
        config.bool(chartKey, default: false)
    }
}
