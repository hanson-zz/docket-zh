import AppKit
import SwiftUI

/// 喝水角色样式的主角：一只玻璃杯，水位是今天的进度；选的角色站在杯子
/// 旁边（不再缩成探头），身上还是原来那套灰/彩水位效果（见 `WaterPanda`：
/// 水面以下全彩、以上去饱和发灰，中间一条白色波浪水面），水位和杯子同步。
/// 表情跟着 `WaterMood` 换（举杯、欢呼、打盹），渴成骷髅时换成骷髅图（见
/// `WaterParched`），水照样从底下涨，喝一杯就复活。六只角色都一样。
///
/// 杯子用代码画，不用新图；角色用原来的图，所以六只角色都不用重画。
/// `phase` 为 nil 时水面不随时间动（扩展栏上一整天不重画），相位跟着水位
/// 走，涨水那半秒里杯子和角色的水面一起漂一段波；面板传自己的时钟让水面
/// 一直轻轻动。打开“减少动态效果”时直接跳到新水位。
struct WaterCupGauge: View {
    var character: WaterCharacter
    var mood: WaterMood
    /// 0...1 toward today's goal.
    var level: Double
    var celebrating: Bool
    var parched: Bool
    /// 杯子的高度。
    var height: CGFloat
    var reduceMotion: Bool
    /// 水面的相位（秒）；nil 是静止水面，见 `WaterCupPage.restingPhase`。
    var phase: Double? = nil
    /// 角色的高度是杯子的几成。
    var characterScale: CGFloat = 0.82
    /// 角色有这么一截（按角色宽度算）站到杯子前面，省一点宽度。
    var overlap: CGFloat = 0.1
    /// 面板里的大杯：多画刻度和杯壁高光。
    var detailed: Bool = false

    private var cupWidth: CGFloat { height * 0.64 }
    private var characterHeight: CGFloat { height * characterScale }
    private var characterWidth: CGFloat { characterHeight * CGFloat(character.aspect) }

    /// 整个组件的宽度，排版用。
    static func width(height: CGFloat, character: WaterCharacter,
                      characterScale: CGFloat = 0.82, overlap: CGFloat = 0.1) -> CGFloat {
        height * 0.64 + height * characterScale * CGFloat(character.aspect) * (1 - overlap)
    }

    var body: some View {
        let surface = phase ?? WaterCupPage.restingPhase(level: level)
        HStack(alignment: .bottom, spacing: -characterWidth * overlap) {
            WaterCupGlass(level: level, phase: surface, reduceMotion: reduceMotion, detailed: detailed)
                .frame(width: cupWidth, height: height)
            WaterPanda(character: character, mood: mood, level: level, phase: surface,
                       celebrating: celebrating, height: characterHeight, parched: parched,
                       reduceMotion: reduceMotion)
        }
        .frame(width: Self.width(height: height, character: character,
                                 characterScale: characterScale, overlap: overlap),
               height: height, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }
}

/// 只有杯子：杯身、水、白色波浪水面和杯沿。
struct WaterCupGlass: View {
    var level: Double
    var phase: Double
    var reduceMotion: Bool
    var detailed: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let cup = WaterCupShape()
            let amplitude = max(1, height * (detailed ? 0.02 : 0.03))
            ZStack {
                cup.fill(detailed ? Self.bigBody : WidgetStyle.primary.opacity(0.06))
                WaterWave(level: level, phase: phase, amplitude: amplitude)
                    .fill(LinearGradient(colors: [WaterStyle.water.opacity(detailed ? 0.55 : 0.7),
                                                  WaterStyle.water.opacity(detailed ? 0.8 : 0.9)],
                                         startPoint: .top, endPoint: .bottom))
                    .clipShape(cup)
                WaterWave(level: level, phase: phase, amplitude: amplitude, closed: false)
                    .stroke(WaterStyle.surface.opacity(level > 0.005 && level < 0.995 ? 0.9 : 0),
                            style: StrokeStyle(lineWidth: max(1, height / 40), lineCap: .round))
                    .clipShape(cup)
                if detailed {
                    // 25% / 50% / 75% 的刻度。
                    ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                        Capsule()
                            .fill(Self.bigTick)
                            .frame(width: width * 0.12, height: 1.2)
                            .position(x: width * 0.2, y: height * (1 - mark))
                    }
                    // 杯壁一道淡高光。
                    Capsule()
                        .fill(Self.bigHighlight)
                        .frame(width: 3.5, height: height * 0.7)
                        .rotationEffect(.degrees(-2))
                        .position(x: width * 0.84, y: height * 0.45)
                }
                cup.stroke(detailed ? Self.bigRim : WidgetStyle.primary.opacity(0.55),
                           style: StrokeStyle(lineWidth: max(1.2, height / (detailed ? 70 : 30)), lineJoin: .round))
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: level)
        }
    }
}

extension WaterCupGlass {
    // 面板大杯的杯身：深色下还是原来的深色杯身 + 白描边（杯里的百分比白字）；
    // 浅色玻璃上换成浅玻璃杯身 + 淡深色描边，杯里的百分比跟着用深字
    // （`percentInk`）。扩展栏小杯不走这里。
    static let bigBody = Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.28),
                                            light: NSColor.white.withAlphaComponent(0.55))
    static let bigRim = Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.6),
                                           light: NSColor.black.withAlphaComponent(0.28))
    static let bigTick = Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.4),
                                            light: NSColor.black.withAlphaComponent(0.25))
    static let bigHighlight = Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.12),
                                                 light: NSColor.white.withAlphaComponent(0.9))
    /// 杯里百分比的字色：深色下白，浅色下主文字色。
    static let percentInk = Color.panelPrimary
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
