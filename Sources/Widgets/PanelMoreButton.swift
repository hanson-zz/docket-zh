import SwiftUI

/// 面板右上角的 ··· （11-24 起替代面板底部的「外观」栏）。系统原生菜单，点空白就关；
/// 各面板可以在前面放自己的中频项，最后固定一项「外观…」，点了在面板里进外观页
/// （由 `WidgetDetailChrome` 接管，左上角返回）。小组件库预览里不画。
struct PanelMoreButton<Items: View>: View {
    @ViewBuilder var items: () -> Items
    @Environment(\.openPanelAppearance) private var openAppearance

    var body: some View {
        if let openAppearance {
            Menu {
                items()
                Divider()
                Button(tr("外观…")) { openAppearance() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.panelFill))
                    .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("更多"))
            .accessibilityLabel(tr("更多"))
        }
    }
}

extension PanelMoreButton where Items == EmptyView {
    init() { self.items = { EmptyView() } }
}

private struct OpenPanelAppearanceKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    /// 有外观可调的面板里，``PanelMoreButton`` 用它打开外观页；没有就不画 ··· 。
    var openPanelAppearance: (@MainActor @Sendable () -> Void)? {
        get { self[OpenPanelAppearanceKey.self] }
        set { self[OpenPanelAppearanceKey.self] = newValue }
    }
}

/// 面板里的外观页：返回加颜色与背景（和 设置 ▸ 小组件 同一块）。只换显示的内容，
/// 不碰小组件的状态（播放、计时照旧）。
struct PanelAppearancePage: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var width: CGFloat
    var back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("外观", context: "appearance"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.panelPrimary)
                .frame(height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("返回"))
            WidgetAppearanceSection(instance: WidgetWriter.current(instance.id) ?? instance,
                                    context: context, width: width, embedded: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
