import SwiftUI

/// 详情面板底部的“外观”：一行入口（主题色小圆点和当前的颜色、背景），
/// 点开就地显示和设置 ▸ 小组件同一块“颜色与背景”（`WidgetTintPicker`），
/// 正在播放在它上面多一行「面板样式」（标准 / 黑胶模式，`MusicPanelStyle`），
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
    /// 嵌在面板自己的「外观」页里（11-24 起从 ··· 菜单进）：不画入口行，内容直接展开。
    var embedded = false

    @State private var open = false
    /// 没解锁时点了黑胶模式：显示一行 Pro 提示（付费墙同时弹出）。
    @State private var vinylAsked = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false

    private var unlocked: Bool { licenseUnlocked || supporterUnlocked || context.isPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !embedded {
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
            }

            if open || embedded {
                // 精简卡片只开精简面板，不给黑胶选项。
                if !embedded, WidgetAppearance.offersPanelStyle(instance.kind), MusicCard.size(instance.config) == .full {
                    panelStyleRow
                }
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

    /// 正在播放的面板样式：标准 / 黑胶模式，选了立刻写回，面板当场换样子。黑胶模式是
    /// Pro（旁边是 Pro 标识）：没解锁时点它弹付费墙、不改配置，下面一行提示；已经存着
    /// 黑胶模式（试用到期）的照旧存着，面板画标准样式，同样显示这行提示。
    private var panelStyleRow: some View {
        let stored = MusicPanelStyle.of(instance.config)
        let shown = ProLicenseGate.musicPanelStyle(config: instance.config, unlocked: unlocked)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tr("面板样式"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Picker(tr("面板样式"), selection: Binding(
                    get: { shown },
                    set: { style in
                        guard !context.isPreview else { return }
                        guard ProLicenseGate.canChoose(.music, [MusicPanelStyle.key: .string(style.rawValue)],
                                                       unlocked: unlocked) else {
                            vinylAsked = true
                            PaywallWindow.shared.show()
                            return
                        }
                        vinylAsked = false
                        let latest = WidgetWriter.current(instance.id) ?? instance
                        WidgetWriter.write(latest) { $0 = MusicPanelStyle.choosing(style, in: $0) }
                    })) {
                    ForEach(MusicPanelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(.system(size: 13))
            }
            // 黑胶 11-24 起免费，isPro 恒为假，这行提示不会再出现。
            if !unlocked, vinylAsked || stored.isPro {
                HStack(spacing: 8) {
                    Text(tr("黑胶模式是 Pro 功能，现在显示标准样式"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(tr("解锁")) { PaywallWindow.shared.show() }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// 入口上的小圆点：卡片这一刻的主色（没解锁时自定义颜色退回默认，和卡片一样）。
    private var dotColor: Color {
        WidgetTintStyle(kind: instance.kind, config: instance.config).main(dark: scheme == .dark)
    }
}
