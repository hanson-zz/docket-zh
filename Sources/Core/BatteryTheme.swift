import Foundation

/// 电池小组件跟随「外观 ▸ 颜色」的规则。
///
/// 默认颜色时一切照旧：液态的水和外圈按电量从红经黄到绿，低电量模式黄，
/// 充电绿；经典的电量那一截平时不上色，低于 20% 橙、10% 红。
///
/// 选了颜色（预设、自定义或跟随系统强调色）时，原来那些表示电量的红黄绿
/// 主色（水、外圈、像素格、粒子环、小熊猫怀里的小电池、经典的电量那一截
/// 和圆环）都换成所选颜色，按 `WidgetTint.readable` 调到在卡片上看得清。
/// 只有一种情况保留红色：电量 20% 及以下且没在充电，这是警告，选了什么
/// 颜色都要看得出来，液态的低电量圆滴也照旧鼓出来。
public enum BatteryTheme {
    /// 这张电池卡片要用的主题色：没选颜色（或这种卡片不能选颜色）是 nil，
    /// 各处照旧用电量的颜色。跟随系统强调色时用 `systemAccent`（界面读到的
    /// 系统强调色），读不到也是 nil。
    public static func color(_ choice: WidgetTint.Choice, systemAccent: ColorCode?, dark: Bool) -> ColorCode? {
        guard WidgetTint.offersColor(.battery), choice.isChosen else { return nil }
        guard let main = WidgetTint.palette(choice, kind: .battery)?.main ?? systemAccent else { return nil }
        return WidgetTint.readable(main, dark: dark)
    }

    /// 选了颜色以后仍要报警吗：连着、没在充电、印出来的百分比 20% 及以下。
    /// 和液态低电量圆滴同一条线（`BatteryLiquidFX.isLow`）。
    public static func warns(level: Double, charging: Bool, present: Bool) -> Bool {
        BatteryLiquidFX.isLow(level: level, charging: charging, present: present)
    }

    /// 报警用的红，和液态水的红、电池格的 10% 红一致（#FF453A）。
    public static let warningRed = BatteryLiquidFX.red

    static func rgb(_ code: ColorCode) -> BatteryRGB {
        BatteryRGB(code.red, code.green, code.blue)
    }

    /// 横向、竖向电池格里水的颜色。`theme` 为 nil 时就是原来的
    /// `BatteryLiquidFX.cellWaterColor`（低电量模式黄、充电绿、其余按电量渐变）。
    public static func cellWaterColor(level: Double, charging: Bool, lowPower: Bool,
                                      present: Bool = true, theme: ColorCode?) -> BatteryRGB {
        guard let theme else {
            return BatteryLiquidFX.cellWaterColor(level: level, charging: charging, lowPower: lowPower)
        }
        return warns(level: level, charging: charging, present: present) ? warningRed : rgb(theme)
    }

    /// 圆形仪表（液态、像素电池、能量粒子、小熊猫）的颜色。`theme` 为 nil 时
    /// 和原来一样：按电量分档，液态的水和外圈再换成随电量平滑过渡的渐变色，
    /// 低电量模式黄。选了颜色时主色和高光换成主题色，低电量仍是红色、仍会
    /// 慢慢呼吸。
    public static func gaugeTint(level: Double, charging: Bool, lowPower: Bool, present: Bool,
                                 liquid: Bool, theme: ColorCode?) -> BatteryColorMap.Tint {
        var tint = BatteryColorMap.tint(level: level, lowPower: lowPower, charging: charging)
        guard let theme else {
            if liquid {
                tint.color = BatteryLiquidFX.gaugeWaterColor(level: level, lowPower: lowPower)
                tint.highlight = tint.color.mixed(with: .white, 0.35)
            }
            return tint
        }
        if warns(level: level, charging: charging, present: present) {
            tint.band = .red
            tint.color = warningRed
            tint.pulses = true
        } else {
            tint.color = rgb(theme)
            tint.pulses = false
        }
        tint.highlight = tint.color.mixed(with: .white, 0.35)
        return tint
    }

    /// 经典外观电量那一截（实心）的颜色：只有平时（`.normal`）才换成主题色，
    /// 低电量的橙、红和没连上的虚框照旧。nil 表示照旧用原来的颜色。
    public static func classicFill(tone: ShapeMeters.CellTone, theme: ColorCode?) -> ColorCode? {
        guard let theme, tone == .normal else { return nil }
        return theme
    }

    /// 经典外观的百分比圆环、图标样式的设备图标和小闪电（原来是固定的电池绿）：
    /// 选了颜色时换成主题色，低电量报警时是红色。nil 表示照旧用电池绿。
    public static func accent(level: Double, charging: Bool, present: Bool, theme: ColorCode?) -> BatteryRGB? {
        guard let theme else { return nil }
        return warns(level: level, charging: charging, present: present) ? warningRed : rgb(theme)
    }
}
