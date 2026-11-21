import SwiftUI

/// Chrome、Safari 的动态图标，只在码头自己画的图标上加：
/// 悬停时 Chrome 圆盘轻转 15 度弹回、Safari 表盘轻摆停住（外壳不动）；
/// 当前网页真的在加载时，沿图标边缘走一道细蓝弧，加载完淡出；
/// 在下载时右下角挂蓝色下载徽标（Safari 带真实进度），在出声时挂紫色播放徽标加柔光。
/// 读不到就不画。减弱动态效果时不转、不走弧，徽标静态照挂。不拦鼠标。
struct LiveBrowserModifier: ViewModifier {
    var browser: LiveBrowser
    var side: CGFloat
    /// 开关开着且没开减弱动态效果。
    var active: Bool
    /// 开关开着（减弱动态效果时徽标仍挂）。
    var enabled: Bool
    var isRunning: Bool

    @State private var hoverCount = 0
    @State private var client = UUID()
    @State private var wanted = false

    private var chrome: ChromeLoadingMonitor { .shared }
    private var monitor: LiveBrowserMonitor { .shared }
    private var state: LiveBrowserState { enabled ? monitor.state(browser) : LiveBrowserState() }
    private var loading: Bool {
        guard active else { return false }
        return browser == .chrome ? chrome.loading : state.loading
    }
    private var corner: LiveBrowserState.Corner? { state.corner }

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
            .overlay {
                if let corner {
                    LiveBrowserCornerBadge(corner: corner, download: state.download, side: side)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: corner)
            .animation(.easeInOut(duration: 0.35), value: loading)
            .onHover { inside in
                if inside, active { hoverCount += 1 }
            }
            .onAppear {
                if browser == .chrome { chrome.want(client, active && isRunning) }
                setWanted(enabled && isRunning)
            }
            .onDisappear {
                if browser == .chrome { chrome.want(client, false) }
                setWanted(false)
            }
            .onChange(of: active && isRunning) { _, on in
                if browser == .chrome { chrome.want(client, on) }
            }
            .onChange(of: enabled && isRunning) { _, on in setWanted(on) }
    }

    private func setWanted(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        monitor.want(browser, on)
    }
}

/// 右下角的状态徽标：蓝底白色下载箭头（知道进度时外圈画进度），或紫底白色播放三角加一圈柔光。
private struct LiveBrowserCornerBadge: View {
    var corner: LiveBrowserState.Corner
    var download: LiveBrowserDownload
    var side: CGFloat

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let length = CGFloat(g.length)
        let d = max(10, length * 0.4)
        let line = max(1.5, d * 0.1)
        let fill = corner == .download
            ? LinearGradient(colors: [Color(hex: "#4DA8FF"), Color(hex: "#1F6BFF")], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: "#B07CFF"), Color(hex: "#7B3DF0")], startPoint: .top, endPoint: .bottom)
        ZStack {
            if corner == .playing {
                // 柔光：沿图标内容区一圈淡紫，静态，不呼吸。
                RoundedRectangle(cornerRadius: CGFloat(g.corner), style: .continuous)
                    .stroke(Color(hex: "#A66BFF").opacity(0.55), lineWidth: max(1.5, length * 0.035))
                    .frame(width: length, height: length)
                    .shadow(color: Color(hex: "#A66BFF").opacity(0.6), radius: length * 0.08)
            }
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: line * 0.8)
                if corner == .download, case .fraction(let f) = download {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, f)))
                        .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(line * 1.4)
                }
                Image(systemName: corner == .download ? "arrow.down" : "play.fill")
                    .font(.system(size: d * (corner == .download ? 0.46 : 0.4), weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: corner == .playing ? d * 0.04 : 0)
            }
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.25), radius: d * 0.08, y: d * 0.04)
            .offset(x: length / 2 - d * 0.32, y: length / 2 - d * 0.32)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 加载中：沿图标内容区圆角边走的一道细蓝弧，不确定进度，一圈 1 秒。
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
