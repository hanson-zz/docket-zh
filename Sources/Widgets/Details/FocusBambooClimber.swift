import SwiftUI

/// 专注计时面板进度环右边的竹竿：专注进行中小熊猫按进度顺着竹竿往上爬（0 在底，
/// 100% 到顶）；中途手动结束或重置时滑下来；完成一轮时到顶欢呼。竹篮按每天专注的
/// 分钟数给竹叶，这一轮的分钟已经由专注记录记上，这里只演欢呼、不改数据。
///
/// 码头 Pro（`ProLicenseGate.canUseFocusPanda`）：没解锁时竹竿旁是一只静态的小熊猫，
/// 点一下弹付费墙。面板每秒刷新一次，小熊猫跟着一秒挪一下，不另开计时器。
struct FocusBambooClimber: View {
    var state: TimerState
    var now: Date
    var unlocked: Bool
    var isPreview: Bool

    @State private var event: FocusPandaClimb.Event?
    @State private var slideOffset: CGFloat = 0
    @State private var cheerBounce = false

    static let width: CGFloat = 50
    static let poleHeight: CGFloat = 140
    private static let climberHeight: CGFloat = 30
    private static let cheerHeight: CGFloat = 38
    private static let staticHeight: CGFloat = 34

    private static let bambooLight = Color(hex: "#A5D46A")
    private static let bambooDeep = Color(hex: "#5E9A33")
    private static let bambooNode = Color(hex: "#3F6E1F")

    private var travel: CGFloat { Self.poleHeight - Self.climberHeight }

    var body: some View {
        let active = FocusPandaClimb.isActive(state)
        ZStack(alignment: .bottomTrailing) {
            if active || event != nil {
                pole
                    .padding(.trailing, 6)
                    .transition(.opacity)
                panda(active: active)
            }
        }
        .frame(width: Self.width, height: Self.poleHeight + 8, alignment: .bottomTrailing)
        .animation(.easeOut(duration: 0.25), value: active || event != nil)
        .onChange(of: state) { old, new in
            guard unlocked, !isPreview,
                  let next = FocusPandaClimb.event(from: old, to: new, now: .now) else { return }
            play(next, from: FocusPandaClimb.progress(old, now: .now))
        }
    }

    // MARK: 竹竿

    private var pole: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [Self.bambooLight, Self.bambooDeep],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 7, height: Self.poleHeight)
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(Self.bambooNode.opacity(0.75))
                        .frame(width: 9, height: 1.5)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.poleHeight)
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.bambooLight)
                .rotationEffect(.degrees(-35))
                .offset(x: 8, y: -5)
                .accessibilityHidden(true)
        }
        .frame(width: 20, height: Self.poleHeight)
        .accessibilityHidden(true)
    }

    // MARK: 小熊猫

    @ViewBuilder
    private func panda(active: Bool) -> some View {
        if !unlocked {
            // 免费：竹竿底下一只静态的小熊猫，点一下看 Pro。
            Button { PaywallWindow.shared.show() } label: {
                art("pet-panda-idle", height: Self.staticHeight)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .help(tr("小熊猫爬竹竿陪你专注是码头 Pro 专属。点一下购买、输入激活码或开始试用。"))
        } else if event == .cheer {
            art("pet-panda-cheer", height: Self.cheerHeight)
                .scaleEffect(cheerBounce ? 1.08 : 0.92, anchor: .bottom)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Self.bambooLight)
                        .offset(x: -4, y: cheerBounce ? -10 : 0)
                        .opacity(cheerBounce ? 1 : 0.4)
                        .accessibilityHidden(true)
                }
                .padding(.trailing, 4)
                .offset(y: -(Self.poleHeight - Self.cheerHeight + 4))
                .accessibilityLabel(tr("小熊猫爬到顶，欢呼"))
        } else if event == .slide {
            art(DesktopPetStrip.jump.imageName(2), height: Self.climberHeight)
                .padding(.trailing, 10)
                .offset(y: -slideOffset)
                .accessibilityLabel(tr("小熊猫滑下来了"))
        } else if active {
            let progress = FocusPandaClimb.progress(state, now: now)
            let running = state.paused == nil
            // 走着时一秒颠一下，看着在爬。
            let bob: CGFloat = running && Int(now.timeIntervalSince1970) % 2 == 1 ? 2 : 0
            art(DesktopPetStrip.jump.imageName(1), height: Self.climberHeight)
                .padding(.trailing, 10)
                .offset(y: -(CGFloat(FocusPandaClimb.climbOffset(progress: progress, travel: Double(travel))) + bob))
                .animation(.easeInOut(duration: 0.6), value: progress)
                .accessibilityLabel(tr("小熊猫爬到 \(Int((progress * 100).rounded()))%"))
        }
    }

    private func art(_ name: String, height: CGFloat) -> some View {
        Group {
            if let image = DesktopPetArt.image(name), image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: image.size.width * height / image.size.height, height: height)
            }
        }
    }

    // MARK: 动画

    private func play(_ next: FocusPandaClimb.Event, from progress: Double) {
        event = next
        switch next {
        case .slide:
            slideOffset = CGFloat(FocusPandaClimb.climbOffset(progress: progress, travel: Double(travel)))
            withAnimation(.easeIn(duration: 0.55)) { slideOffset = 0 }
            finish(after: 1.4, next)
        case .cheer:
            cheerBounce = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4).repeatCount(5, autoreverses: true)) {
                cheerBounce = true
            }
            finish(after: 3, next)
        }
    }

    private func finish(after seconds: Double, _ which: FocusPandaClimb.Event) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if event == which { event = nil }
        }
    }
}
