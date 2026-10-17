import SwiftUI

/// 电池面板里的“充电上限”：开关、上限、缓冲，以及助手的状态和安装按钮。
struct ChargeLimitSection: View {
    var now: Date

    private var service: ChargeLimitService { ChargeLimitService.shared }

    var body: some View {
        let config = service.config
        let state = service.state(now: now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("充电上限")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.75))
                ProBadge()
                Spacer()
                Toggle("", isOn: Binding(get: { config.enabled },
                                         set: { on in service.update { $0.enabled = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("充电上限")
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
                        .tint(.white)
                }
                HStack(spacing: 6) {
                    Text("低于")
                    Menu("\(config.limit - config.buffer)%") {
                        ForEach(ChargeLimitConfig.buffers, id: \.self) { b in
                            Button("\(config.limit - b)%（缓冲 \(b)%）") { service.update { $0.buffer = b } }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Text("再恢复充电")
                    Spacer()
                }
                .font(WidgetStyle.caption(11))
                .foregroundStyle(.white.opacity(0.7))
            }
            Text(caption(state, config: config))
                .font(WidgetStyle.caption(11))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if let problem = service.problem {
                Text(problem)
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(Color(hex: "#FF9F0A"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                switch state {
                case .notInstalled:
                    button("安装助手") { service.install() }
                case .needsUpdate:
                    button("更新助手") { service.install() }
                case .starting, .unsupported, .running:
                    EmptyView()
                }
                if state != .notInstalled {
                    button("卸载助手") { service.uninstall() }
                }
                if state != .running {
                    button("复制诊断") { service.copyDiagnostics(now: now) }
                }
                if service.working { ProgressView().controlSize(.small) }
                Spacer()
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
        .task {
            // 面板开着时每 5 秒看一眼助手的状态。
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func caption(_ state: ChargeLimitService.State, config: ChargeLimitConfig) -> String {
        switch state {
        case .notInstalled:
            return "上限可以先调好。真正暂停充电要先安装一个后台助手（输入一次管理员密码），装好后马上按 \(config.limit)% 执行。"
        case .starting:
            return "助手正在启动，上限暂未生效。超过 10 秒还停在这里，试试卸载后重新安装。"
        case .unsupported:
            return "助手在这台 Mac 上找不到能控制充电的芯片接口（CHTE、CH0B/CH0C 都读不到），暂时没法限制充电。Intel Mac 也不支持。"
        case .needsUpdate:
            return "码头更新了，助手也要更新一下，更新前上限暂不生效。"
        case .running:
            guard config.enabled, config.isActive else {
                return "已关闭，电池照常充满。macOS 自带的“优化电池充电”仍然有效。"
            }
            if let status = service.status, status.inhibited {
                return "已到 \(config.limit)%，暂停充电中，电源直接供电。"
            }
            return "充到 \(config.limit)% 自动暂停，掉到 \(config.limit - config.buffer)% 再继续充。"
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(WidgetStyle.label(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.18)))
            .disabled(service.working)
    }
}
