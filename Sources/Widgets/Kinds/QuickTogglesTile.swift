import SwiftUI

/// A row of round buttons for the things done many times a day, chosen in
/// the widget's settings (`actions`). Switches with a state, like Keep Awake
/// or hidden files, are lit while on; actions that cannot be undone, like
/// emptying the Trash or quitting apps, ask first.
///
/// 截图识字、二维码、演示模式、只锁键盘、低电量模式是码头 Pro 工具：没解锁时
/// 已勾上的照样占位，但画得暗一些、右下角带小锁，点按弹付费墙，不执行。正开着
/// 的仍能点一下关掉。添加面板的预览不上锁。
///
/// 设置或面板里打开「卡片圆钮下显示名字」后，每个圆钮下写短名字（`shortTitle`）。
/// 保持唤醒按卡片选的时长打开，到点自动关（`KeepAwakeTimer`），悬停写剩多久。
/// 点圆钮以外的地方打开面板（大按钮、保持唤醒时长、编辑排序）。
struct QuickTogglesTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var actions: QuickActions { QuickActions.shared }
    private var chosen: [QuickToggle] { QuickToggle.chosen(instance.config) }
    private var names: Bool { QuickToggle.showsNames(instance.config) }
    private var awakeMinutes: Int { KeepAwakeTimer.minutes(instance.config) }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: names ? 2 : 6) { buttons }
            } else {
                HStack(spacing: names ? 2 : 8) { buttons }
            }
        }
        // 设置或面板里换了时长：正开着的保持唤醒从现在起按新时长计。
        .onChange(of: awakeMinutes) { _, minutes in
            if !context.isPreview { actions.changeKeepAwakeDuration(minutes: minutes) }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let unlocked = licenseUnlocked || supporter || context.isPreview
        ForEach(chosen) { toggle in
            let on = !context.isPreview && toggle.hasState && actions.isOn(toggle)
            let locked = !ProLicenseGate.canUseTool(toggle, isOn: on, unlocked: unlocked)
            VStack(spacing: 2) {
                TileGlyph(symbol: toggle.symbol, size: 11,
                          tint: on ? .orange : (locked ? WidgetStyle.primary.opacity(0.4) : WidgetStyle.primary),
                          action: context.isPreview ? nil : {
                              if locked {
                                  PaywallWindow.shared.show()
                              } else if toggle == .keepAwake {
                                  actions.toggleKeepAwake(minutes: awakeMinutes)
                              } else {
                                  actions.perform(toggle)
                              }
                          })
                    .overlay(alignment: .bottomTrailing) {
                        if locked { lockBadge }
                    }
                if names {
                    Text(verbatim: toggle.shortTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(on ? Color.orange : WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 44)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
                .help(locked ? tr("\(toggle.title)：码头 Pro 专属，点一下解锁")
                      : (on ? onHelp(toggle) : toggle.help))
                .accessibilityLabel(toggle.title)
                .accessibilityValue(locked ? ProFeatures.label
                                    : (toggle.hasState ? (on ? tr("开") : tr("关")) : ""))
        }
    }

    /// 开着时的悬停：保持唤醒写还剩多久（悬停时算，不为它每分钟重画卡片）。
    private func onHelp(_ toggle: QuickToggle) -> String {
        guard toggle == .keepAwake else { return tr("\(toggle.title)：已打开") }
        return tr("\(toggle.title)：\(KeepAwakeTimer.remaining(until: actions.keepAwakeUntil, now: .now))")
    }

    /// Pro 工具没解锁时右下角的小锁。
    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 6.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 11, height: 11)
            .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
            .offset(x: 2, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
