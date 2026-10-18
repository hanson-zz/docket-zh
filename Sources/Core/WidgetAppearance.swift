import Foundation

/// 卡片详情面板底部的“外观”入口：点开就地改这张卡片的主题色和背景，
/// 和设置 ▸ 小组件里的“颜色与背景”是同一套（`WidgetTint`），Pro 项照旧上锁。
/// 这里是它不碰界面的部分：哪些卡片有这个入口、入口上的一行摘要、色块
/// 一排放几个。
public enum WidgetAppearance {
    /// 有颜色或背景可选的卡片才有入口，和设置里列不列“颜色与背景”一致。
    public static func offered(_ kind: WidgetKind) -> Bool {
        WidgetTint.offersColor(kind) || WidgetTint.offersBackground(kind)
    }

    /// 这张卡片的颜色或背景调过（不是默认）。只算这种卡片能选的那一项：
    /// 不提供背景的卡片里留着的旧背景值不算。
    public static func isCustomized(_ config: WidgetConfig, kind: WidgetKind) -> Bool {
        let color = WidgetTint.offersColor(kind) && WidgetTint.choice(config) != .kindDefault
        let background = WidgetTint.offersBackground(kind) && WidgetTint.background(config) != .plain
        return color || background
    }

    /// 入口右边的一行摘要：选过的颜色和背景，用“ · ”连起来；都没调过是“默认”。
    public static func summary(_ config: WidgetConfig, kind: WidgetKind) -> String {
        var parts: [String] = []
        if WidgetTint.offersColor(kind) {
            switch WidgetTint.choice(config) {
            case .kindDefault: break
            case .system: parts.append(tr("跟随系统"))
            case .preset(let preset): parts.append(preset.title)
            case .custom: parts.append(tr("自定义颜色"))
            }
        }
        if WidgetTint.offersBackground(kind) {
            let background = WidgetTint.background(config)
            if background != .plain { parts.append(tr("\(background.title)背景")) }
        }
        return parts.isEmpty ? tr("默认") : parts.joined(separator: " · ")
    }

    /// 一排放几个色块：放得下几个放几个，至少 1 个，最多 `maximum` 个
    /// （设置页是 9 个一排，面板窄，按面板宽度少放几个）。
    public static func swatchColumns(available: Double, cell: Double, spacing: Double,
                                     maximum: Int = 9) -> Int {
        guard available.isFinite, cell > 0, maximum > 0 else { return 1 }
        let fit = Int(((available + spacing) / (cell + spacing)).rounded(.down))
        return min(maximum, max(1, fit))
    }
}
