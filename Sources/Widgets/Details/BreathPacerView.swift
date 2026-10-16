import SwiftUI

/// 环境音面板里的呼吸引导。
///
/// 一个会呼吸的圆：吸气时慢慢鼓起来，屏息时停住并亮一圈，呼气时缩回去，
/// 外面一圈细弧走完就是这一步结束。中间写着“吸气 4”这样的提示。
/// 点“开始”后才动；没开始时是一个安静的小圆，不占动画。
/// 节奏选择存在本机偏好里，所有环境音卡片共用。
struct BreathPacerView: View {
    var isPreview: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ambient.breathPattern") private var patternRaw = BreathPacer.Pattern.calm.rawValue
    @State private var startedAt: Date?

    private var pattern: BreathPacer.Pattern { BreathPacer.Pattern.parse(patternRaw) }
    private var running: Bool { startedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("呼吸引导")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 14) {
                TimelineView(.animation(minimumInterval: 1 / BreathPacer.framesPerSecond(
                    running: running, reduceMotion: reduceMotion), paused: !running)) { tick in
                    orb(now: tick.date)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(running ? "跟着圆圈呼吸，肩膀放松。" : "选一个节奏，跟着圆圈慢慢呼吸。")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        guard !isPreview else { return }
                        startedAt = running ? nil : .now
                    } label: {
                        Label(running ? "结束" : "开始", systemImage: running ? "stop.fill" : "wind")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Capsule().fill(.white.opacity(running ? 0.26 : 0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(running ? "结束呼吸引导" : "开始呼吸引导")
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .glassPane(cornerRadius: 12)
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
                .stroke(.white.opacity(0.12), lineWidth: 2)
            if let state {
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)],
                                     center: .center, startRadius: 2, endRadius: 40))
                .overlay {
                    Circle().strokeBorder(.white.opacity(holding ? 0.6 : 0.2), lineWidth: holding ? 1.5 : 0.5)
                }
                .scaleEffect(0.45 + 0.45 * fullness)
            VStack(spacing: 0) {
                Text(state?.phase.title ?? "准备")
                    .font(.system(size: 12, weight: .semibold))
                if let state {
                    Text("\(state.secondsLeft)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.map { "\($0.phase.title)，还剩 \($0.secondsLeft) 秒" } ?? "呼吸引导未开始")
    }
}
