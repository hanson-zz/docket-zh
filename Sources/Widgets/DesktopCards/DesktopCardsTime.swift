import AppKit
import SwiftUI

// MARK: - 桌面卡片 · 时间组
//
// 时钟、世界时钟、秒表、专注计时、倒计时、闹钟、时间进度、一周日程、农历、纪念日、日历
// 钉在桌面时的专属布局。小 160×160 / 中 340×160 / 大 340×340 各排一版：
// - 小号：一个核心数字或状态，最多一个能点的操作。
// - 中号：核心加 2~4 个次要信息或一排操作。
// - 大号：核心加列表 / 月历 / 操作区，完整显示，不滚动。
// 每档列几条、挑哪几条在 Core 的 `DesktopTimeCards`。数据和扩展栏同一份：读
// `WidgetInstance` 的配置，改动照旧走 `WidgetWriter` 或各自的共享状态（专注计时是
// `TimerStateProvider`），扩展栏卡片和面板马上跟着变。卡片的玻璃底由 `DesktopCard` 画，
// 这里只画内容；字最小 13pt，浅色深色都用面板语义色，主题色当字时用 `panelReadable`。
//
// 文件：本文件是入口、共用零件、时钟、世界时钟、秒表；`+Timers` 是专注计时、倒计时、
// 闹钟；`+Days` 是时间进度、一周日程、农历、纪念日、日历。

@MainActor
enum DesktopCardsTime {
    /// 时间组的专属布局；不是本组的种类返回 nil，走通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopTimeCards.kinds.contains(widget.kind) else { return nil }
        let card: AnyView
        switch widget.kind {
        case .clock: card = AnyView(DeskClockCard(widget: widget, size: size, now: now))
        case .world: card = AnyView(DeskWorldCard(widget: widget, size: size, now: now))
        case .stopwatch: card = AnyView(DeskStopwatchCard(widget: widget, size: size, now: now))
        case .timer: card = AnyView(TimeDeskFocusCard(widget: widget, size: size, now: now))
        case .countdown: card = AnyView(TimeDeskCountdownCard(widget: widget, size: size, now: now))
        case .alarm: card = AnyView(TimeDeskAlarmCard(widget: widget, size: size, now: now))
        case .progress: card = AnyView(TimeDeskProgressCard(widget: widget, size: size, now: now))
        case .week: card = AnyView(TimeDeskWeekCard(widget: widget, size: size, now: now))
        case .lunar: card = AnyView(TimeDeskLunarCard(widget: widget, size: size, now: now))
        case .anniversary: card = AnyView(TimeDeskAnniversaryCard(widget: widget, size: size, now: now))
        case .calendar: card = AnyView(TimeDeskCalendarCard(widget: widget, size: size, now: now))
        default: return nil
        }
        return AnyView(card.frame(width: size.width, height: size.height))
    }

    /// 卡片内边距：小号 14，中 / 大 16。
    static func inset(_ size: DesktopPinSize) -> CGFloat { size == .small ? 14 : 16 }

    /// 写回这张卡片现在存着的那份配置（不写回旧的）。
    static func write(_ widget: WidgetInstance, _ change: (inout WidgetConfig) -> Void) {
        let current = WidgetWriter.current(widget.id) ?? widget
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { change(&$0) }
        }
    }

    /// 卡片上原来写死的强调色：颜色面板里选过就换成选的（和扩展栏卡片同一规则）。
    static func accent(_ widget: WidgetInstance, own: Color, dark: Bool) -> Color {
        let style = WidgetTintStyle(kind: widget.kind, config: widget.config)
        return style.isChosen ? style.main(dark: dark) : own
    }
}

// MARK: - 共用零件

/// 卡片左上角的小标题：图标 + 名字（13pt 次级字），右边可放一段说明。
struct TimeDeskHeader<Trailing: View>: View {
    var symbol: String
    var title: String
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.panelReadable)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension TimeDeskHeader where Trailing == EmptyView {
    init(symbol: String, title: String, tint: Color) {
        self.init(symbol: symbol, title: title, tint: tint) { EmptyView() }
    }
}

/// 圆形按钮：主操作是实心反色（浅色下黑底白字，深色下白底黑字），其余是薄玻璃底。
/// 不用主题色铺底，免得大块发光；点击区域就是整个圆。
struct TimeDeskRoundButton: View {
    var symbol: String
    var label: String
    var diameter: CGFloat = 40
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: max(13, diameter * 0.36), weight: .bold))
                .foregroundStyle(prominent ? Color.panelOnPrimary : Color.panelPrimary)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(prominent ? Color.panelPrimary : Color.panelFill)
                }
                .overlay {
                    if !prominent { Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 胶囊按钮：字 13~17pt，高 30~52。`highlight` 是淡主题色底（上次用的预设）。
struct TimeDeskPill: View {
    var title: String
    var symbol: String? = nil
    var prominent = false
    var highlight: Color? = nil
    var height: CGFloat = 32
    var fontSize: CGFloat = 14
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: max(13, fontSize - 1), weight: .bold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.panelOnPrimary : (highlight?.panelReadable ?? Color.panelPrimary))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                Capsule().fill(prominent ? Color.panelPrimary
                               : (highlight.map { $0.opacity(0.16) } ?? Color.panelFill))
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(highlight.map { $0.opacity(0.45) } ?? Color.panelStroke,
                                           lineWidth: highlight == nil ? 0.5 : 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 进度环：空轨道 + 主题色的一段（浅色下加深到看得清）。
struct TimeDeskRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.panelTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint.panelGraphic, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// 细进度条。
struct TimeDeskBar: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                Capsule().fill(tint.panelGraphic)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 空的时候：一句话 + 一句去哪里加。
struct TimeDeskEmpty: View {
    var symbol: String
    var title: String
    var hint: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color.panelTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 细分隔线（横或竖）。
struct TimeDeskRule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Color.panelSeparator)
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

/// 大号数字：圆体。调用处再加 `.monospacedDigit()`。
func timeDeskNumber(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

/// 「周二 10月27日」，跟着界面语言。
func timeDeskDate(_ date: Date, zone: TimeZone = .current) -> String {
    var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    style.timeZone = zone
    style.locale = L10n.interfaceLocale
    return date.formatted(style)
}

// MARK: - 时钟

/// 时钟：标准样式画桌面版的表盘和大字时间；选了别的样式（翻页、霓虹、辉光管……）时
/// 把那种样式的扩展栏卡片放大摆上去，下面补日期，样式和 Pro 规则照旧。
private struct DeskClockCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var face: ClockFace {
        ClockStyles.face(widget.config, unlocked: ProAccess.isUnlocked, preview: false)
    }

    private var isStandard: Bool {
        if case .standard = face { return true }
        return false
    }

    private var bold: Bool {
        if case .standard(let bold) = face { return bold }
        return false
    }

    var body: some View {
        if isStandard { standard } else { styled }
    }

    @ViewBuilder
    private var standard: some View {
        let time = ClockFormat.compactTime(now, zone: .current)
        switch size {
        case .small:
            VStack(spacing: 6) {
                DeskDial(widget: widget, now: now, diameter: 64)
                timeText(time, size: 28)
                Text(timeDeskDate(now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
            .padding(DesktopCardsTime.inset(size))
        case .medium:
            HStack(spacing: 20) {
                DeskDial(widget: widget, now: now, diameter: 118)
                VStack(alignment: .leading, spacing: 6) {
                    timeText(time, size: 50)
                    Text(timeDeskDate(now))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                    Text(DeskClockFacts.weekLine(now))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
        case .large:
            VStack(spacing: 12) {
                DeskDial(widget: widget, now: now, diameter: 156)
                VStack(spacing: 2) {
                    timeText(time, size: 40)
                    Text(timeDeskDate(now))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
                DeskClockFacts(now: now)
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    private func timeText(_ time: (time: String, meridiem: String?), size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: time.time)
                .font(.system(size: size, weight: bold ? .heavy : .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
            if let meridiem = time.meridiem {
                Text(verbatim: meridiem)
                    .font(.system(size: max(13, size * 0.32), weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// 别的样式：扩展栏卡片放大（`DesktopTileFit`，不缩小到设计尺寸以下），下面日期。
    @ViewBuilder
    private var styled: some View {
        switch size {
        case .small:
            DesktopTileFit(widget: widget, now: now, box: size.size)
        case .medium:
            VStack(spacing: 0) {
                DesktopTileFit(widget: widget, now: now, box: CGSize(width: 340, height: 120))
                Text(timeDeskDate(now))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .padding(.bottom, 14)
            }
        case .large:
            VStack(spacing: 8) {
                DesktopTileFit(widget: widget, now: now, box: CGSize(width: 340, height: 220))
                Text(timeDeskDate(now))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                DeskClockFacts(now: now)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }
}

/// 大表盘：12 个刻度（整点粗），时针分针，按小组件设置画秒针（颜色同扩展栏卡片）。
private struct DeskDial: View {
    var widget: WidgetInstance
    var now: Date
    var diameter: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let angles = ClockHands.angles(now, zone: .current)
        let seconds = ClockHands.showsSecondHand(widget.config)
        let secondColor = ClockHands.source(widget.config, unlocked: ProAccess.isUnlocked)
            .resolved(dark: scheme == .dark, on: .panel)
        ZStack {
            Circle().fill(Color.panelFill)
            Circle().strokeBorder(Color.panelStroke, lineWidth: 1)
            ForEach(0..<12, id: \.self) { index in
                let major = index % 3 == 0
                Capsule()
                    .fill(major ? Color.panelPrimary.opacity(0.8) : Color.panelTertiary)
                    .frame(width: major ? 2.5 : 1.5, height: diameter * (major ? 0.09 : 0.055))
                    .offset(y: -diameter * (major ? 0.395 : 0.41))
                    .rotationEffect(.degrees(Double(index) * 30))
            }
            hand(length: diameter * 0.25, width: max(3, diameter * 0.035), degrees: angles.hour)
            hand(length: diameter * 0.36, width: max(2.2, diameter * 0.022), degrees: angles.minute)
            if seconds {
                Capsule()
                    .fill(secondColor)
                    .frame(width: 1.4, height: diameter * 0.44)
                    .offset(y: -diameter * 0.16)
                    .rotationEffect(.degrees(angles.second))
                    .animation(nil, value: angles.second)
            }
            Circle()
                .fill(seconds ? secondColor : Color.panelPrimary)
                .frame(width: max(5, diameter * 0.05), height: max(5, diameter * 0.05))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
        Capsule()
            .fill(Color.panelPrimary)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

/// 大号底下一排三格：第几周、今天过了多少、今年还剩几天。
private struct DeskClockFacts: View {
    var now: Date

    static func week(_ now: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: now)
    }

    /// 中号第三行：「第 44 周 · 剩 65 天」。
    static func weekLine(_ now: Date) -> String {
        tr("第 \(week(now)) 周") + " · " + TimeProgress.remaining(.year, now: now)
    }

    var body: some View {
        let day = TimeProgress.percent(TimeProgress.fraction(.day, now: now))
        HStack(spacing: 8) {
            fact(tr("第 \(Self.week(now)) 周"), tr("本周"))
            fact("\(day)%", tr("今天已过"))
            fact(TimeProgress.remaining(.year, now: now), tr("今年"))
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
    }
}

// MARK: - 世界时钟

/// 世界时钟：小号一个别处的城市（大字时间、时差、能不能联系），中号三列，大号一城一行。
/// 格子外观跟扩展栏一样：普通透出玻璃，天空（Pro）画当地此刻的天空和地标，没解锁时画普通。
private struct DeskWorldCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var look: WorldClockLook {
        ProLicenseGate.worldClockLook(config: widget.config, unlocked: ProAccess.isUnlocked)
    }

    private var cities: [WorldCity] {
        let list = WorldClockList.cities(widget.config)
        return DesktopTimeCards.worldCities(list.isEmpty ? [WorldClockList.legacyCity(widget.config)] : list,
                                            size: size)
    }

    var body: some View {
        let list = cities
        switch size {
        case .small:
            if let city = list.first {
                DeskWorldCell(city: city, now: now, look: look, layout: .hero)
            }
        case .medium:
            HStack(spacing: look == .sky ? 6 : 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0, look == .plain {
                        TimeDeskRule(vertical: true).padding(.vertical, 22)
                    }
                    DeskWorldCell(city: city, now: now, look: look, layout: .column)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(look == .sky ? 8 : 0)
        case .large:
            VStack(spacing: 10) {
                TimeDeskHeader(symbol: "globe.asia.australia.fill",
                               title: WidgetCatalog.entry(.world)?.name ?? tr("世界时钟"),
                               tint: Color.panelSecondary) {
                    Text(tr("此处 \(ClockFormat.time(now, zone: .current))"))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
                VStack(spacing: look == .sky ? 6 : 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                        if index > 0, look == .plain { TimeDeskRule() }
                        DeskWorldCell(city: city, now: now, look: look, layout: .row)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }
}

/// 一个城市：天空格子自己画底和地标，普通格子透明。
private struct DeskWorldCell: View {
    enum Layout { case hero, column, row }

    var city: WorldCity
    var now: Date
    var look: WorldClockLook
    var layout: Layout

    private var zone: TimeZone { city.timeZone ?? .current }
    private var isHere: Bool { city.id == WorldCities.reference()?.id }

    var body: some View {
        let phase = WorldClockSky.phase(city, now: now)
        let sky = look == .sky
        let ink = sky ? Color(sky: WorldClockSky.ink(phase)) : Color.panelPrimary
        let soft = sky ? ink.opacity(0.82) : Color.panelSecondary
        ZStack {
            if sky {
                LinearGradient(colors: WorldClockSky.colors(phase).map { Color(sky: $0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                CityLandmarkMark(landmark: city.landmark, color: ink.opacity(0.4), lineWidth: 1)
                    .frame(width: layout == .row ? 30 : 40, height: layout == .row ? 30 : 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            }
            content(ink: ink, soft: soft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(city.name), \(ClockFormat.time(now, zone: zone)), \(WorldClockText.offsetLine(city, now: now))")
    }

    private var time: (time: String, meridiem: String?) { ClockFormat.compactTime(now, zone: zone) }

    /// 那边不是同一天时的「明天」「昨天」。
    private var dayHint: String? { WorldClockTile.dayHint(now, zone: zone) }

    private var offsetLine: String {
        let line = WorldClockText.offsetLine(city, now: now)
        return dayHint.map { "\($0) · \(line)" } ?? line
    }

    /// 格子窄时的时差：「−12 小时」，此处写「此处」。
    private var shortOffset: String {
        isHere ? tr("此处") : DesktopTimeCards.shortOffset(WorldClockText.offsetSeconds(zone, now: now))
    }

    private var hour: Int {
        var calendar = Calendar.current
        calendar.timeZone = zone
        return calendar.component(.hour, from: now)
    }

    @ViewBuilder
    private func content(ink: Color, soft: Color) -> some View {
        switch layout {
        case .hero:
            VStack(alignment: .leading, spacing: 4) {
                nameLine(ink: ink, size: 15)
                Spacer(minLength: 0)
                bigTime(ink: ink, soft: soft, size: 44)
                Text(dayHint.map { "\(shortOffset) · \($0)" } ?? shortOffset)
                    .font(.system(size: 13))
                    .foregroundStyle(soft)
                    .lineLimit(1)
                if !isHere {
                    Text(WorldClockContact.reason(there: zone, now: now).text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .column:
            VStack(spacing: 4) {
                nameLine(ink: ink, size: 14)
                bigTime(ink: ink, soft: soft, size: 32)
                Text(dayHint ?? WorldClockText.dayPart(hour: hour))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(soft)
                    .lineLimit(1)
                Text(shortOffset)
                    .font(.system(size: 13))
                    .foregroundStyle(soft)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .row:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    nameLine(ink: ink, size: 15)
                    Text(offsetLine)
                        .font(.system(size: 13))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                bigTime(ink: ink, soft: soft, size: 26)
            }
            .padding(.leading, 12)
            .padding(.trailing, look == .sky ? 44 : 12)
        }
    }

    private func nameLine(ink: Color, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: city.name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
            if !isHere {
                ContactDot(level: WorldClockContact.reason(there: zone, now: now).level, size: 8)
            }
        }
    }

    private func bigTime(ink: Color, soft: Color, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: time.time)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ink)
            if let meridiem = time.meridiem {
                Text(verbatim: meridiem)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(soft)
            }
        }
        .lineLimit(1)
    }
}

// MARK: - 秒表

/// 秒表：大数字带两位小数（跑着时一秒 10 帧），开始 / 暂停直接点。中号右边最近三圈，
/// 大号下面计次表，最快绿、最慢红。状态是小组件自己的配置，和扩展栏、面板同一份。
private struct DeskStopwatchCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    var body: some View {
        let running = StopwatchLaps.isRunning(widget.config)
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: !running)) { tick in
            content(now: running ? tick.date : now, running: running)
        }
    }

    private var title: String { WidgetCatalog.entry(.stopwatch)?.name ?? tr("秒表") }

    @ViewBuilder
    private func content(now: Date, running: Bool) -> some View {
        let elapsed = StopwatchLaps.elapsed(widget.config, now: now)
        let laps = StopwatchLaps.laps(widget.config)
        switch size {
        case .small:
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                figure(elapsed, size: 36)
                Text(StopwatchLaps.caption(running: running, elapsed: elapsed, lapCount: laps.count))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if running {
                        TimeDeskPill(title: tr("计次"), height: 34) { StopwatchActions.lap(widget) }
                        TimeDeskRoundButton(symbol: "pause.fill", label: tr("暂停"), diameter: 34, prominent: true) {
                            StopwatchActions.toggle(widget)
                        }
                    } else {
                        if elapsed > 0 {
                            TimeDeskRoundButton(symbol: "arrow.counterclockwise", label: tr("重置"), diameter: 34) {
                                StopwatchActions.reset(widget)
                            }
                        }
                        TimeDeskPill(title: elapsed > 0 ? tr("继续") : tr("开始"), symbol: "play.fill",
                                     prominent: true, height: 34) { StopwatchActions.toggle(widget) }
                    }
                }
            }
            .padding(DesktopCardsTime.inset(size))
        case .medium:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    TimeDeskHeader(symbol: "stopwatch", title: title, tint: Color.timerGreen)
                    figure(elapsed, size: 44)
                    controls(running: running, elapsed: elapsed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !laps.isEmpty {
                    TimeDeskRule(vertical: true).padding(.vertical, 6)
                    lapList(laps, limit: DesktopTimeCards.rows(.stopwatch, .medium))
                        .frame(width: 118)
                }
            }
            .padding(DesktopCardsTime.inset(size))
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                TimeDeskHeader(symbol: "stopwatch", title: title, tint: Color.timerGreen) {
                    if !laps.isEmpty {
                        Text(tr("本圈 \(StopwatchLaps.lapText(StopwatchLaps.currentLap(laps, elapsed: elapsed)))"))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                figure(elapsed, size: 60)
                    .frame(maxWidth: .infinity)
                controls(running: running, elapsed: elapsed)
                TimeDeskRule()
                if laps.isEmpty {
                    Text(running ? tr("点「计次」记下这一圈") : tr("开始后可以计次"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    lapList(laps, limit: DesktopTimeCards.rows(.stopwatch, .large))
                    Spacer(minLength: 0)
                }
            }
            .padding(DesktopCardsTime.inset(size))
        }
    }

    private func figure(_ elapsed: TimeInterval, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(StopwatchLaps.main(elapsed))
                .font(timeDeskNumber(size))
                .foregroundStyle(Color.panelPrimary)
            Text(StopwatchLaps.hundredths(elapsed))
                .font(timeDeskNumber(max(13, size * 0.6), .semibold))
                .foregroundStyle(Color.panelSecondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// 跑着：计次、暂停。停着：开始（或继续），有数时重置。
    private func controls(running: Bool, elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            if running {
                TimeDeskPill(title: tr("计次"), symbol: "flag.fill") { StopwatchActions.lap(widget) }
                TimeDeskPill(title: tr("暂停"), symbol: "pause.fill", prominent: true) {
                    StopwatchActions.toggle(widget)
                }
            } else {
                if elapsed > 0 {
                    TimeDeskPill(title: tr("重置"), symbol: "arrow.counterclockwise") { StopwatchActions.reset(widget) }
                }
                TimeDeskPill(title: elapsed > 0 ? tr("继续") : tr("开始"), symbol: "play.fill", prominent: true) {
                    StopwatchActions.toggle(widget)
                }
            }
        }
    }

    private func lapList(_ laps: [TimeInterval], limit: Int) -> some View {
        VStack(spacing: 6) {
            ForEach(DesktopTimeCards.lapRows(laps, limit: limit), id: \.number) { row in
                HStack(spacing: 6) {
                    Text(tr("第 \(row.number) 圈"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                    Spacer(minLength: 2)
                    if size == .large, row.fastest || row.slowest {
                        Text(row.fastest ? tr("最快") : tr("最慢"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle((row.fastest ? Color.timerGreen : Color.timerTomato).panelReadable)
                    }
                    Text(StopwatchLaps.lapText(row.seconds))
                        .font(timeDeskNumber(15, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.fastest ? Color.timerGreen.panelReadable
                                         : (row.slowest ? Color.timerTomato.panelReadable : Color.panelPrimary))
                }
                .lineLimit(1)
            }
        }
    }
}
