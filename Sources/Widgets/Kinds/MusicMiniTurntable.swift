import AppKit
import SwiftUI

/// 正在播放「完整」卡片左边的小唱盘：银色唱盘（有素材用 Resources/Vinyl 的拉丝金属）、
/// 和黑胶面板同一套画法的唱片（`VinylDisc`，中心是封面）、不转的反光（`VinylSheen`）、
/// 银色唱臂。播放时唱片转、唱臂落在音轨上；暂停时停转、唱臂抬回支架。
/// `spinning` 为假（减弱动态效果、卡片看不见、预览）时不开时间线，唱片静止。
struct MusicMiniTurntable: View {
    var artwork: NSImage?
    var fallback: NSImage?
    var tint: ArtworkTint?
    var playing: Bool
    var spinning: Bool
    var dark: Bool

    /// 33⅓ 转每分钟，约每秒 200 度。
    private static let degreesPerSecond = 200.0
    private static let fps = 24.0

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let platter = d / 2
            let r = platter * 0.86
            let label = r * 0.34
            let scale = r / 110
            TimelineView(.animation(minimumInterval: 1 / Self.fps, paused: !spinning)) { tick in
                let angle = spinning
                    ? (tick.date.timeIntervalSinceReferenceDate * Self.degreesPerSecond)
                        .truncatingRemainder(dividingBy: 360)
                    : 0
                ZStack {
                    platterView(platter)
                        .frame(width: platter * 2, height: platter * 2)
                        .shadow(color: .black.opacity(dark ? 0.45 : 0.2), radius: 3, y: 2)
                    Circle()
                        .fill(.black.opacity(dark ? 0.55 : 0.32))
                        .frame(width: r * 2, height: r * 2)
                        .blur(radius: 1.2)
                        .offset(y: 0.8)
                    VinylDisc(radius: r, label: label, artwork: artwork ?? fallback, labelColor: labelColor,
                              scale: scale, texture: nil)
                        .frame(width: r * 2, height: r * 2)
                        .rotationEffect(.degrees(angle))
                    VinylSheen(radius: r, label: label, scale: scale, dark: dark)
                        .frame(width: r * 2, height: r * 2)
                    Circle()
                        .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.5)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 2.5))
                        .frame(width: 4, height: 4)
                }
                .frame(width: d, height: d)
                .overlay(alignment: .topLeading) { arm(d: d) }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func platterView(_ radius: CGFloat) -> some View {
        if let art = VinylArt.platter {
            Image(nsImage: art).resizable().interpolation(.high).brightness(dark ? -0.12 : 0)
        } else {
            Circle()
                .fill(AngularGradient(colors: dark ? [Color(white: 0.30), Color(white: 0.55), Color(white: 0.24),
                                                      Color(white: 0.42), Color(white: 0.30)]
                                                   : [Color(white: 0.80), Color(white: 0.98), Color(white: 0.74),
                                                      Color(white: 0.92), Color(white: 0.80)],
                                      center: .center, angle: .degrees(-35)))
                .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.22 : 0.75), lineWidth: 0.6))
        }
    }

    /// 唱臂：转轴在唱盘右上角外一点，竖着画再绕转轴转；播放 24 度落在音轨上，暂停 4 度搭在边上。
    @ViewBuilder
    private func arm(d: CGFloat) -> some View {
        let pivot = CGPoint(x: d * 0.97, y: d * 0.06)
        let length = d * 0.62
        let angle = playing ? 24.0 : 4.0
        if let art = VinylArt.tonearm {
            let height = length / CGFloat(VinylArt.armTip - VinylArt.armPivot.y)
            let width = height * CGFloat(VinylArt.armAspect)
            let anchor = UnitPoint(x: VinylArt.armPivot.x, y: VinylArt.armPivot.y)
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .brightness(dark ? -0.08 : 0)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0.5, y: 1)
                .rotationEffect(.degrees(angle), anchor: anchor)
                .position(x: pivot.x + width * (0.5 - anchor.x), y: pivot.y + height * (0.5 - anchor.y))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: playing)
        } else {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.7)], startPoint: .leading,
                                     endPoint: .trailing))
                .frame(width: 2.4, height: length)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(white: 0.85)).frame(width: 6, height: 9)
                }
                .rotationEffect(.degrees(angle), anchor: .top)
                .position(x: pivot.x, y: pivot.y + length / 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: playing)
        }
    }

    private var labelColor: Color {
        guard let tint else { return Color(white: 0.55) }
        let rgb = tint.glow
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
