import SwiftUI

/// 设置 ▸ 通用 ▸「消息灵动岛与刘海小岛」里的「刘海小岛」（码头 Pro，默认关）。
///
/// 锁定方式同消息灵动岛：没解锁时开关旁边是 Pro 胶囊，打开开关只弹付费墙、不改配置；
/// 关掉不拦。解锁前已经打开的照旧存着，只是不显示，解锁或试用后自动恢复。打开后可以
/// 勾选显示哪几种活动（下载、计时器、会议、收音机、充电）。
struct NotchIslandSettingsRows: View {
    @Binding var settings: NotchIslandSettings

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool {
        ProLicenseGate.canUse(.notchIsland, unlocked: licenseUnlocked || supporter)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { settings.enabled && unlocked },
            set: { on in
                if on, !unlocked {
                    PaywallWindow.shared.show()
                    return
                }
                settings.enabled = on
            })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tr("刘海小岛"))
                    if !unlocked {
                        Button { PaywallWindow.shared.show() } label: { ProBadge() }
                            .buttonStyle(.plain)
                            .help(ProFeatures.help)
                    }
                }
                Text(tr("下载、专注计时和倒计时卡片、快开始的会议、收音机和插上电源时，从刘海两侧长出黑色小岛，和刘海连成一体；两件事同时进行时第二件变成右边的小圆岛。指针停在小岛上时展开成卡片，可以暂停、换台、调音量。没有刘海的屏幕在顶部居中显示同样的形状。全屏 App、演示模式和消息卡弹出时不显示，音量、亮度提示出现时先收起。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if settings.enabled && unlocked {
            ForEach(NotchIslandKind.settingsOrder, id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { settings.isOn(kind) },
                    set: { settings.set(kind, $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if settings.kinds.isEmpty {
                Text(tr("一种活动都没勾选时小岛不会出现。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
