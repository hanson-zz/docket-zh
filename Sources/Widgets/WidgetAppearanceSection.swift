import SwiftUI

/// 详情面板底部的“外观”：一行入口（主题色小圆点和当前的颜色、背景），
/// 点开就地显示和设置 ▸ 小组件同一块“颜色与背景”（`WidgetTintPicker`），
/// 改了立刻写回这张卡片，扩展栏上的卡片跟着变。自定义取色和渐变背景照旧
/// 是码头 Pro，没解锁时带小锁，点了弹付费墙。
///
/// 每次打开面板都是收起的（`WidgetDetailChrome` 按这次打开给它新的身份）；
/// 展开后内容变高，面板照常按新高度重新摆。
struct WidgetAppearanceSection: View {
    var instance: WidgetInstance
    var context: WidgetContext
    /// 面板内容区的宽度，算色块一排放几个。
    var width: CGFloat

    @State private var open = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("外观", context: "appearance"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                        .overlay { Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5) }
                    // 窄面板里先让摘要截断，不把整行撑宽。
                    Text(WidgetAppearance.summary(instance.config, kind: instance.kind))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(open ? tr("收起外观") : tr("改这张卡片的主题色和背景"))
            .accessibilityLabel(tr("外观", context: "appearance"))
            .accessibilityValue(WidgetAppearance.summary(instance.config, kind: instance.kind))
            .accessibilityHint(open ? tr("收起外观") : tr("改这张卡片的主题色和背景"))

            if open {
                WidgetTintPicker(instance: instance,
                                 columns: WidgetAppearance.swatchColumns(
                                     available: Double(width), cell: Double(WidgetTintPicker.swatchCell),
                                     spacing: Double(WidgetTintPicker.swatchSpacing)),
                                 showsPreview: false) { change in
                    guard !context.isPreview else { return }
                    // 写之前取一次存着的最新一份，免得盖掉面板打开后别处的改动。
                    let latest = WidgetWriter.current(instance.id) ?? instance
                    WidgetWriter.write(latest, change)
                }
            }
        }
    }

    /// 入口上的小圆点：卡片这一刻的主色（没解锁时自定义颜色退回默认，和卡片一样）。
    private var dotColor: Color {
        WidgetTintStyle(kind: instance.kind, config: instance.config).main(dark: scheme == .dark)
    }
}
