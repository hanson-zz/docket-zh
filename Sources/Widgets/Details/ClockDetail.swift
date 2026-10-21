import SwiftUI

/// 时钟的展开面板，样子跟着卡片的外观走。
///
/// 像素卡片开点阵屏，液晶卡片开七段数码管，标准开带天空的经典面板，模拟表盘、
/// 翻页、中文、霓虹、实景各有一套（`ClockPanelKind`，画法在 ClockPanelFaces.swift）。
/// Pro 样式没解锁时卡片画成翻页，面板也开翻页，卡片和面板对得上。
///
/// 几套面板的信息一样：时间到秒、日期、今天过了多少、三座城市的世界时钟、
/// 农历和下一个节气、第几周，以及下一个日程和下一个闹钟（没有就不显示）。
struct ClockDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 一天才变的（农历、节气、日出日落），每分钟重算一次。
    @State private var daily: ClockPanelDaily?
    /// 下一个日程和闹钟，也是每分钟读一次：日历查询不便宜，不必每秒做。
    @State private var event: ClockPanelData.Upcoming?
    @State private var alarm: ClockPanelData.Upcoming?

    /// 卡片实际画的画法，没解锁的 Pro 样式是翻页。
    private var face: ClockFace {
        ClockStyles.face(instance.config, unlocked: ProAccess.isUnlocked, preview: context.isPreview)
    }

    var body: some View {
        // The seconds have to be driven from here. `WidgetDetailChrome`
        // assigns its root view once when the panel opens, so `context.now` is
        // frozen for as long as it stays up and a second hand read from it
        // would sit perfectly still.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            panel(model(at: tick.date))
                .onChange(of: Int(tick.date.timeIntervalSince1970) / 60) { _, _ in refresh(tick.date) }
        }
        .onAppear { refresh(.now) }
    }

    private func model(at now: Date) -> ClockPanelModel {
        let second = Calendar.current.component(.second, from: now)
        return ClockPanelModel(
            now: now,
            digits: ClockDigits(now: now, zone: .current),
            progress: ClockPanelData.day(now),
            cities: ClockPanelData.cities(instance.config).map { ClockPanelData.cityTime($0, now: now) },
            daily: daily ?? ClockPanelDaily.at(now),
            event: event,
            alarm: alarm,
            // 冒号奇数秒灭；减少动态效果时不闪。
            colonOn: reduceMotion || second % 2 == 0,
            tint: panelTint)
    }

    /// 每分钟一次：农历这些一天的读数，下一个日程（没有日历权限是 nil，那一行
    /// 不显示），码头上各个闹钟卡片里最先要响的一个。
    private func refresh(_ now: Date) {
        daily = ClockPanelDaily.at(now)
        guard !context.isPreview else { return }
        event = CalendarEventStore.nextEvent(after: now)
        let alarms = TimedAlertDriver.shared.widgets().filter { $0.kind == .alarm }.map(\.config)
        alarm = ClockPanelData.nextAlarm(alarms, now: now)
    }

    @ViewBuilder
    private func panel(_ model: ClockPanelModel) -> some View {
        let input = ClockPanelInput(model: model, editable: !context.isPreview, onPick: pick)
        switch ClockPanelKind.of(face) {
        case .pixel: PixelClockPanel(input: input)
        case .lcd: LCDClockPanel(input: input)
        case .classic: ClassicClockPanel(input: input)
        case .analog: AnalogClockPanel(input: input)
        case .flip: FlipClockPanel(input: input, face: face)
        case .words: WordsClockPanel(input: input)
        case .neon: NeonClockPanel(input: input)
        case .nixie: NixieClockPanel(input: input)
        }
    }

    /// 世界时钟换城市：写回 `clockCities`，面板跟着刷新。
    private func pick(_ slot: Int, _ city: WorldCity) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { ClockPanelData.set(city, at: slot, in: &$0) }
    }
}

// MARK: - Shared panel parts
//
// Clock and World Clock are one panel pointed at two different zones, the same
// way their tiles are one readout pointed at two different zones. These live
// here for the same reason `ClockReadout` lives in ClockTile.swift.

/// The time to the second, in whichever clock the locale runs.
///
/// Built from the tile's own formatter rather than a second one, so the panel
/// and the card that opened it can never disagree about 24h versus 12h. The
/// seconds and the meridiem are stepped down and greyed: they are what the
/// panel adds, not what it leads with.
struct ClockPanelTime: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var now: Date
    var zone: TimeZone
    var size: CGFloat

    var body: some View {
        let parts = ClockFormat.compactTime(now, zone: zone)
        let seconds = ClockPanelFormat.seconds(now, zone: zone)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.time)
                .font(WidgetStyle.value(size))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(parts.time)
            Text(":\(seconds)")
                .font(WidgetStyle.value(size * 0.5))
                .foregroundStyle(panelTint.accent(or: WidgetStyle.secondary))
                .monospacedDigit()
                .rollingValue(seconds)
            if let meridiem = parts.meridiem {
                Text(meridiem)
                    .font(WidgetStyle.label(size * 0.36))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// A label and a figure on one line - the row idiom the system panel uses.
struct ClockPanelRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(WidgetStyle.label(13))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
                .rollingValue(value)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// What the panels add to `ClockFormat`, which stops at what a tile can fit.
enum ClockPanelFormat {
    /// The date the tile abbreviates to "Fri, 25 Sep", written out.
    static func fullDate(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// Two digits always, so the figure beside the minutes does not jump width
    /// nine times a minute.
    static func seconds(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let value = calendar.component(.second, from: date)
        return value < 10 ? "0\(value)" : "\(value)"
    }

    /// The zone as the system names it, and named for the half of the year it
    /// is currently in: a zone on summer time is "British Summer Time", not
    /// the standard name it will go back to in October.
    static func zoneName(_ zone: TimeZone, at date: Date) -> String {
        let style: NSTimeZone.NameStyle = zone.isDaylightSavingTime(for: date)
            ? .daylightSaving : .standard
        return zone.localizedName(for: style, locale: .current) ?? zone.identifier
    }

    /// "GMT+1", "GMT+5:30". Minutes only where the zone has them, and the
    /// typographic minus so the sign carries the digits' own weight.
    static func gmt(_ zone: TimeZone, at date: Date) -> String {
        let total = zone.secondsFromGMT(for: date)
        let sign = total < 0 ? "\u{2212}" : "+"
        let minutes = abs(total) / 60
        let rest = minutes % 60
        guard rest != 0 else { return "GMT\(sign)\(minutes / 60)" }
        return "GMT\(sign)\(minutes / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// How far a zone runs from this one, in words. Computed at a date rather
    /// than in the abstract because the gap moves twice a year, and the two
    /// zones rarely change on the same weekend.
    static func difference(_ zone: TimeZone, at date: Date) -> String {
        let delta = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard delta != 0 else { return tr("与此处时间相同") }
        let minutes = abs(delta) / 60
        var parts: [String] = []
        if minutes / 60 > 0 { parts.append(tr("\(minutes / 60) 小时")) }
        if minutes % 60 > 0 { parts.append(tr("\(minutes % 60) 分钟")) }
        return (delta > 0 ? tr("比此处快 ") : tr("比此处慢 ")) + parts.joined(separator: " ")
    }
}
