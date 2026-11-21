import SwiftUI

/// Chrome、Safari 的动态图标，只在码头自己画的图标上加：
/// 悬停时 Chrome 圆盘轻转 15 度弹回、Safari 表盘轻摆停住（外壳不动）；
/// Chrome 当前标签页真的在加载时，沿图标边缘走一道细蓝弧，加载完淡出。
/// 读不到加载状态时不画弧。减弱动态效果时两样都不做。不拦鼠标。
struct LiveBrowserModifier: ViewModifier {
    var browser: LiveBrowser
    var side: CGFloat
    /// 开关开着且没开减弱动态效果。
    var active: Bool
    var isRunning: Bool

    @State private var hoverCount = 0
    @State private var client = UUID()

    private var chrome: ChromeLoadingMonitor { .shared }
    private var loading: Bool { browser == .chrome && active && chrome.loading }

    func body(content: Content) -> some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let dial = CGFloat(g.length * browser.dialFraction)
        content
            .overlay {
                if active {
                    // 同一张图标裁成中间一圈盖在原图上转：外壳留在原位不动。
                    content
                        .frame(width: side, height: side)
                        .mask { Circle().frame(width: dial, height: dial) }
                        .keyframeAnimator(initialValue: 0.0, trigger: hoverCount) { view, angle in
                            view.rotationEffect(.degrees(angle))
                        } keyframes: { _ in
                            let k = browser.hoverKeyframes + [0, 0]
                            KeyframeTrack {
                                SpringKeyframe(k[0], duration: 0.2, spring: .bouncy)
                                SpringKeyframe(k[1], duration: 0.3, spring: .bouncy)
                                SpringKeyframe(k[2], duration: 0.3, spring: .smooth)
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if loading {
                    LiveBrowserRingView(side: side)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: loading)
            .onHover { inside in
                if inside, active { hoverCount += 1 }
            }
            .onAppear { if browser == .chrome { chrome.want(client, active && isRunning) } }
            .onDisappear { if browser == .chrome { chrome.want(client, false) } }
            .onChange(of: active && isRunning) { _, on in
                if browser == .chrome { chrome.want(client, on) }
            }
    }
}

/// Chrome 加载中：沿图标内容区圆角边走的一道细蓝弧，不确定进度，一圈 1 秒。
private struct LiveBrowserRingView: View {
    var side: CGFloat

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let length = CGFloat(g.length)
        let line = max(1.5, length * 0.045)
        let interval = LiveIconMotion.frameInterval(.spin, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        TimelineView(.animation(minimumInterval: interval)) { context in
            let head = LiveBrowserRing.head(at: context.date.timeIntervalSinceReferenceDate)
            let shape = RoundedRectangle(cornerRadius: CGFloat(g.corner), style: .continuous)
            ZStack {
                shape.stroke(Color(hex: "#7CC4FF").opacity(0.22), lineWidth: line)
                arc(shape, from: head - LiveBrowserRing.arc, to: head, line: line)
                if head < LiveBrowserRing.arc {
                    // 弧跨过起点时补上前一段。
                    arc(shape, from: 1 + head - LiveBrowserRing.arc, to: 1, line: line)
                }
            }
            .frame(width: length - line, height: length - line)
            .shadow(color: Color(hex: "#3D9BFF").opacity(0.45), radius: line)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func arc(_ shape: RoundedRectangle, from: Double, to: Double, line: CGFloat) -> some View {
        shape
            .trim(from: max(0, from), to: min(1, to))
            .stroke(LinearGradient(colors: [Color(hex: "#9AD4FF"), Color(hex: "#1F7BFF")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: line, lineCap: .round))
    }
}
