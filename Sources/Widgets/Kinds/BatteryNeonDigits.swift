import AppKit
import SwiftUI

// 「霓虹灯管」电量数字：很细的圆润数字画成空心玻璃管（淡灰描边加一道高光），按电量
// 从下往上灌亮，亮的那截带柔和发光。扩展栏电池卡片（BatteryGauge 的霓虹外观）、
// 系统小组件「码头 · 电池」和插电动画共用这一个视图。
//
// 这个文件也编进系统小组件扩展（project.yml 的 DocklingWidgets），只能用 SwiftUI、
// AppKit 和 Sources/Core/BatteryNeon.swift，不能引用主 App 里别的类型。

extension BatteryNeon.RGB {
    var neonColor: Color { Color(red: red, green: green, blue: blue) }
}

struct BatteryNeonDigits: View {
    /// 要画的字，一般是电量数字；读不到时是「-」。
    var text: String
    /// 按哪个电量取颜色。
    var percent: Int
    /// 灯管亮到哪里，0...1（插电动画里从 0 灌上来）。
    var fraction: Double
    var fontSize: CGFloat
    var showsPercentSign = true
    /// 发光强度，0 不发光。
    var glow: Double = 1
    /// 换掉按电量取的颜色（扩展栏卡片在「外观 ▸ 颜色」选了颜色时）。
    var tint: BatteryNeon.RGB?
    /// 不跟系统外观、固定按深色底画（插电动画画在桌面上方）。
    var forceDark = false

    @Environment(\.colorScheme) private var scheme

    init(text: String, percent: Int, fraction: Double, fontSize: CGFloat, showsPercentSign: Bool = true,
         glow: Double = 1, tint: BatteryNeon.RGB? = nil, forceDark: Bool = false) {
        self.text = text
        self.percent = percent
        self.fraction = fraction
        self.fontSize = fontSize
        self.showsPercentSign = showsPercentSign
        self.glow = glow
        self.tint = tint
        self.forceDark = forceDark
    }

    private var dark: Bool { forceDark || scheme == .dark }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.03) {
            tube(text, size: fontSize)
            if showsPercentSign {
                Text(verbatim: "%")
                    .font(.system(size: max(13, fontSize * 0.3), weight: .light, design: .rounded))
                    .foregroundStyle(dark ? Color.white.opacity(0.72) : Color.black.opacity(0.5))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(text)%"))
    }

    private func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 一串字的灯管：玻璃（空心描边加高光）在下，亮的那截叠在上面，用遮罩从底下往上露。
    private func tube(_ string: String, size: CGFloat) -> some View {
        let color = (tint ?? BatteryNeon.color(percent: percent, dark: dark)).neonColor
        let core = BatteryNeon.core(tint ?? BatteryNeon.color(percent: percent, dark: dark), dark: dark).neonColor
        let metrics = Self.metrics(size: size)
        let lit = BatteryNeon.maskHeight(fraction: fraction, descent: metrics.descent, capHeight: metrics.cap)
        let highlight = BatteryNeon.tubeWidth(fontSize: size) * 0.35
        return ZStack(alignment: .bottom) {
            // 玻璃管：常规粗细的字挖掉中间极细的一道，剩下两条细边，就是空心的管壁。
            ZStack {
                Text(verbatim: string).font(font(size, .regular))
                    .foregroundStyle(dark ? Color.white.opacity(0.34) : Color(white: 0.55).opacity(0.55))
                Text(verbatim: string).font(font(size, .ultraLight))
                    .foregroundStyle(.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            // 管壁上一道高光，往左上偏一点。
            Text(verbatim: string).font(font(size, .ultraLight))
                .foregroundStyle(Color.white.opacity(dark ? 0.32 : 0.85))
                .offset(x: CGFloat(-highlight), y: CGFloat(-highlight))
            // 亮的那截：管体、芯，遮罩从底往上露到电量那里；发光在遮罩之后加，只围着亮的部分。
            ZStack {
                Text(verbatim: string).font(font(size, .light)).foregroundStyle(color)
                Text(verbatim: string).font(font(size, .ultraLight)).foregroundStyle(core)
            }
            .mask(alignment: .bottom) {
                Rectangle().frame(height: CGFloat(max(0, lit)))
            }
            .shadow(color: color.opacity((dark ? 0.85 : 0.5) * glow), radius: size * 0.05)
            .shadow(color: color.opacity((dark ? 0.55 : 0.3) * glow), radius: size * 0.14)
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// 字框底边到基线的距离和数字的高度，和上面的字同一个字体（细体、圆润）。
    static func metrics(size: CGFloat) -> (descent: Double, cap: Double) {
        let base = NSFont.systemFont(ofSize: size, weight: .light)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return (Double(-font.descender), Double(font.capHeight))
    }
}
