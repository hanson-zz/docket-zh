import SwiftUI

/// 截图工具：只管“动作”。截区域、截窗口、识字、录屏四个按钮，每个下面两个字。
/// 截出来的东西去“最近截图”看，识字的结果直接拷贝。
///
/// 识字和快速开关里的“截图识字”是同一个 Pro 工具、同一套实现：没解锁时画暗一些、
/// 右下角带小锁，点按弹付费墙，和快速开关一样。录屏时录屏按钮变红、下面写计时，
/// 再点一次停止。卡片空白处照旧打开系统的“截屏”App（有定时和选区录制）。
struct CaptureTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recording: ScreenRecording { ScreenRecording.shared }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 8) {
                    HStack(spacing: 8) { button(.region, label: false); button(.window, label: false) }
                    HStack(spacing: 8) { button(.text, label: false); button(.record, label: false) }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(CaptureAction.allCases) { action in
                        button(action, label: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func isLocked(_ action: CaptureAction) -> Bool {
        guard let toggle = action.quickToggle else { return false }
        let unlocked = licenseUnlocked || supporter || context.isPreview
        return !ProLicenseGate.canUseTool(toggle, isOn: false, unlocked: unlocked)
    }

    private func isLive(_ action: CaptureAction) -> Bool {
        action == .record && !context.isPreview && recording.isRecording
    }

    private func tint(_ action: CaptureAction) -> Color {
        if isLive(action) { return .red }
        if isLocked(action) { return WidgetStyle.primary.opacity(0.4) }
        return WidgetStyle.primary
    }

    @ViewBuilder
    private func button(_ action: CaptureAction, label: Bool) -> some View {
        let locked = isLocked(action)
        let live = isLive(action)
        VStack(spacing: 3) {
            TileGlyph(symbol: live ? "stop.fill" : action.symbol, size: 11, tint: tint(action),
                      morphs: action == .record,
                      action: context.isPreview ? nil : {
                          if locked { PaywallWindow.shared.show() } else { ScreenCapture.perform(action) }
                      })
                .overlay(alignment: .bottomTrailing) {
                    if locked { lockBadge }
                }
                .overlay {
                    if live && !reduceMotion { RecordingPulse() }
                }
            if label {
                caption(action, live: live)
            }
        }
        .help(help(action, locked: locked, live: live))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action.title)
        .accessibilityValue(locked ? ProFeatures.label : (live ? tr("正在录屏") : ""))
    }

    @ViewBuilder
    private func caption(_ action: CaptureAction, live: Bool) -> some View {
        if live, let started = recording.startedAt {
            Text(RecordingClock.text(context.now.timeIntervalSince(started)))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.red)
                .lineLimit(1)
        } else {
            Text(action.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isLocked(action) ? WidgetStyle.secondary : WidgetStyle.primary.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func help(_ action: CaptureAction, locked: Bool, live: Bool) -> String {
        if locked { return tr("\(action.title)：码头 Pro 专属，点一下解锁") }
        if live { return tr("正在录屏，点一下停止") }
        return action.help
    }

    /// Pro 工具没解锁时右下角的小锁，和快速开关一样。
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

/// 录屏时按钮外一圈慢慢呼吸的细红环。打开“减少动态效果”时不画，只靠红色和计时。
private struct RecordingPulse: View {
    @State private var on = false

    var body: some View {
        Circle()
            .strokeBorder(Color.red.opacity(on ? 0.15 : 0.55), lineWidth: 1.2)
            .frame(width: 26, height: 26)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
