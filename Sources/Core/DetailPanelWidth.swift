import Foundation

/// 详情面板里内容能用多宽。
///
/// 面板外框按小组件给定的宽度（`WidgetDetail.width`）画，内容区左右各留
/// `padding`，尾巴在左右两侧（竖排扩展栏）时再让出尾巴的深度。内容里任何
/// 一块的自然宽度比这还大，整列内容就会被撑宽：外框靠左对齐，多出来的
/// 部分全落在右边，被面板裁掉，看起来右边距没了、右边的字被切
/// （beta.27 正在播放面板：封面后面的光晕画成 1.64 倍封面宽，约 335pt，
/// 比 320 面板的内容区 288pt 宽出 47pt）。装饰性的光晕、阴影只能画在
/// 背景里，不能参与排版。
public enum DetailPanelWidth {
    /// 面板内容区每一侧的内边距。
    public static let padding: CGFloat = 16

    /// 内容区宽度：面板宽减两侧内边距，尾巴在左右两侧时再减尾巴深度。
    public static func content(panel: CGFloat, tailDepth: CGFloat, tailOnSide: Bool) -> CGFloat {
        max(0, panel - padding * 2 - (tailOnSide ? tailDepth : 0))
    }

    /// 内容实际宽度比内容区宽出多少（不超出时是 0）。小于 `tolerance` 的
    /// 舍入误差不算。
    public static func overflow(content measured: CGFloat, available: CGFloat,
                                tolerance: CGFloat = 0.5) -> CGFloat {
        let extra = measured - available
        return extra > tolerance ? extra : 0
    }
}
