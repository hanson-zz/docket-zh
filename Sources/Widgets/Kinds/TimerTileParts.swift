import SwiftUI

/// 计时类卡片共用的小零件：卡片上的胶囊按钮、到点时的左右晃、到点时的整卡按钮。

/// 卡片上的胶囊按钮（倒计时的预设、闹钟的稍后和关掉、秒表的计次）。
///
/// 和 `TileGlyph` 一样只有自己那么大：卡片其余地方的点按要留给码头去打开面板。
/// 小组件库的预览里画出来但不能按，`action` 传 nil。
struct TimerPill: View {
    var title: String
    var size: CGFloat = 11
    var height: CGFloat = 20
    /// 高亮的那个（上次用的预设、关掉）用主题色。
    var tint: Color?
    var minWidth: CGFloat = 0
    /// 给了就是实心按钮：`tint` 铺满底，字用这个颜色（久坐提醒的「起来了」，
    /// 粉底深字）。没给时照旧淡底彩字。
    var solidInk: Color? = nil
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .contentShape(Capsule())
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            .font(.system(size: size, weight: solidInk == nil ? .semibold : .bold))
            .foregroundStyle(solidInk.map { AnyShapeStyle($0) }
                             ?? tint.map { AnyShapeStyle($0) }
                             ?? AnyShapeStyle(WidgetStyle.primary.opacity(0.88)))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background {
                Capsule().fill(tint.map { $0.opacity(solidInk == nil ? 0.26 : 1) } ?? WidgetStyle.primary.opacity(0.1))
            }
    }
}

extension View {
    /// 到点时卡片左右晃。`active` 为假或系统打开“减少动态效果”时不晃。
    func timerShake(_ active: Bool) -> some View {
        modifier(TimerShake(active: active))
    }
}

private struct TimerShake: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-2.5, duration: 0.09)
                    CubicKeyframe(2.5, duration: 0.18)
                    CubicKeyframe(-2.5, duration: 0.18)
                    CubicKeyframe(2.5, duration: 0.18)
                    CubicKeyframe(0, duration: 0.09)
                    // 晃一阵停一下，像闹钟在桌上跳。
                    LinearKeyframe(0, duration: 0.5)
                }
            }
        } else {
            content
        }
    }
}

/// 计时卡片上的小熊猫图。读不到图时退回一个符号，卡片不会空一块。
struct TimerPanda: View {
    var name: String
    var fallback: String
    var height: CGFloat

    var body: some View {
        if let image = PandaArt.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallback)
                .font(.system(size: height * 0.45, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
                .frame(width: height, height: height)
        }
    }
}

extension Color {
    /// 计时类卡片的几种强调色，和效果图一致。
    static let timerOrange = Color(hex: "#FF9F43")
    static let timerAmber = Color(hex: "#FFC94D")
    static let timerGreen = Color(hex: "#4CD787")
    static let timerTomato = Color(hex: "#FF6B5A")
    static let timerPink = Color(hex: "#FF7BA9")
    /// 实心粉按钮上的深字（久坐提醒的「起来了」「我起身活动了」），对比度约 6.9。
    static let timerPinkInk = Color(hex: "#3A0D1F")
}
