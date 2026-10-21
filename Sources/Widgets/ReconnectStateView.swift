import AppKit
import SwiftUI

/// 断网时天气和 GitHub 面板共用的状态：一个拔出来的插头对着插座，电线轻轻晃。
/// 点“重新连接”时插头推回插座、插口冒电光；这次还是没连上，插头再退出来；
/// 连上了，面板换回正常内容，这一块自然消失。
///
/// 两种尺寸：`full` 用在完全没有数据的时候，占住内容的位置；
/// `compact` 是一条细横幅，用在还有上次的数据、只是这次没刷新成功的时候。
///
/// 省电：只有拔着并且没开“减少动态效果”时才以 10 帧晃动，插着时是静止的图。
struct ReconnectStateView: View {
    enum Style { case full, compact }

    var title: String
    var detail: String? = nil
    /// 服务这会儿正在重试。
    var loading: Bool = false
    var style: Style = .full
    /// 不给就不显示按钮（比如节流期间不允许再点）。
    var retry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holding = false

    var body: some View {
        let phase = PlugReconnect.phase(loading: loading, holding: holding)
        switch style {
        case .full: full(phase)
        case .compact: compact(phase)
        }
    }

    // MARK: Layouts

    private func full(_ phase: PlugReconnect.Phase) -> some View {
        VStack(spacing: 10) {
            PlugArt(phase: phase, reduceMotion: reduceMotion)
                .frame(width: 136, height: 46)
            VStack(spacing: 3) {
                Text(phase == .reconnecting ? tr("正在重新连接…") : title)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                if let detail {
                    Text(detail)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if retry != nil {
                PanelButton(title: tr("重新连接"), symbol: "powerplug.fill", prominent: true) { press() }
                    .frame(maxWidth: 160)
                    .disabled(phase == .reconnecting)
                    .opacity(phase == .reconnecting ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .glassPane()
    }

    private func compact(_ phase: PlugReconnect.Phase) -> some View {
        HStack(spacing: 10) {
            PlugArt(phase: phase, reduceMotion: reduceMotion)
                .frame(width: 136, height: 46)
                .scaleEffect(0.5)
                .frame(width: 68, height: 23)
            VStack(alignment: .leading, spacing: 1) {
                Text(phase == .reconnecting ? tr("正在重新连接…") : title)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                if let detail {
                    Text(detail)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if retry != nil {
                Button { press() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 24, height: 24)
                        .background(Color.panelFillStrong, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(phase == .reconnecting)
                .help("重新连接")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassPane()
    }

    private func press() {
        holding = true
        retry?()
        Task {
            try? await Task.sleep(for: .seconds(PlugReconnect.minimumHold))
            holding = false
        }
    }
}

// MARK: - Art

/// 插座固定在右边，插头连着从左边过来的电线。全部用形状画，没有图片。
private struct PlugArt: View {
    var phase: PlugReconnect.Phase
    var reduceMotion: Bool

    var body: some View {
        let fps = PlugReconnect.framesPerSecond(phase, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? PlugReconnect.swayFPS), paused: fps == nil)) { clock in
            let t = clock.date.timeIntervalSinceReferenceDate
            let gap = PlugReconnect.gap(phase, t: t, reduceMotion: reduceMotion)
            let sag = PlugReconnect.sag(gap: gap, t: t, reduceMotion: reduceMotion)
            GeometryReader { proxy in
                let size = proxy.size
                let mid = size.height / 2
                // 插座宽 18，靠右；插头身 24 加插脚 7，插好时插脚有 5 进到插座里。
                let socketX = size.width - 18
                let pluggedLeft = socketX + 5 - 31
                let left = pluggedLeft - 34 * gap

                ZStack(alignment: .topLeading) {
                    Cord(end: left, sag: 14 * sag)
                        .stroke(.panelTertiary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    plug
                        .offset(x: left, y: mid - 9)

                    socket
                        .offset(x: socketX, y: mid - 15)

                    if phase == .reconnecting {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#FFD60A").panelReadable)
                            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                            .offset(x: socketX - 4, y: mid - 26)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.62), value: phase)
            }
        }
        .accessibilityHidden(true)
    }

    private var plug: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.panelPrimary.opacity(0.85))
                .frame(width: 24, height: 18)
            VStack(spacing: 6) {
                Capsule().fill(.panelPrimary.opacity(0.85)).frame(width: 7, height: 2.5)
                Capsule().fill(.panelPrimary.opacity(0.85)).frame(width: 7, height: 2.5)
            }
        }
    }

    private var socket: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(phase == .reconnecting ? Color.panelFillStrong : Color.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.panelQuaternary, lineWidth: 1)
            }
            .overlay {
                // 插孔：浅色下插座是白玻璃，压暗要比 .panelShade 深才看得见。
                let hole = Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.45),
                                              light: NSColor.black.withAlphaComponent(0.35))
                VStack(spacing: 5.5) {
                    Capsule().fill(hole).frame(width: 6, height: 3)
                    Capsule().fill(hole).frame(width: 6, height: 3)
                }
            }
            .frame(width: 18, height: 30)
    }
}

/// 从左边缘垂下来再接到插头尾部的一段电线。可动画，插头滑动时线跟着走。
private struct Cord: Shape {
    var end: CGFloat
    var sag: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(end, sag) }
        set { end = newValue.first; sag = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: 0, y: y + 4))
        path.addQuadCurve(to: CGPoint(x: max(end, 1), y: y),
                          control: CGPoint(x: max(end, 1) * 0.5, y: y + sag))
        return path
    }
}
