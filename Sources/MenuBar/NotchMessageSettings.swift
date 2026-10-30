import AppKit
import SwiftUI

/// 设置 ▸ 通用 ▸「消息灵动岛」（码头 Pro，默认关）。
///
/// 没解锁时开关旁边是 Pro 胶囊，打开开关只弹付费墙、不改配置；关掉不拦。解锁前已经
/// 打开的照旧存着，只是不观察横幅、不弹卡片，解锁或试用后自动恢复（同窗口预览）。
/// 打开后列出状态自查（辅助功能、通知中心、最近一次读到横幅、发一条测试通知）、启用
/// 哪几个 App、位置（自动让位 / 刘海下方 / 刘海旁小胶囊）、几秒后收起和「卡片弹出后关掉
/// 系统横幅」（默认关），底下写清楚它是
/// 怎么拿到消息的、什么时候拿不到。
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
                NotchMessageStatusRows()
                NotchMessageProbeRow()

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

                Toggle(isOn: $settings.closeSystemBanner) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("卡片弹出后关掉系统横幅"))
                        Text(tr("消息卡展开后，替你关掉屏幕右上角对应的那条系统横幅，只在横幅自己带「关闭」时才关。关掉后这条通知可能也不会留在通知中心里，「打开」只能打开 App，不能直接定位到那个聊天。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text(tr("消息灵动岛"))
        } footer: {
            Text(tr("码头通过「\(NotchMessageDiagnosis.permissionName(osMajor: NotchMessageStatus.osMajor))」权限读取系统通知横幅（不是通知权限），只读，不拦截、不修改系统通知。系统横幅和消息卡会同时出现：把这些 App 的通知样式改成「无」可以去掉重复，但横幅不出现时码头也收不到；专注模式、勿扰、全屏演示或屏幕共享时横幅不出现，同样收不到。全屏 App 和演示时不弹卡片。信息的回复用自动化（AppleScript）发送，第一次发送时 macOS 会问是否允许码头控制「信息」。"))
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

/// 状态自查：辅助功能、通知中心、最近一次读到横幅，各一行，前面一个小圆点（绿正常、
/// 橙要处理、灰在等），要处理的下面写怎么办。每秒刷新：在系统设置里给了权限，这里
/// 跟着变。判断和文案在 Core 的 `NotchMessageDiagnosis`。
private struct NotchMessageStatusRows: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = NotchMessageStatus.shared.snapshot()
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("状态"))
                ForEach(NotchMessageDiagnosis.lines(snapshot, now: context.date), id: \.title) { line in
                    NotchDiagnosisLineView(line: line)
                }
                if !snapshot.trusted {
                    Button(tr("去授权")) { AppWindows.requestAccess() }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 「发一条测试通知」和它的结果。
private struct NotchMessageProbeRow: View {
    @State private var copied = false

    var body: some View {
        let status = NotchMessageStatus.shared
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Button(tr("发一条测试通知")) { NotchMessageController.shared.sendTestNotification() }
                    .disabled(status.probe.token != nil)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("测试"))
                    Text(tr("码头自己发一条通知，读到了就弹出消息卡。码头的通知要允许，样式选「横幅」。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let line = status.probe.line(status.snapshot()) {
                NotchDiagnosisLineView(line: line)
            }
            HStack(spacing: 8) {
                Button(copied ? tr("已复制") : tr("复制诊断信息")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(status.diagnosticText(), forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                Text(tr("弹不出来时复制发给开发者：只有版本、权限和通知中心的结构，不含消息内容。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 一行状态：圆点、名字、结果，下面一句怎么办。颜色只在圆点上，字用主色和次要色，
/// 浅色、深色和液态玻璃底上都看得清。
private struct NotchDiagnosisLineView: View {
    var line: NotchMessageDiagnosis.Line

    private var dot: Color {
        switch line.level {
        case .ok: .green
        case .warning: .orange
        case .idle: .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(line.title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Text(line.value)
                    .font(.system(size: 13, weight: line.level == .warning ? .semibold : .regular))
                    .foregroundStyle(line.level == .warning ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let hint = line.hint {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
