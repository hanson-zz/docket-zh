import AppKit
import SwiftUI

/// 喝水角色样式的主角：一只玻璃杯，水位是今天的进度；选的角色缩小到杯子
/// 右下角探个头，表情跟着 `WaterMood` 换（举杯、欢呼、打盹），渴成骷髅时
/// 换成骷髅图（见 `WaterParched`），喝一杯就复活。
///
/// 杯子用代码画，不用新图；角色用原来的图，所以六只角色都不用重画。
/// 水面不随时间动（扩展栏上一整天不重画），涨水时平滑过渡，打开“减少动态
/// 效果”时直接跳到新水位。
struct WaterCupGauge: View {
    var character: WaterCharacter
    var mood: WaterMood
    /// 0...1 toward today's goal.
    var level: Double
    var celebrating: Bool
    var parched: Bool
    /// 杯子的高度；角色约为它的一半。
    var height: CGFloat
    var reduceMotion: Bool

    private var cupWidth: CGFloat { height * 0.64 }
    private var peekHeight: CGFloat { height * 0.5 }
    private var peekWidth: CGFloat { peekHeight * CGFloat(character.aspect) }
    /// 角色有一部分压在杯子上，只多占这么宽。
    private var overhang: CGFloat { peekWidth * 0.62 }

    private var picture: NSImage? {
        if parched, let skeleton = WaterArt.skeleton(character) { return skeleton }
        return WaterArt.image(character, mood)
    }

    var body: some View {
        let cup = WaterCupShape()
        let amplitude = max(1, height * 0.03)
        ZStack(alignment: .bottomLeading) {
            ZStack {
                cup.fill(WidgetStyle.primary.opacity(0.06))
                WaterWave(level: level, phase: 0.3, amplitude: amplitude)
                    .fill(LinearGradient(colors: [WaterStyle.water.opacity(0.7), WaterStyle.water.opacity(0.9)],
                                         startPoint: .top, endPoint: .bottom))
                    .clipShape(cup)
                WaterWave(level: level, phase: 0.3, amplitude: amplitude, closed: false)
                    .stroke(WaterStyle.surface.opacity(level > 0.005 && level < 0.995 ? 0.9 : 0),
                            style: StrokeStyle(lineWidth: max(1, height / 40), lineCap: .round))
                    .clipShape(cup)
                cup.stroke(WidgetStyle.primary.opacity(0.55),
                           style: StrokeStyle(lineWidth: max(1.2, height / 30), lineJoin: .round))
            }
            .frame(width: cupWidth, height: height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: level)

            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: peekWidth, height: peekHeight)
                    .id(parched ? "skeleton" : mood.rawValue)
                    .transition(.opacity)
                    .offset(x: cupWidth + overhang - peekWidth)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mood)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: parched)
            }
        }
        .frame(width: cupWidth + overhang, height: height, alignment: .bottomLeading)
        .overlay(alignment: .topLeading) {
            if celebrating, !parched {
                Image(systemName: "sparkles")
                    .font(.system(size: max(7, height * 0.22), weight: .semibold))
                    .foregroundStyle(Color(hex: PaletteColor.yellow.hex))
                    .offset(x: cupWidth - height * 0.1, y: -height * 0.06)
                    .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 上宽下窄、底角圆一点的玻璃杯轮廓。
struct WaterCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        let taper = rect.width * 0.11
        let radius = min(rect.width * 0.14, rect.height * 0.1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - taper, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - taper - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - taper, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + taper + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + taper, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX + taper, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 一排小杯：满了的是水的颜色，没满的是淡淡的空杯。
struct WaterCupRow: View {
    var filled: Int
    var slots: Int
    var cupWidth: CGFloat
    var spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<slots, id: \.self) { index in
                let full = index < filled
                SmallCupShape()
                    .fill(full ? WaterStyle.water.opacity(0.9) : WidgetStyle.primary.opacity(0.15))
                    .frame(width: cupWidth, height: cupWidth * 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 小杯：一个倒梯形。
struct SmallCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        let taper = rect.width * 0.16
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - taper, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + taper, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
