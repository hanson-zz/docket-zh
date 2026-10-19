import Foundation

/// 电池单设备“电量”样式（原来叫“状态”）的纯逻辑。原来是设备图标外面一圈百分比圆环，
/// 和电池格、液态画成电池以后的样子对不上；现在经典和液态也画一块横向
/// 电池（电池形外轮廓、正极小凸起、按电量填满），百分比写在电池里，
/// 充电时数字前面一道闪电，低于 20% 变橙、10% 变红（和电池格一样，见
/// `ShapeMeters.cellTone`），旁边是状态和设备名。像素电池、能量粒子、
/// 小熊猫照旧画它们自己的。
///
/// 存的值不变：仍是 `layout` 为 status，外观仍读 `BatteryLook`，旧卡片
/// 读出来直接换成新画法，配置不用改。
public enum BatteryStatusCell {
    /// 电量样式用不用电池形状：和电池格同一条规则，经典和液态画电池。
    public static func drawsCell(look raw: String) -> Bool {
        ShapeMeters.drawsCell(look: raw)
    }

    /// 写在电池里的数字（不带 %）：没连上是“-”，绝不编一个电量出来。
    public static func label(level: Double, present: Bool) -> String {
        guard present, level.isFinite else { return "-" }
        return "\(Int((min(max(level, 0), 1) * 100).rounded()))"
    }

    /// 电池画多大：卡片约 58pt 高，扣掉上下边距后电池高 26 到 30、长是高的
    /// 2.1 倍，里面放得下“⚡100%”。
    public static func cellSize(cardHeight: Double) -> (width: Double, height: Double) {
        let usable = cardHeight.isFinite ? cardHeight : 58
        let height = min(30, max(26, (usable * 0.5).rounded()))
        return ((height * 2.1).rounded(), height)
    }

    /// 数字压在电量那一截上用什么颜色：经典外观平时那一截是不上色的前景色
    /// （深色外观白、浅色外观黑），数字要反过来；橙、红和液态的水是彩色，
    /// 数字一律白。没连上时电池是空的，不用反色。
    /// 经典外观选了颜色（`themed`）时，平时那一截是主题色，数字按主题色的
    /// 亮度用深色或白色（`onTheme`）。
    public enum Ink: Equatable, Sendable {
        case inverted
        case white
        case onTheme
        case none
    }

    public static func inkOnFill(tone: ShapeMeters.CellTone, liquid: Bool, themed: Bool = false) -> Ink {
        switch tone {
        case .absent: .none
        case .low, .critical: .white
        case .normal: liquid ? .white : (themed ? .onTheme : .inverted)
        }
    }

    /// 横向电池各部分的尺寸，`BatteryCellShape` 和压在上面的数字共用，
    /// 数字的反色正好盖住电量那一截。
    public struct Geometry: Equatable, Sendable {
        /// 正极小凸起的长度。
        public var nub: Double
        /// 电池身子（不含凸起）的长度。
        public var bodyLong: Double
        public var stroke: Double
        /// 外框到电量那一截的距离。
        public var inset: Double
        public var radius: Double
        /// 电量那一截满格时的长和宽。
        public var innerLong: Double
        public var innerShort: Double

        /// 电量那一截现在的右边（从电池左边算起）。
        public func fillEnd(_ fill: Double) -> Double {
            let clamped = fill.isFinite ? min(max(fill, 0), 1) : 0
            return inset + innerLong * clamped
        }
    }

    /// `long` 是电池的长边，`short` 是短边。
    public static func geometry(long: Double, short: Double) -> Geometry {
        let nub = max(2, long * 0.07)
        let bodyLong = long - nub - 1
        let stroke = max(1.4, short * 0.08)
        let inset = stroke + max(1, short * 0.07)
        let radius = short * 0.26
        return Geometry(nub: nub, bodyLong: bodyLong, stroke: stroke, inset: inset, radius: radius,
                        innerLong: max(0, bodyLong - inset * 2), innerShort: max(0, short - inset * 2))
    }
}
