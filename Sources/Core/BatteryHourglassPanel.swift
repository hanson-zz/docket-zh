import Foundation

extension BatteryHourglass {
    /// 面板用不用沙漏这一套（头部大沙漏、按小时的沙柱、沙色玻璃小格、沙色充电上限）：
    /// 卡片是电池格（`layout` 为 gauge，Pro）、已解锁（或是预览），而且领头那台设备的
    /// 外观画沙漏（经典、液态；小熊猫外观里非 Mac 的设备界面先换成液态再传进来）。
    /// 其他样式（电量、仅图标）和电池格的像素电池、能量粒子、小熊猫，面板照旧。
    public static func panelHeader(layout: String, look: String, unlocked: Bool) -> Bool {
        layout == ProFeatures.batteryGaugeLayout && unlocked && drawsHourglass(look: look)
    }
}

/// 电池格沙漏样式面板的纯计算：品牌沙色、今天按小时的沙柱、今天小结、健康小格。
/// 界面只管照着画（`BatteryDetail` 里沙漏那一套）。
public enum BatteryHourglassPanel {

    // MARK: 尺寸

    /// 头部沙漏高 104pt，和原来液态圆球的直径一样，占位不变。
    public static let heroHeight = 104.0
    /// 沙漏要画闪电角标，宽按 `BatteryHourglassCell` 的 0.76 个高留。
    public static var heroWidth: Double { (heroHeight * 0.76).rounded() }

    // MARK: 品牌沙色

    /// 深色玻璃上的沙色（暖金 #E9B65C）。
    public static let sandDark = BatteryRGB(0xE9 / 255.0, 0xB6 / 255.0, 0x5C / 255.0)

    /// 面板的品牌沙色（沙柱、圆环、图标、开关、滑块）。深色是暖金；浅色玻璃上
    /// 暖金只有约 1.7 : 1，压到图形 3 : 1（`PanelContrast.graphic`）。
    public static func sand(dark: Bool) -> BatteryRGB {
        dark ? sandDark : readableOnLight(sandDark)
    }

    /// 浅色玻璃上图形够 3 : 1 的颜色，本来够的原样。
    public static func readableOnLight(_ rgb: BatteryRGB) -> BatteryRGB {
        let code = PanelContrast.graphic(ColorCode(red: rgb.red, green: rgb.green, blue: rgb.blue))
        return BatteryRGB(code.red, code.green, code.blue)
    }

    /// 大沙漏的沙色：颜色规则和卡片一样（`BatteryHourglass.sandColor`），浅色外观下
    /// 压到 3 : 1，免得浅绿、浅黄的沙在近白玻璃上发虚。深色原样。
    public static func heroSand(level: Double, charging: Bool, lowPower: Bool, present: Bool,
                                theme: ColorCode?, dark: Bool) -> BatteryRGB {
        let rgb = BatteryHourglass.sandColor(level: level, charging: charging, lowPower: lowPower,
                                             present: present, theme: theme)
        return dark ? rgb : readableOnLight(rgb)
    }

    /// 充电上限里 Pro 胶囊：浅沙色底（上 #F6D28C 下 #E8B258）配深棕字 #3A2508，
    /// 浅色深色都一样，对比度 7 以上。
    public static let proFillTop = ColorCode(hex: "#F6D28C")!
    public static let proFillBottom = ColorCode(hex: "#E8B258")!
    public static let proInk = ColorCode(hex: "#3A2508")!

    // MARK: 今天的沙柱

    /// 今天一个小时一根沙柱。
    public struct HourColumn: Equatable, Sendable {
        /// 0...23。
        public var hour: Int
        /// 这个小时最后一次记下的电量，没记到是 nil（Mac 睡着、还没到）。
        public var percent: Int?
        /// 这个小时里充过电。
        public var charging: Bool
        /// 柱子画报警红：最后一次记录 20% 及以下、没在充电（和卡片同一条线）。
        public var warns: Bool
        /// 现在所在的这个小时，描一道边。
        public var isCurrent: Bool
        /// 还没到的小时，只画一粒小点。
        public var isFuture: Bool

        public init(hour: Int, percent: Int?, charging: Bool, warns: Bool, isCurrent: Bool, isFuture: Bool) {
            self.hour = hour
            self.percent = percent
            self.charging = charging
            self.warns = warns
            self.isCurrent = isCurrent
            self.isFuture = isFuture
        }
    }

    /// 样本落在 `dayStart` 起的第几个小时，0...23，当天以外是 nil。夏令时那天
    /// 按经过的时长算，最多 24 根，多出来的一小时并进最后一根。
    static func hourIndex(of date: Date, dayStart: Date) -> Int? {
        let elapsed = date.timeIntervalSince(dayStart)
        guard elapsed >= 0, elapsed < 25 * 3600 else { return nil }
        return min(23, Int(elapsed / 3600))
    }

    /// 24 根沙柱。`samples` 是今天的样本（`BatteryHistory.samples`），先后顺序
    /// 不限；`now` 在今天以外时没有「现在」，也没有「还没到」。
    public static func hourColumns(samples: [BatteryHistory.Sample], dayStart: Date, now: Date) -> [HourColumn] {
        var last: [Int: BatteryHistory.Sample] = [:]
        var charged = Set<Int>()
        for sample in samples {
            guard let hour = hourIndex(of: sample.date, dayStart: dayStart) else { continue }
            if let previous = last[hour], previous.date > sample.date {} else { last[hour] = sample }
            if sample.charging { charged.insert(hour) }
        }
        let nowHour = hourIndex(of: now, dayStart: dayStart)
        return (0..<24).map { hour in
            let sample = last[hour]
            let percent = sample.map { min(100, max(0, $0.percent)) }
            let warns = sample.map {
                BatteryTheme.warns(level: Double($0.percent) / 100, charging: $0.charging, present: true)
            } ?? false
            return HourColumn(hour: hour, percent: percent, charging: charged.contains(hour), warns: warns,
                              isCurrent: hour == nowHour, isFuture: nowHour.map { hour > $0 } ?? false)
        }
    }

    /// 一根柱子画多高（占图表高的比例）。有电量至少 0.04，2% 也看得见一截。
    public static func columnHeight(_ column: HourColumn) -> Double {
        guard let percent = column.percent else { return 0 }
        return max(0.04, Double(percent) / 100)
    }

    /// 一根都没记到：画「刚开始记录」的空状态，不画坐标线。
    public static func isEmpty(_ columns: [HourColumn]) -> Bool {
        !columns.contains { $0.percent != nil }
    }

    // MARK: 今天小结

    public struct DaySummary: Equatable, Sendable {
        /// 今天最低到过多少，没样本是 nil。
        public var lowest: Int?
        /// 今天充了多久（按 5 分钟一格的样本数算）。
        public var chargingMinutes: Int

        public init(lowest: Int?, chargingMinutes: Int) {
            self.lowest = lowest
            self.chargingMinutes = chargingMinutes
        }
    }

    public static func daySummary(samples: [BatteryHistory.Sample]) -> DaySummary {
        let lowest = samples.map(\.percent).min().map { min(100, max(0, $0)) }
        let slots = samples.filter(\.charging).count
        return DaySummary(lowest: lowest, chargingMinutes: slots * Int(BatteryHistory.slotLength / 60))
    }

    /// 「今天」右边那一句：「最低 38% · 充电 1 小时 20 分钟」，没充过只写最低，
    /// 没样本是 nil（空状态自己有一句）。
    public static func summaryText(_ summary: DaySummary) -> String? {
        guard let lowest = summary.lowest else { return nil }
        var parts = [tr("最低 \(lowest)%")]
        if summary.chargingMinutes > 0 {
            parts.append(tr("充电 \(BatteryStatusText.duration(minutes: summary.chargingMinutes))"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 健康小格

    /// 最大容量低于 80% 时圆环换成橙色（macOS 也在 80% 以下提示建议维修）。
    public static let capacityWarnBelow = 80

    public static func capacityWarns(_ percent: Int) -> Bool { percent < capacityWarnBelow }

    /// 圆环画多满：最大容量的百分比，0...1。
    public static func capacityFraction(_ percent: Int) -> Double {
        min(1, max(0, Double(percent) / 100))
    }
}
