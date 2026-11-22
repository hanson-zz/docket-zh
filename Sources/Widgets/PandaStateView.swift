import AppKit
import SwiftUI

/// 小熊猫六状态的图：按名字读一次就留着（`Bundle.main.image` 会一起读 @2x）。
@MainActor
enum PandaStateArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard !missing.contains(name), let image = Bundle.main.image(forResource: name) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }

    static func exists(_ name: String) -> Bool { image(name) != nil }

    /// 这个样子该画的图名（正式素材优先，缺图回退），一张都没有时 nil。
    static func name(_ pose: PandaPose) -> String? {
        PandaStateResolver.imageName(pose, exists: exists)
    }
}

/// 面板里的主角小熊猫：给常态和一次短暂表态，自己解析成该画的图。
///
/// - 同一面板只放一只，状态之间淡入淡出（`PandaMotion.transition`）；
/// - 切进「完成」「提醒」时轻轻动一下（单次，不循环）；
/// - 待机有眨眼图时 10 到 20 秒眨一次（事件驱动的 `.task`，不做逐帧重绘）；
/// - 减弱动态效果时只换静帧；
/// - 方形画布按高度画、底部对齐（同一尺寸和底部锚点），不拦截任何点击。
struct PandaStateView: View {
    var base: PandaPose
    var pulse: PandaPulse? = nil
    var size: CGFloat
    /// 一张图都读不到时的符号（截图工具、素材缺失）；nil 时什么也不画。
    var fallbackSymbol: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 只为了表态到期后重新算一次；不是动画时钟。
    @State private var tick = 0
    @State private var blinking = false
    @State private var bounce = false

    init(_ state: PandaState, pulse: PandaPulse? = nil, size: CGFloat, fallbackSymbol: String? = nil) {
        self.base = .state(state)
        self.pulse = pulse
        self.size = size
        self.fallbackSymbol = fallbackSymbol
    }

    init(pose: PandaPose, pulse: PandaPulse? = nil, size: CGFloat, fallbackSymbol: String? = nil) {
        self.base = pose
        self.pulse = pulse
        self.size = size
        self.fallbackSymbol = fallbackSymbol
    }

    private var pose: PandaPose {
        _ = tick
        return PandaStateResolver.resolve(base: base, pulse: pulse, now: .now)
    }

    var body: some View {
        let shown = pose
        let state = shown.state
        let blinkName = PandaMotion.blinks(state, reduceMotion: reduceMotion,
                                           hasBlinkFrame: PandaStateArt.exists(PandaStateResolver.blinkName))
            ? PandaStateResolver.blinkName : nil
        let stateName = PandaStateArt.name(shown)
        // 眨眼只换一帧，不淡入淡出（动画只跟着状态图走）。
        let name = (blinking ? blinkName : nil) ?? stateName
        ZStack(alignment: .bottom) {
            if let name, let image = PandaStateArt.image(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .id(name)
                    .transition(.opacity)
            } else if let fallbackSymbol {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.panelSecondary)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size, alignment: .bottom)
        // 单次动作：以脚底为轴轻轻弹一下，0.9 秒内回原样。
        .scaleEffect(bounce ? 1.08 : 1, anchor: .bottom)
        .rotationEffect(.degrees(bounce && state == .alert ? -4 : 0), anchor: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: PandaMotion.transition), value: stateName)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: state, initial: false) { _, next in
            guard PandaMotion.playsOneShot(next, reduceMotion: reduceMotion) else { return }
            withAnimation(.spring(duration: PandaMotion.oneShot * 0.4, bounce: 0.5)) { bounce = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(PandaMotion.oneShot * 0.45))
                withAnimation(.easeOut(duration: PandaMotion.oneShot * 0.55)) { bounce = false }
            }
        }
        // 表态到期回常态：睡到 until 再算一次。
        .task(id: pulse) {
            guard let pulse else { return }
            let left = pulse.until.timeIntervalSinceNow
            guard left > 0 else { return }
            try? await Task.sleep(for: .seconds(left + 0.05))
            guard !Task.isCancelled else { return }
            tick &+= 1
        }
        // 待机偶尔眨眼：只在有眨眼图、没减弱动态效果时。
        .task(id: blinkName) {
            guard blinkName != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PandaMotion.blinkDelay(unit: .random(in: 0...1))))
                guard !Task.isCancelled else { return }
                blinking = true
                try? await Task.sleep(for: .seconds(PandaMotion.blinkDuration))
                blinking = false
            }
        }
    }
}

extension AIChatCenter {
    /// 这个服务最近一次 API 回答在哪一步；不是 API 方式（网页、App 拿不到回答）或者还没问过时 nil。
    func pandaPhase(_ service: AIService?) -> AIQuickResultPhase? {
        guard let service, mode(for: service) == .api else { return nil }
        guard let last = messages(service.id).last, last.role == .assistant else {
            return isGenerating(service.id) ? .thinking : nil
        }
        return AIQuickResult.phase(status: last.status, text: last.text)
    }
}
