import Foundation

/// 喝水、Codex 用量和小熊猫的竹篮的可选“液态”外观，和专注计时、时间进度
/// 一样画 `LiquidWater`，这里只管选哪种外观和水位多高。默认都不变。
///
/// - 喝水：液态是一种 layout（`LiquidMotion.layout`），和角色、圆环并列，
///   整张卡片是一杯水，水位是今天的进度。
/// - Codex 用量：用 `look` 键，ring（默认）或 liquid；每个额度一个小圆杯，
///   水位跟着圆环原来显示的数（已用或剩余）。
/// - 小熊猫的竹篮：用 `look` 键，leaf（默认）或 liquid；整张卡片一篮竹叶色
///   的水，水位是今天三项的平均进度，满篮那天水面闪金光。
public enum LiquidLooks {
    public static let key = "look"

    public enum CodexLook: String, CaseIterable, Sendable {
        case ring, liquid

        public var title: String {
            switch self {
            case .ring: tr("圆环")
            case .liquid: tr("液态")
            }
        }
    }

    public enum BasketLook: String, CaseIterable, Sendable {
        case leaf, liquid

        public var title: String {
            switch self {
            case .leaf: tr("竹叶")
            case .liquid: tr("液态")
            }
        }
    }

    public static func codexLook(_ config: WidgetConfig) -> CodexLook {
        CodexLook(rawValue: config.string(key, default: CodexLook.ring.rawValue)) ?? .ring
    }

    public static func basketLook(_ config: WidgetConfig) -> BasketLook {
        BasketLook(rawValue: config.string(key, default: BasketLook.leaf.rawValue)) ?? .leaf
    }

    /// 喝水的液态 layout（没存 `layout` 的老卡片是角色，见 `WaterLayout`）。
    public static func waterIsLiquid(_ config: WidgetConfig) -> Bool {
        WaterLayout.stored(config) == .liquid
    }

    /// 喝水液态的水体更浓：前浪上沿 62%、底部 46%、后浪 22%（别的液态是
    /// 30%、14%、12%），整张卡片一眼看得出是一杯水；白字另加一圈淡黑描边。
    public static let waterDensity = LiquidDensity(top: 0.62, bottom: 0.46, back: 0.22)
    /// 其他液态外观原来的浓度。
    public static let standardDensity = LiquidDensity(top: 0.30, bottom: 0.14, back: 0.12)

    /// 喝水液态点 + 时水珠从哪里溅起（水面横向 0...1）：横排靠右，在 + 旁边；
    /// 竖排在正中。
    public static func waterSplashOrigin(vertical: Bool) -> Double { vertical ? 0.5 : 0.82 }

    /// 液态卡片（喝水、时间进度、小熊猫竹篮）上浮在水上的字离卡片左右边的
    /// 最小距离。水铺满整张卡片到边，字至少留 12pt，不会贴着水边。
    public static let liquidTextInset: Double = 12

    /// 喝水液态的字和 + 按钮离卡片左右边的距离。水铺满整张卡片（抵消了
    /// `WidgetSurface` 的 10pt 内边距），字自己再留 12pt，不会贴着水边。
    public static let waterTextInset: Double = liquidTextInset

    /// 喝水液态横排的副标题：没达标是「毫升 · 60%」，刚好达标「今天达标啦」，
    /// 超过目标「今天达标啦 · 144%」（四舍五入，到 101% 才写）。主数字照旧
    /// 「2300 / 1600」。
    public static func waterCaption(total: Int, goal: Int, ounces: Bool) -> String {
        guard goal > 0, total >= goal else {
            return "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: total, goal: goal))%"
        }
        let over = Int((Double(total) / Double(goal) * 100).rounded())
        return over > 100 ? tr("今天达标啦 · \(over)%") : tr("今天达标啦")
    }

    /// 喝水的水位：今天喝的除以目标，超过目标也只到满。
    public static func waterLevel(total: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return LiquidMotion.level(Double(total) / Double(goal))
    }

    /// Codex 一个额度杯子的水位：显示剩余时是剩下的比例，否则是用掉的。
    public static func codexLevel(usedFraction: Double, showsRemaining: Bool) -> Double {
        let used = LiquidMotion.level(usedFraction)
        return showsRemaining ? 1 - used : used
    }

    /// 竹篮的水位：参加的几项进度的平均，一项都不参加时是空的。
    public static func basketLevel(_ items: [PerfectDayProgress]) -> Double {
        let taking = items.filter { $0.mark.takesPart }
        guard !taking.isEmpty else { return 0 }
        let sum = taking.reduce(0) { $0 + LiquidMotion.level($1.fraction) }
        return LiquidMotion.level(sum / Double(taking.count))
    }

    /// 整张卡片的水在这一刻的高度（卡片高度的比例）。没满时最高到 94%，
    /// 波浪不会顶出上沿；满了略高过上沿，整张卡盖住，不在顶上留一条底色的黑边。
    public static func cardFill(_ level: Double) -> Double {
        let level = LiquidMotion.level(level)
        return level >= 1 ? 1.04 : level * 0.94
    }
}

/// 整张卡片那杯水的浓度：前浪从水面到底边的不透明度渐变，和后浪的不透明度。
public struct LiquidDensity: Equatable, Sendable {
    public var top: Double
    public var bottom: Double
    public var back: Double

    public init(top: Double, bottom: Double, back: Double) {
        self.top = top
        self.bottom = bottom
        self.back = back
    }
}
