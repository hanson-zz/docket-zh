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

/// 一段文字后面跟一个 Pro 标识（是 Pro 时）。
struct ProLabel: View {
    var title: String
    var isPro: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            if isPro { ProBadge() }
        }
    }
}
