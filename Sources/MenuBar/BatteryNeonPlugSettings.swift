import SwiftUI

/// 「插电时霓虹动画」开关（码头 Pro，默认开）：设置 ▸ 通用的「电池」一节和电池小组件
/// 的设置里各放一个，是同一个开关。
///
/// 没解锁时开关显示关着，旁边是 Pro 胶囊，打开只弹付费墙、不改配置；解锁后按存的
/// 值（没存过就是开）。真正播不播看 `BatteryNeonPlugController`。
struct BatteryNeonPlugToggle: View {
    @AppStorage(BatteryNeon.plugAnimationKey) private var enabled = true
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool { licenseUnlocked || supporter }

    var body: some View {
        Toggle(isOn: Binding(
            get: { enabled && unlocked },
            set: { on in
                if on, !unlocked {
                    PaywallWindow.shared.show()
                    return
                }
                enabled = on
            })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("插电时霓虹动画")
                    if !unlocked {
                        Button { PaywallWindow.shared.show() } label: { ProBadge() }
                            .buttonStyle(.plain)
                            .help(ProFeatures.help)
                    }
                }
                Text("接上电源时，一滴光从刘海落下，把屏幕上方的霓虹电量数字从下往上灌亮，约 2.5 秒；之后刘海旁留一个电量小胶囊，几秒后淡出。全屏、屏幕共享、演示模式时不播，30 秒内反复插拔只播一次。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
