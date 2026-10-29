import SwiftUI

// MARK: - 卜卦 · 每日一签的附加界面
//
// 免费：星座 / 属相徽章和今日幸运色、幸运数字（签上）、本周寄语（签下面一小块）。
// Pro：收藏、签历（月历回顾）、签卡分享图三个入口；签筒和铜钱皮肤。没解锁时入口带小锁和
// Pro 角标，点了走现有的付费墙。规则、数据和存法都在 Core（DivinationDaily）。
// 所有内容按面板内容宽（Divination.panelContentWidth，266）排，字不小于 13pt。

// MARK: - 皮肤入口（签筒、铜钱共用）

/// 现在该画的签筒和铜钱皮肤。抱签筒的姿势图（盖一层筒身着色图）和铜钱（DivinationCoin，
/// 换一套着色好的正反面）只从这里读，起卦页、每日一签页、桌面卡片都一样；没解锁时是默认款。
struct DivinationSkinChoice: Equatable, Sendable {
    var tube: TubeSkin = .bamboo
    var coin: CoinSkin = .classic
}

extension EnvironmentValues {
    @Entry var divinationSkin = DivinationSkinChoice()
}

/// 按卡片配置和 Pro 状态把皮肤放进环境。试用到期、激活时立刻重画。
private struct DivinationSkinModifier: ViewModifier {
    var config: WidgetConfig
    var isPreview: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    func body(content: Content) -> some View {
        let unlocked = !isPreview && (licenseUnlocked || supporter)
        content.environment(\.divinationSkin,
                            DivinationSkinChoice(tube: Divination.tubeSkin(config, unlocked: unlocked),
                                                 coin: Divination.coinSkin(config, unlocked: unlocked)))
    }
}

extension View {
    /// 卜卦的签筒、铜钱按这张卡片选的皮肤画（Pro；没解锁画默认款）。
    func divinationSkins(_ config: WidgetConfig, isPreview: Bool = false) -> some View {
        modifier(DivinationSkinModifier(config: config, isPreview: isPreview))
    }
}

// MARK: - 写回

/// 签历收藏和星座 / 属相的写回：取最新存着的那份配置，算完写回。
@MainActor
enum DivinationDailyPlay {
    static func toggleFavorite(day: String, in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        Divination.toggleFavorite(day: day, in: &widget.config)
        WidgetWriter.update(widget)
    }
}

// MARK: - 星座 / 属相徽章

/// 小徽章：一个圆章（星座符号或生肖字）加名字。
struct DivinationSignBadge: View {
    var sign: DivinationSign

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: sign.symbol)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DivinationStyle.buttonFill))
                .overlay(Circle().strokeBorder(DivinationStyle.gold, lineWidth: 1))
            Text(verbatim: sign.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 2)
        .padding(.trailing, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.panelFill))
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sign.name)
    }
}

/// 签上的一行：徽章、今日幸运色、幸运数字。没选星座 / 属相时什么也不画。
struct DivinationSignBadgeRow: View {
    var config: WidgetConfig
    var now: Date
    var isPreview = false

    private var sign: DivinationSign? { isPreview ? .leo : Divination.sign(config) }

    var body: some View {
        if let sign {
            let luck = Divination.luck(day: Divination.dayKey(now), sign: sign)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    DivinationSignBadge(sign: sign)
                    luckColor(luck)
                    luckNumber(luck)
                }
                VStack(spacing: 6) {
                    DivinationSignBadge(sign: sign)
                    HStack(spacing: 10) {
                        luckColor(luck)
                        luckNumber(luck)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func luckColor(_ luck: DailyLuck) -> some View {
        HStack(spacing: 4) {
            Text(tr("幸运色"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
            Circle()
                .fill(Color(hex: luck.color.hex))
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 1))
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(verbatim: luck.color.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func luckNumber(_ luck: DailyLuck) -> some View {
        HStack(spacing: 4) {
            Text(tr("幸运数字"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
            Text(verbatim: "\(luck.number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DivinationStyle.red)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - 本周寄语

/// 签下面的一小块：本周寄语，每周一换。
struct DivinationWeeklyNote: View {
    var now: Date

    var body: some View {
        (Text(tr("本周寄语"))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(DivinationStyle.red)
            + Text(verbatim: "  ")
            + Text(verbatim: DivinationWeekly.line(now))
            .font(.system(size: 13))
            .foregroundStyle(Color.panelPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.panelStroke, lineWidth: 0.5))
    }
}

// MARK: - 每日一签页的外壳

/// 每日一签页：平时是今天的签加本周寄语和三个入口（收藏、签历、签卡）；点签历换成月历，
/// 点签卡换成分享图。页里原来的内容原样放在 `content` 里。
struct DivinationStickHost<Content: View>: View {
    var instance: WidgetInstance
    var context: WidgetContext
    /// 今天的签（没抽是 nil；摇的时候也是 nil）。
    var index: Int?
    @ViewBuilder var content: () -> Content

    enum Mode: Equatable { case today, archive, card }

    @State private var mode: Mode = .today
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool { context.isPreview || licenseUnlocked || supporter }
    private var config: WidgetConfig { instance.config }
    private var today: String { Divination.dayKey(context.now) }

    var body: some View {
        Group {
            switch mode {
            case .today:
                VStack(spacing: 10) {
                    content()
                    DivinationWeeklyNote(now: context.now)
                    tools
                }
            case .archive:
                DivinationArchiveView(instance: instance, context: context) { mode = .today }
            case .card:
                if let index {
                    DivinationShareView(instance: instance, context: context, index: index) { mode = .today }
                } else {
                    Color.clear.frame(height: 1).onAppear { mode = .today }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: mode)
    }

    private var favorite: Bool {
        !context.isPreview && Divination.record(day: today, in: config)?.favorite == true
    }

    private var tools: some View {
        HStack(spacing: 6) {
            if index != nil {
                DivinationToolChip(symbol: favorite ? "star.fill" : "star", title: favorite ? tr("已收藏") : tr("收藏", context: "verb"),
                                   locked: !unlocked, tinted: favorite) {
                    guard !context.isPreview else { return }
                    guard ProLicenseGate.canUseDivinationArchive(unlocked: unlocked) else {
                        return PaywallWindow.shared.show()
                    }
                    DivinationDailyPlay.toggleFavorite(day: today, in: instance)
                }
            }
            DivinationToolChip(symbol: "calendar", title: tr("签历"), locked: !unlocked) {
                guard !context.isPreview else { return }
                guard ProLicenseGate.canUseDivinationArchive(unlocked: unlocked) else {
                    return PaywallWindow.shared.show()
                }
                mode = .archive
            }
            if index != nil {
                DivinationToolChip(symbol: "square.and.arrow.up", title: tr("签卡"), locked: !unlocked) {
                    guard !context.isPreview else { return }
                    guard ProLicenseGate.canShareDivinationCard(unlocked: unlocked) else {
                        return PaywallWindow.shared.show()
                    }
                    mode = .card
                }
            }
            if !unlocked { ProBadge() }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 一个小玻璃入口：图标加两个字。锁着时图标换成小锁，点了弹付费墙（由调用方判断）。
struct DivinationToolChip: View {
    var symbol: String
    var title: String
    var locked: Bool
    var tinted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: locked ? "lock.fill" : symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tinted ? DivinationStyle.red : Color.panelSecondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Capsule().fill(Color.panelFill))
            .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(locked ? ProFeatures.help : title)
        .accessibilityLabel(locked ? "\(title) \(ProFeatures.label)" : title)
    }
}

/// 左上角的「‹ 今天」：回到今天的签。
struct DivinationBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DivinationStyle.red)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 签级配色（月历小点）

enum DivinationLevelDot {
    /// 上上红、上吉珊瑚、中吉金、中平竹青、下签灰：浅色深色玻璃上都看得清。
    static func color(_ level: StickLevel) -> Color {
        switch level {
        case .best: DivinationStyle.red
        case .great: Color(hex: "#F07F5A")
        case .good: DivinationStyle.gold
        case .fair: Color(hex: "#5E9B5A")
        case .low: Color(hex: "#8E8E93")
        }
    }

    /// 图例上的短名：上上、上吉、中吉、中平、下（签诗内容，英文界面也保持中文）。
    static func short(_ level: StickLevel) -> String {
        level.title.replacingOccurrences(of: "签", with: "")
    }
}
