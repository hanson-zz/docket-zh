import SwiftUI

/// A row of round buttons for the things done many times a day, chosen in
/// the widget's settings (`actions`). Switches with a state, like Keep Awake
/// or hidden files, are lit while on; actions that cannot be undone, like
/// emptying the Trash or quitting apps, ask first.
///
/// 截图识字、二维码、演示模式、只锁键盘、低电量模式是码头 Pro 工具：没解锁时
/// 已勾上的照样占位，但画得暗一些、右下角带小锁，点按弹付费墙，不执行。正开着
/// 的仍能点一下关掉。添加面板的预览不上锁。
struct QuickTogglesTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var actions: QuickActions { QuickActions.shared }
    private var chosen: [QuickToggle] { QuickToggle.chosen(instance.config) }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) { buttons }
            } else {
                HStack(spacing: 8) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let unlocked = licenseUnlocked || supporter || context.isPreview
        ForEach(chosen) { toggle in
            let on = !context.isPreview && toggle.hasState && actions.isOn(toggle)
            let locked = !ProLicenseGate.canUseTool(toggle, isOn: on, unlocked: unlocked)
            TileGlyph(symbol: toggle.symbol, size: 11,
                      tint: on ? .orange : (locked ? WidgetStyle.primary.opacity(0.4) : WidgetStyle.primary),
                      action: context.isPreview ? nil : {
                          if locked { PaywallWindow.shared.show() } else { actions.perform(toggle) }
                      })
                .overlay(alignment: .bottomTrailing) {
                    if locked { lockBadge }
                }
                .help(locked ? tr("\(toggle.title)：码头 Pro 专属，点一下解锁")
                      : (on ? tr("\(toggle.title)：已打开") : toggle.help))
                .accessibilityLabel(toggle.title)
                .accessibilityValue(locked ? ProFeatures.label
                                    : (toggle.hasState ? (on ? tr("开") : tr("关")) : ""))
        }
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
