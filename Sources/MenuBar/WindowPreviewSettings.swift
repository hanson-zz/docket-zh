import SwiftUI

/// 设置 ▸ 扩展栏 ▸「悬停显示窗口预览」（码头 Pro，默认关）。
///
/// 没解锁时开关旁边是 Pro 胶囊，打开开关只弹付费墙、不改配置；关掉不拦。
/// 解锁前已经打开的开关照旧存着，只是扩展栏上不弹，解锁或试用后自动恢复。
struct WindowPreviewSettingRow: View {
    @Binding var enabled: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool {
        ProLicenseGate.canUse(.windowPreview, unlocked: licenseUnlocked || supporter)
    }

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
                    Text(tr("悬停显示窗口预览"))
                    if !unlocked {
                        Button { PaywallWindow.shared.show() } label: { ProBadge() }
                            .buttonStyle(.plain)
                            .help(ProFeatures.help)
                    }
                }
                Text(tr("鼠标停在正在运行的 App 上约 0.5 秒，弹出它的窗口缩略图，点一下切过去。缩略图要屏幕录制权限，没给时只列窗口名。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
