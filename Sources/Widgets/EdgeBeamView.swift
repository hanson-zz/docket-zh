import SwiftUI

// 沿边流光的画法：一道细细的彗星光沿形状边缘绕圈，外加一层很淡的柔光。
// 规则（开关、动静、相位、切段、亮度）在 Core 的 `EdgeBeam`。
//
// 思路参考 border-beam-ios（MIT，Copyright (c) ismnoiet，
// https://github.com/ismnoiet/border-beam-ios），这里是自己写的精简版：
// 用 Canvas 按路径比例截出几段描边，不用 Metal 着色器，也不加依赖。
//
// 用法：`.edgeBeam(active: 生成中, shape: .rounded(16), tint: panelTint?.color)`。
// 放在 `.readableGlass(in:)` / `.glassEffect` 之后，是叠在玻璃外层的 overlay，
// 不会被玻璃翻深。不拦截点击，读屏不读。

extension EdgeBeam.Outline {
    /// 在 `rect` 里的路径；`inset` 往里收，圆角跟着收。
    func path(in rect: CGRect, inset: CGFloat) -> Path {
        let inner = rect.insetBy(dx: inset, dy: inset)
        guard inner.width > 0, inner.height > 0 else { return Path() }
        switch self {
        case .rounded(let radius):
            return RoundedRectangle(cornerRadius: max(0, CGFloat(radius) - inset), style: .continuous).path(in: inner)
        case .capsule:
            return Capsule(style: .continuous).path(in: inner)
        case .circle:
            let side = min(inner.width, inner.height)
            let square = CGRect(x: inner.midX - side / 2, y: inner.midY - side / 2, width: side, height: side)
            return Circle().path(in: square)
        }
    }
}

extension View {
    /// 沿边流光：`active` 为真时淡入并绕圈，变假时淡出、停掉时间线。
    /// `tint` 是小组件此刻的强调色（颜色面板里选过的），nil 时用柔和的白或灰。
    /// 设置里关掉「沿边流光」时不画；减弱动态效果、低电量模式时只画一道静止的光。
    func edgeBeam(active: Bool, shape: EdgeBeam.Outline, tint: Color? = nil) -> some View {
        modifier(EdgeBeamModifier(active: active, outline: shape, tint: tint))
    }
}

private struct EdgeBeamModifier: ViewModifier {
    var active: Bool
    var outline: EdgeBeam.Outline
    var tint: Color?

    @AppStorage(EdgeBeam.enabledKey) private var enabled = EdgeBeam.defaultEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// 正在显示（淡出时先变假，淡出走完图层才拿掉）。
    @State private var shown = false

    private var currentMotion: EdgeBeam.Motion {
        // 低电量模式和码头其他动效一样在画的时候读一次，不另开监听。
        EdgeBeam.motion(enabled: enabled, active: active, reduceMotion: reduceMotion,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func body(content: Content) -> some View {
        let now = currentMotion
        let on = now != .off
        content
            .overlay {
                if shown {
                    EdgeBeamLayer(outline: outline, color: color, dark: scheme == .dark,
                                  moving: now == .moving)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: on, initial: true) { _, visible in
                guard shown != visible else { return }
                if reduceMotion {
                    shown = visible
                } else {
                    withAnimation(.easeInOut(duration: EdgeBeam.fadeDuration)) { shown = visible }
                }
            }
    }

    private var color: Color {
        if let tint { return tint }
        let code = EdgeBeam.neutral(dark: scheme == .dark)
        return Color(.sRGB, red: code.red, green: code.green, blue: code.blue, opacity: 1)
    }
}

/// 光本身。只有在流动时才开时间线（最多每秒 30 帧）；静止时只画一帧。
private struct EdgeBeamLayer: View {
    var outline: EdgeBeam.Outline
    var color: Color
    var dark: Bool
    var moving: Bool

    /// 每次出现从这一刻起算，光从固定位置开始绕。
    @State private var start = Date()

    var body: some View {
        if moving {
            TimelineView(.animation(minimumInterval: 1 / EdgeBeam.frameRate, paused: false)) { context in
                canvas(head: EdgeBeam.phase(elapsed: context.date.timeIntervalSince(start)
                                            + EdgeBeam.stillHead * EdgeBeam.lapDuration))
            }
        } else {
            canvas(head: EdgeBeam.stillHead)
        }
    }

    private func canvas(head: Double) -> some View {
        let look = EdgeBeam.look(dark: dark)
        let segments = EdgeBeam.segments(head: head)
        let inset = CGFloat(EdgeBeam.inset(dark: dark))
        let outline = outline
        let color = color
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let path = outline.path(in: rect, inset: inset)
            // 柔光：同一串段，宽一点、模糊、很淡。
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: CGFloat(look.glowBlur)))
                for segment in segments {
                    glow.stroke(path.trimmedPath(from: CGFloat(segment.from), to: CGFloat(segment.to)),
                                with: .color(color.opacity(look.glowOpacity * segment.strength)),
                                style: StrokeStyle(lineWidth: CGFloat(look.glowWidth), lineCap: .butt))
                }
            }
            // 主线：细线，头亮尾淡。
            for segment in segments {
                context.stroke(path.trimmedPath(from: CGFloat(segment.from), to: CGFloat(segment.to)),
                               with: .color(color.opacity(look.lineOpacity * segment.strength)),
                               style: StrokeStyle(lineWidth: CGFloat(look.lineWidth), lineCap: .butt))
            }
        }
    }
}
