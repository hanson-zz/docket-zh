import SwiftUI
import AppKit

/// 环境音面板里的呼吸引导。
///
/// 一个会呼吸的圆：吸气时慢慢鼓起来，屏息时停住并亮一圈，呼气时缩回去，
/// 外面一圈细弧走完就是这一步结束。中间写着“吸气 4”这样的提示。
/// 点“开始”后才动；没开始时是一个安静的小圆，不占动画。
/// 节奏选择存在本机偏好里，所有环境音卡片共用。
struct BreathPacerView: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var isPreview: Bool
    /// 环境音面板里默认收起，只留一行标题，点开才显示圆圈（面板不至于太高）。
    var collapsible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ambient.breathPattern") private var patternRaw = BreathPacer.Pattern.calm.rawValue
    @AppStorage("ambient.breathOpen") private var open = false
    @State private var startedAt: Date?

    /// 呼吸圆的亮芯：深色下白光，浅色玻璃上白色看不出来，换成淡淡的深色。
    private static let orbCore = Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.55),
                                                    light: NSColor.black.withAlphaComponent(0.12))

    private var pattern: BreathPacer.Pattern { BreathPacer.Pattern.parse(patternRaw) }
    private var running: Bool { startedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if collapsible {
                    Button {
                        open.toggle()
                        if !open { startedAt = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tr("呼吸引导"))
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(open ? tr("收起呼吸引导") : tr("展开呼吸引导"))
                } else {
                    Text("呼吸引导")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                }
                Spacer()
                Menu {
                    ForEach(BreathPacer.Pattern.allCases) { option in
                        Button {
                            patternRaw = option.rawValue
                            if running { startedAt = .now }
                        } label: {
                            if option == pattern {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Text(pattern.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if !collapsible || open {
                HStack(spacing: 14) {
                    TimelineView(.animation(minimumInterval: 1 / BreathPacer.framesPerSecond(
                        running: running, reduceMotion: reduceMotion), paused: !running)) { tick in
                        orb(now: tick.date)
                    }
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(running ? tr("跟着圆圈呼吸，肩膀放松。") : tr("选一个节奏，跟着圆圈慢慢呼吸。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            guard !isPreview else { return }
                            startedAt = running ? nil : .now
                        } label: {
                            Label(running ? tr("结束") : tr("开始"), systemImage: running ? "stop.fill" : "wind")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(Capsule().fill(running ? Color.panelRaised : Color.panelFill).panelLift(running))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(running ? tr("结束呼吸引导") : tr("开始呼吸引导"))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .glassPane(cornerRadius: 12)
            }
        }
    }

    @ViewBuilder
    private func orb(now: Date) -> some View {
        let state: BreathPacer.State? = startedAt.map {
            BreathPacer.state(elapsed: now.timeIntervalSince($0), pattern: pattern)
        }
        // 减少动态效果时圆圈不缩放，只换文字和外圈进度。
        let fullness = state.map { reduceMotion ? 0.6 : $0.fullness } ?? 0.25
        let holding = state?.phase == .holdIn || state?.phase == .holdOut
        ZStack {
            Circle()
                .stroke(.panelStroke, lineWidth: 2)
            if let state {
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(panelTint.accent(or: .panelSecondary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(RadialGradient(colors: [Self.orbCore, .panelFill],
                                     center: .center, startRadius: 2, endRadius: 40))
                .overlay {
                    Circle().strokeBorder(Color.panelPrimary.opacity(holding ? 0.6 : 0.2), lineWidth: holding ? 1.5 : 0.5)
                }
                .scaleEffect(0.45 + 0.45 * fullness)
            VStack(spacing: 0) {
                Text(state?.phase.title ?? tr("准备"))
                    .font(.system(size: 13, weight: .semibold))
                if let state {
                    Text("\(state.secondsLeft)")
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.panelPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.map { tr("\($0.phase.title)，还剩 \($0.secondsLeft) 秒") } ?? tr("呼吸引导未开始"))
    }
}
