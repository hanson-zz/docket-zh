import SwiftUI

/// 设置 ▸ 通用 ▸「消息灵动岛」（码头 Pro，默认关）。
///
/// 没解锁时开关旁边是 Pro 胶囊，打开开关只弹付费墙、不改配置；关掉不拦。解锁前已经
/// 打开的照旧存着，只是不观察横幅、不弹卡片，解锁或试用后自动恢复（同窗口预览）。
/// 打开后列出辅助功能权限、启用哪几个 App、位置（自动让位 / 刘海下方 / 刘海旁小胶囊）
/// 和几秒后收起，底下写清楚它是怎么拿到消息的、什么时候拿不到。
struct NotchMessageSettingsSection: View {
    @Binding var settings: NotchMessageSettings

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool {
        ProLicenseGate.canUse(.notchMessage, unlocked: licenseUnlocked || supporter)
    }

    var body: some View {
        Section {
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
                        Text(tr("消息灵动岛"))
                        if !unlocked {
                            Button { PaywallWindow.shared.show() } label: { ProBadge() }
                                .buttonStyle(.plain)
                                .help(ProFeatures.help)
                        }
                    }
                    Text(tr("信息、WhatsApp、微信的通知到达时，在刘海下方展开消息卡：头像、发件人、两行预览。信息可以在刘海里直接回复，WhatsApp 和微信点一下跳到对应 App。几秒后收起成刘海两侧的未读数，指针停在卡片上时不收。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if settings.enabled && unlocked {
                AccessibilityRow()

                ForEach(NotchMessageApp.allCases, id: \.self) { app in
                    Toggle(app.title, isOn: Binding(
                        get: { settings.isOn(app) },
                        set: { settings.set(app, $0) }))
                }

                Picker(tr("位置"), selection: $settings.position) {
                    ForEach(NotchMessagePosition.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                Text(Self.positionHelp(settings.position))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(tr("自动收起"), selection: Binding(
                    get: { settings.dismissSeconds },
                    set: { settings.seconds = $0 })) {
                    ForEach(NotchMessageSettings.secondChoices, id: \.self) { seconds in
                        Text(tr("\(seconds) 秒后")).tag(seconds)
                    }
                }
            }
        } header: {
            Text(tr("消息灵动岛"))
        } footer: {
            Text(tr("码头通过辅助功能读取系统通知横幅，只读，不拦截、不修改系统通知。系统横幅和消息卡会同时出现：把这些 App 的通知样式改成「无」可以去掉重复，但横幅不出现时码头也收不到；专注模式、勿扰、全屏演示或屏幕共享时横幅不出现，同样收不到。全屏 App 和演示时不弹卡片。信息的回复用自动化（AppleScript）发送，第一次发送时 macOS 会问是否允许码头控制「信息」。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func positionHelp(_ position: NotchMessagePosition) -> String {
        switch position {
        case .auto:
            tr("拾掇等刘海 App 在刘海附近时，消息卡落在它们下面；它们的面板正展开时先排队，最多等 8 秒，之后改用刘海旁的小胶囊。只读取窗口属于哪个 App 和位置，不需要屏幕录制权限。")
        case .belowNotch:
            tr("消息卡总是接在刘海正下方，不管别的刘海 App。")
        case .capsule:
            tr("只在刘海右边显示一个小胶囊和未读数，完全不占刘海中间，点一下再展开消息卡。")
        }
    }
}

/// 辅助功能权限：给了写「已授权」，没给时一句说明加「去授权」。每两秒看一次，
/// 在系统设置里打开后这里跟着变。
private struct AccessibilityRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let trusted = AppWindows.isTrusted
            LabeledContent {
                if trusted {
                    Text(tr("已授权"))
                        .foregroundStyle(.secondary)
                } else {
                    Button(tr("去授权")) { AppWindows.requestAccess() }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("辅助功能权限"))
                    Text(tr("读系统通知横幅需要辅助功能权限，没给时不会弹出消息卡。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
