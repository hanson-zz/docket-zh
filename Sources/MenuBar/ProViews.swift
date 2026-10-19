import AppKit
import SwiftUI

/// 小熊猫橙，码头 Pro 的强调色。
private let proAccent = Color(hex: ShelfColor.redPanda.hex)

/// 付费墙和设置页共用的 Pro 功能清单：哪些东西是 Pro 由 `ProFeatures` 决定。
private struct ProPerk: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String

    static var all: [ProPerk] {
        let kinds = ProFeatures.proKinds
            .compactMap { WidgetCatalog.entry($0)?.name }
            .sorted()
            .joined(separator: tr("、"))
        return [
            ProPerk(id: "kinds", symbol: "square.grid.2x2.fill", title: tr("Pro 小组件"), detail: kinds),
            ProPerk(id: "liquid", symbol: "drop.fill", title: tr("液态外观"),
                    detail: tr("所有小组件的液态外观，电池的液态电量也包括在内")),
            ProPerk(id: "faces", symbol: "clock.fill", title: tr("专属表盘和角色"),
                    detail: tr("时钟的霓虹、实景、液晶表盘和翻页的大号卡片；企鹅、水獭、章鱼三个角色（柴犬、橘猫在喝水里累计达标 3 天、7 天免费解锁）")),
            ProPerk(id: "looks", symbol: "battery.100percent.bolt", title: tr("Wi-Fi 和电池外观"),
                    detail: tr("数字、点状、细线 Wi-Fi；像素电池、能量粒子、小熊猫抱电池")),
            ProPerk(id: "colors", symbol: "paintpalette.fill", title: tr("专属配色和样式"),
                    detail: tr("小熊猫橙、樱花粉等底板配色；小组件自定义颜色和渐变背景；便签更多纸色；天气多城市、电池格、时间进度四格；习惯打卡第 4 个起和近七天报告")),
            ProPerk(id: "tools", symbol: "wand.and.stars", title: tr("Pro 工具"),
                    detail: tr("快速开关的截图识字、二维码、演示模式、只锁键盘、低电量模式；刘海里的 AI 对话；电池充电上限")),
        ]
    }
}

// MARK: - 付费墙

/// 码头 Pro 付费墙：功能清单、购买、输入激活码、开始 7 天试用。
struct ProPaywallView: View {
    var onClose: () -> Void
    @State private var license = ProLicenseManager.shared
    @AppStorage(Supporter.key) private var supporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(proAccent)
                Text("码头 Pro")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                ProBadge()
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭")
            }

            Text("码头的基础功能一直免费。Pro 解锁下面这些小组件、外观和工具，一次买断，不用订阅。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(ProPerk.all) { perk in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: perk.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(proAccent.opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(perk.title).fontWeight(.semibold)
                            Text(perk.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(proAccent.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            ProStatusLine(state: license.state, supporter: supporter)

            HStack(spacing: 10) {
                if license.canStartTrial && !supporter {
                    Button {
                        license.startTrial()
                    } label: {
                        Text(tr("开始 \(ProLicenseConfig.trialDays) 天免费试用"))
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(proAccent)
                }
                Button {
                    license.buy()
                } label: {
                    Text(tr("购买")).frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("首批特价 \(ProLicenseConfig.launchPrice)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(proAccent)
                    Text(tr("之后 \(ProLicenseConfig.price) · 正式版 \(ProLicenseConfig.fullPrice)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .controlSize(.large)

            if !license.isActivated {
                ProKeyField()
            }
        }
        .padding(24)
        .frame(width: 480, height: 700, alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                RadialGradient(colors: [proAccent.opacity(0.28), .clear],
                               center: .topLeading, startRadius: 10, endRadius: 360)
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: license.state) { _, state in
            // 激活成功就关掉；开始试用也关掉，用户回到刚才想加的东西。
            if state.isUnlocked { onClose() }
        }
    }
}

/// 一行状态：图标加一句话。
private struct ProStatusLine: View {
    var state: ProLicenseState
    var supporter: Bool

    var body: some View {
        let unlocked = ProLicenseGate.isUnlocked(state, supporter: supporter)
        HStack(spacing: 6) {
            Image(systemName: unlocked ? "checkmark.seal.fill" : "info.circle")
                .foregroundStyle(unlocked ? proAccent : Color.secondary)
            Text(supporter && !state.isUnlocked ? tr("已按赞助者解锁 Pro，谢谢你的支持") : state.statusText)
                .font(.callout.weight(.medium))
        }
    }
}

/// 输入许可证或兑换码，加激活按钮和中文错误提示。
struct ProKeyField: View {
    @State private var license = ProLicenseManager.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已经购买或收到兑换码？在这里输入")
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                TextField(ProLicenseText.inputPlaceholder, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(activate)
                    .disabled(license.isWorking)
                Button(action: activate) {
                    HStack(spacing: 6) {
                        if license.isWorking { ProgressView().controlSize(.small) }
                        Text("激活")
                    }
                }
                .disabled(license.isWorking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = license.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(proAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activate() {
        let text = key
        Task {
            if await license.activate(text) { key = "" }
        }
    }
}

@MainActor
final class PaywallWindow: HostedWindow {
    static let shared = PaywallWindow()

    func show() {
        ProLicenseManager.shared.refreshState()
        present(ProPaywallView(onClose: { [weak self] in self?.close() }),
                title: tr("码头 Pro"), size: NSSize(width: 480, height: 700), chromeless: true)
    }
}

// MARK: - 设置 ▸ 码头 Pro

/// 设置窗口里的“码头 Pro”页：状态、剩余试用天数、购买、输入激活码或兑换码、解绑本机。
struct ProSettingsPane: View {
    @State private var license = ProLicenseManager.shared
    @AppStorage(Supporter.key) private var supporter = false
    @State private var confirmDeactivate = false
    @AppStorage(ProUnlockFirstRun.soundKey) private var celebrationSound = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(proAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("码头 Pro").font(.title3.weight(.semibold))
                            ProBadge()
                        }
                        ProStatusLine(state: license.state, supporter: supporter)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if case .trial = license.state, let end = license.trialEndDate {
                    LabeledContent("试用到期") {
                        Text(end.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if license.isActivated {
                    LabeledContent("许可证") {
                        Text(license.maskedKey ?? "").monospaced()
                    }
                    if let last = license.lastValidated {
                        LabeledContent("上次校验") {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            } footer: {
                Text(ProLicenseText.priceLine + tr("。离线时最多保留 \(ProLicenseConfig.offlineGraceDays) 天，联网后自动重新校验。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !license.isActivated {
                Section {
                    HStack(spacing: 10) {
                        if license.canStartTrial && !supporter {
                            Button(tr("开始 \(ProLicenseConfig.trialDays) 天免费试用")) { license.startTrial() }
                                .buttonStyle(.borderedProminent)
                                .tint(proAccent)
                        }
                        Button(tr("购买（首批特价 \(ProLicenseConfig.launchPrice)）")) { license.buy() }
                        Button("查看 Pro 功能…") { PaywallWindow.shared.show() }
                            .buttonStyle(.link)
                    }
                    ProKeyField()
                } header: {
                    Text("激活")
                }
            } else {
                Section {
                    LabeledContent {
                        Button("解绑本机…") { confirmDeactivate = true }
                            .disabled(license.isWorking)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("解绑本机")
                            Text("换新 Mac 前先解绑，激活名额会留给下一台。兑换码同样一码一机，解绑后可以换机。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let message = license.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(proAccent)
                    }
                } header: {
                    Text("这台 Mac")
                }
            }

            Section {
                Toggle("解锁动画音效", isOn: $celebrationSound)
                LabeledContent {
                    // 没激活时重看会写着“Pro 已激活”，先不让点。
                    Button("重看解锁动画") { ProUnlockCelebration.shared.replay() }
                        .disabled(!license.isActivated)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("解锁动画")
                        Text("第一次激活成功时自动播放一次，之后可以在这里重看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("关于 Pro")
            }

            Section("Pro 包含") {
                ForEach(ProPerk.all) { perk in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(perk.title)
                            Text(perk.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: perk.symbol).foregroundStyle(proAccent)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { license.refreshState() }
        .confirmationDialog("解绑这台 Mac？", isPresented: $confirmDeactivate) {
            Button("解绑", role: .destructive) {
                Task { await license.deactivate() }
            }
        } message: {
            Text("解绑后这台 Mac 回到免费版，用同一个许可证或兑换码可以在别的 Mac 上激活。")
        }
    }
}
