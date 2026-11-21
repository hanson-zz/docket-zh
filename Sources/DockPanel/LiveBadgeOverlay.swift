import SwiftUI

/// 信息、微信、邮件图标的「消息未读」动态：只在码头自己画的图标上加，不改 App 本身的图标。
///
/// 简洁（默认）：原色不变，右上角红色角标，来新消息时角标和图标轻弹一次。
/// 趣味：按未读数分级换色（2 到 3 条蓝、4 到 6 条紫、7 到 8 条紫粉、9 条及以上红粉），
/// 角标旁挂闪光、火焰或液滴，都是静态挂件，只有新消息那一下弹。白色气泡转色相后仍是白的，
/// 原来的标志一直认得出。读不到未读数时什么都不画。减弱动态效果时不弹，只换状态。
struct LiveBadgeModifier: ViewModifier {
    var app: LiveBadgeApp
    var side: CGFloat
    /// 设置里的预览：传入演示读数时不读程序坞。
    var demo: LiveBadgeReading?
    var demoPulse: Int = 0

    @AppStorage(LiveBadgeStyle.key) private var styleRaw = LiveBadgeStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var monitor: LiveBadgeMonitor { .shared }

    func body(content: Content) -> some View {
        let reading = demo ?? monitor.reading(app)
        let look = LiveBadgeLook.of(app, reading: reading, style: LiveBadgeStyle(stored: styleRaw))
        let trigger = demo == nil ? monitor.pulseGeneration(app) : demoPulse
        content
            .hueRotation(.degrees(look.hueRotation))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: look.hueRotation)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : trigger) { view, scale in
                view.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.08, duration: 0.22, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .smooth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let text = look.badgeText {
                    LiveBadgeChip(text: text, accent: look.accent, side: side, trigger: trigger,
                                  animate: !reduceMotion)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: look.badgeText == nil)
            .task(id: demo == nil) {
                guard demo == nil else { return }
                monitor.retain()
                defer { monitor.release() }
                // 一直挂着，视图消失时任务取消才退出。
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            }
    }
}

/// 右上角的红色角标和它旁边的挂件。
private struct LiveBadgeChip: View {
    var text: String
    var accent: LiveBadgeAccent
    var side: CGFloat
    var trigger: Int
    var animate: Bool

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let diameter = max(10, side * (text.isEmpty ? 0.18 : 0.3))
        let font = max(9, diameter * 0.62)
        ZStack {
            accentView(diameter: diameter)
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#FF5A4E"), Color(hex: "#E5242B")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: max(0.8, diameter * 0.06)))
                .frame(width: text.count > 1 ? diameter * (0.55 + 0.32 * CGFloat(text.count)) : diameter,
                       height: diameter)
                .shadow(color: .black.opacity(0.25), radius: diameter * 0.08, y: diameter * 0.05)
                .overlay {
                    if !text.isEmpty {
                        Text(verbatim: text)
                            .font(.system(size: font, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, diameter * 0.14)
                    }
                }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: animate ? trigger : 0) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.3, duration: 0.18, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.55, spring: .bouncy)
            }
        }
        // 角标中心大约压在图标内容区右上角往里一点，和系统程序坞的位置相近。
        .offset(x: -(CGFloat(g.inset) - diameter * 0.18), y: CGFloat(g.inset) - diameter * 0.18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func accentView(diameter: CGFloat) -> some View {
        switch accent {
        case .none:
            EmptyView()
        case .sparkle:
            Image(systemName: "sparkle")
                .font(.system(size: diameter * 0.55, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFE37A"), Color(hex: "#FFB020")],
                                                startPoint: .top, endPoint: .bottom))
                .offset(x: diameter * 0.55, y: -diameter * 0.5)
        case .flame:
            Image(systemName: "flame.fill")
                .font(.system(size: diameter * 0.7, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFD54A"), Color(hex: "#FF6A1F")],
                                                startPoint: .top, endPoint: .bottom))
                .offset(y: -diameter * 0.62)
        case .drip:
            // 角标下沿挂两滴红色液滴，一长一短，不动。
            HStack(alignment: .top, spacing: diameter * 0.16) {
                drop(width: diameter * 0.16, height: diameter * 0.34)
                drop(width: diameter * 0.2, height: diameter * 0.5)
            }
            .offset(x: -diameter * 0.04, y: diameter * 0.55)
        }
    }

    private func drop(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: "#E5242B"), Color(hex: "#C0141C")],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
    }
}
