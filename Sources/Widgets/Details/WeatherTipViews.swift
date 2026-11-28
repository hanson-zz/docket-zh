import SwiftUI

/// 天气暖心提示的界面部分：把面板手上的数据交给 `WeatherTips`，
/// 用面板顶上的小熊猫气泡呈现。判断和文案都在 Core（WeatherTips）。
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

    /// 小熊猫的样子交给 `PandaStateResolver.weather`：下雨下雪用雨雪场景图（提醒级别也是），
    /// 风大、空气差这类重要天气举爪提醒，紫外线那句用喝水场景图；其余平常天按现在的天气
    /// 给晴、冷、热场景图，没有天气数据时待机。
    static func pandaPose(_ kind: WeatherTips.Tip.Kind, alert: Bool,
                          conditions: WeatherSceneInput? = nil) -> PandaPose {
        PandaStateResolver.weather(kind, alertStyle: alert, conditions: conditions)
    }

    /// 天气场景要的真实数据：现在的气温、体感、天气图标和这一小时降水；没有当前天气时 nil。
    static func sceneInput(weather: WeatherNow?, nowcast: WeatherNowcast?) -> WeatherSceneInput? {
        let temperature = weather?.temperatureC ?? nowcast?.current?.temperatureC
        let apparent = nowcast?.current?.apparentC
        guard weather != nil || temperature != nil else { return nil }
        return WeatherSceneInput(temperatureC: temperature, apparentC: apparent,
                                 symbolName: weather?.symbolName, precipitationMM: weather?.precipitationMM)
    }
}

/// 面板顶上：小熊猫说一句（最高优先级的那句），液态玻璃气泡，跟随浅色 / 深色。
struct WeatherTipBubble: View {
    var tip: WeatherTips.Tip

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 气泡只说最要紧的一句：重要天气算提醒。
            PandaStateView(pose: WeatherTipSource.pandaPose(tip.kind, alert: WeatherGlance.rank(tip.kind) <= 1),
                           size: PandaStage.small.side, fallbackSymbol: "heart.fill")

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
