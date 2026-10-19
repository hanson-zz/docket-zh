import Foundation

/// 便签纸上的墨色：按纸色算对比度挑深墨还是浅墨，不够 WCAG 正文的 4.5:1 时
/// 再把墨往纯黑或纯白里推，直到够了为止。
///
/// 便签的手写字笔画细，卡片上只有 15pt 左右，中间色的纸（雾霾蓝、牛皮纸、
/// 珊瑚红、湖水青这类）最容易糊。原来按“是不是两种深色纸”二选一，新加的纸色
/// 一旦落在中间就没人管；这里每种纸都算一遍，测试保证列表里每一种都够。
public enum PaperInk {
    /// 平时的深墨和浅墨，和原来的一样。
    public static let darkInk = "#1C1C1E"
    public static let lightInk = "#F4F4F6"

    /// WCAG AA 正文的最低对比度。
    public static let minimumContrast = 4.5

    /// 纸色和墨色的对比度，1 到 21。认不出的颜色当作 1。
    public static func contrast(paper: String, ink: String) -> Double {
        guard let a = ColorCode(hex: paper), let b = ColorCode(hex: ink) else { return 1 }
        return WidgetTint.contrastRatio(a, b)
    }

    /// 这张纸上用的墨：深墨、浅墨里对比度高的那个；还不够 `minimum` 时，
    /// 朝同一个方向（深墨往黑、浅墨往白）一点点加深，最多到纯黑或纯白。
    public static func ink(on paper: String, minimum: Double = minimumContrast) -> String {
        guard let fill = ColorCode(hex: paper) else { return darkInk }
        let dark = ColorCode(hex: darkInk)!
        let light = ColorCode(hex: lightInk)!
        let darkRatio = WidgetTint.contrastRatio(fill, dark)
        let lightRatio = WidgetTint.contrastRatio(fill, light)
        let useLight = lightRatio > darkRatio
        let base = useLight ? light : dark
        if max(darkRatio, lightRatio) >= minimum { return base.hex }
        let target = useLight ? ColorCode(red: 1, green: 1, blue: 1) : ColorCode(red: 0, green: 0, blue: 0)
        var amount = 0.0
        var result = base
        while WidgetTint.contrastRatio(fill, result) < minimum, amount < 1 {
            amount = min(1, amount + 0.1)
            result = base.mixed(with: target, by: amount)
        }
        return result.hex
    }

    /// 墨是浅色的（纸是深色的）。胶带和卷角的高光跟着它调。
    public static func inkIsLight(on paper: String) -> Bool {
        guard let ink = ColorCode(hex: ink(on: paper)) else { return false }
        return WidgetTint.luminance(ink) > 0.5
    }
}
