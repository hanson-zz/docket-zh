import SwiftUI

/// 天气暖心提示的界面部分：把面板和卡片手上的数据交给 `WeatherTips`，
/// 面板顶上的小熊猫气泡，卡片上轮换的一行。判断和文案都在 Core（WeatherTips）。
enum WeatherTipSource {
    /// 把一个城市手上的数据拼成判断用的输入；哪项没有就留空，那一类提示跳过。
    static func input(weather: WeatherNow?, nowcast: WeatherNowcast?, aqi: Int?, forecast: DailyForecast?,
                      now: Date, zone: TimeZone, fahrenheit: Bool) -> WeatherTips.Input {
        WeatherTips.Input(
            now: now, zone: zone,
            temperatureC: weather?.temperatureC ?? nowcast?.current?.temperatureC,
            apparentC: nowcast?.current?.apparentC,
            windSpeed: weather?.windSpeed ?? nowcast?.current?.windSpeed,
            aqi: aqi,
            rain: nowcast.flatMap { RainOutlook.status($0.slots, now: now) },
            currentPrecipitationMM: weather?.precipitationMM,
            hours: nowcast?.hours ?? [],
            yesterday: forecast?.day(offset: -1, now: now),
            today: forecast?.today(now: now),
            tomorrow: forecast?.day(offset: 1, now: now),
            fahrenheit: fahrenheit)
    }

    /// 小熊猫的姿势：风和日丽（只剩穿衣那句）时欢呼，喝水那张配紫外线，其余站着提醒。
    /// 只用 Resources/Pet 里现成的小熊猫图。
    static func pandaImage(_ kind: WeatherTips.Tip.Kind) -> String {
        switch kind {
        case .clothing: "pet-panda-cheer"
        case .uv: "pet-panda-drink"
        default: "pet-panda-idle"
        }
    }
}

/// 面板顶上：小熊猫说一句（最高优先级的那句），液态玻璃气泡，跟随浅色 / 深色。
struct WeatherTipBubble: View {
    var tip: WeatherTips.Tip

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Group {
                if let image = PandaArt.image(WeatherTipSource.pandaImage(tip.kind)) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.panelSecondary)
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            Text(verbatim: tip.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .padding(.trailing, 11)
                .padding(.vertical, 7)
                .background { WeatherTipGlass() }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("暖心提示") + " " + tip.text)
    }
}

/// 气泡的液态玻璃：和面板里的玻璃小块（`glassPane`）同一套做法，一块更亮的玻璃加
/// 顶上亮、往下渐隐的细亮边，只是形状带尖角。面板本身已是系统 `glassEffect`，
/// 玻璃上不再叠一层系统玻璃（会发灰发糊），用半透明亮层透出下面的面板和天色。
///
/// 底比 `panelFill` 亮一档，保证天色透上来时字仍清楚：浅色白 0.55（近黑字
/// #18161C 在偏暗的天色上也约 10 以上），深色白 0.10（白字在较亮的天色上也约 5，常见约 11），都过正文 4.5。字用
/// panelPrimary，不用次级色。
struct WeatherTipGlass: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        let shape = WeatherTipBubbleShape()
        shape
            .fill(Color.white.opacity(light ? 0.55 : 0.10))
            .overlay {
                shape.stroke(
                    LinearGradient(colors: light
                                   ? [.white.opacity(0.95), .white.opacity(0.4)]
                                   : [.white.opacity(0.22), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(light ? 0.06 : 0), radius: 3, y: 1)
    }
}

/// 圆角气泡，左边一个小尖角指向小熊猫。
struct WeatherTipBubbleShape: Shape {
    var radius: CGFloat = 11
    var tail: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        // 一条连续的轮廓（描边不会在尖角和气泡之间留一道缝）：顺时针，左边中间伸出尖角。
        let left = rect.minX + tail
        let r = min(radius, rect.height / 2, (rect.width - tail) / 2)
        let mid = rect.midY
        let reach = min(tail, max(0, mid - rect.minY - r))
        var path = Path()
        path.move(to: CGPoint(x: left + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: left + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: left, y: mid + reach))
        path.addLine(to: CGPoint(x: rect.minX, y: mid))
        path.addLine(to: CGPoint(x: left, y: mid - reach))
        path.addLine(to: CGPoint(x: left, y: rect.minY + r))
        path.addArc(center: CGPoint(x: left + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// 卡片上轮换的那一行：13pt，一行，不缩字（放不下时卡片整行不显示，见 WeatherTile）。
struct WeatherTipLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WeatherTipLine.heart)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.primary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("暖心提示") + " " + text)
    }

    /// 小红心，浅色深色卡片上都看得见的珊瑚色（只做装饰，字照旧用主文字色）。
    static let heart = Color(hex: "#FF7A6B")
}
