import Foundation

/// 小表盘三根指针的角度和秒针的尺寸。时钟「标准」样式卡片左侧的小表盘、
/// 世界时钟卡片和时钟面板城市行共用一个表盘（`AnalogClockFace`），
/// 只有时钟标准卡片画秒针，见 `ClockReadout.secondHand`。
///
/// 角度从 12 点起顺时针，单位是度，0..<360。
public enum ClockHands {
    /// 时、分、秒三根指针的角度。时针跟着分钟走，分针跟着整分走（和原来
    /// 一样不随秒爬），秒针每秒跳一格。
    public static func angles(_ date: Date, zone: TimeZone) -> (hour: Double, minute: Double, second: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let second = Double(parts.second ?? 0)
        let minute = Double(parts.minute ?? 0)
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60
        return (hour / 12 * 360, minute / 60 * 360, second / 60 * 360)
    }

    /// 秒针长度占表盘直径的比例：比分针（0.37）稍长。
    public static let secondLength = 0.40
    /// 秒针粗细（pt），比分针（1.6）细得多。
    public static let secondWidth = 0.9
    /// 中心小圆点直径占表盘直径的比例，不小于 `minimumDot`。
    public static let dotRatio = 0.12
    public static let minimumDot = 2.2

    public static func dotDiameter(_ diameter: Double) -> Double {
        max(minimumDot, diameter * dotRatio)
    }

    /// 秒针颜色：颜色面板里选了颜色用选的，没选（默认）用时钟自己的主题色
    /// （琥珀 #FFB340），都调到在当前外观的卡片上看得清（`WidgetTint.readable`）。
    /// 跟随系统强调色时返回 nil，由界面用系统强调色画。
    public static func secondTint(_ config: WidgetConfig, dark: Bool, unlocked: Bool) -> ColorCode? {
        let choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        guard let palette = WidgetTint.palette(choice, kind: .clock) else { return nil }
        return WidgetTint.readable(palette.main, dark: dark)
    }
}
