import SwiftUI
import AppKit
import CoreImage

/// 信息、微信、邮件图标的「消息未读」动态：只在码头自己画的图标上加，不改 App 本身的图标。
///
/// 简洁（默认）：原色不变，右上角红色角标，来新消息时角标和图标轻弹一次。
/// 趣味：按未读数分级换色（2 到 3 条蓝、4 到 6 条紫、7 到 8 条紫粉、9 条及以上红粉），
/// 角标旁挂闪光、火焰或液滴，都是静态挂件，只有新消息那一下弹。白色气泡转色相后仍是白的，
/// 原来的标志一直认得出。读不到未读数时什么都不画。减弱动态效果时不弹，只换状态。
struct LiveBadgeModifier: ViewModifier {
    var app: LiveBadgeApp
    var side: CGFloat
    /// 设置里的预览：传入演示读数时不读程序坞。
    var demo: LiveBadgeReading?
    var demoPulse: Int = 0
    /// 程序坞上的格子传入图标原图：换色用 Core Image 先画好一张盖上去，不靠 SwiftUI 的
    /// hueRotation 滤镜（真机上码头扩展栏里这个滤镜不生效，图标一直是原色）。
    var image: NSImage?

    @AppStorage(LiveBadgeStyle.key) private var styleRaw = LiveBadgeStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var monitor: LiveBadgeMonitor { .shared }
    private var mail: MailActivityMonitor { .shared }
    private var mailCorner: LiveMailActivity.Corner? {
        app == .mail && demo == nil ? mail.activity.corner : nil
    }

    func body(content: Content) -> some View {
        let reading = demo ?? monitor.reading(app)
        let look = LiveBadgeLook.of(app, reading: reading, style: LiveBadgeStyle(stored: styleRaw))
        let trigger = demo == nil ? monitor.pulseGeneration(app) : demoPulse
        content
            .hueRotation(.degrees(image == nil ? look.hueRotation : 0))
            .overlay {
                if let image, look.hueRotation != 0, let tinted = LiveBadgeTint.shared.image(image, degrees: look.hueRotation) {
                    Image(nsImage: tinted)
                        .resizable()
                        .interpolation(.high)
                        .id(look.hueRotation)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: look.hueRotation)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : trigger) { view, scale in
                view.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.08, duration: 0.22, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .smooth)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let text = look.badgeText {
                    LiveBadgeChip(text: text, accent: look.accent, side: side, trigger: trigger,
                                  animate: !reduceMotion)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: look.badgeText == nil)
            .overlay {
                // 邮件来新信时左上角闪三道光，跟未读数轻弹同一次。
                if app == .mail, !reduceMotion {
                    LiveMailSparkle(side: side, trigger: trigger)
                }
            }
            .overlay {
                if let mailCorner {
                    LiveMailCornerBadge(corner: mailCorner, side: side, animate: !reduceMotion)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: mailCorner)
            .task(id: demo == nil) {
                guard demo == nil else { return }
                monitor.retain()
                if app == .mail { mail.retain() }
                defer {
                    monitor.release()
                    if app == .mail { mail.release() }
                }
                // 一直挂着，视图消失时任务取消才退出。
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            }
    }
}

/// 右上角的红色角标和它旁边的挂件。
private struct LiveBadgeChip: View {
    var text: String
    var accent: LiveBadgeAccent
    var side: CGFloat
    var trigger: Int
    var animate: Bool

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let diameter = max(10, side * (text.isEmpty ? 0.18 : 0.3))
        let font = max(9, diameter * 0.62)
        ZStack {
            accentView(diameter: diameter)
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#FF5A4E"), Color(hex: "#E5242B")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: max(0.8, diameter * 0.06)))
                .frame(width: text.count > 1 ? diameter * (0.55 + 0.32 * CGFloat(text.count)) : diameter,
                       height: diameter)
                .shadow(color: .black.opacity(0.25), radius: diameter * 0.08, y: diameter * 0.05)
                .overlay {
                    if !text.isEmpty {
                        Text(verbatim: text)
                            .font(.system(size: font, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, diameter * 0.14)
                    }
                }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: animate ? trigger : 0) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.3, duration: 0.18, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.55, spring: .bouncy)
            }
        }
        // 角标中心大约压在图标内容区右上角往里一点，和系统程序坞的位置相近。
        .offset(x: -(CGFloat(g.inset) - diameter * 0.18), y: CGFloat(g.inset) - diameter * 0.18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func accentView(diameter: CGFloat) -> some View {
        switch accent {
        case .none:
            EmptyView()
        case .sparkle:
            Image(systemName: "sparkle")
                .font(.system(size: diameter * 0.55, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFE37A"), Color(hex: "#FFB020")],
                                                startPoint: .top, endPoint: .bottom))
                .offset(x: diameter * 0.55, y: -diameter * 0.5)
        case .flame:
            Image(systemName: "flame.fill")
                .font(.system(size: diameter * 0.7, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFD54A"), Color(hex: "#FF6A1F")],
                                                startPoint: .top, endPoint: .bottom))
                .offset(y: -diameter * 0.62)
        case .drip:
            // 角标下沿挂两滴红色液滴，一长一短，不动。
            HStack(alignment: .top, spacing: diameter * 0.16) {
                drop(width: diameter * 0.16, height: diameter * 0.34)
                drop(width: diameter * 0.2, height: diameter * 0.5)
            }
            .offset(x: -diameter * 0.04, y: diameter * 0.55)
        }
    }

    private func drop(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: "#E5242B"), Color(hex: "#C0141C")],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
    }
}

/// 新邮件：左上角三道暖白短光，0.9 秒内亮起再淡掉。平时完全透明。
private struct LiveMailSparkle: View {
    var side: CGFloat
    var trigger: Int

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let length = CGFloat(g.length)
        let ray = max(3, length * 0.16)
        let line = max(1.5, length * 0.045)
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color(hex: "#FFE7A3"))
                    .frame(width: line, height: ray)
                    .offset(y: -ray * 0.9)
                    .rotationEffect(.degrees(-80 + Double(i) * 32))
            }
        }
        .shadow(color: Color(hex: "#FFC94D").opacity(0.7), radius: line)
        .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, t in
            view.opacity(t).scaleEffect(0.7 + 0.3 * t)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.01)
                SpringKeyframe(1.0, duration: 0.25, spring: .snappy)
                LinearKeyframe(1.0, duration: 0.3)
                LinearKeyframe(0.0, duration: 0.35)
            }
        }
        .offset(x: -length * 0.42, y: -length * 0.42)
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 邮件右下角：撰写中挂一支橙色铅笔，发送中挂一圈转动的小蓝环。
private struct LiveMailCornerBadge: View {
    var corner: LiveMailActivity.Corner
    var side: CGFloat
    var animate: Bool

    var body: some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let length = CGFloat(g.length)
        let d = max(10, length * 0.38)
        let line = max(1.5, d * 0.13)
        ZStack {
            Circle().fill(.white)
                .shadow(color: .black.opacity(0.25), radius: d * 0.08, y: d * 0.04)
            switch corner {
            case .composing:
                Image(systemName: "pencil")
                    .font(.system(size: d * 0.56, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFB340"), Color(hex: "#FF7A1A")],
                                                    startPoint: .top, endPoint: .bottom))
            case .sending:
                if animate {
                    TimelineView(.animation(minimumInterval: LiveIconMotion.frameInterval(
                        .spin, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))) { context in
                        let head = LiveBrowserRing.head(at: context.date.timeIntervalSinceReferenceDate)
                        sendingRing(line: line).rotationEffect(.degrees(head * 360))
                    }
                } else {
                    sendingRing(line: line)
                }
            }
        }
        .frame(width: d, height: d)
        .offset(x: length / 2 - d * 0.32, y: length / 2 - d * 0.32)
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sendingRing(line: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(LinearGradient(colors: [Color(hex: "#9AD4FF"), Color(hex: "#1F7BFF")],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: line, lineCap: .round))
            .padding(line * 1.3)
    }
}

/// 消息未读换色：用 Core Image 的色相旋转把图标画成新的一张，按图标和角度缓存。
@MainActor
final class LiveBadgeTint {
    static let shared = LiveBadgeTint()
    private let context = CIContext()
    private var cache: [String: NSImage] = [:]

    func image(_ source: NSImage, degrees: Double) -> NSImage? {
        let key = "\(ObjectIdentifier(source).hashValue)-\(Int(degrees.rounded()))"
        if let hit = cache[key] { return hit }
        var rect = CGRect(origin: .zero, size: source.size)
        guard let cg = source.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let filter = CIFilter(name: "CIHueAdjust") else { return nil }
        filter.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        filter.setValue(degrees * .pi / 180, forKey: kCIInputAngleKey)
        guard let output = filter.outputImage,
              let rendered = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        else { return nil }
        let result = NSImage(cgImage: rendered, size: source.size)
        if cache.count > 40 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
