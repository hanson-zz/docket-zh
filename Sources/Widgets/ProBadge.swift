import SwiftUI

/// 码头 Pro 的固定标识：一个小熊猫橙的小胶囊“Pro”，不发光。
///
/// 添加小组件面板的卡片、设置里的小组件管理和样式/外观选择、快速开关的
/// 工具列表、AI 刘海和充电上限都用这一个，哪里是 Pro 由 `ProFeatures` 决定。
struct ProBadge: View {
    var body: some View {
        Text(ProFeatures.badgeTitle)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
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
