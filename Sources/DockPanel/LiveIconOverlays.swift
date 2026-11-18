import SwiftUI

/// An opt-in visual accent for Finder in Dockling's shelf, not a replacement for Finder's artwork.
/// 小脸要一眼看得出：占图标一半大，眼白加黑眼珠跟着指针转，冒出时弹一下。
struct LiveFinderCompanion: View {
    var side: CGFloat
    var pointer: CGPoint?

    @State private var popped = false

    private var face: CGFloat { side * 0.5 }

    private var pupilOffset: CGSize {
        guard let pointer else { return .zero }
        let x = max(-1, min(1, (pointer.x / max(side, 1) - 0.5) * 2))
        let y = max(-1, min(1, (pointer.y / max(side, 1) - 0.5) * 2))
        return CGSize(width: x * face * 0.07, height: y * face * 0.07)
    }

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().fill(Color(red: 1.0, green: 0.84, blue: 0.45).opacity(0.55))
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1, face * 0.04))
            HStack(spacing: face * 0.1) {
                eye
                eye
            }
            .offset(y: -face * 0.08)
            Capsule()
                .fill(Color.black.opacity(0.8))
                .frame(width: face * 0.26, height: max(1.5, face * 0.06))
                .offset(y: face * 0.24)
        }
        .frame(width: face, height: face)
        .shadow(color: .black.opacity(0.35), radius: face * 0.08, y: face * 0.03)
        .scaleEffect(popped ? 1 : 0.4, anchor: .bottomTrailing)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: popped)
        .onAppear { popped = true }
        .onDisappear { popped = false }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white)
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: face * 0.13, height: face * 0.13)
                .offset(pupilOffset)
        }
        .frame(width: face * 0.26, height: face * 0.26)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: max(0.5, face * 0.015)))
    }
}

/// Shows only during an observed Chrome launch transition; it does not claim to
/// measure browser tab load activity or fabricate a percentage.
/// 粗一点、带深色描边，浅色深色桌面都看得见；转 2.2 秒，图标同时轻轻弹一下。
struct LiveChromeLaunchRing: View {
    var side: CGFloat
    var running: Bool

    @State private var visible = false
    @State private var turning = false
    @State private var dismissal: Task<Void, Never>?

    var body: some View {
        let width = max(3, side * 0.09)
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: width + max(1.5, side * 0.03), lineCap: .round))
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(
                    AngularGradient(colors: [.white.opacity(0.2), .white, Color(red: 1.0, green: 0.85, blue: 0.3)], center: .center),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
        }
        .padding(-side * 0.04)
        .rotationEffect(.degrees(turning ? 360 : 0))
        .scaleEffect(visible ? 1 : 0.7)
        .opacity(visible ? 1 : 0)
        .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: turning)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: running) { _, newValue in
            dismissal?.cancel()
            guard newValue else {
                visible = false
                turning = false
                return
            }
            visible = true
            turning = true
            dismissal = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2200))
                guard !Task.isCancelled else { return }
                visible = false
                turning = false
            }
        }
        .onDisappear {
            dismissal?.cancel()
            turning = false
        }
    }
}

/// A normalized, datasource-driven live icon progress visual for a future
/// verified AI usage provider. Unknown progress stays indeterminate.
struct LiveIconProgressRing: View {
    var side: CGFloat
    var state: LiveIconState
    var policy: LiveIconPolicy

    var body: some View {
        let presentation = policy.presentation(for: state)
        ZStack {
            switch presentation {
            case .staticIcon:
                EmptyView()
            case .staticProgress, .animatedProgress:
                Circle()
                    .trim(from: 0, to: state.normalizedProgress ?? 0.72)
                    .stroke(.cyan, style: StrokeStyle(lineWidth: max(1.5, side * 0.045), lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .completionMark:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .attentionMark:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
