import Foundation

/// Codex 用量详情面板的侧重，跟着卡片样式走（`CodexCard`、`LiquidLooks`）。
///
/// - 小卡（状态 + 两个圆环）点开是「用量优先」：顶部两个大圆环，外观选了液态
///   时是两只大号液态杯；下面今日 / 本周统计，会话列表收成一行摘要，点开展开。
/// - 中卡（小熊猫、项目和正在做什么 + 两条进度条）点开是「会话优先」：小熊猫
///   和总状态、正在运行的会话在上，用量是两条粗进度条，统计在下。
///
/// 没存 layout 的老卡片按小卡读；液态外观只画在小卡上（设置里中卡不列这一项），
/// 中卡就算存着 look = liquid 也还是会话优先。
public enum CodexDetailEmphasis: String, CaseIterable, Sendable {
    /// 用量优先，大圆环。
    case usageRings
    /// 用量优先，大号液态杯。
    case usageLiquid
    /// 会话优先，粗进度条。
    case sessions

    public static func from(_ config: WidgetConfig) -> CodexDetailEmphasis {
        if CodexCard.isMedium(config) { return .sessions }
        return LiquidLooks.codexLook(config) == .liquid ? .usageLiquid : .usageRings
    }

    /// 用量在最上面（小卡的两种外观）。
    public var usageFirst: Bool { self != .sessions }

    /// 会话列表默认收成一行摘要（用量优先时）。
    public var foldsSessions: Bool { usageFirst }

    /// 头部画小熊猫（会话优先）；用量优先只画状态点，和小卡的状态行一致。
    public var showsPanda: Bool { self == .sessions }

    /// 用量优先时大圆环 / 大液态杯的直径。面板 340 宽、两列各一格玻璃，
    /// 直径 104 时中间 30pt 百分比和下面两行 13pt 字都放得下。
    public static let gaugeDiameter: Double = 104

    /// 会话优先时主额度进度条的粗细（中卡是 6，面板加粗到 12；分组的小额度 8）。
    public static let mainBarHeight: Double = 12
    public static let groupBarHeight: Double = 8

    /// 收起时那一行摘要：「2 个会话进行中」「3 个会话 · 1 个等你确认」
    /// 「2 个会话已完成」，没有会话时「现在没有进行中的会话」。
    public static func sessionSummary(_ states: [CodexActivity]) -> String {
        guard !states.isEmpty else { return tr("现在没有进行中的会话") }
        let waiting = states.filter { $0 == .waiting }.count
        let running = states.filter { $0 == .working || $0 == .waiting }.count
        if waiting > 0 { return tr("\(states.count) 个会话 · \(waiting) 个等你确认") }
        if running > 0 { return tr("\(running) 个会话进行中") }
        return tr("\(states.count) 个会话已完成")
    }

    /// 摘要那一行左边圆点的状态：有等你确认的就是橙色，其次工作中，再其次完成。
    public static func summaryState(_ states: [CodexActivity]) -> CodexActivity {
        for state in [CodexActivity.waiting, .working, .done] where states.contains(state) { return state }
        return .idle
    }
}
