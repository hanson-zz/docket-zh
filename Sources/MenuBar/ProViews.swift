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
                    detail: tr("所有小组件的液态外观；电池的液态电量插电时水面会晃，低电量变红，颜色随电量渐变")),
            ProPerk(id: "faces", symbol: "clock.fill", title: tr("专属表盘和角色"),
                    detail: tr("时钟的霓虹、实景、液晶表盘和翻页的大号卡片；企鹅、水獭、章鱼三个角色（柴犬、橘猫在喝水里累计达标 3 天、7 天免费解锁）")),
            ProPerk(id: "looks", symbol: "battery.100percent.bolt", title: tr("Wi-Fi 和电池外观"),
                    detail: tr("数字 Wi-Fi；像素电池、能量粒子、小熊猫抱电池")),
            ProPerk(id: "colors", symbol: "paintpalette.fill", title: tr("专属配色和样式"),
                    detail: tr("小熊猫橙、樱花粉等底板配色；小组件自定义颜色和渐变背景；便签更多纸色；天气多城市（多城市样式和面板第 2 个城市起）、电池格（含专属沙漏面板）、时间进度四格、喝水小熊猫角色、收音机 8 款 Pro 外观、纪念日玻璃沙漏、世界时钟多城市天空格子、Codex 用量精版；习惯打卡第 4 个起和近七天报告；书签分组文件夹；专注历史统计（免费只看今天）；快速待办橙黄绿紫四色标签和按颜色筛选")),
            ProPerk(id: "tools", symbol: "wand.and.stars", title: tr("Pro 工具"),
                    detail: tr("快速开关的截图识字、二维码、演示模式、只锁键盘、低电量模式；刘海里的 AI 对话；消息灵动岛（信息、WhatsApp、微信的消息卡，信息可在刘海里回复）；按 App 自动切换输入法；电池充电上限；系统活动超阈值提醒；邮件多账户筛选；录音本机转文字、裁剪和编辑；截图翻译（译文盖在截图上）和贴图；麦克风使用记录保留 30 天；壁纸按早中晚和日出日落自动换；加密货币到价提醒；「算」的汇率完整版（多币种、收藏、固定、记录、小键盘）和卡片轮播收藏；扩展栏悬停显示窗口预览；从小组件库新建应用分组和文件夹分组；程序坞里的 App 换显示图标；快速待办与提醒事项双向同步；快速待办的重复待办（每天、每周、工作日）；钉在桌面不限张数和大号卡片；卜卦每日一签的签历和收藏、签卡分享图、签筒和铜钱皮肤")),
        ]
    }
}

// MARK: - 付费墙

/// 付费墙首屏的六个功能块：标题加一句短说明，数量从 `ProFeatures` 数。
/// 完整名单在“查看完整清单”里，用的是 `ProPerk.all`。
private struct ProTile: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String

    static var all: [ProTile] {
        [
            ProTile(id: "kinds", symbol: "square.grid.2x2.fill",
                    title: tr("\(ProFeatures.proKinds.count) 个 Pro 小组件"), detail: tr("股票、播客、竹篮等")),
            ProTile(id: "liquid", symbol: "drop.fill",
                    title: tr("液态外观"), detail: tr("\(ProFeatures.liquidKinds.count) 种会晃的水面")),
            ProTile(id: "faces", symbol: "clock.fill",
                    title: tr("专属表盘和角色"), detail: tr("\(ProFeatures.exclusiveStyleCount) 种外观")),
            ProTile(id: "looks", symbol: "battery.100percent.bolt",
                    title: tr("Wi-Fi 和电池外观"), detail: tr("像素、粒子、小熊猫")),
            ProTile(id: "colors", symbol: "paintpalette.fill",
                    title: tr("配色和高级样式"), detail: tr("自定义颜色、渐变")),
            ProTile(id: "tools", symbol: "wand.and.stars",
                    title: tr("Pro 工具"), detail: tr("AI 刘海、充电上限")),
        ]
    }
}

/// 付费墙的尺寸和字号。字号最小 13pt，法律小字 12pt。
private enum PaywallMetrics {
    static let size = NSSize(width: 540, height: 860)
    static let padding: CGFloat = 26
    static let pandaHeight: CGFloat = 108
    static let tileHeight: CGFloat = 84
    static let gridSpacing: CGFloat = 12
}

/// 戴皇冠的小熊猫，和解锁动画同一张图（Resources/Unlock/unlock-panda-crown.png）。
@MainActor
private enum PaywallArt {
    private static var crown: NSImage?

    static var crownPanda: Image {
        if let crown { return Image(nsImage: crown) }
        guard let url = Bundle.main.url(forResource: ProUnlockPose.crown.rawValue, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "crown.fill")
        }
        crown = image
        return Image(nsImage: image)
    }
}

/// 码头 Pro 付费墙：六个功能块、价格卡、购买、7 天试用，许可证和兑换码收在一行链接里；
/// 完整清单在同一个窗口里切过去，可以返回。
struct ProPaywallView: View {
    var onClose: () -> Void
    @State private var license = ProLicenseManager.shared
    @AppStorage(Supporter.key) private var supporter = false
    @State private var showsAll = false
    @State private var showsKeyField = false
    @State private var earlybird: ProEarlybird?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsAll {
                ProPaywallFullList(back: { withAnimation(.snappy) { showsAll = false } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭")
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
        .frame(width: PaywallMetrics.size.width, height: PaywallMetrics.size.height, alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                // 顶部一抹淡淡的小熊猫橙光晕。
                RadialGradient(colors: [proAccent.opacity(0.30), proAccent.opacity(0.08), .clear],
                               center: UnitPoint(x: 0.25, y: 0.0), startRadius: 10, endRadius: 420)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // 只有首批档去问卖完没有；价格卡只写“首批限量 N 个”，不公开剩余个数。
            guard ProPriceTiers.current == 0 else { return }
            earlybird = await ProEarlybirdFetcher.fetch()
        }
        .onChange(of: license.state) { _, state in
            // 激活成功就关掉；开始试用也关掉，用户回到刚才想加的东西。
            if state.isUnlocked { onClose() }
        }
    }

    private var main: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)
                tiles
                Button {
                    withAnimation(.snappy) { showsAll = true }
                } label: {
                    Text(tr("查看完整清单 ›"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(proAccent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.bottom, 14)

                ProPriceCard(display: ProPriceDisplay.make(earlybird: earlybird))
                Text(tr("实际价格以结账页为准"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.leading, 4)

                buttons
                    .padding(.top, 16)
            }
            .padding(.horizontal, PaywallMetrics.padding)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PaywallArt.crownPanda
                .resizable()
                .scaledToFit()
                .frame(height: PaywallMetrics.pandaHeight)
                .foregroundStyle(proAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("码头 Pro")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(.bottom, 2)
                Text(tr("基础功能一直免费"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.82))
                Text(tr("Pro 一次买断，不用订阅"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.82))
            }
            Spacer(minLength: 40)
        }
    }

    private var tiles: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: PaywallMetrics.gridSpacing), count: 2)
        return LazyVGrid(columns: columns, spacing: PaywallMetrics.gridSpacing) {
            ForEach(ProTile.all) { tile in
                HStack(spacing: 12) {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(proAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        // 英文标题较长，允许折成两行，不截断。
                        Text(tile.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tile.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // 同一行两块等高：英文标题折行时另一块跟着撑高。
                .frame(maxWidth: .infinity, minHeight: PaywallMetrics.tileHeight, maxHeight: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var canTry: Bool { license.canStartTrial && !supporter }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                license.buy()
            } label: {
                Text(tr("购买码头 Pro"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(proAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canTry {
                Button {
                    license.startTrial()
                } label: {
                    Text(tr("先免费试用 \(ProLicenseConfig.trialDays) 天，不用填卡"))
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ProStatusLine(state: license.state, supporter: supporter, fontSize: 13)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            if !license.isActivated {
                if showsKeyField {
                    ProKeyField(inPaywall: true)
                        .padding(.top, 2)
                        .transition(.opacity)
                } else {
                    Button {
                        withAnimation(.snappy) { showsKeyField = true }
                    } label: {
                        Text(tr("已有许可证或兑换码？输入激活 ›"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.62))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 价格卡：小字档位和剩余个数、大号现价、划线下一档、剩余进度条、三档一行。
private struct ProPriceCard: View {
    var display: ProPriceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(display.badge)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(proAccent)
                Spacer(minLength: 12)
                if let fraction = display.remainingFraction {
                    Capsule()
                        .fill(.white.opacity(0.14))
                        .frame(width: 120, height: 8)
                        .overlay(alignment: .leading) {
                            Capsule().fill(proAccent).frame(width: max(8, 120 * fraction), height: 8)
                        }
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(display.price)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let next = display.nextPrice {
                    Text(next)
                        .font(.system(size: 18))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(tr("原价 \(next)"))
                }
            }
            Text(display.tiersLine)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(proAccent.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(proAccent.opacity(0.55), lineWidth: 1))
    }
}

/// 付费墙里的完整清单：按分类列出全部 Pro 内容，字号不低于 13pt，顶部可以返回。
private struct ProPaywallFullList: View {
    var back: () -> Void

    private func title(_ perk: ProPerk) -> String {
        perk.id == "kinds" ? tr("\(ProFeatures.proKinds.count) 个 Pro 小组件") : perk.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Text(tr("‹ 返回"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(proAccent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Text(tr("Pro 完整清单"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, PaywallMetrics.padding)
            .padding(.top, 22)
            .padding(.trailing, 40)
            .padding(.bottom, 14)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProPerk.all) { perk in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: perk.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(proAccent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(perk))
                                    .font(.system(size: 15, weight: .semibold))
                                Text(perk.detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text(ProLicenseText.priceLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, PaywallMetrics.padding)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// 向授权中转要首批剩余个数，3 秒没回或出错返回 nil。
private enum ProEarlybirdFetcher {
    static func fetch() async -> ProEarlybird? {
        var request = URLRequest(url: ProPriceTiers.earlybirdURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ProEarlybird.parse(result.0)
    }
}

/// 一行状态：图标加一句话。
private struct ProStatusLine: View {
    var state: ProLicenseState
    var supporter: Bool
    /// 付费墙里用 13pt；设置页沿用系统的 callout。
    var fontSize: CGFloat? = nil

    var body: some View {
        let unlocked = ProLicenseGate.isUnlocked(state, supporter: supporter)
        HStack(spacing: 6) {
            Image(systemName: unlocked ? "checkmark.seal.fill" : "info.circle")
                .foregroundStyle(unlocked ? proAccent : Color.secondary)
            Text(supporter && !state.isUnlocked ? tr("已按赞助者解锁 Pro，谢谢你的支持") : state.statusText)
                .font(fontSize.map { Font.system(size: $0, weight: .medium) } ?? Font.system(size: 13, weight: .medium))
        }
    }
}

/// 输入许可证或兑换码，加激活按钮和中文错误提示。
struct ProKeyField: View {
    /// 付费墙里：链接已经说明了用途，不再重复标题，错误提示用 13pt。
    var inPaywall = false
    @State private var license = ProLicenseManager.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !inPaywall {
                Text("已经购买或收到兑换码？在这里输入")
                    .font(.system(size: 13, weight: .medium))
            }
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
                    .font(.system(size: 13))
                    .foregroundStyle(proAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(inPaywall ? .large : .regular)
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
                title: tr("码头 Pro"), size: PaywallMetrics.size, chromeless: true)
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
                    .font(.system(size: 13))
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
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let message = license.errorMessage {
                        Text(message)
                            .font(.system(size: 13))
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
                            .font(.system(size: 13))
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
                                .font(.system(size: 13))
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
