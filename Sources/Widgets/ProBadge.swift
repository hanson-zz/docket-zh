import SwiftUI

/// 码头 Pro 的固定标识：一个小熊猫橙的小胶囊“Pro”，不发光。
///
/// 添加小组件面板的卡片、设置里的小组件管理和样式/外观选择、快速开关的
/// 工具列表、AI 刘海和充电上限都用这一个，哪里是 Pro 由 `ProFeatures` 决定。
///
/// 默认字 13pt，和设置页、面板里的 13pt 文字一样大；放进 26 到 28pt 高的
/// 胶囊钮或很挤的小格子时用 `compact`，保留原来的 9pt，免得撑满或喧宾夺主。
struct ProBadge: View {
    var compact = false

    /// 角标字号和胶囊内边距，小组件库的「新」角标也用这一套。
    static func fontSize(compact: Bool) -> CGFloat { compact ? 9 : 13 }
    static func horizontalPadding(compact: Bool) -> CGFloat { compact ? 5 : 7 }
    static func verticalPadding(compact: Bool) -> CGFloat { compact ? 1.5 : 2 }

    var body: some View {
        Text(ProFeatures.badgeTitle)
            .font(.system(size: Self.fontSize(compact: compact), weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Self.horizontalPadding(compact: compact))
            .padding(.vertical, Self.verticalPadding(compact: compact))
            .background(Capsule().fill(Color(hex: ShelfColor.redPanda.hex)))
            .fixedSize()
            .help(ProFeatures.help)
            .accessibilityLabel(ProFeatures.label)
    }
}

/// 「新」标识：近期新增的小组件。和 Pro 一样高、一样的字号和内边距，但不是实心：
/// 淡淡一层强调色底加强调色字，两个并排时 Pro 仍是最醒目的那个，也没有发光。
struct NewBadge: View {
    var compact = false

    @Environment(\.colorScheme) private var scheme

    /// 字色：浅色下压深（`panelReadable`），深色下往白里提三成，深灰卡片上也看得清。
    private var ink: Color {
        scheme == .dark ? Color.accentColor.mix(with: .white, by: 0.3) : Color.accentColor.panelReadable
    }

    var body: some View {
        Text("新")
            .font(.system(size: ProBadge.fontSize(compact: compact), weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, ProBadge.horizontalPadding(compact: compact))
            .padding(.vertical, ProBadge.verticalPadding(compact: compact))
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
            .fixedSize()
            .help("近期新增的小组件")
            .accessibilityLabel("新")
    }
}

/// Pro 和「新」角标放在一起：Pro 在前，间距 4。
///
/// 全仓库的角标都按同一套规则摆（以前小组件库卡片的角标压在预览右上角、
/// 再用 `.offset` 往外顶出卡片边，和预览的小卡片挤在一起）：
///
/// - 列表、设置、面板标题这类「一行字」：角标跟在名字后面（`BadgedTitle`），名字
///   单行、优先占宽，角标 `fixedSize` 不缩，不再 `.offset` 出行。
/// - 卡片、格子：角标放在卡片自己预留的顶边一行（`BadgeStrip`），靠右、在卡片
///   边框和内边距以内，不压预览、不和名字抢一行；没有角标的卡片这一行空着，
///   所以同一排卡片的预览和名字照样对齐。
/// - 胶囊钮、很挤的小格子用 `compact`（9pt，见 `ProBadge`）。
struct FeatureBadges: View {
    var pro: Bool
    var new: Bool
    var compact = false

    var body: some View {
        if pro || new {
            HStack(spacing: 4) {
                if pro { ProBadge(compact: compact) }
                if new { NewBadge(compact: compact) }
            }
            .fixedSize()
        }
    }
}

/// 卡片顶边的角标行（见 `FeatureBadges` 的规则）：固定高度，没角标时空着。
struct BadgeStrip: View {
    var pro: Bool
    var new: Bool
    var compact = false

    /// 一个角标的高度：字号的行高加上下内边距。
    static func height(compact: Bool) -> CGFloat { compact ? 14 : 20 }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            FeatureBadges(pro: pro, new: new, compact: compact)
        }
        .frame(height: Self.height(compact: compact))
    }
}

/// 名字后面跟角标的一行：名字单行、宽度不够时截名字，角标不缩不出行。
struct BadgedTitle: View {
    var title: String
    var pro: Bool
    var new: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .lineLimit(1)
                .layoutPriority(1)
            FeatureBadges(pro: pro, new: new)
        }
    }
}

/// 一段文字后面跟一个 Pro 标识（是 Pro 时）。
struct ProLabel: View {
    var title: String
    var isPro: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .layoutPriority(1)
            if isPro { ProBadge() }
        }
    }
}
