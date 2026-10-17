import SwiftUI

/// 界面上可以被聚光灯照到的控件，各自报上自己的位置。
struct SpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 标一个聚光灯导览的目标，名字对应 `SpotlightStop.id`。
    func spotlightTarget(_ id: String) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// 压暗整个窗口、只留一个圆角亮洞的形状。亮洞的位置和大小可以动画，
/// 换站时亮洞从上一个控件滑到下一个，而不是一闪就换。
struct SpotlightShape: Shape {
    var hole: CGRect
    var corner: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y),
                             AnimatablePair(hole.size.width, hole.size.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        return path
    }
}

/// 聚光灯导览的一层：压暗、亮洞、亮洞边上一圈慢慢呼吸的光，和说明卡片。
///
/// 点卡片上的“下一步”或压暗的地方往下走，最后一站是“知道了”；Esc 或“跳过导览”随时结束。
/// 打开“减少动态效果”时亮洞直接跳到下一站，光圈不呼吸。
struct SpotlightOverlay: View {
    var stops: [SpotlightStop]
    var anchors: [String: Anchor<CGRect>]
    @Binding var index: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let calloutSize = CGSize(width: 290, height: 132)
    private let gap: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            if let current = index, stops.indices.contains(current) {
                let stop = stops[current]
                let target = anchors[stop.id].map { proxy[$0] } ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
                let hole = SpotlightTour.cutout(target, padding: 8, in: bounds)
                let center = SpotlightTour.calloutCenter(cutout: hole, size: calloutSize, gap: gap,
                                                         margin: 16, in: bounds)
                ZStack(alignment: .topLeading) {
                    SpotlightShape(hole: hole, corner: 14)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .contentShape(SpotlightShape(hole: hole, corner: 14), eoFill: true)
                        .onTapGesture { advance() }

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .scaleEffect(pulse ? 1.04 : 1)
                        .opacity(pulse ? 0.35 : 0.9)
                        .offset(x: hole.minX, y: hole.minY)
                        .allowsHitTesting(false)

                    callout(stop, at: current)
                        .frame(width: calloutSize.width)
                        .position(center)
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: current)
                .transition(.opacity)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                }
                .onDisappear { pulse = false }
            }
        }
    }

    private func callout(_ stop: SpotlightStop, at current: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stop.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(SpotlightTour.counter(index: current, total: stops.count))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(stop.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("跳过导览") { close() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if current > 0 {
                    Button("上一步") { move(to: current - 1) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                }
                Button {
                    advance()
                } label: {
                    Text(SpotlightTour.next(after: current, total: stops.count) == nil ? tr("知道了") : tr("下一步"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(Color.accentColor, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stop.title)。\(stop.message)")
    }

    private func advance() {
        guard let current = index else { return }
        if let next = SpotlightTour.next(after: current, total: stops.count) {
            move(to: next)
        } else {
            close()
        }
    }

    private func move(to next: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.4)) { index = next }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { index = nil }
    }
}
