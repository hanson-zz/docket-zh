import SwiftUI

/// 电池面板里的“充电上限”：开关、上限、缓冲，以及助手的状态和安装按钮。
///
/// 充电上限是码头 Pro 的功能：没解锁时开关和安装、更新助手的按钮弹付费墙，
/// 上限和缓冲变灰；已打开的不再生效，电池照常充电，解锁后恢复。卸载助手和
/// 复制诊断一直能用。
struct ChargeLimitSection: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var now: Date
    /// 电池格沙漏样式面板的品牌沙色（`BatterySand.color`）：有值时开关、滑块用沙色，
    /// Pro 标识换成沙色胶囊；不传是 nil，和原来一样。
    var sand: Color? = nil

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var service: ChargeLimitService { ChargeLimitService.shared }

    private var unlocked: Bool {
        ProLicenseGate.canUse(.chargeLimit, unlocked: licenseUnlocked || supporter)
    }

    var body: some View {
        let config = service.config
        let state = service.state(now: now)
        let unlocked = self.unlocked
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("充电上限")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelSecondary)
                if sand != nil {
                    BatterySand.ProCapsule()
                } else {
                    ProBadge()
                }
                Spacer()
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .accessibilityHidden(true)
                }
                // 没解锁时开关显示为关（上限此时不生效），拨它弹付费墙。
                Toggle("", isOn: Binding(get: { unlocked && config.enabled },
                                         set: { on in
                                             guard unlocked else { PaywallWindow.shared.show(); return }
                                             service.update { $0.enabled = on }
                                         }))
                    .toggleStyle(.switch)
                    .tint(sand ?? panelTint.control)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("充电上限")
                    .help(unlocked ? "" : ProFeatures.help)
            }
            // 上限和缓冲随时能调，先存进设置文件；助手装好跑起来后照这个执行。
            Group {
                HStack(spacing: 8) {
                    Text("\(config.limit)%")
                        .font(WidgetStyle.value(17))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .frame(width: 52, alignment: .leading)
                    Slider(value: Binding(get: { Double(config.limit) },
                                          set: { v in service.update { $0.limit = Int(v) } }),
                           in: 50...100, step: 5)
                        .controlSize(.mini)
                        .tint(sand ?? panelTint.accent(or: .panelPrimary))
                }
                HStack(spacing: 6) {
                    Text("低于")
                    Menu("\(config.limit - config.buffer)%") {
                        ForEach(ChargeLimitConfig.buffers, id: \.self) { b in
                            Button(tr("\(config.limit - b)%（缓冲 \(b)%）")) { service.update { $0.buffer = b } }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Text("再恢复充电")
                    Spacer()
                }
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
            }
            .disabled(!unlocked)
            .opacity(unlocked ? 1 : 0.5)
            Text(unlocked ? caption(state, config: config) : lockedCaption(config))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = service.problem {
                Text(problem)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                switch state {
                case .notInstalled:
                    button(tr("安装助手"), locked: !unlocked) { install(unlocked) }
                case .needsUpdate:
                    button(tr("更新助手"), locked: !unlocked) { install(unlocked) }
                case .starting, .unsupported, .running:
                    EmptyView()
                }
                if state != .notInstalled {
                    button(tr("卸载助手")) { service.uninstall() }
                }
                if state != .running {
                    button(tr("复制诊断")) { service.copyDiagnostics(now: now) }
                }
                if service.working { ProgressView().controlSize(.small) }
                Spacer()
                if !unlocked {
                    button(tr("解锁码头 Pro…")) { PaywallWindow.shared.show() }
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
        .onChange(of: unlocked) { _, value in service.applyLicense(unlocked: value) }
        .task {
            // 面板开着时每 5 秒看一眼助手的状态。
            while !Task.isCancelled {
                service.applyLicense(unlocked: unlocked)
                service.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func caption(_ state: ChargeLimitService.State, config: ChargeLimitConfig) -> String {
        switch state {
        case .notInstalled:
            return tr("上限可以先调好。真正暂停充电要先安装一个后台助手（输入一次管理员密码），装好后马上按 \(config.limit)% 执行。")
        case .starting:
            return tr("助手正在启动，上限暂未生效。超过 10 秒还停在这里，试试卸载后重新安装。")
        case .unsupported:
            return tr("助手在这台 Mac 上找不到能控制充电的芯片接口（CHTE、CH0B/CH0C 都读不到），暂时没法限制充电。Intel Mac 也不支持。")
        case .needsUpdate:
            return tr("码头更新了，助手也要更新一下，更新前上限暂不生效。")
        case .running:
            guard config.enabled, config.isActive else {
                return tr("已关闭，电池照常充满。macOS 自带的“优化电池充电”仍然有效。")
            }
            if let status = service.status, status.inhibited {
                return tr("已到 \(config.limit)%，暂停充电中，电源直接供电。")
            }
            return tr("充到 \(config.limit)% 自动暂停，掉到 \(config.limit - config.buffer)% 再继续充。")
        }
    }

    /// 没解锁时安装、更新助手只弹付费墙。
    private func install(_ unlocked: Bool) {
        guard unlocked else { PaywallWindow.shared.show(); return }
        service.install()
    }

    /// 没解锁时的说明。
    private func lockedCaption(_ config: ChargeLimitConfig) -> String {
        if config.enabled {
            return tr("充电上限是码头 Pro 功能。现在没有解锁，上限已暂停生效，电池照常充满；解锁后自动恢复 \(config.limit)% 上限。")
        }
        return tr("充电上限是码头 Pro 功能，解锁后可以让电池充到设定的电量就暂停。")
    }

    private func button(_ title: String, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(WidgetStyle.label(13))
        .foregroundStyle(.panelPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.panelRaised).panelLift())
        .disabled(service.working)
    }
}
