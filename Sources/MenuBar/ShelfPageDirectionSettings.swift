import SwiftUI

/// 设置 ▸ 布局 ▸ 切换布局里的「翻页方向」：左右（免费）或上下（码头 Pro）。
/// 没解锁时选上下弹付费墙，不改设置；已经存着上下但授权过期时显示左右，解锁后恢复。
struct ShelfPageDirectionRow: View {
    @Binding var direction: ShelfPageDirection

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool {
        ProLicenseGate.canUse(.verticalPaging, unlocked: licenseUnlocked || supporter)
    }

    var body: some View {
        Picker(selection: Binding(
            get: { unlocked ? direction : .horizontal },
            set: { choice in
                if choice == .vertical, !unlocked {
                    PaywallWindow.shared.show()
                    return
                }
                direction = choice
            })) {
            ForEach(ShelfPageDirection.allCases, id: \.self) { choice in
                Text(choice.label).tag(choice)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tr("翻页方向"))
                    if !unlocked {
                        Button { PaywallWindow.shared.show() } label: { ProBadge() }
                            .buttonStyle(.plain)
                            .help(ProFeatures.help)
                    }
                }
                Text(tr("选上下时，在底部或顶部的扩展栏上两指上滑到下一个布局、下滑回上一个；指针停在小组件上照旧滑开面板，左右滑用来滚动放不下的扩展栏。左右两边的扩展栏照旧左右翻。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pickerStyle(.segmented)
    }
}
