import SwiftUI

/// 「算」卡片字牌里画的东西：小熊猫脸框的拟人计算器（比例和颜色在 Core 的 `CalcBadge`）。
///
/// 全用 SwiftUI 形状按边长比例自绘，40、34、32、26pt 都是这一张，跟着浅色 / 深色走；
/// 中英文界面共用。外面的方底照旧是 `TileBadge`。不加眨眼动画：右眼一直眨着。
struct CalcBadgeFace: View {
    var size: CGFloat
    /// 前三个键的颜色（卡片主题色，已调过可读性）。nil 是跟随系统强调色。
    var keyColor: ColorCode?

    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            face
            screen
            eyes
            keys
        }
        .frame(width: size, height: size)
    }

    // MARK: 脸框、眉斑、腮

    private var face: some View {
        let box = CalcBadge.face
        let shape = BoxRect(box: box, corner: CalcBadge.faceCorner)
        return ZStack {
            shape.fill(vertical(CalcBadge.pandaHighlight, CalcBadge.panda, box))
            // 下框两角的奶白腮，裁进脸框里
            ZStack {
                ForEach(0..<CalcBadge.cheeks.count, id: \.self) { i in
                    BoxEllipse(box: CalcBadge.cheeks[i]).fill(Color(code: CalcBadge.cream))
                }
            }
            .clipShape(shape)
            BoxRect(box: box, corner: CalcBadge.faceCorner, inset: CalcBadge.faceRim / 2)
                .stroke(fade(from: 150 / 255.0, box), lineWidth: CalcBadge.faceRim * size)
            ForEach(0..<CalcBadge.brows.count, id: \.self) { i in
                BoxEllipse(box: CalcBadge.brows[i]).fill(Color(code: CalcBadge.cream))
            }
        }
    }

    // MARK: 屏幕和眼睛

    private var screen: some View {
        let box = CalcBadge.screen
        let colors = CalcBadge.screenColors(dark: dark)
        return ZStack {
            BoxRect(box: box, corner: CalcBadge.screenCorner).fill(vertical(colors.top, colors.bottom, box))
            BoxRect(box: box, corner: CalcBadge.screenCorner, inset: CalcBadge.screenRim / 2)
                .stroke(fade(from: CalcBadge.screenRimOpacity(dark: dark), box),
                        lineWidth: CalcBadge.screenRim * size)
        }
    }

    private var eyes: some View {
        let eye = CalcBadge.openEye
        let white = CalcBadge.eyeWhite
        return ZStack {
            BoxRect(box: eye, corner: eye.width / 2)
                .fill(vertical(white.mixed(with: ColorCode(red: 1, green: 1, blue: 1), by: 0.3), white, eye))
            WinkArc(wink: CalcBadge.wink)
                .stroke(Color(code: white),
                        style: StrokeStyle(lineWidth: CalcBadge.wink.lineWidth * size, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: 按键

    private var keys: some View {
        ZStack {
            ForEach(CalcBadge.Key.allCases, id: \.self) { key in
                keyView(key)
            }
        }
    }

    private func keyView(_ key: CalcBadge.Key) -> some View {
        let box = CalcBadge.key(key)
        let shape = BoxRect(box: box, corner: box.height / 2)
        let width = key == .equals ? CalcBadge.equalsStroke(size: size) : CalcBadge.symbolStroke(size: size)
        return ZStack {
            shape.fill(keyFill(key, box))
            BoxRect(box: box, corner: box.height / 2, inset: CalcBadge.keyRim / 2)
                .stroke(fade(from: 150 / 255.0, box), lineWidth: CalcBadge.keyRim * size)
            KeySymbol(segments: CalcBadge.symbolSegments(key, size: Double(size)))
                .stroke(ink(key), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// 键的底色：「＝」小熊猫橙红；其余是主题色（浅色外观压深一点），跟随系统强调色时用强调色。
    private func keyFill(_ key: CalcBadge.Key, _ box: CalcBadge.Box) -> LinearGradient {
        if key.isAccent {
            let g = CalcBadge.keyGradient(CalcBadge.panda)
            return vertical(g.top, g.bottom, box)
        }
        guard let keyColor else {
            return LinearGradient(colors: [Color.accentColor.mix(with: .white, by: 0.22),
                                           Color.accentColor.mix(with: .black, by: 0.10)],
                                  startPoint: point(box.y0), endPoint: point(box.y1))
        }
        let g = CalcBadge.keyGradient(CalcBadge.keyFill(main: keyColor, dark: dark))
        return vertical(g.top, g.bottom, box)
    }

    private func ink(_ key: CalcBadge.Key) -> Color {
        if key.isAccent { return Color(code: CalcBadge.equalsInk) }
        guard let keyColor else { return .white }
        let fill = CalcBadge.keyFill(main: keyColor, dark: dark)
        return CalcBadge.keyInkIsDark(on: fill) ? Color(code: CalcBadge.darkKeyInk) : .white
    }

    // MARK: 渐变

    /// 在 `box` 的上下沿之间竖向渐变（形状铺满整个字牌，渐变按框的位置定起止）。
    private func vertical(_ top: ColorCode, _ bottom: ColorCode, _ box: CalcBadge.Box) -> LinearGradient {
        LinearGradient(colors: [Color(code: top), Color(code: bottom)],
                       startPoint: point(box.y0), endPoint: point(box.y1))
    }

    /// 上缘亮边：白色从 `opacity` 渐隐到 0，液态玻璃那样只亮顶上。
    private func fade(from opacity: Double, _ box: CalcBadge.Box) -> LinearGradient {
        LinearGradient(colors: [.white.opacity(opacity), .white.opacity(0)],
                       startPoint: point(box.y0), endPoint: point(box.y1))
    }

    private func point(_ y: Double) -> UnitPoint { UnitPoint(x: 0.5, y: y) }
}

// MARK: - 按比例画的形状

/// 一个按边长比例放的圆角矩形（`inset` 往里收，描边用，免得线宽一半落到框外）。
private struct BoxRect: Shape {
    var box: CalcBadge.Box
    var corner: Double
    var inset: Double = 0

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        let r = CGRect(x: rect.minX + (box.x0 + inset) * s, y: rect.minY + (box.y0 + inset) * s,
                       width: max(0, box.width - inset * 2) * s, height: max(0, box.height - inset * 2) * s)
        let radius = min(max(0, corner - inset) * s, min(r.width, r.height) / 2)
        return Path(roundedRect: r, cornerRadius: radius, style: .continuous)
    }
}

private struct BoxEllipse: Shape {
    var box: CalcBadge.Box

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        return Path(ellipseIn: CGRect(x: rect.minX + box.x0 * s, y: rect.minY + box.y0 * s,
                                      width: box.width * s, height: box.height * s))
    }
}

/// 右眼眨成的 ^ 弧。
private struct WinkArc: Shape {
    var wink: CalcBadge.Wink

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        var path = Path()
        let points = wink.points().map { CGPoint(x: rect.minX + $0.x * s, y: rect.minY + $0.y * s) }
        path.addLines(points)
        return path
    }
}

/// 键上的符号：几段直线，用圆头描边。
private struct KeySymbol: Shape {
    var segments: [((Double, Double), (Double, Double))]

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        var path = Path()
        for (a, b) in segments {
            path.move(to: CGPoint(x: rect.minX + a.0 * s, y: rect.minY + a.1 * s))
            path.addLine(to: CGPoint(x: rect.minX + b.0 * s, y: rect.minY + b.1 * s))
        }
        return path
    }
}
