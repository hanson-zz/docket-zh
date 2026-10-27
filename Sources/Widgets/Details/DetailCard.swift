import SwiftUI

/// The card every panel is drawn on.
///
/// Panels used to be forms: a label and a figure per row, dividers between
/// the groups, grey on the popover's grey. Now Playing showed the other way
/// to do it, one card whose backdrop *is* the reading, with the content laid
/// on it, and this is that card for every panel.
///
/// It reaches past the panel's own padding to 6pt from its edge, where a
/// 14pt corner sits concentric with the panel's 20.
///
/// 液态玻璃：卡片底是 macOS 26 的系统 `glassEffect`，跟着设置里的
/// 「跟随系统 / 浅色 / 深色」走（AppAppearance 设到 NSApp.appearance，环境里的
/// colorScheme 跟着变），不再强制深色。内容的颜色用 PanelColors.swift 里的语义色。
/// 收音机、相框、壁纸这类例外传 `forceDark: true`（或外面套 `.panelForceDark()`），
/// 卡片换回原来的石墨实心底，内容固定深色。系统「降低透明度」时玻璃换成实心底。
extension EnvironmentValues {
    /// 面板画在钉在桌面的卡片里，见 `DetailCard.flat`。
    @Entry var detailCardEmbedded: Bool = false
}

struct DetailCard<Backdrop: View, Content: View>: View {
    /// 保持原来的暗色石墨卡（例外面板用）。
    var forceDark = false
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var content: () -> Content

    static var bleed: CGFloat { 10 }
    static var corner: CGFloat { 14 }

    /// 颜色面板里选了颜色时，卡片顶上一抹淡淡的主题色（不超过 15%），
    /// 天空、封面这类有意思的底也加，只在顶边，盖不住它们。
    @Environment(\.panelTint) private var panelTint
    @Environment(\.panelForcedDark) private var inheritedDark

    init(forceDark: Bool = false,
         @ViewBuilder backdrop: @escaping () -> Backdrop,
         @ViewBuilder content: @escaping () -> Content) {
        self.forceDark = forceDark
        self.backdrop = backdrop
        self.content = content
    }

    private var dark: Bool { forceDark || inheritedDark }

    /// 钉在桌面的卡片里（`detailCardEmbedded`）：外面那张桌面卡片已经是液态玻璃，
    /// 这里不再画一层玻璃、不往外伸，内容和底色铺满整张卡片，免得卡片里套一块
    /// 比卡片窄的玻璃。例外面板（石墨实心底）照样画底，也铺满。
    @Environment(\.detailCardEmbedded) private var embedded

    var body: some View {
        if embedded { flat } else { card }
    }

    private var flat: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    if dark { PanelGlassSurface(cornerRadius: 0, dark: true) }
                    backdrop()
                    if let panelTint {
                        TintGlow(color: panelTint.color, opacity: panelTint.glow, reach: panelTint.reach)
                    }
                }
            }
            .panelForceDark(dark)
    }

    private var card: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    PanelGlassSurface(cornerRadius: Self.corner, dark: dark)
                    backdrop()
                    if let panelTint {
                        TintGlow(color: panelTint.color, opacity: panelTint.glow, reach: panelTint.reach)
                    }
                }
            }
            .panelForceDark(dark)
            .clipShape(.rect(cornerRadius: Self.corner, style: .continuous))
            .overlay {
                if dark {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
            }
            .padding(-Self.bleed)
    }
}

/// 卡片最底下那层：液态玻璃（跟随外观），或例外面板的石墨实心底。
/// `ClockPanelParts` 里自己画卡的时钟面板也用它。
struct PanelGlassSurface: View {
    var cornerRadius: CGFloat
    var dark: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if dark {
            MeshBackdrop.graphite
        } else if reduceTransparency {
            shape.fill(scheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F4F4F6"))
        } else {
            Color.clear
                .glassEffect(.regular, in: shape)
        }
    }
}

// MARK: - Chips

/// A small figure with its name above it, on a pane of frosted glass.
///
/// What replaces the label-and-value row. A row puts the label and the figure
/// as far apart as the panel is wide and draws a line under them; a chip keeps
/// the two together and sets several side by side.
struct StatChip: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Color.panelTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
                .rollingValue(value)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 10)
    }
}

extension View {
    /// A pane of the card's own frosted glass: lighter than the card, with a
    /// hairline catching the light along its top. 浅色下是一块更白的玻璃，
    /// 深色下和原来一样。
    func glassPane(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassPaneModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassPaneModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let light = scheme == .light
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: light
                                           ? [.white.opacity(0.95), .white.opacity(0.4)]
                                           : [.white.opacity(0.22), .white.opacity(0.04)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Backdrops

/// The card's surface: neutral, with the widget's own colour only as a faint
/// warmth in one corner.
///
/// It was the widget's colour as a whole-card mesh, and even pulled halfway
/// to graphite a card of calendar red or AirDrop amber read as a coloured
/// sticker, not as part of the Mac. Apple's own surfaces are neutral, and
/// colour is something placed on them: a ring, a mark, a figure. So the card
/// is the same surface for every widget, told apart by what is on it, and
/// the colour is a hint you notice second.
///
/// 液态玻璃以后，卡片底由 `DetailCard` 的玻璃负责，这里只在玻璃上加一层很淡的
/// 光和角上的颜色；例外面板（`panelForcedDark`）还是原来的石墨渐变。
struct MeshBackdrop: View {
    var color: Color
    /// 颜色本身有意思（电量、涨跌、逾期、隔空投送的模式、取的颜色、事件
    /// 自己的颜色），角上的暖光不跟着颜色面板换。默认跟：选了颜色时角上的
    /// 暖光换成选的颜色（`PanelTint`）。顶上那一抹光晕由 `DetailCard` 画。
    var fixed = false

    @Environment(\.panelTint) private var panelTint
    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.colorScheme) private var scheme

    /// 角上那一抹实际用的颜色。
    private var shown: Color { fixed ? color : panelTint.accent(or: color) }

    static let graphite = Color(red: 0.115, green: 0.115, blue: 0.13)
    /// How much of the widget's colour reaches the corner glow.
    static var hint: Double { 0.16 }

    /// A colour taken most of the way to graphite: for surfaces that have to
    /// keep a meaning (water, a sky) without becoming the loudest thing.
    static func muted(_ colour: Color, by amount: Double = 0.72) -> Color {
        colour.mix(with: graphite, by: amount)
    }

    var body: some View {
        if forcedDark {
            graphiteBody
        } else {
            glassBody
        }
    }

    /// 玻璃上的一层：浅色下顶上更亮一点，深色下往下压暗一点，角上一抹颜色。
    private var glassBody: some View {
        let light = scheme == .light
        return ZStack {
            LinearGradient(colors: light
                           ? [.white.opacity(0.22), .white.opacity(0.06)]
                           : [.black.opacity(0.04), .black.opacity(0.2)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [shown.opacity(light ? Self.hint * 0.8 : Self.hint), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 280)
            LinearGradient(colors: [.white.opacity(light ? 0.25 : 0.06), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
        }
    }

    private var graphiteBody: some View {
        let base = Self.graphite
        return ZStack {
            LinearGradient(stops: [
                .init(color: base.mix(with: .white, by: 0.07), location: 0),
                .init(color: base, location: 0.45),
                .init(color: base.mix(with: .black, by: 0.4), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [shown.opacity(Self.hint), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 280)
            // A sheen along the top edge, the way light catches the lip of
            // an aluminium case.
            LinearGradient(colors: [.white.opacity(0.06), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
        }
    }
}

/// The sky at an hour in a zone, with the sun or the moon where it is.
///
/// The colour is the time of day before it is anything else: navy through the
/// night, rose at dawn, blue through the day, amber into dusk. A dotted arc
/// runs across the card as the day's path, with the sun on it at the current
/// hour between six and six, and the moon and a scatter of stars outside it.
///
/// 液态玻璃：天色只是玻璃上一层淡淡的颜色（浅色约 26%，深色约 38%），弧线和
/// 星星用语义色；例外面板（`panelForcedDark`）还是原来压暗的实心天色。
struct SkyBackdrop: View {
    var date: Date
    var zone: TimeZone

    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.colorScheme) private var scheme

    private var hour: Double {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    var body: some View {
        let colors = forcedDark
            ? Self.palette(hour)
            : Self.rawPalette(hour).map { $0.opacity(scheme == .light ? 0.26 : 0.38) }
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                if !isDay { stars(in: size) }
                path(in: size)
                    .stroke(forcedDark ? Color.white.opacity(0.18) : Color.panelQuaternary,
                            style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                orb(in: size)
            }
        }
    }

    private var isDay: Bool { (6..<18).contains(hour) }

    /// A shallow arc from the card's lower left corner to its lower right,
    /// cresting a little below the top.
    private func path(in size: CGSize) -> Path {
        Path { p in
            p.move(to: CGPoint(x: -10, y: size.height * 0.95))
            p.addQuadCurve(to: CGPoint(x: size.width + 10, y: size.height * 0.95),
                           control: CGPoint(x: size.width / 2, y: -size.height * 0.15))
        }
    }

    /// Where on that arc the sun, or the moon on the night's own arc, is now.
    private func point(in size: CGSize) -> CGPoint {
        let t = isDay ? (hour - 6) / 12 : ((hour + 6).truncatingRemainder(dividingBy: 24)) / 12
        let start = CGPoint(x: -10, y: size.height * 0.95)
        let end = CGPoint(x: size.width + 10, y: size.height * 0.95)
        let control = CGPoint(x: size.width / 2, y: -size.height * 0.15)
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }

    private func orb(in size: CGSize) -> some View {
        let at = point(in: size)
        let glow: Color = isDay ? Color(red: 1, green: 0.93, blue: 0.8) : Color(white: 0.9)
        return ZStack {
            // A tight halo, not a bloom: at midday the sun crests behind the
            // time itself, and a wide glow there washed the figures out.
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
            Circle()
                .fill(glow.opacity(0.85))
                .frame(width: isDay ? 9 : 7, height: isDay ? 9 : 7)
        }
        .position(at)
    }

    /// Fixed positions rather than random ones, so the stars do not move
    /// every second when the view redraws.
    private func stars(in size: CGSize) -> some View {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.12, 0.18, 1.6), (0.27, 0.42, 1.1), (0.41, 0.12, 1.3), (0.58, 0.3, 1.0),
            (0.73, 0.15, 1.5), (0.86, 0.38, 1.1), (0.93, 0.1, 1.2), (0.66, 0.55, 0.9),
            (0.2, 0.65, 0.9), (0.48, 0.6, 1.0),
        ]
        let star: Color = forcedDark ? .white.opacity(0.55) : .panelTertiary
        return ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
            Circle()
                .fill(star)
                .frame(width: spot.2, height: spot.2)
                .position(x: size.width * spot.0, y: size.height * spot.1)
        }
    }

    /// Top and bottom of the sky for an hour, blended across the edges of
    /// each band so the colour never jumps on the hour.
    static func palette(_ hour: Double) -> [Color] {
        rawPalette(hour).map { MeshBackdrop.muted($0, by: 0.6) }
    }

    /// 没压暗的天色，玻璃上用。
    static func rawPalette(_ hour: Double) -> [Color] {
        let night: [Color] = [Color(red: 0.05, green: 0.07, blue: 0.2), Color(red: 0.1, green: 0.1, blue: 0.3)]
        let dawn: [Color] = [Color(red: 0.22, green: 0.22, blue: 0.42), Color(red: 0.62, green: 0.4, blue: 0.4)]
        let day: [Color] = [Color(red: 0.15, green: 0.33, blue: 0.56), Color(red: 0.3, green: 0.47, blue: 0.66)]
        let dusk: [Color] = [Color(red: 0.26, green: 0.17, blue: 0.38), Color(red: 0.66, green: 0.36, blue: 0.28)]
        let stops: [(Double, [Color])] = [(0, night), (5, night), (6.5, dawn), (8.5, day),
                                          (16.5, day), (18.5, dusk), (20, night), (24, night)]
        // The sky's hue is kept as a tone, not a colour: enough to tell
        // night from noon at a glance, not enough to look like a wallpaper.
        for i in 1..<stops.count where hour <= stops[i].0 {
            let (h0, c0) = stops[i - 1], (h1, c1) = stops[i]
            let f = h1 == h0 ? 0 : (hour - h0) / (h1 - h0)
            return zip(c0, c1).map { $0.mix(with: $1, by: f) }
        }
        return night
    }
}

/// The weather's own sky, from the condition's symbol: blue for sun, slate
/// for cloud, steel for rain, pale for snow, indigo by night. The condition's
/// symbol is set large and soft in the corner, as a light source rather than
/// an icon.
///
/// 液态玻璃：天色只是玻璃上一层淡色（浅色约 20%，深色约 32%），角上的大图标用
/// 主文字色；例外面板（`panelForcedDark`）还是原来压暗的实心天色。
struct WeatherBackdrop: View {
    var symbol: String

    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.colorScheme) private var scheme

    private var colors: [Color] {
        forcedDark
            ? Self.palette(symbol).map { MeshBackdrop.muted($0, by: 0.6) }
            : Self.palette(symbol).map { $0.opacity(scheme == .light ? 0.2 : 0.32) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(forcedDark ? Color.white : Color.panelPrimary)
                .font(.system(size: 150))
                .opacity(0.07)
                .blur(radius: 3)
                .offset(x: 34, y: -30)
        }
        .clipped()
    }

    static func palette(_ symbol: String) -> [Color] {
        if symbol.contains("moon") {
            return [Color(red: 0.08, green: 0.1, blue: 0.28), Color(red: 0.18, green: 0.16, blue: 0.4)]
        }
        if symbol.contains("snow") || symbol.contains("sleet") {
            return [Color(red: 0.3, green: 0.37, blue: 0.47), Color(red: 0.42, green: 0.49, blue: 0.58)]
        }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("bolt") {
            return [Color(red: 0.16, green: 0.22, blue: 0.32), Color(red: 0.28, green: 0.36, blue: 0.46)]
        }
        if symbol.contains("fog") || symbol.contains("smoke") || symbol.contains("haze") {
            return [Color(red: 0.34, green: 0.36, blue: 0.4), Color(red: 0.48, green: 0.5, blue: 0.54)]
        }
        if symbol.contains("sun") {
            return [Color(red: 0.13, green: 0.32, blue: 0.56), Color(red: 0.27, green: 0.46, blue: 0.66)]
        }
        return [Color(red: 0.22, green: 0.27, blue: 0.36), Color(red: 0.32, green: 0.38, blue: 0.47)]
    }
}
