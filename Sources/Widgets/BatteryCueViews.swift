import SwiftUI

/// 电池卡片和面板上的小熊猫：Mac 电量低于 20% 又没接电源时举爪提醒（一直在，接上电源就走），
/// 充满时挥爪一次、2.4 秒后消失。其余时间什么都不画，界面是纯数据。
///
/// 判定在 Core（`BatteryPandaCue`、`BatteryFullWatch`），采样器给出 `fullPulse`；
/// 这里只照着画。出现时轻轻弹一下（单次，不循环），减弱动态效果时只换静帧。
struct BatteryPandaCueView: View {
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 现在该画哪个样子：低电量提醒优先，其次充满那一下；都没有时 nil（不画）。
    static var shown: PandaState? {
        let metrics = BatteryMetrics.shared
        let base = metrics.device(.mac).flatMap { mac -> PandaState? in
            guard mac.present else { return nil }
            return BatteryPandaCue.base(percent: BatteryColorMap.percent(mac.level), onPower: mac.onPower,
                                        charging: mac.charging)
        }
        return base ?? metrics.fullPulse.map { _ in PandaState.done }
    }

    var body: some View {
        let shown = Self.shown
        ZStack(alignment: .bottom) {
            if let shown {
                PandaStateView(shown, size: size)
                    .modifier(BatteryPandaHop())
                    .id(shown)
                    .transition(.opacity)
            }
        }
        .frame(width: shown == nil ? 0 : size, height: shown == nil ? 0 : size, alignment: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: PandaMotion.transition), value: shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 小熊猫出现时以脚底为轴弹一下，和 `PandaStateView` 的单次动作同一节奏。
private struct BatteryPandaHop: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.08 : 1, anchor: .bottom)
            .task {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: PandaMotion.oneShot * 0.4, bounce: 0.5)) { up = true }
                try? await Task.sleep(for: .seconds(PandaMotion.oneShot * 0.45))
                withAnimation(.easeOut(duration: PandaMotion.oneShot * 0.55)) { up = false }
            }
    }
}

/// 充电时圆环下面垫一层同色的宽弧，慢慢呼吸（1.6 秒一明一暗）。只改透明度，不逐帧重绘；
/// 没在充电、卡片不在屏幕上、或打开减弱动态效果时整层不画。
struct BatteryChargeBreath: View {
    /// 弧画到哪里（0...1，已经乘过圆环的开口比例）。
    var trim: Double
    var tint: Color
    var lineWidth: CGFloat
    /// 弧的起点转多少度（和上面那条电量弧一致）。
    var rotation: Double
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if active, !reduceMotion, trim > 0 {
            Circle()
                .trim(from: 0, to: CGFloat(min(max(trim, 0), 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth * 1.9, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .phaseAnimator([0.0, 0.32]) { arc, glow in
                    arc.opacity(glow)
                } animation: { _ in .easeInOut(duration: 1.6) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// 多设备卡片某一格的轻提示：圆环外一圈高亮描边，圆环下面压一个小胶囊「已连接」「已断开」
/// 「电量低」，2 到 3 秒后随采样器的提示到期一起消失。不发系统通知。
struct AccessoryFlashRing: View {
    var change: AccessoryChange?
    var lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let change {
                Circle()
                    .stroke(Self.color(change), lineWidth: lineWidth)
                    .padding(-lineWidth * 1.4)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: change)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func color(_ change: AccessoryChange) -> Color {
        switch change {
        case .connected: Color(hex: MetricColor.batteryPresent)
        case .disconnected: WidgetStyle.secondary
        case .low: BatteryTheme.warningRed.swiftUI
        }
    }
}

/// 圆环下面那个小胶囊；字 13pt，垫可读玻璃，浅色深色桌面都看得清。
struct AccessoryFlashCapsule: View {
    var change: AccessoryChange

    var body: some View {
        Text(change.label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(change == .low ? BatteryTheme.warningRed.swiftUI : WidgetStyle.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .readableGlass(in: Capsule())
            .accessibilityLabel(change.label)
    }
}
