import AppKit
import SwiftUI

// 收音机的三款复古皮肤：木壳电子管、晶体管便携、数码卡座。
//
// 全部用 SwiftUI 代码画：木纹、布纹、打孔网、拉丝金属、段码、VU 表和琴键都是
// Canvas 和渐变，唯一的位图是复用的小熊猫贴纸（Resources/Pet/pet-panda-idle.png）。
// 配色和布局照设计稿 design/radio-retro.py：面板内容宽 288pt（320 减两边 16），
// 卡片 212 × 62。刻度上的 FM 数字是按收藏顺序排的位置（见 `RadioDial.frequency`），
// 指针跟着频道走，换台时动画移过去，打开“减少动态效果”时直接跳到位。
// 实心按钮上的图标一律深色；字最小 13pt。

// MARK: - 颜色

enum RadioRetroInk {
    static let amber = Color(hex: "#FFA53A")
    static let amberDeep = Color(hex: "#E07A10")
    static let red = Color(hex: "#FF5A48")
    /// 红色压在深色面板上做小字时浅一档（#FF5A48 在当前行的淡红底上只有约 3.6:1，
    /// 这个约 4.7:1 起）。
    static let redText = Color(hex: "#FF8577")
    static let vfd = Color(hex: "#7CF5A4")
    static let led = Color(hex: "#2FBF6A")
    static let inkWood = Color(hex: "#2A1606")
    static let inkRed = Color(hex: "#2A0703")
    static let inkMetal = Color(hex: "#1C1F23")
    static let brass = Color(hex: "#C9A25A")
    static let ivory = Color(hex: "#EADBB8")
    static let cream = Color(hex: "#F3E3C3")
    static let dialInk = Color(hex: "#3A2410")
    static let scaleInk = Color(hex: "#2B2B2B")
    static let chromeLight = Color(hex: "#DFE1E5")

    static let chrome = Gradient(stops: [
        .init(color: Color(hex: "#F4F5F7"), location: 0), .init(color: Color(hex: "#A4A7AD"), location: 0.35),
        .init(color: Color(hex: "#E3E5E8"), location: 0.6), .init(color: Color(hex: "#7D8087"), location: 1),
    ])
    static let metalKey = Gradient(colors: [Color(hex: "#F2F3F5"), Color(hex: "#B7BBC1")])
}

extension RadioSkin {
    /// 皮肤的强调色：琥珀、红、VFD 绿。经典是原来的暖橙。
    var accent: Color {
        switch self {
        case .classic: Color(hex: "#FF9F2E")
        case .wood: RadioRetroInk.amber
        case .transistor: RadioRetroInk.red
        case .deck: RadioRetroInk.vfd
        }
    }

    /// 深色面板上小字（13pt 上下）用的强调色，对背景至少 4.5:1。琥珀和 VFD 绿
    /// 本身够亮，红换成浅一档的 `redText`。
    var textAccent: Color {
        switch self {
        case .transistor: RadioRetroInk.redText
        default: accent
        }
    }

    /// 实心按钮上的深色图标。
    var ink: Color {
        switch self {
        case .classic, .deck: RadioRetroInk.inkMetal
        case .wood: RadioRetroInk.inkWood
        case .transistor: RadioRetroInk.inkRed
        }
    }
}

// MARK: - 画法

/// 可复现的随机数：木纹、皮革颗粒、拉丝每次画得一样。
struct RadioGrainRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// Canvas 里共用的几样画法，坐标都是 pt。
enum RadioRetroDraw {
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func line(_ c: inout GraphicsContext, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                     _ color: Color, _ width: CGFloat, round: Bool = false) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt))
    }

    /// 13pt 起的标签，`anchor` 决定对齐；y 是字的竖直中线。
    static func label(_ c: inout GraphicsContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 13,
                      weight: Font.Weight = .semibold, color: Color, anchor: UnitPoint = .leading) {
        c.draw(Text(verbatim: text).font(.system(size: size, weight: weight)).monospacedDigit().foregroundStyle(color),
               at: CGPoint(x: x, y: y), anchor: anchor)
    }

    /// 胡桃木纹：一条条起伏的细线，深浅两色。
    static func woodGrain(_ c: inout GraphicsContext, _ rect: CGRect, seed: UInt64, lines: Int) {
        var rnd = RadioGrainRandom(seed: seed)
        for i in 0..<lines {
            let spread: Double = Double(i) + rnd.next() * 0.6
            let y: Double = Double(rect.minY) + spread * Double(rect.height) / Double(lines)
            let amp: Double = 1.2 + rnd.next() * 2.6
            let phase: Double = rnd.next() * 6
            var path = Path()
            for k in 0...40 {
                let step = Double(k)
                let x: Double = Double(rect.minX) + Double(rect.width) * step / 40
                let wave: Double = amp * sin(step / 40 * 8.82 + phase) + 0.8 * sin(step * 0.9 + phase)
                let point = CGPoint(x: x, y: y + wave)
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let dark = rnd.next() < 0.65
            let opacity = 0.10 + rnd.next() * 0.22
            let width = 0.5 + rnd.next() * 1.1
            c.stroke(path, with: .color((dark ? Color(hex: "#2A1408") : Color(hex: "#9A6338")).opacity(opacity)),
                     lineWidth: width)
        }
    }

    /// 七段数码管的一位。`on` 为亮的段，其余只留一层暗影。
    static func segmentDigit(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                             char: Character, color: Color, ghost: Double) {
        let map: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
                                        "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"]
        let th = w * 0.19
        let skew = w * 0.12
        let hm = h / 2
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + px + skew * (1 - py / h), y: y + py)
        }
        let segments: [(Character, [(CGFloat, CGFloat)])] = [
            ("a", [(th * 0.6, 0), (w - th * 0.6, 0), (w - th * 1.3, th), (th * 1.3, th)]),
            ("d", [(th * 1.3, h - th), (w - th * 1.3, h - th), (w - th * 0.6, h), (th * 0.6, h)]),
            ("g", [(th, hm), (th * 1.6, hm - th / 2), (w - th * 1.6, hm - th / 2), (w - th, hm),
                   (w - th * 1.6, hm + th / 2), (th * 1.6, hm + th / 2)]),
            ("f", [(0, th * 0.6), (th, th * 1.3), (th, hm - th * 0.7), (0, hm - th * 0.2)]),
            ("e", [(0, hm + th * 0.2), (th, hm + th * 0.7), (th, h - th * 1.3), (0, h - th * 0.6)]),
            ("b", [(w, th * 0.6), (w, hm - th * 0.2), (w - th, hm - th * 0.7), (w - th, th * 1.3)]),
            ("c", [(w, hm + th * 0.2), (w, h - th * 0.6), (w - th, h - th * 1.3), (w - th, hm + th * 0.7)]),
        ]
        let lit = map[char] ?? ""
        for (name, corners) in segments {
            var path = Path()
            path.addLines(corners.map { point($0.0, $0.1) })
            path.closeSubpath()
            c.fill(path, with: .color(color.opacity(lit.contains(name) ? 1 : ghost)))
        }
    }

    /// 一串段码字（数字、空格和小数点），返回画完后的右边 x。
    @discardableResult
    static func segmentText(_ c: inout GraphicsContext, _ text: String, x: CGFloat, y: CGFloat, h: CGFloat,
                            color: Color, ghost: Double = 0.08) -> CGFloat {
        let w = h * 0.56
        var cursor = x
        for char in text {
            if char == "." {
                c.fill(circle(cursor - h * 0.04, y + h - h * 0.07, h * 0.075), with: .color(color))
                cursor += h * 0.16
            } else {
                segmentDigit(&c, x: cursor, y: y, w: w, h: h, char: char, color: color, ghost: ghost)
                cursor += w + h * 0.26
            }
        }
        return cursor
    }

    /// 镀铬喇叭网上的打孔：六边形排布的小黑孔，只画在圆里。
    static func perforation(_ c: inout GraphicsContext, cx: CGFloat, cy: CGFloat, radius: CGFloat,
                            spacing: CGFloat, hole: CGFloat) {
        let rows = Int(radius / (spacing * 0.866)) + 1
        let cols = Int(radius / spacing) + 1
        var path = Path()
        for j in -rows...rows {
            for i in -cols...cols {
                let hx = cx + CGFloat(i) * spacing + (abs(j) % 2 == 1 ? spacing / 2 : 0)
                let hy = cy + CGFloat(j) * spacing * 0.866
                let dx = hx - cx, dy = hy - cy
                if dx * dx + dy * dy < radius * radius { path.addPath(circle(hx, hy, hole)) }
            }
        }
        c.fill(path, with: .color(Color(hex: "#141416").opacity(0.92)))
    }
}

// MARK: - 小熊猫贴纸

/// 白色模切底加小熊猫原图，略微歪着贴。
struct RadioPandaSticker: View {
    var height: CGFloat
    var tilt: Double

    var body: some View {
        let width = height * 191 / 256
        ZStack {
            RoundedRectangle(cornerRadius: (width + 6) / 2.4, style: .continuous)
                .fill(Color(hex: "#FBF7EF"))
                .overlay(RoundedRectangle(cornerRadius: (width + 6) / 2.4, style: .continuous)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 0.6))
                .frame(width: width + 6, height: height + 5)
            if let image = PandaArt.image("pet-panda-idle") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width + 6, height: height + 5)
        .rotationEffect(.degrees(tilt))
        .accessibilityHidden(true)
    }
}

// MARK: - 面板：机身

/// 面板顶上的机身，按皮肤换。`onTune` 换到某个收藏，`onNext` 换下一台。
struct RadioRetroFace: View {
    var skin: RadioSkin
    var count: Int
    var index: Int
    var playing: Bool
    var volume: Double
    var stationName: String
    var animated: Bool
    var onTune: (Int) -> Void
    var onNext: () -> Void

    var body: some View {
        switch skin {
        case .classic:
            EmptyView()
        case .wood:
            RadioWoodFace(count: count, index: index, playing: playing, volume: volume,
                          onTune: onTune, onNext: onNext)
        case .transistor:
            RadioTransistorFace(count: count, index: index, playing: playing, onTune: onTune, onNext: onNext)
        case .deck:
            RadioDeckFace(count: count, index: index, playing: playing, stationName: stationName,
                          animated: animated, onTune: onTune)
        }
    }
}

/// 指针动画：换台时弹过去，减少动态效果时直接到位。
private struct NeedleMotion: ViewModifier {
    var value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.18), value: value)
    }
}

// MARK: 木壳电子管

struct RadioWoodFace: View {
    var count: Int
    var index: Int
    var playing: Bool
    var volume: Double
    var onTune: (Int) -> Void
    var onNext: () -> Void

    nonisolated static let size = CGSize(width: 288, height: 200)
    /// 刻度窗和刻度的位置。
    nonisolated static let window = CGRect(x: 14, y: 12, width: 260, height: 58)
    nonisolated static let scaleStart: CGFloat = 72
    nonisolated static let scaleEnd: CGFloat = 256
    nonisolated static let knobRadius: CGFloat = 22
    nonisolated static let volumeKnob = CGPoint(x: 40, y: 122)
    nonisolated static let tuneKnob = CGPoint(x: 248, y: 122)

    private var fraction: Double { RadioDial.dialFraction(RadioDial.frequency(index, count: count)) }

    var body: some View {
        let needleX = Self.scaleStart + (Self.scaleEnd - Self.scaleStart) * CGFloat(fraction)
        ZStack(alignment: .topLeading) {
            Canvas { c, _ in
                Self.drawCabinet(&c, count: count, index: index, playing: playing, volume: volume)
            }
            .frame(width: Self.size.width, height: Self.size.height)

            // 琥珀细指针，外面一圈淡光。
            ZStack {
                Capsule().fill(RadioRetroInk.amber.opacity(0.28)).frame(width: 6)
                Capsule().fill(RadioRetroInk.amberDeep).frame(width: 1.8)
            }
            .frame(width: 6, height: Self.window.height - 6)
            .offset(x: needleX - 3, y: Self.window.minY + 3)
            .modifier(NeedleMotion(value: index))
            .allowsHitTesting(false)

            RadioPandaSticker(height: 28, tilt: -10)
                .offset(x: 178 - 3, y: 154 - 2.5)
                .allowsHitTesting(false)

            // 点或拖刻度窗：换到最近的收藏。
            Color.clear
                .frame(width: Self.window.width, height: Self.window.height)
                .contentShape(.rect)
                .offset(x: Self.window.minX, y: Self.window.minY)
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard count > 0 else { return }
                    let x = Self.window.minX + value.location.x
                    let f = Double((x - Self.scaleStart) / (Self.scaleEnd - Self.scaleStart))
                    let target = RadioDial.nearestStation(toFraction: f, count: count)
                    if target != index { onTune(target) }
                })
                .help(tr("点刻度换台"))
                .accessibilityLabel(tr("调谐刻度"))
                .accessibilityValue(RadioDial.fmText(index, count: count))

            Button(action: onNext) {
                Circle().fill(Color.clear).frame(width: Self.knobRadius * 2, height: Self.knobRadius * 2)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: Self.tuneKnob.x - Self.knobRadius, y: Self.tuneKnob.y - Self.knobRadius)
            .disabled(count < 2)
            .help(tr("下一个电台"))
            .accessibilityLabel(tr("下一个电台"))
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    nonisolated static func drawCabinet(_ c: inout GraphicsContext, count: Int, index: Int, playing: Bool, volume: Double) {
        typealias D = RadioRetroDraw
        let w = size.width, h = size.height
        c.fill(D.rr(1, 3, w, h, 16), with: .color(.black.opacity(0.4)))
        let body = D.rr(0, 0, w, h, 16)
        c.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: Color(hex: "#7A4628"), location: 0), .init(color: Color(hex: "#5A321B"), location: 0.45),
            .init(color: Color(hex: "#3F2111"), location: 1),
        ]), startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
        c.drawLayer { layer in
            layer.clip(to: body)
            D.woodGrain(&layer, CGRect(x: 0, y: 0, width: w, height: h), seed: 7, lines: 26)
        }
        c.stroke(D.rr(0.5, 0.5, w - 1, h - 1, 15.5), with: .color(Color(hex: "#FFD9A8").opacity(0.22)), lineWidth: 1)
        c.stroke(D.rr(6, 6, w - 12, h - 12, 11), with: .color(Color(hex: "#1A0B03").opacity(0.35)), lineWidth: 1)

        // 刻度窗：黄铜框、奶油色玻璃，播放时灯亮一些。
        let win = window
        c.fill(D.rr(win.minX - 3, win.minY - 3, win.width + 6, win.height + 6, 9), with: .color(RadioRetroInk.brass))
        c.stroke(D.rr(win.minX - 3, win.minY - 3, win.width + 6, win.height + 6, 9),
                 with: .color(Color(hex: "#5A3A10").opacity(0.6)), lineWidth: 0.8)
        let glass = D.rr(win.minX, win.minY, win.width, win.height, 6)
        c.fill(glass, with: .linearGradient(Gradient(colors: [Color(hex: "#F7E7C0"), Color(hex: "#E8CB8D")]),
                                           startPoint: CGPoint(x: 0, y: win.minY), endPoint: CGPoint(x: 0, y: win.maxY)))
        c.fill(glass, with: .radialGradient(Gradient(colors: [Color(hex: "#FFC56A").opacity(playing ? 0.55 : 0.2),
                                                              Color(hex: "#FFC56A").opacity(0)]),
                                           center: CGPoint(x: win.midX, y: win.midY), startRadius: 0,
                                           endRadius: win.width * 0.6))
        let ink = RadioRetroInk.dialInk
        D.label(&c, "FM", x: win.minX + 10, y: win.minY + 17.5, weight: .heavy, color: ink)
        D.label(&c, "MHz", x: win.minX + 10, y: win.minY + 41.5, color: ink.opacity(0.8))
        let x0 = scaleStart, x1 = scaleEnd
        for f in 88...108 {
            let x = x0 + CGFloat(f - 88) / 20 * (x1 - x0)
            let major = f % 4 == 0
            D.line(&c, x, win.minY + 30, x, win.minY + (major ? 44 : 38), ink.opacity(0.85), major ? 1.2 : 0.8)
            if major { D.label(&c, String(f), x: x, y: win.minY + 16.5, color: ink, anchor: .center) }
        }
        D.line(&c, x0, win.minY + 30, x1, win.minY + 30, ink.opacity(0.6), 0.8)
        for (station, mhz) in RadioDial.frequencies(count: count).enumerated() {
            let x = x0 + CGFloat(RadioDial.dialFraction(mhz)) * (x1 - x0)
            c.fill(D.circle(x, win.minY + 50, 2.2), with: .color(ink.opacity(station == index ? 0.95 : 0.5)))
        }
        c.fill(D.rr(win.minX, win.minY, win.width, 7, 3), with: .color(.white.opacity(0.28)))

        // 喇叭网：拱顶，米色布纹，几根竖木条，顶上一颗魔眼。
        let gx: CGFloat = 80, gy: CGFloat = 82, gw: CGFloat = 128, gh: CGFloat = 106
        var arch = Path()
        arch.move(to: CGPoint(x: gx, y: gy + gh))
        for step in 0...32 {
            let angle: Double = Double.pi + Double.pi * Double(step) / 32
            let half: CGFloat = gw / 2
            arch.addLine(to: CGPoint(x: gx + half + half * CGFloat(cos(angle)), y: gy + 30 + 30 * CGFloat(sin(angle))))
        }
        arch.addLine(to: CGPoint(x: gx + gw, y: gy + gh))
        arch.closeSubpath()
        c.stroke(arch, with: .color(RadioRetroInk.brass), lineWidth: 6)
        c.fill(arch, with: .color(Color(hex: "#E6D6B4")))
        c.drawLayer { layer in
            layer.clip(to: arch)
            var warp = Path()
            var y = gy + 0.6
            while y < gy + gh {
                warp.move(to: CGPoint(x: gx, y: y))
                warp.addLine(to: CGPoint(x: gx + gw, y: y))
                y += 1.2
            }
            layer.stroke(warp, with: .color(Color(hex: "#B9A47C").opacity(0.75)), lineWidth: 0.55)
            var weft = Path()
            var x = gx + 0.6
            while x < gx + gw {
                weft.move(to: CGPoint(x: x, y: gy))
                weft.addLine(to: CGPoint(x: x, y: gy + gh))
                x += 1.2
            }
            layer.stroke(weft, with: .color(.white.opacity(0.35)), lineWidth: 0.45)
            for k in 0..<6 {
                let bx = gx + 14 + CGFloat(k) * 20
                D.line(&layer, bx, gy, bx, gy + gh, Color(hex: "#7A5A30").opacity(0.22), 2.2)
            }
        }
        c.stroke(arch, with: .color(Color(hex: "#3A2008").opacity(0.5)), lineWidth: 1)
        drawMagicEye(&c, cx: gx + gw / 2, cy: gy + 26, r: 9, tuned: playing)

        drawKnob(&c, center: volumeKnob, r: knobRadius, turn: volume / 100, label: tr("音量"))
        let tuned = RadioDial.dialFraction(RadioDial.frequency(index, count: count))
        drawKnob(&c, center: tuneKnob, r: knobRadius, turn: count > 0 ? tuned : 0.5, label: tr("调台"))
    }

    /// 魔眼：调准（播放中）时阴影扇区收窄。
    nonisolated static func drawMagicEye(_ c: inout GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, tuned: Bool) {
        typealias D = RadioRetroDraw
        c.fill(D.circle(cx, cy, r + 3.5), with: .color(RadioRetroInk.brass))
        c.fill(D.circle(cx, cy, r + 2), with: .color(Color(hex: "#120A04")))
        c.fill(D.circle(cx, cy, r), with: .radialGradient(Gradient(stops: [
            .init(color: Color(hex: "#FFE2A8"), location: 0), .init(color: RadioRetroInk.amber, location: 0.45),
            .init(color: Color(hex: "#7A3A06"), location: 1),
        ]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        let spread = (tuned ? 14.0 : 40.0) * Double.pi / 180
        var sector = Path()
        sector.move(to: CGPoint(x: cx, y: cy))
        sector.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(-Double.pi / 2 - spread),
                      endAngle: .radians(-Double.pi / 2 + spread), clockwise: false)
        sector.closeSubpath()
        c.fill(sector, with: .color(Color(hex: "#2A1204").opacity(0.85)))
        c.fill(D.circle(cx, cy, r * 0.32), with: .color(Color(hex: "#1A0D05")))
        c.fill(D.circle(cx, cy, r + 9), with: .color(RadioRetroInk.amber.opacity(tuned ? 0.1 : 0.04)))
    }

    /// 胶木旋钮：滚花一圈，指示线按 `turn`（0 到 1）在 -135° 到 135° 之间转。
    nonisolated static func drawKnob(_ c: inout GraphicsContext, center: CGPoint, r: CGFloat, turn: Double, label: String) {
        typealias D = RadioRetroDraw
        let cx = center.x, cy = center.y
        c.fill(D.circle(cx + 1.2, cy + 2, r + 1), with: .color(.black.opacity(0.35)))
        c.fill(D.circle(cx, cy, r), with: .radialGradient(Gradient(stops: [
            .init(color: Color(hex: "#7A4A2C"), location: 0), .init(color: Color(hex: "#3B1F10"), location: 0.55),
            .init(color: Color(hex: "#160A04"), location: 1),
        ]), center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        for k in 0..<28 {
            let a: Double = 2 * Double.pi * Double(k) / 28
            let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
            let inner: CGFloat = r - 3.2, outer: CGFloat = r - 0.4
            D.line(&c, cx + inner * ca, cy + inner * sa, cx + outer * ca, cy + outer * sa, .black.opacity(0.45), 1)
        }
        c.fill(D.circle(cx, cy, r * 0.62), with: .color(.black.opacity(0.18)))
        c.fill(D.circle(cx - r * 0.2, cy - r * 0.25, r * 0.28), with: .color(.white.opacity(0.07)))
        let a = (-135 + 270 * min(max(turn, 0), 1)) * Double.pi / 180
        let reach: CGFloat = r * 0.7
        D.line(&c, cx, cy, cx + reach * CGFloat(sin(a)), cy - reach * CGFloat(cos(a)), Color(hex: "#EBD9B4").opacity(0.9), 2.2,
               round: true)
        D.label(&c, label, x: cx, y: cy + r + 15.5, color: RadioRetroInk.cream, anchor: .center)
    }
}

// MARK: 晶体管便携

struct RadioTransistorFace: View {
    var count: Int
    var index: Int
    var playing: Bool
    var onTune: (Int) -> Void
    var onNext: () -> Void

    /// 机身 288 × 196；天线和拨轮伸出机身顶上，多画 44pt，排版时让回去。
    nonisolated static let bodySize = CGSize(width: 288, height: 196)
    nonisolated static let top: CGFloat = 44
    nonisolated static let scale = CGRect(x: 190, y: 20, width: 82, height: 162)
    nonisolated static var scaleStart: CGFloat { scale.minY + 38 }
    nonisolated static var scaleEnd: CGFloat { scale.maxY - 12 }
    nonisolated static let wheel = CGRect(x: 210, y: -10, width: 62, height: 22)

    private var fraction: Double { RadioDial.dialFraction(RadioDial.frequency(index, count: count)) }

    var body: some View {
        let t = Self.top
        let needleY = Self.scaleStart + (Self.scaleEnd - Self.scaleStart) * CGFloat(fraction)
        ZStack(alignment: .topLeading) {
            Canvas { c, _ in
                Self.drawSet(&c, count: count, index: index)
            }
            .frame(width: Self.bodySize.width, height: Self.bodySize.height + t)

            // 红指针横切刻度，左边一个小三角。
            Canvas { c, size in
                RadioRetroDraw.line(&c, 3, size.height / 2, size.width - 3, size.height / 2, RadioRetroInk.red, 2)
                var tip = Path()
                tip.move(to: CGPoint(x: 3, y: size.height / 2 - 5))
                tip.addLine(to: CGPoint(x: 10, y: size.height / 2))
                tip.addLine(to: CGPoint(x: 3, y: size.height / 2 + 5))
                tip.closeSubpath()
                c.fill(tip, with: .color(RadioRetroInk.red))
            }
            .frame(width: Self.scale.width, height: 12)
            .offset(x: Self.scale.minX, y: t + needleY - 6)
            .modifier(NeedleMotion(value: index))
            .allowsHitTesting(false)

            RadioPandaSticker(height: 28, tilt: 8)
                .offset(x: 130 - 3, y: t + 132 - 2.5)
                .allowsHitTesting(false)

            Color.clear
                .frame(width: Self.scale.width, height: Self.scale.height)
                .contentShape(.rect)
                .offset(x: Self.scale.minX, y: t + Self.scale.minY)
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard count > 0 else { return }
                    let y = Self.scale.minY + value.location.y
                    let f = Double((y - Self.scaleStart) / (Self.scaleEnd - Self.scaleStart))
                    let target = RadioDial.nearestStation(toFraction: f, count: count)
                    if target != index { onTune(target) }
                })
                .help(tr("点刻度换台"))
                .accessibilityLabel(tr("调谐刻度"))
                .accessibilityValue(RadioDial.fmText(index, count: count))

            // 拨轮只露出 22pt 高，点击区上下各让出 3pt，凑够 28pt。
            Button(action: onNext) {
                Rectangle().fill(Color.clear).frame(width: Self.wheel.width, height: Self.wheel.height + 6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .offset(x: Self.wheel.minX, y: t + Self.wheel.minY - 3)
            .disabled(count < 2)
            .help(tr("下一个电台"))
            .accessibilityLabel(tr("下一个电台"))
        }
        .frame(width: Self.bodySize.width, height: Self.bodySize.height + t, alignment: .topLeading)
        .padding(.top, -t)
    }

    nonisolated static func drawSet(_ c: inout GraphicsContext, count: Int, index: Int) {
        typealias D = RadioRetroDraw
        let t = top
        let w = bodySize.width, h = bodySize.height
        // 天线（压在机身后）。
        let ax: CGFloat = 194, ay = t + 4, tx: CGFloat = 160, ty: CGFloat = 2
        D.line(&c, ax, ay, tx, ty, Color(hex: "#8D9097"), 3.2, round: true)
        D.line(&c, ax, ay, tx, ty, Color(hex: "#F2F3F5").opacity(0.9), 1.2, round: true)
        for f: CGFloat in [0.35, 0.65] {
            c.fill(D.circle(ax + (tx - ax) * f, ay + (ty - ay) * f, 2.2), with: .color(Color(hex: "#C9CCD2")))
        }
        c.fill(D.circle(tx, ty + 1.5, 3.4), with: .color(Color(hex: "#E8EAEE")))
        c.stroke(D.circle(tx, ty + 1.5, 3.4), with: .color(Color(hex: "#6B6E75")), lineWidth: 0.8)

        // 镀铬边框和皮革，带颗粒和缝线。
        let chrome = GraphicsContext.Shading.linearGradient(RadioRetroInk.chrome, startPoint: CGPoint(x: 0, y: t),
                                                           endPoint: CGPoint(x: w * 0.2, y: t + h))
        c.fill(D.rr(1, t + 3, w, h, 20), with: .color(.black.opacity(0.45)))
        c.fill(D.rr(0, t, w, h, 20), with: chrome)
        let leather = D.rr(6, t + 6, w - 12, h - 12, 14)
        c.fill(leather, with: .linearGradient(Gradient(colors: [Color(hex: "#45332A"), Color(hex: "#22180F")]),
                                              startPoint: CGPoint(x: 6, y: t + 6),
                                              endPoint: CGPoint(x: w * 0.4, y: t + h)))
        c.drawLayer { layer in
            layer.clip(to: leather)
            var rnd = RadioGrainRandom(seed: 11)
            for _ in 0..<520 {
                let x = CGFloat(6 + rnd.next() * Double(w - 12))
                let y = CGFloat(Double(t) + 6 + rnd.next() * Double(h - 12))
                let r = CGFloat(0.4 + rnd.next() * 0.9)
                let dark = rnd.next() < 0.6
                let opacity = 0.18 + rnd.next() * 0.2
                layer.fill(D.circle(x, y, r), with: .color((dark ? Color.black : Color(hex: "#8A6A55")).opacity(opacity)))
            }
        }
        c.stroke(D.rr(11, t + 11, w - 22, h - 22, 10), with: .color(Color(hex: "#B08A6C").opacity(0.55)),
                 style: StrokeStyle(lineWidth: 0.9, dash: [3, 2.2]))

        // 顶上露出一截的竖拨轮。
        let wh = wheel
        c.fill(D.rr(wh.minX, t + wh.minY, wh.width, wh.height, 8), with: .linearGradient(Gradient(stops: [
            .init(color: Color(hex: "#2A2A2E"), location: 0), .init(color: Color(hex: "#5A5C62"), location: 0.5),
            .init(color: Color(hex: "#1C1C1F"), location: 1),
        ]), startPoint: CGPoint(x: wh.minX, y: 0), endPoint: CGPoint(x: wh.maxX, y: 0)))
        for k in 1..<15 {
            let x = wh.minX + CGFloat(k) * wh.width / 15
            D.line(&c, x, t + wh.minY + 2, x, t + wh.maxY - 6, .black.opacity(0.55), 1.2)
            D.line(&c, x + 0.9, t + wh.minY + 2, x + 0.9, t + wh.maxY - 6, .white.opacity(0.18), 0.5)
        }

        // 大圆打孔喇叭网。
        let gcx: CGFloat = 86, gcy = t + h / 2, gr: CGFloat = 74
        c.fill(D.circle(gcx + 1, gcy + 2.5, gr), with: .color(.black.opacity(0.4)))
        c.fill(D.circle(gcx, gcy, gr), with: chrome)
        c.fill(D.circle(gcx, gcy, gr - 5), with: .radialGradient(Gradient(stops: [
            .init(color: Color(hex: "#F2F3F5"), location: 0), .init(color: Color(hex: "#B8BBC1"), location: 0.7),
            .init(color: Color(hex: "#7D8087"), location: 1),
        ]), center: CGPoint(x: gcx - gr * 0.2, y: gcy - gr * 0.3), startRadius: 0, endRadius: gr * 1.4))
        c.drawLayer { layer in
            layer.clip(to: D.circle(gcx, gcy, gr - 7))
            D.perforation(&layer, cx: gcx, cy: gcy, radius: gr - 9, spacing: 6.4, hole: 1.9)
        }
        c.fill(D.circle(gcx, gcy, 15), with: chrome)
        c.stroke(D.circle(gcx, gcy, 15), with: .color(Color(hex: "#6B6E75")), lineWidth: 0.8)
        D.label(&c, "6", x: gcx, y: gcy, weight: .heavy, color: RadioRetroInk.inkMetal, anchor: .center)

        // 竖向刻度窗。
        let s = scale.offsetBy(dx: 0, dy: t)
        c.fill(D.rr(s.minX - 3, s.minY - 3, s.width + 6, s.height + 6, 9), with: chrome)
        c.fill(D.rr(s.minX, s.minY, s.width, s.height, 6),
               with: .linearGradient(Gradient(colors: [Color(hex: "#F4ECDA"), Color(hex: "#E6D9BC")]),
                                     startPoint: CGPoint(x: 0, y: s.minY), endPoint: CGPoint(x: 0, y: s.maxY)))
        let ink = RadioRetroInk.scaleInk
        D.label(&c, "FM", x: s.minX + 10, y: s.minY + 15.5, weight: .heavy, color: ink)
        D.label(&c, "MHz", x: s.maxX - 8, y: s.minY + 15.5, color: ink.opacity(0.8), anchor: .trailing)
        let y0 = scaleStart + t, y1 = scaleEnd + t
        for f in 88...108 {
            let y = y0 + CGFloat(f - 88) / 20 * (y1 - y0)
            let major = f % 4 == 0
            D.line(&c, s.minX + 10, y, s.minX + (major ? 26 : 19), y, ink.opacity(0.85), major ? 1.1 : 0.7)
            if major { D.label(&c, String(f), x: s.minX + 34, y: y, color: ink) }
        }
        for (station, mhz) in RadioDial.frequencies(count: count).enumerated() {
            let y = y0 + CGFloat(RadioDial.dialFraction(mhz)) * (y1 - y0)
            c.fill(D.circle(s.maxX - 9, y, 2.2), with: .color(ink.opacity(station == index ? 0.95 : 0.45)))
        }
        c.fill(D.rr(s.minX, s.minY, s.width, 6, 3), with: .color(.white.opacity(0.35)))
    }
}

// MARK: 数码卡座

struct RadioDeckFace: View {
    var count: Int
    var index: Int
    var playing: Bool
    var stationName: String
    var animated: Bool
    var onTune: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static let size = CGSize(width: 288, height: 214)
    nonisolated static let screen = CGRect(x: 12, y: 30, width: 264, height: 72)
    nonisolated static let meterY: CGFloat = 114
    nonisolated static let meterSize = CGSize(width: 128, height: 48)
    nonisolated static let keyY: CGFloat = 172

    var body: some View {
        let vfd = RadioRetroInk.vfd
        let s = Self.screen
        ZStack(alignment: .topLeading) {
            Canvas { c, _ in
                Self.drawChassis(&c, count: count, index: index, playing: playing)
            }
            .frame(width: Self.size.width, height: Self.size.height)

            Text(verbatim: stationName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(vfd)
                .shadow(color: vfd.opacity(0.55), radius: 1.6)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: s.width - 130, alignment: .leading)
                .offset(x: s.minX + 12, y: s.minY + 7)

            RadioPandaSticker(height: 21, tilt: 6)
                .offset(x: 254 - 3, y: 5 - 2.5)
                .allowsHitTesting(false)

            meters
                .offset(x: 12, y: Self.meterY)
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                ForEach(0..<RadioDial.presetKeys, id: \.self) { key in presetKey(key) }
            }
            .offset(x: 12, y: Self.keyY)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    // VU 表：表盘静态，表针按播放状态做假动画（不读真实电平）。
    private var meters: some View {
        let active = animated && playing && !reduceMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { tick in
            let time = tick.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { channel in
                    let level: Double = !playing ? 0
                        : (active ? RadioVU.level(time: time, channel: channel) : RadioVU.still[channel])
                    Canvas { c, size in
                        Self.drawMeter(&c, size: size, label: channel == 0 ? "L" : "R", level: level)
                    }
                    .frame(width: Self.meterSize.width + 4, height: Self.meterSize.height + 4)
                    .padding(-2)
                    .frame(width: Self.meterSize.width, height: Self.meterSize.height)
                }
            }
        }
    }

    private func presetKey(_ key: Int) -> some View {
        let station = RadioDial.presetStation(key: key, count: count)
        let pressed = RadioDial.pressedKey(index: index, count: count) == key
        let off: CGFloat = pressed ? 2 : 0
        return Button {
            if let station, station != index { onTune(station) }
        } label: {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.black.opacity(0.4))
                    .frame(height: 30)
                    .offset(y: 3)
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: pressed
                                             ? [Color(hex: "#D6D9DD"), Color(hex: "#A9ADB3")]
                                             : [Color(hex: "#F7F8F9"), Color(hex: "#D3D6DA")],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
                    Text(verbatim: String(key + 1))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(RadioRetroInk.inkMetal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Capsule()
                        .fill(pressed ? RadioRetroInk.led : .black.opacity(0.25))
                        .frame(width: 6, height: 3)
                        .padding(.top, 5)
                        .padding(.trailing, 6)
                }
                .frame(height: 30 - off)
                .offset(y: off)
            }
            .frame(width: 48, height: 33, alignment: .top)
            .contentShape(.rect)
            .opacity(station == nil ? 0.45 : 1)
            .modifier(NeedleMotion(value: index))
        }
        .buttonStyle(.plain)
        .disabled(station == nil)
        .help(station.map { _ in tr("预设 \(key + 1)") } ?? tr("没有这个预设"))
        .accessibilityLabel(tr("预设 \(key + 1)"))
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }

    nonisolated static func drawChassis(_ c: inout GraphicsContext, count: Int, index: Int, playing: Bool) {
        typealias D = RadioRetroDraw
        let w = size.width, h = size.height
        c.fill(D.rr(1, 3, w, h, 12), with: .color(.black.opacity(0.45)))
        let body = D.rr(0, 0, w, h, 12)
        c.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: Color(hex: "#E2E4E7"), location: 0), .init(color: Color(hex: "#BFC2C7"), location: 0.5),
            .init(color: Color(hex: "#CDD0D4"), location: 1),
        ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        c.drawLayer { layer in
            layer.clip(to: body)
            var rnd = RadioGrainRandom(seed: 5)
            for _ in 0..<110 {
                let y = CGFloat(rnd.next() * Double(h))
                let light = rnd.next() < 0.5
                let opacity = 0.05 + rnd.next() * 0.12
                D.line(&layer, 0, y, w, y, (light ? Color.white : Color.black).opacity(opacity), 0.35)
            }
        }
        c.stroke(D.rr(0.5, 0.5, w - 1, h - 1, 11.5), with: .color(.white.opacity(0.6)), lineWidth: 1)
        D.label(&c, tr("立体声 · 数码调谐"), x: 12, y: 15.5, weight: .bold, color: RadioRetroInk.inkMetal.opacity(0.85))

        // VFD 屏。
        let s = screen
        let vfd = RadioRetroInk.vfd
        c.fill(D.rr(s.minX - 3, s.minY - 3, s.width + 6, s.height + 6, 8), with: .color(Color(hex: "#2A2C30")))
        c.fill(D.rr(s.minX, s.minY, s.width, s.height, 6),
               with: .linearGradient(Gradient(colors: [Color(hex: "#0E1411"), Color(hex: "#070A08")]),
                                     startPoint: CGPoint(x: 0, y: s.minY), endPoint: CGPoint(x: 0, y: s.maxY)))
        for k in 1..<24 {
            D.line(&c, s.minX + 4, s.minY + CGFloat(k) * 3, s.maxX - 4, s.minY + CGFloat(k) * 3, vfd.opacity(0.035), 0.3)
        }
        c.drawLayer { lit in
            lit.addFilter(.shadow(color: vfd.opacity(0.55), radius: 1.6))
            D.label(&lit, "FM", x: s.minX + 12, y: s.minY + 53.5, weight: .heavy, color: vfd)
            let mhz = RadioDial.frequency(index, count: count)
            let end = D.segmentText(&lit, RadioDial.segmentText(mhz), x: s.minX + 40, y: s.minY + 32, h: 30,
                                    color: vfd)
            D.label(&lit, "MHz", x: end + 6, y: s.minY + 56.5, weight: .bold, color: vfd)
            let bars = playing ? 4 : 1
            for k in 0..<5 {
                let bh = 5 + CGFloat(k) * 3.4
                lit.fill(D.rr(s.maxX - 58 + CGFloat(k) * 9, s.minY + 26 - bh, 6, bh, 1),
                         with: .color(vfd.opacity(k < bars ? 1 : 0.12)))
            }
            let stereo = playing ? 1.0 : 0.15
            lit.stroke(D.rr(s.maxX - 104, s.minY + 9, 28, 18, 3), with: .color(vfd.opacity(stereo)), lineWidth: 1)
            D.label(&lit, "ST", x: s.maxX - 90, y: s.minY + 18, weight: .heavy, color: vfd.opacity(stereo),
                    anchor: .center)
            D.label(&lit, RadioDial.presetLabel(index: index, count: count), x: s.maxX - 12, y: s.minY + 56.5,
                    weight: .heavy, color: vfd, anchor: .trailing)
        }
        c.fill(D.rr(s.minX, s.minY, s.width, 8, 3), with: .color(.white.opacity(0.06)))
    }

    /// 一只 VU 表，画在留了 2pt 边的画布里。`level` 0 到 1。
    nonisolated static func drawMeter(_ c: inout GraphicsContext, size: CGSize, label: String, level: Double) {
        typealias D = RadioRetroDraw
        let x: CGFloat = 2, y: CGFloat = 2
        let w = size.width - 4, h = size.height - 4
        c.fill(D.rr(0, 0, size.width, size.height, 6), with: .color(Color(hex: "#2A2C30")))
        let face = D.rr(x, y, w, h, 4)
        c.fill(face, with: .linearGradient(Gradient(colors: [Color(hex: "#F6EBCD"), Color(hex: "#E9D6A6")]),
                                           startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + h)))
        c.fill(face, with: .radialGradient(Gradient(colors: [Color(hex: "#FFC46A").opacity(0.45),
                                                             Color(hex: "#FFC46A").opacity(0)]),
                                           center: CGPoint(x: x + w / 2, y: y + h * 0.95), startRadius: 0,
                                           endRadius: w * 0.7))
        let pcx = x + w / 2, pcy = y + h + 18, r = h + 6
        let ink = RadioRetroInk.scaleInk
        let redInk = Color(hex: "#C8331F")
        func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
            let a = degrees * Double.pi / 180
            return CGPoint(x: pcx + radius * CGFloat(sin(a)), y: pcy - radius * CGFloat(cos(a)))
        }
        for k in 0..<13 {
            let degrees = -46 + Double(k) * 92 / 12
            let r0 = r - (k % 3 == 0 ? 9 : 6)
            let a = point(degrees, r0), b = point(degrees, r - 2)
            D.line(&c, a.x, a.y, b.x, b.y, k >= 9 ? redInk : ink, k % 3 == 0 ? 1.1 : 0.8)
        }
        let redStart = RadioVU.angle(RadioVU.redFrom)
        var arc = Path()
        arc.addArc(center: CGPoint(x: pcx, y: pcy), radius: r - 2, startAngle: .degrees(-90 - 46),
                   endAngle: .degrees(-90 + redStart), clockwise: false)
        c.stroke(arc, with: .color(ink), lineWidth: 0.8)
        var red = Path()
        red.addArc(center: CGPoint(x: pcx, y: pcy), radius: r - 2, startAngle: .degrees(-90 + redStart),
                   endAngle: .degrees(-90 + 46), clockwise: false)
        c.stroke(red, with: .color(redInk), lineWidth: 2.2)
        D.label(&c, "VU", x: x + 8, y: y + h - 11.5, weight: .heavy, color: ink)
        D.label(&c, label, x: x + w - 8, y: y + h - 11.5, weight: .heavy, color: ink, anchor: .trailing)
        c.drawLayer { layer in
            layer.clip(to: face)
            let tip = point(RadioVU.angle(level), r - 4)
            D.line(&layer, pcx, pcy, tip.x, tip.y, Color(hex: "#111111"), 1.3)
        }
        c.fill(D.rr(x, y, w, 5, 2), with: .color(.white.opacity(0.3)))
    }
}

// MARK: - 面板：读数、走带、音量

/// 机身下面的大字台名和一行说明。
struct RadioRetroReadout: View {
    var name: String
    var detail: String
    var detailColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(detailColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 上一台、播放、下一台三个实心键，图标深色。
struct RadioRetroTransport: View {
    var skin: RadioSkin
    var playing: Bool
    var canPlay: Bool
    var canStep: Bool
    var onPrevious: () -> Void
    var onToggle: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            key("backward.end.fill", main: false, label: tr("上一个电台"), action: onPrevious)
                .disabled(!canStep)
            Spacer().frame(width: skin == .deck ? 18 : 10)
            key(playing ? "pause.fill" : "play.fill", main: true, label: playing ? tr("暂停") : tr("收听"),
                action: onToggle)
                .disabled(!canPlay)
            Spacer().frame(width: skin == .deck ? 18 : 10)
            key("forward.end.fill", main: false, label: tr("下一个电台"), action: onNext)
                .disabled(!canStep)
            Spacer(minLength: 0)
        }
    }

    private func key(_ symbol: String, main: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RadioRetroKeyFace(skin: skin, symbol: symbol, main: main, lit: playing,
                              size: skin == .deck ? (main ? 50 : 38) : (main ? 54 : 38))
        }
        .buttonStyle(RadioRetroPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 按下时略微缩一下，减少动态效果时不缩。
struct RadioRetroPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: configuration.isPressed)
    }
}

/// 一颗走带键的样子：木壳是象牙色圆钮和琥珀主钮，晶体管是镀铬钮和红色主钮，
/// 卡座是圆角方形金属键，主键顶上一颗绿灯。
struct RadioRetroKeyFace: View {
    var skin: RadioSkin
    var symbol: String
    var main: Bool
    var lit: Bool
    var size: CGFloat

    var body: some View {
        let glyph = Image(systemName: symbol)
            .playPauseMorph(symbol, enabled: main)
            .font(.system(size: main ? size * 0.36 : size * 0.34, weight: .bold))
            .foregroundStyle(skin.ink)
        Group {
            switch skin {
            case .deck:
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(gradient: RadioRetroInk.metalKey, startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.45), radius: 0, x: 0.8, y: 2.5)
                    glyph.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if main {
                        Capsule()
                            .fill(lit ? RadioRetroInk.led : .black.opacity(0.25))
                            .frame(width: 16, height: 3)
                            .padding(.top, 5)
                    }
                }
            case .transistor:
                ZStack {
                    Circle().fill(.black.opacity(0.4)).offset(x: 0.8, y: 2)
                    Circle().fill(LinearGradient(gradient: RadioRetroInk.chrome, startPoint: .top, endPoint: .bottom))
                    if main {
                        Circle().fill(RadioRetroInk.red).padding(2.5)
                        Circle().fill(.white.opacity(0.16)).frame(width: size * 0.4, height: size * 0.4)
                            .offset(x: -size * 0.12, y: -size * 0.17)
                    } else {
                        Circle().fill(Color(hex: "#C9CCD2")).padding(3)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.6).padding(3))
                    }
                    glyph
                }
            case .wood, .classic:
                ZStack {
                    Circle().fill(.black.opacity(0.35)).offset(x: 0.8, y: 2)
                    Circle().fill(main ? RadioRetroInk.amber : RadioRetroInk.ivory)
                    Circle().strokeBorder(RadioRetroInk.brass, lineWidth: 1.6)
                    Circle().fill(.white.opacity(0.18)).frame(width: size * 0.45, height: size * 0.45)
                        .offset(x: -size * 0.12, y: -size * 0.17)
                    glyph
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(skin == .deck ? AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                     : AnyShape(Circle()))
    }
}

/// 音量：喇叭、按皮肤画的推子槽和钮、百分比。拖动时只调播放器，松手才存。
struct RadioRetroVolume: View {
    var skin: RadioSkin
    var value: Double
    var enabled: Bool
    var onChange: (Double) -> Void
    var onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = width * CGFloat(min(max(value / 100, 0), 1))
                ZStack(alignment: .leading) {
                    track(width: width, filled: x)
                    knob.offset(x: x - knobWidth / 2)
                }
                .frame(height: proxy.size.height)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled, width > 0 else { return }
                        onChange((Double(min(max(drag.location.x / width, 0), 1)) * 100).rounded())
                    }
                    .onEnded { _ in if enabled { onEnd() } })
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel(tr("音量"))
            .accessibilityValue("\(Int(value.rounded()))%")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: onChange(min(100, value + 10)); onEnd()
                case .decrement: onChange(max(0, value - 10)); onEnd()
                @unknown default: break
                }
            }
            Text(verbatim: "\(Int(value.rounded()))%")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var knobWidth: CGFloat {
        switch skin {
        case .deck: 12
        case .transistor: 17
        default: 18
        }
    }

    @ViewBuilder private func track(width: CGFloat, filled: CGFloat) -> some View {
        switch skin {
        case .deck:
            ZStack(alignment: .leading) {
                Canvas { c, size in
                    for k in 0...20 {
                        let x = size.width * CGFloat(k) / 20
                        RadioRetroDraw.line(&c, x, 0, x, k % 5 == 0 ? 4 : 2, .white.opacity(0.35), 0.8)
                    }
                }
                .frame(height: 4)
                .offset(y: -8)
                Capsule().fill(.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    .frame(height: 4)
                Capsule().fill(RadioRetroInk.vfd.opacity(0.9)).frame(width: max(0, filled), height: 4)
            }
        case .transistor:
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 6)
                Capsule().fill(RadioRetroInk.red).frame(width: max(0, filled), height: 6)
            }
        case .wood, .classic:
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .frame(height: 6)
                Capsule().fill(RadioRetroInk.brass).frame(width: max(0, filled), height: 6)
            }
        }
    }

    @ViewBuilder private var knob: some View {
        switch skin {
        case .deck:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#F2F3F5"), Color(hex: "#A9ADB3")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.black.opacity(0.4), lineWidth: 0.6))
                .overlay(Rectangle().fill(Color(hex: "#333333")).frame(width: 8, height: 1.2))
                .frame(width: 12, height: 18)
        case .transistor:
            Circle()
                .fill(LinearGradient(gradient: RadioRetroInk.chrome, startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.6))
                .frame(width: 17, height: 17)
        case .wood, .classic:
            Circle()
                .fill(Color(hex: "#3B1F10"))
                .overlay(Circle().strokeBorder(RadioRetroInk.brass, lineWidth: 1.6))
                .frame(width: 18, height: 18)
        }
    }
}

// MARK: - 卡片

/// 卡片左边的迷你机身：木壳是小刻度条加喇叭网，晶体管是圆网加竖刻度，
/// 卡座是迷你段码屏。指针或数字跟着频道走。
struct RadioRetroTileArt: View {
    var skin: RadioSkin
    var count: Int
    var index: Int
    var playing: Bool
    /// 木壳和晶体管是方的，边长；卡座按 62 × 40 等比缩放到这个高度。
    var height: CGFloat = 44

    nonisolated static func width(_ skin: RadioSkin, height: CGFloat) -> CGFloat {
        skin == .deck ? height * 62 / 40 : height
    }

    var body: some View {
        let frequency = RadioDial.frequency(index, count: count)
        let fraction = RadioDial.dialFraction(frequency)
        let design: CGSize = skin == .deck ? CGSize(width: 62, height: 40) : CGSize(width: 44, height: 44)
        let scale = height / design.height
        Canvas { c, _ in
            c.scaleBy(x: scale, y: scale)
            switch skin {
            case .wood: Self.drawWood(&c, fraction: fraction)
            case .transistor: Self.drawTransistor(&c, fraction: fraction)
            case .deck: Self.drawDeck(&c, frequency: frequency, playing: playing)
            case .classic: break
            }
        }
        .frame(width: design.width * scale, height: design.height * scale)
        .accessibilityHidden(true)
    }

    nonisolated static func drawWood(_ c: inout GraphicsContext, fraction: Double) {
        typealias D = RadioRetroDraw
        let box = D.rr(0, 0, 44, 44, 9)
        c.fill(box, with: .linearGradient(Gradient(colors: [Color(hex: "#7A4628"), Color(hex: "#3F2111")]),
                                          startPoint: .zero, endPoint: CGPoint(x: 13, y: 44)))
        c.drawLayer { layer in
            layer.clip(to: box)
            D.woodGrain(&layer, CGRect(x: 0, y: 0, width: 44, height: 44), seed: 3, lines: 9)
        }
        c.fill(D.rr(5, 5, 34, 11, 2.5), with: .color(Color(hex: "#EED7A2")))
        c.stroke(D.rr(5, 5, 34, 11, 2.5), with: .color(RadioRetroInk.brass), lineWidth: 1)
        for k in 0..<7 {
            let x = 9 + CGFloat(k) * 4.3
            D.line(&c, x, 8, x, 12, RadioRetroInk.dialInk.opacity(0.8), 0.6)
        }
        let nx = 9 + 26 * CGFloat(fraction)
        D.line(&c, nx, 6, nx, 15, RadioRetroInk.amber.opacity(0.3), 3.5)
        D.line(&c, nx, 6, nx, 15, RadioRetroInk.amberDeep, 1.4)
        c.fill(D.rr(13, 20, 18, 19, 4), with: .color(Color(hex: "#E6D6B4")))
        c.stroke(D.rr(13, 20, 18, 19, 4), with: .color(RadioRetroInk.brass), lineWidth: 1)
        c.fill(D.circle(22, 25, 2.4), with: .color(RadioRetroInk.amber))
        c.stroke(D.circle(22, 25, 2.4), with: .color(Color(hex: "#120A04")), lineWidth: 0.8)
        c.fill(D.circle(8, 31, 3.6), with: .color(Color(hex: "#2A1408")))
        c.fill(D.circle(36, 31, 3.6), with: .color(Color(hex: "#2A1408")))
    }

    nonisolated static func drawTransistor(_ c: inout GraphicsContext, fraction: Double) {
        typealias D = RadioRetroDraw
        let chrome = GraphicsContext.Shading.linearGradient(RadioRetroInk.chrome, startPoint: .zero,
                                                           endPoint: CGPoint(x: 9, y: 44))
        c.fill(D.rr(0, 0, 44, 44, 10), with: chrome)
        c.fill(D.rr(2.5, 2.5, 39, 39, 8), with: .color(Color(hex: "#33251D")))
        c.fill(D.circle(18, 23, 14.5), with: chrome)
        c.drawLayer { layer in
            layer.clip(to: D.circle(18, 23, 12.5))
            D.perforation(&layer, cx: 18, cy: 23, radius: 13, spacing: 3.6, hole: 1.05)
        }
        c.fill(D.rr(34, 8, 6, 30, 2), with: .color(Color(hex: "#EFE6D2")))
        let ny = 8 + 30 * CGFloat(fraction)
        D.line(&c, 33, ny, 41, ny, RadioRetroInk.red, 1.6)
    }

    nonisolated static func drawDeck(_ c: inout GraphicsContext, frequency: Double, playing: Bool) {
        typealias D = RadioRetroDraw
        c.fill(D.rr(0, 0, 62, 40, 7), with: .linearGradient(Gradient(colors: [Color(hex: "#E2E4E7"),
                                                                              Color(hex: "#B5B8BD")]),
                                                            startPoint: .zero, endPoint: CGPoint(x: 0, y: 40)))
        c.fill(D.rr(4, 4, 54, 32, 4), with: .color(Color(hex: "#0A0E0B")))
        c.drawLayer { lit in
            let vfd = RadioRetroInk.vfd
            lit.addFilter(.shadow(color: vfd.opacity(0.55), radius: 1.2))
            D.segmentText(&lit, RadioDial.segmentText(frequency), x: 7, y: 16, h: 13, color: vfd)
            for k in 0..<4 {
                let bh = 2 + CGFloat(k) * 1.6
                lit.fill(D.rr(9 + CGFloat(k) * 4, 10 - bh, 2.6, bh, 0.6),
                         with: .color(vfd.opacity(playing || k == 0 ? 1 : 0.15)))
            }
        }
    }
}

/// 卡片上的实心播放键：琥珀圆钮、镀铬圈红钮、金属方键带绿灯，图标深色。
struct RadioRetroTilePlay: View {
    var skin: RadioSkin
    var playing: Bool
    var size: CGFloat = 26

    var body: some View {
        let symbol = playing ? "pause.fill" : "play.fill"
        let glyph = Image(systemName: symbol)
            .playPauseMorph(symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(skin.ink)
        Group {
            switch skin {
            case .deck:
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(LinearGradient(gradient: RadioRetroInk.metalKey, startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                            .strokeBorder(.white.opacity(0.7), lineWidth: 0.6))
                    glyph.frame(maxWidth: .infinity, maxHeight: .infinity).offset(y: size * 0.04)
                    Capsule().fill(playing ? RadioRetroInk.led : .black.opacity(0.25))
                        .frame(width: size * 0.38, height: max(1.5, size * 0.08))
                        .padding(.top, size * 0.11)
                }
            case .transistor:
                ZStack {
                    Circle().fill(LinearGradient(gradient: RadioRetroInk.chrome, startPoint: .top, endPoint: .bottom))
                    Circle().fill(RadioRetroInk.red).padding(size * 0.07)
                    glyph
                }
            case .wood, .classic:
                ZStack {
                    Circle().fill(RadioRetroInk.amber)
                    Circle().strokeBorder(RadioRetroInk.brass, lineWidth: 1)
                    glyph
                }
            }
        }
        .frame(width: size, height: size)
    }
}
