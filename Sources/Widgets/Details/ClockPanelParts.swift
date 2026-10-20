import SwiftUI

// 时钟面板的共用部分：每一秒的读数、视觉语言（主题）、几块信息模块
// （今天进度、世界时钟、农历和本周、下一个日程和闹钟）和点阵、数码管这些小画法。
// 八套面板（ClockPanelFaces.swift）只换头部和主题，信息模块都从这里来。

// MARK: - 读数

/// 面板这一秒要画的全部东西。每秒由 `ClockDetail` 的 TimelineView 算一次；
/// 农历、节气、日出这些一天才变的放在 `daily`，每分钟算一次。
struct ClockPanelModel {
    var now: Date
    var digits: ClockDigits
    var progress: ClockPanelData.DayProgress
    var cities: [ClockPanelData.CityTime]
    var daily: ClockPanelDaily
    var event: ClockPanelData.Upcoming?
    var alarm: ClockPanelData.Upcoming?
    /// 冒号这一秒亮不亮：奇数秒灭；减少动态效果时一直亮。
    var colonOn: Bool
    /// 颜色面板选的强调色，没选过是各面板自己的颜色。
    var tint: PanelTint?

    var zoneLabel: String { ClockPanelFormat.gmt(.current, at: now) }
    var fullDate: String { ClockPanelFormat.fullDate(now, zone: .current) }
}

/// 一天才变一次的：农历和下一个节气、第几周、日出日落。
struct ClockPanelDaily {
    var lunar: ClockPanelData.Lunar
    /// “丙午马年”。
    var lunarYear: String
    var week: Int
    var dayOfYear: Int
    /// 日出、日落、昼长。天气没有定位时是 nil，那一行不显示。
    var sun: (rise: String, set: String, length: String)?

    @MainActor
    static func at(_ now: Date) -> ClockPanelDaily {
        let week = ClockPanelData.week(now)
        var sun: (rise: String, set: String, length: String)?
        if let place = WeatherService.shared.place {
            let zone = place.zone.flatMap(TimeZone.init(identifier:)) ?? .current
            if case .normal(let rise, let set)? = SunTimes.on(now, latitude: place.lat, longitude: place.lon, zone: zone) {
                sun = (rise: ClockFormat.time(rise, zone: zone), set: ClockFormat.time(set, zone: zone),
                       length: ClockPanelData.daylightText(rise: rise, set: set))
            }
        }
        let year = ChineseCalendar.lunar(now)
        return ClockPanelDaily(lunar: ClockPanelData.lunar(now), lunarYear: "\(year.ganzhiYear)\(year.zodiac)年",
                               week: week.week,
                               dayOfYear: week.dayOfYear, sun: sun)
    }
}

// MARK: - 主题

/// 小数字（世界时钟、日程时间）怎么画，跟着面板的头部走。
enum ClockPanelFigures {
    case pixel, segment, rounded, serif, flip, neon, nixie
}

/// 进度条怎么画。
enum ClockPanelBar {
    /// 一格一格（像素 48 格，其余 24 格）。
    case cells(Int)
    /// 一根连续的细条。
    case line
}

/// 一套面板的视觉语言：字色、分隔、小卡片的底、强调色和小数字的画法。
struct ClockPanelTheme {
    var ink: Color
    var dim: Color
    var rule: Color
    var tile: Color
    var tileStroke: Color
    /// 秒数和进度当前格。
    var accent: Color
    /// 进度条走过的格子。
    var lit: Color
    /// 进度条没走到的格子。
    var unlit: Color
    var figures: ClockPanelFigures
    /// 小数字自己的颜色（霓虹的青、辉光管的橙），nil 用 `ink`。
    var figureInk: Color? = nil
    var bar: ClockPanelBar
    /// 进度条下面标 0 6 12 18 24。
    var axis: Bool = false
    /// 分隔线画成点线（点阵屏）。
    var dottedRule: Bool = false
    /// 字体的样子：衬线给中文面板。
    var design: Font.Design = .default
    /// 霓虹的光晕颜色，nil 不发光。
    var glow: Color?
    /// 节气那行用强调色。
    var accentTerm: Bool = true

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

extension View {
    /// 一点点光晕，只贴着字，不往外铺。
    @ViewBuilder
    func clockPanelGlow(_ color: Color?, _ radius: CGFloat) -> some View {
        if let color {
            shadow(color: color.opacity(0.55), radius: radius * 0.5)
                .shadow(color: color.opacity(0.25), radius: radius)
        } else {
            self
        }
    }
}

// MARK: - 卡片

/// 和 `DetailCard` 一样的位置、圆角和描边，多一个开关：液晶面板保持单色，
/// 顶上不加颜色面板的那一抹光晕。
struct ClockPanelCard<Backdrop: View, Content: View>: View {
    var glows = true
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var content: () -> Content

    @Environment(\.panelTint) private var panelTint

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    backdrop()
                    if glows, let panelTint {
                        TintGlow(color: panelTint.color, opacity: panelTint.glow, reach: panelTint.reach)
                    }
                }
            }
            .environment(\.colorScheme, .dark)
            .clipShape(.rect(cornerRadius: DetailCard<EmptyView, EmptyView>.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DetailCard<EmptyView, EmptyView>.corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .padding(-DetailCard<EmptyView, EmptyView>.bleed)
    }
}

/// 点阵屏的底：深色上一层很淡的点，像没亮的像素。
struct PixelGridBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.067, green: 0.071, blue: 0.082)
            Canvas { context, size in
                let step: CGFloat = 4
                var y: CGFloat = 1
                while y < size.height {
                    var x: CGFloat = 1
                    while x < size.width {
                        context.fill(Path(CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                                     with: .color(.white.opacity(0.035)))
                        x += step
                    }
                    y += step
                }
            }
        }
    }
}

// MARK: - 分隔

struct ClockPanelRule: View {
    var theme: ClockPanelTheme

    var body: some View {
        if theme.dottedRule {
            Line()
                .stroke(theme.rule, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 3.5]))
                .frame(height: 1.2)
        } else {
            Rectangle().fill(theme.rule).frame(height: 0.8)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: 0, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

// MARK: - 今天进度

struct ClockPanelProgress: View {
    var model: ClockPanelModel
    var theme: ClockPanelTheme
    /// 左边的说法：“今天 41%”或经典面板的“今天已过 41%”。
    var passedWording = false

    var body: some View {
        let p = model.progress
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(passedWording ? tr("今天已过 \(p.percent)%") : tr("今天 \(p.percent)%"))
                    .font(theme.font(15, .semibold))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text(ClockPanelData.remainingText(p))
                    .font(theme.font(14))
                    .foregroundStyle(theme.dim)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            bar(p.fraction)
            if theme.axis {
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        if hour > 0 { Spacer(minLength: 0) }
                        Text(verbatim: "\(hour)")
                            .font(theme.font(13))
                            .foregroundStyle(theme.dim)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func bar(_ fraction: Double) -> some View {
        switch theme.bar {
        case .line:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.unlit)
                    Capsule().fill(theme.accent)
                        .frame(width: max(5, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        case .cells(let count):
            let filled = ClockPanelData.filledCells(fraction, of: count)
            HStack(spacing: count > 30 ? 1.6 : 2.4) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: count > 30 ? 0.8 : 1.4, style: .continuous)
                        .fill(index < filled ? theme.lit : index == filled ? theme.accent : theme.unlit)
                        .clockPanelGlow(index <= filled ? theme.glow : nil, 2)
                }
            }
            .frame(height: count > 30 ? 14 : 13)
        }
    }
}

// MARK: - 小数字

/// 世界时钟、日程这些地方的小号时间，画法跟着面板。
struct ClockPanelFigure: View {
    var text: String
    var size: CGFloat
    var theme: ClockPanelTheme
    var color: Color?

    var body: some View {
        let ink = color ?? theme.figureInk ?? theme.ink
        switch theme.figures {
        case .pixel:
            PanelPixelText(text: text, dot: size / 7, color: ink)
        case .segment:
            SegmentText(text: text, height: size, ink: ink)
        case .rounded:
            Text(verbatim: text)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink)
        case .serif:
            Text(verbatim: text)
                .font(.system(size: size, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(ink)
        case .flip:
            HStack(spacing: 2) {
                ForEach(Array(text.split(separator: ":").enumerated()), id: \.offset) { _, part in
                    Text(verbatim: String(part))
                        .font(.system(size: size * 0.86, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ink)
                        .padding(.horizontal, 3)
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.1))
                                Rectangle().fill(.black.opacity(0.3)).frame(height: 0.8)
                            }
                        }
                }
            }
        case .neon:
            Text(verbatim: text)
                .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(ink)
                .clockPanelGlow(theme.glow ?? ink, 2.5)
        case .nixie:
            Text(verbatim: text)
                .font(.system(size: size, weight: .light).monospacedDigit())
                .foregroundStyle(ink)
                .clockPanelGlow(ink, 2.5)
        }
    }
}

/// 一串七段数码：数字和“-”画成数码管，冒号画两个点，暗段留 7% 残影。
struct SegmentText: View {
    var text: String
    var height: CGFloat
    var ink: Color
    var ghost: Double = 0.07
    /// 冒号这一秒亮不亮。
    var colonOn = true

    var body: some View {
        let width = height * 0.52
        HStack(spacing: height * 0.14) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == ":" {
                    VStack(spacing: height * 0.28) {
                        Rectangle().frame(width: height * 0.1, height: height * 0.1)
                        Rectangle().frame(width: height * 0.1, height: height * 0.1)
                    }
                    .foregroundStyle(ink.opacity(colonOn ? 1 : ghost))
                } else if ch == " " {
                    SevenSegmentDigit(character: "8", on: ink.opacity(ghost), off: ink.opacity(ghost))
                        .frame(width: width, height: height)
                } else {
                    SevenSegmentDigit(character: ch, on: ink, off: ink.opacity(ghost))
                        .frame(width: width, height: height)
                }
            }
        }
        .accessibilityLabel(text)
    }
}

/// 一串 `PixelFont` 点阵字，暗点 7%。冒号可以单独灭掉（奇偶秒闪）。
struct PanelPixelText: View {
    var text: String
    var dot: CGFloat
    var color: Color
    var offOpacity: Double = 0.07
    var colonOn = true

    private var columns: Int {
        let cells = text.map { PixelFont.glyph($0)?.first?.count ?? ($0 == " " ? 2 : PixelFont.width) }
        return cells.reduce(0, +) + max(0, text.count - 1)
    }

    var body: some View {
        Canvas { context, _ in
            var x = 0
            for ch in text {
                let glyph = PixelFont.glyph(ch)
                let width = glyph?.first?.count ?? (ch == " " ? 2 : PixelFont.width)
                let blank = ch == ":" && !colonOn
                for row in 0..<PixelFont.height {
                    for column in 0..<width {
                        let lit = !blank && (glyph?[row][column] ?? false)
                        let rect = CGRect(x: CGFloat(x + column) * dot, y: CGFloat(row) * dot,
                                          width: dot * 0.82, height: dot * 0.82)
                        context.fill(Path(roundedRect: rect, cornerRadius: dot * 0.2),
                                     with: .color(lit ? color : color.opacity(offOpacity)))
                    }
                }
                x += width + 1
            }
        }
        .frame(width: CGFloat(columns) * dot, height: CGFloat(PixelFont.height) * dot)
        .accessibilityLabel(text)
    }
}

/// 面板新画的 7x7 点阵小图标：日、月、日历、闹钟。
struct PanelPixelIcon: View {
    enum Glyph {
        case sun, moon, calendar, bell

        var rows: [String] {
            switch self {
            case .sun: ["...#...", ".#...#.", "..###..", "#.###.#", "..###..", ".#...#.", "...#..."]
            case .moon: ["..###..", ".##....", "##.....", "##.....", "##.....", ".##....", "..###.."]
            case .calendar: ["#######", "#######", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#######"]
            case .bell: ["...#...", "..###..", ".#####.", ".#####.", ".#####.", "#######", "...#..."]
            }
        }
    }

    var glyph: Glyph
    var dot: CGFloat
    var color: Color

    var body: some View {
        Canvas { context, _ in
            for (row, line) in glyph.rows.enumerated() {
                for (column, ch) in line.enumerated() where ch == "#" {
                    let rect = CGRect(x: CGFloat(column) * dot, y: CGFloat(row) * dot,
                                      width: dot * 0.82, height: dot * 0.82)
                    context.fill(Path(roundedRect: rect, cornerRadius: dot * 0.2), with: .color(color))
                }
            }
        }
        .frame(width: dot * 7, height: dot * 7)
    }
}

// MARK: - 世界时钟

/// 三座城市一排。点一座城市可以换成别的（码头小组件库的预览里不能改）。
struct ClockPanelCities: View {
    var model: ClockPanelModel
    var theme: ClockPanelTheme
    var editable: Bool
    var onPick: (Int, WorldCity) -> Void
    /// 每座城市一张小卡片（经典、模拟表盘），否则三列直接排。
    var cards = false
    /// 卡片上画小表盘（模拟表盘面板）而不是日月图标。
    var dials = false

    var body: some View {
        HStack(alignment: .top, spacing: cards ? 8 : 10) {
            ForEach(Array(model.cities.enumerated()), id: \.offset) { slot, city in
                cell(slot, city)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 正在换的那一格，弹出共用的城市选择器（带搜索，别的格已有的城市打勾）。
    @State private var picking: Int?

    /// 三格对应的城市，给选择器判断“已添加”。
    private var chosen: [WorldCity] {
        model.cities.map { WorldCity(storage: "\($0.zone)|\($0.name)") ?? WorldCity(name: $0.name, zone: $0.zone) }
    }

    @ViewBuilder
    private func cell(_ slot: Int, _ city: ClockPanelData.CityTime) -> some View {
        let content = cards ? AnyView(card(city)) : AnyView(column(city))
        if editable {
            Button {
                // 选择器里要打字：先让面板成为 key。
                WidgetDetailWindow.shared.focusField {}
                picking = slot
            } label: {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点按换一座城市"))
            .popover(isPresented: Binding(get: { picking == slot },
                                          set: { if !$0 { picking = nil } }),
                     arrowEdge: .bottom) {
                let list = chosen
                WorldCityPicker(added: list.enumerated().filter { $0.offset != slot }.map(\.element),
                                mode: .replace,
                                current: slot < list.count ? list[slot] : nil,
                                listHeight: 260) { picked in
                    onPick(slot, picked)
                    picking = nil
                }
                .padding(14)
                .frame(width: 320)
            }
        } else {
            content
        }
    }

    private func column(_ city: ClockPanelData.CityTime) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(verbatim: city.name)
                    .font(theme.font(14, .semibold))
                    .foregroundStyle(theme.ink)
                dayIcon(city.isDay)
            }
            ClockPanelFigure(text: city.clock, size: theme.figures == .pixel ? 21 : 22, theme: theme)
            Text(ClockPanelData.relativeLine(city))
                .font(theme.font(13))
                .foregroundStyle(theme.dim)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func card(_ city: ClockPanelData.CityTime) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if dials {
                    AnalogClockFace(now: model.now, zone: TimeZone(identifier: city.zone) ?? .current, diameter: 20)
                } else {
                    Image(systemName: city.isDay ? "sun.max" : "moon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.dim)
                }
                Text(verbatim: city.name)
                    .font(theme.font(14, .semibold))
                    .foregroundStyle(theme.ink)
            }
            Text(verbatim: city.clock)
                .font(theme.font(19, .bold).monospacedDigit())
                .foregroundStyle(theme.ink)
            Text((city.isDay ? tr("昼") : tr("夜")) + " " + ClockPanelData.relativeLine(city))
                .font(theme.font(13))
                .foregroundStyle(theme.dim)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 10)
    }

    /// 白天亮太阳，晚上亮月亮。液晶两个都画，另一个留残影。
    @ViewBuilder
    private func dayIcon(_ isDay: Bool) -> some View {
        switch theme.figures {
        case .pixel:
            PanelPixelIcon(glyph: isDay ? .sun : .moon, dot: 1.7, color: isDay ? theme.accent : theme.dim)
        case .segment:
            HStack(spacing: 2) {
                Image(systemName: "sun.max.fill").foregroundStyle(theme.ink.opacity(isDay ? 1 : 0.1))
                Image(systemName: "moon.fill").foregroundStyle(theme.ink.opacity(isDay ? 0.1 : 1))
            }
            .font(.system(size: 11, weight: .semibold))
        default:
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.dim)
        }
    }
}

// MARK: - 农历和本周

/// 两张小卡：农历（日子和下一个节气）、本周（第几周、今年第几天）。
/// 中文面板头部已经写了农历，只留本周一张。
struct ClockPanelAlmanac: View {
    var model: ClockPanelModel
    var theme: ClockPanelTheme
    var showsLunar = true

    var body: some View {
        let daily = model.daily
        HStack(spacing: 10) {
            if showsLunar {
                box(title: tr("农历")) {
                    Text(verbatim: daily.lunar.date)
                        .font(theme.font(19, .semibold))
                        .foregroundStyle(theme.ink)
                } sub: {
                    if let term = daily.lunar.term {
                        Text(term)
                            .foregroundStyle(theme.accentTerm ? theme.accent : theme.dim)
                    }
                }
            }
            box(title: tr("本周")) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if showsLunar {
                        ClockPanelFigure(text: "\(daily.week)", size: 22, theme: theme)
                        Text(tr("周"))
                            .font(theme.font(14))
                            .foregroundStyle(theme.ink)
                    } else {
                        Text(tr("第 \(daily.week) 周"))
                            .font(theme.font(19, .semibold))
                            .foregroundStyle(theme.ink)
                    }
                }
            } sub: {
                Text(tr("今年第 \(daily.dayOfYear) 天"))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    private func box<Value: View, Sub: View>(title: String, @ViewBuilder value: () -> Value,
                                             @ViewBuilder sub: () -> Sub) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(theme.font(13))
                .foregroundStyle(theme.dim)
            value()
            sub()
                .font(theme.font(13))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.tile)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.tileStroke, lineWidth: 1)
        }
    }
}

// MARK: - 下一个日程、闹钟

/// 下一个日程和下一个闹钟，各一行；没有就不画那一行，两个都没有整块不画。
struct ClockPanelAgenda: View {
    var model: ClockPanelModel
    var theme: ClockPanelTheme

    static func hasContent(_ model: ClockPanelModel) -> Bool {
        visible(model.event, model.now) != nil || visible(model.alarm, model.now) != nil
    }

    /// 已经过了的不画，等下一分钟重新读。
    private static func visible(_ item: ClockPanelData.Upcoming?, _ now: Date) -> ClockPanelData.Upcoming? {
        guard let item, item.at > now else { return nil }
        return item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = Self.visible(model.event, model.now) {
                row(event, icon: .calendar, trailing: ClockPanelData.untilShort(event.at, now: model.now))
            }
            if let alarm = Self.visible(model.alarm, model.now) {
                row(alarm, icon: .bell, trailing: nil)
            }
        }
    }

    private func row(_ item: ClockPanelData.Upcoming, icon: PanelPixelIcon.Glyph, trailing: String?) -> some View {
        let title = [ClockPanelData.dayWord(item.at, now: model.now), item.title].compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 8) {
            glyph(icon)
            ClockPanelFigure(text: ClockPanelData.clockText(item.at), size: 17, theme: theme)
            Text(verbatim: title)
                .font(theme.font(14, .semibold))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(theme.font(13))
                    .foregroundStyle(theme.dim)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private func glyph(_ icon: PanelPixelIcon.Glyph) -> some View {
        if theme.figures == .pixel {
            PanelPixelIcon(glyph: icon, dot: 1.9, color: theme.dim)
        } else {
            Image(systemName: icon == .calendar ? "calendar" : "bell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.dim)
                .frame(width: 16)
        }
    }
}

// MARK: - 共用的下半截

/// 头部下面那一串信息模块，几套面板一样的顺序：今天进度、世界时钟、
/// 农历和本周、下一个日程和闹钟。经典和模拟表盘把世界时钟画成小卡片。
struct ClockPanelSections: View {
    var model: ClockPanelModel
    var theme: ClockPanelTheme
    var editable: Bool
    var onPick: (Int, WorldCity) -> Void
    var cityCards = false
    var dials = false
    var showsLunar = true
    var passedWording = false
    /// 放在农历和日程之间的东西（经典面板的时区行）。
    var extra: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClockPanelProgress(model: model, theme: theme, passedWording: passedWording)
            if !cityCards { ClockPanelRule(theme: theme) }
            ClockPanelCities(model: model, theme: theme, editable: editable, onPick: onPick,
                             cards: cityCards, dials: dials)
            if !cityCards { ClockPanelRule(theme: theme) }
            ClockPanelAlmanac(model: model, theme: theme, showsLunar: showsLunar)
            if let extra { extra }
            if ClockPanelAgenda.hasContent(model) {
                ClockPanelAgenda(model: model, theme: theme)
            }
        }
    }
}
