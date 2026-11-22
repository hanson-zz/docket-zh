import SwiftUI

/// 电池面板里的“充电上限”：开关、上限、缓冲，以及助手的状态和安装按钮。
///
/// 默认折叠成一行：「充电上限 · 80%」加状态胶囊（生效中、未生效、不支持、需安装助手、
/// 需更新助手，判定在 Core 的 `ChargeLimitEffect`）。没生效时下面多一行橙色说明。
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

    /// 默认折叠：只露出标题行（「充电上限 · 80%」）和状态胶囊，开关、滑块、助手按钮
    /// 和兼容性、诊断说明都收在展开里。
    @State private var expanded = false

    var body: some View {
        let config = service.config
        let state = service.state(now: now)
        let unlocked = self.unlocked
        // 开关是用户的意图，胶囊和说明看上限实际生效没有（判定在 Core）。
        let effect = ChargeLimitEffect.resolve(config: config, unlocked: unlocked, helper: state)
        VStack(alignment: .leading, spacing: 8) {
            header(config: config, effect: effect, unlocked: unlocked)
            // 不支持、未生效时，折叠着也写一行说明，不能只剩一个蓝色开关。
            if let notice = effect.notice {
                Text(notice)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(Self.warning.panelReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if expanded {
                controls(config: config, unlocked: unlocked)
                diagnostics(state: state, config: config, unlocked: unlocked)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded = true }
                } label: {
                    HStack(spacing: 3) {
                        Text("查看兼容性与诊断")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelSecondary)
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

    static let warning = Color(hex: "#FF9F0A")
    static let good = Color(hex: "#30D158")

    /// 标题行：折叠箭头、「充电上限 · 80%」、Pro 标识，右边状态胶囊。点整行展开或收起。
    private func header(config: ChargeLimitConfig, effect: ChargeLimitEffect, unlocked: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text(tr("充电上限 · \(config.limit)%"))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                if sand != nil {
                    BatterySand.ProCapsule()
                } else {
                    ProBadge()
                }
                Spacer(minLength: 6)
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .accessibilityHidden(true)
                }
                if let badge = effect.badge {
                    let color = badge.tone == .good ? Self.good : Self.warning
                    Text(badge.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color.panelReadable)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
                        .fixedSize()
                }
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("充电上限 · \(config.limit)%"))
        .accessibilityValue(effect.badge?.text ?? tr("已关闭"))
        .accessibilityHint(expanded ? tr("收起") : tr("展开"))
    }

    /// 展开后的设置：开关、上限、缓冲。开关是用户的意图，生效没有看上面的胶囊。
    @ViewBuilder
    private func controls(config: ChargeLimitConfig, unlocked: Bool) -> some View {
        HStack {
            Text("开启充电上限")
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
            Spacer()
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
                .accessibilityLabel("开启充电上限")
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
    }

    /// 兼容性与诊断：助手的详细说明、兼容性提示、最近的错误和助手按钮。
    @ViewBuilder
    private func diagnostics(state: ChargeLimitService.State, config: ChargeLimitConfig, unlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("兼容性与诊断")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelSecondary)
            Text(unlocked ? caption(state, config: config) : lockedCaption(config))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ChargeLimitEffect.compatibilityNote)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = service.status, status.isFresh(now: now) {
                // 助手自己报的：用哪个芯片接口、最近一次写状态的时间。
                Text(tr("控制接口：\(status.key ?? tr("未找到")) · 助手更新于 \(BatteryWords.updatedText(status.updated, now: now))"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelTertiary)
            }
            if let problem = service.problem {
                Text(problem)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(Self.warning.panelReadable)
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
                button(tr("复制诊断")) { service.copyDiagnostics(now: now) }
                if service.working { ProgressView().controlSize(.small) }
                Spacer()
                if !unlocked {
                    button(tr("解锁码头 Pro…")) { PaywallWindow.shared.show() }
                }
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
