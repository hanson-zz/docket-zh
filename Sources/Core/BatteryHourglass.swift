import Foundation

/// 电池格（`layout` 为 gauge）经典外观的沙漏，和仅图标样式的「图标 + 电量环 +
/// 大号数字」，两处的纯计算都在这里，界面只管照着画。
///
/// 沙漏：下泡的沙面高度按电量线性对应（满电到颈口下方 8%），比按面积换算
/// 更好一眼读出；充电时上泡装着「还没充进来」的那部分，中间细沙往下流，
/// 不充电时上泡是空的、沙面平整。颜色默认是红黄绿（20% 及以下未充电红、
/// 低电量模式黄、其余绿），选了「外观 ▸ 颜色」时沙子整体换成主题色，报警
/// 时只把数字和状态字变红，沙子不变。
///
/// 存的值不变：仍是 `layout` 为 gauge、外观为经典，旧卡片读出来直接换成
/// 沙漏，配置不用改。液态、像素电池、能量粒子、小熊猫照旧。
public enum BatteryHourglass {

    // MARK: 沙量

    /// 满电时沙面占下泡高度的比例（到颈口下方 8%）。
    public static let fullSurface = 0.92
    /// 电量很低时也留一层薄沙，免得 2% 看起来像没连上。
    public static let minimumLevel = 0.05

    /// 下泡沙面高度，占下泡高度（颈口到底）的比例，0...0.92。没连上是 0，
    /// 绝不编一个电量出来。
    public static func sandHeight(level: Double, present: Bool) -> Double {
        guard present, level.isFinite else { return 0 }
        let clamped = min(max(level, 0), 1)
        return fullSurface * max(clamped, minimumLevel)
    }

    /// 上泡里待充的沙，占上泡高度的比例：只在充电时有，约等于还没充进来的
    /// 那部分（至少留一点，充到 95% 也看得出在流）；不充电或没连上是 0。
    public static func topSand(level: Double, charging: Bool, present: Bool) -> Double {
        guard present, charging, level.isFinite else { return 0 }
        let clamped = min(max(level, 0), 1)
        return max(0.12, (1 - clamped) * 0.85)
    }

    /// 沙堆峰顶隆起多高（占沙漏总高）：充电时沙往下落，峰顶鼓一点；平时
    /// 几乎是平的。
    public static func moundHeight(charging: Bool) -> Double {
        charging ? 0.05 : 0.018
    }

    // MARK: 动画

    /// 流沙的帧率：20 帧，够看出颗粒在落，又不像 60 帧那样费电。
    public static let framesPerSecond: Double = 20

    /// 这一刻沙漏的帧率，nil 是一张静止的图：只有连着、正在充电、卡片看得见
    /// 而且没开「减少动态效果」时才动。
    public static func framesPerSecond(charging: Bool, present: Bool, visible: Bool,
                                       reduceMotion: Bool) -> Double? {
        guard present, charging, visible, !reduceMotion else { return nil }
        return framesPerSecond
    }

    // MARK: 颜色

    /// 沙子的颜色。默认（`theme` 为 nil）：20% 及以下未充电红，低电量模式黄，
    /// 其余（含充电）绿。选了颜色时沙子一律是主题色，报警也不变，红色只
    /// 留给数字和状态字（见 `numberWarns`）。
    public static func sandColor(level: Double, charging: Bool, lowPower: Bool, present: Bool,
                                 theme: ColorCode?) -> BatteryRGB {
        if let theme { return BatteryTheme.rgb(theme) }
        if BatteryTheme.warns(level: level, charging: charging, present: present) {
            return BatteryTheme.warningRed
        }
        if lowPower { return BatteryColorMap.lowPowerYellow }
        return BatteryLiquidFX.green
    }

    /// 数字（和沙漏旁的状态字）要不要变红：连着、没在充电、20% 及以下。
    /// 默认颜色和选了颜色时都一样，低电量模式不算。
    public static func numberWarns(level: Double, charging: Bool, present: Bool) -> Bool {
        BatteryTheme.warns(level: level, charging: charging, present: present)
    }

    // MARK: 仅图标 · 大号数字

    /// 数字怎么放：带不带 % 符号，字号缩到多少（1 是原字号）。
    public struct ReadingFit: Equatable, Sendable {
        public var showsSign: Bool
        public var scale: Double

        public init(showsSign: Bool, scale: Double) {
            self.showsSign = showsSign
            self.scale = scale
        }
    }

    /// 估算宽度用的比例（粗体等宽数字约 0.62 个字号宽，% 按 0.6 倍字号画，
    /// 充电时前面一道闪电约 0.6 个字号）。只用来决定先去 % 还是缩小，界面
    /// 另外留了 `minimumScaleFactor` 兜底。
    public static let digitWidth = 0.62
    public static let signScale = 0.6
    public static let signWidth = 0.86
    public static let boltWidth = 0.6

    /// 字最小 13pt。
    public static let minimumPointSize = 13.0

    /// 数字 `label`（不带 %）按 `fontSize` 画要多宽。
    public static func readingWidth(label: String, fontSize: Double, sign: Bool, charging: Bool) -> Double {
        let digits = Double(label.count) * digitWidth * fontSize
        let percent = sign ? signWidth * signScale * fontSize : 0
        let bolt = charging ? boltWidth * fontSize : 0
        return digits + percent + bolt
    }

    /// 宽度 `available` 里放不放得下：先整个放；放不下先去掉 % 符号；还放不下
    /// 再按比例缩小，最小缩到 13pt。没连上（“-”）不带 %。
    public static func readingFit(available: Double, label: String, fontSize: Double, charging: Bool,
                                  present: Bool = true) -> ReadingFit {
        guard fontSize > 0, available.isFinite, available > 0 else {
            return ReadingFit(showsSign: false, scale: minimumScale(fontSize))
        }
        let sign = present
        if readingWidth(label: label, fontSize: fontSize, sign: sign, charging: charging) <= available {
            return ReadingFit(showsSign: sign, scale: 1)
        }
        let bare = readingWidth(label: label, fontSize: fontSize, sign: false, charging: charging)
        if bare <= available { return ReadingFit(showsSign: false, scale: 1) }
        return ReadingFit(showsSign: false, scale: max(minimumScale(fontSize), available / bare))
    }

    static func minimumScale(_ fontSize: Double) -> Double {
        guard fontSize > minimumPointSize else { return 1 }
        return minimumPointSize / fontSize
    }

    /// 仅图标样式每台设备占多宽（电量环 + 数字），`WidgetCatalog` 按它给卡片
    /// 定宽：30 的环、5 的间距、约 49 的数字。
    public static let iconSlotWidth = 84
    public static let iconSlotGap = 8

    /// 仅图标卡片的宽：每台设备一格，加卡片左右的边距。
    public static func iconCardWidth(slots: Int, inset: Double = 20) -> Double {
        let count = max(1, slots)
        return Double(count * iconSlotWidth + (count - 1) * iconSlotGap) + inset
    }
}
