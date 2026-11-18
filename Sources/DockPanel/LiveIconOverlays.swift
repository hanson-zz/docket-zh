import SwiftUI

/// An opt-in visual accent for Finder in Dockling's shelf, not a replacement for Finder's artwork.
struct LiveFinderCompanion: View {
    var side: CGFloat
    var pointer: CGPoint?

    private var pupilOffset: CGSize {
        guard let pointer else { return .zero }
        let x = max(-1, min(1, (pointer.x / max(side, 1) - 0.5) * 2))
        let y = max(-1, min(1, (pointer.y / max(side, 1) - 0.5) * 2))
        return CGSize(width: x * side * 0.024, height: y * side * 0.024)
    }

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(.white.opacity(0.65), lineWidth: max(0.5, side * 0.013))
            HStack(spacing: side * 0.07) {
                eye
                eye
            }
            .offset(y: -side * 0.025)
            Image(systemName: "mouth")
                .resizable()
                .scaledToFit()
                .frame(width: side * 0.14)
                .offset(y: side * 0.11)
                .foregroundStyle(.primary)
        }
        .frame(width: side * 0.34, height: side * 0.34)
        .shadow(radius: side * 0.035, y: side * 0.015)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var eye: some View {
        Circle()
            .fill(.primary)
            .frame(width: side * 0.047, height: side * 0.061)
            .offset(pupilOffset)
    }
}

/// Shows only during an observed Chrome launch transition; it does not claim to
/// measure browser tab load activity or fabricate a percentage.
struct LiveChromeLaunchRing: View {
    var side: CGFloat
    var running: Bool

    @State private var visible = false
    @State private var turning = false
    @State private var dismissal: Task<Void, Never>?

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.78)
            .stroke(.white, style: StrokeStyle(lineWidth: max(2, side * 0.055), lineCap: .round))
            .padding(side * 0.017)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .opacity(visible ? 1 : 0)
            .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: turning)
            .animation(.easeOut(duration: 0.17), value: visible)
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
                    try? await Task.sleep(for: .milliseconds(1300))
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
