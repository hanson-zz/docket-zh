import SwiftUI

/// Current conditions for one city: symbol, temperature and a caption (the
/// city, the condition, wind, the next sunrise or sunset), or the forecast:
/// a day row of 7 or 10 days, an hourly strip, or several cities.
///
/// Four layouts, read through `WeatherStyle` so a card still holding one of
/// the seven old layout values draws as its new layout and option. Within two
/// hours of rain the Current caption says so first: 约 40 分钟后有雨.
struct WeatherTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Warm card. The weather tile is the one tinted widget in the shelf, and
    /// the tint is part of how it reads at a glance.
    private static let sample = WeatherNow(temperatureC: 18,
                                           symbolName: "cloud.sun.fill",
                                           condition: tr("多云"),
                                           windSpeed: 4.2, windFrom: 45, humidity: 62)

    private var layout: String { WeatherStyle.layout(instance.config) }
    private var captionChoice: WeatherStyle.Caption { WeatherStyle.caption(instance.config) }
    private var fahrenheit: Bool { instance.config.bool("fahrenheit") }
    private var showTips: Bool { instance.config.bool(WeatherTips.showKey, default: true) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// An empty `city` means "wherever I am".
    ///
    /// That is the default now. The shipped default was "Oslo" - the city in
    /// the reference screenshots - and a widget that confidently reports the
    /// weather somewhere the user has never been is worse than one that asks.
    private var city: String {
        let stored = instance.config.string("city").trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty { return stored }
        return LocationService.shared.city ?? ""
    }

    /// What the tile says where the city goes.
    ///
    /// Never blank. This app is an accessory and never becomes frontmost, so
    /// a location prompt can go unseen the same way the automation one does -
    /// and a widget showing "--°" under no name at all gives the user nothing
    /// to act on. Say which of the two states it is in.
    private var placeCaption: String {
        if !city.isEmpty { return city }
        let service = LocationService.shared
        return (service.denied || service.unavailable) ? tr("设置城市…") : tr("正在定位…")
    }

    /// The library has no live data, so it shows the reference sample.
    private var weather: WeatherNow? {
        context.isPreview ? Self.sample : WeatherService.shared.current
    }

    private var hours: [WeatherHour] {
        context.isPreview ? Self.sampleHours(from: context.now) : WeatherService.shared.hourly
    }

    var body: some View {
        // No tint of its own. Weather ran an orange card while the clock,
        // battery and activity tiles beside it used the neutral recess, which
        // is the inconsistency - the reference shelf tints only what is
        // genuinely coloured (a sticky note's paper), never a readout.
        WidgetSurface {
            if context.position.isVertical {
                switch layout {
                case WeatherStyle.forecastLayout: forecastColumn
                case WeatherStyle.citiesLayout: citiesColumn
                default: column
                }
            } else {
                switch layout {
                case WeatherStyle.forecastLayout: forecastRow
                case WeatherStyle.citiesLayout: citiesRow
                case WeatherStyle.hourlyLayout: hourlyStrip
                default: wide(caption: currentCaption, tip: cardTip)
                }
            }
        }
        .onAppear { load() }
        .onChange(of: city) { load() }
        .onChange(of: layout) { load() }
        .onChange(of: cities) { load() }
        .onChange(of: showTips) { load() }
        // The shared place can move under this tile (the last city set
        // wins), and the daily forecast has to follow it.
        .onChange(of: sharedPlaceKey) {
            guard !context.isPreview else { return }
            Task { await refreshForecasts() }
        }
        // `now` ticks every second; only act when the 15-minute bucket turns
        // over, which is the cadence MET asks for anyway.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 900) {
            guard !context.isPreview else { return }
            Task {
                await WeatherService.shared.refresh()
                await refreshForecasts()
            }
        }
    }

    private var sharedPlaceKey: String {
        guard let place = WeatherService.shared.place else { return "" }
        return DailyForecast.cacheKey(lat: place.lat, lon: place.lon)
    }

    /// The daily forecasts behind the 7-day, 10-day and multi-city layouts.
    /// Each place is throttled to one fetch per 30 minutes inside the
    /// service, so calling this on every 15-minute tick costs nothing.
    private func refreshForecasts() async {
        // 暖心提示要的降水概率、紫外线、空气质量和昨天今天明天的最高最低温。
        // 两个服务各自限流（15 分钟、30 分钟），每 15 分钟调一次不多花。
        if wantsTips, let place = WeatherService.shared.place {
            await WeatherExtrasService.shared.refresh(place)
            if layout != WeatherStyle.forecastLayout { await ForecastService.shared.refresh(place) }
        }
        switch layout {
        case WeatherStyle.forecastLayout:
            if let place = WeatherService.shared.place {
                await ForecastService.shared.refresh(place)
            }
        case WeatherStyle.citiesLayout:
            await ForecastService.shared.load(cities: cities)
        default:
            break
        }
    }

    private func load() {
        guard !context.isPreview else { return }
        // The multi-city card is its own list of places. It never points the
        // shared service at a city, so the other weather tiles keep theirs.
        if layout == WeatherStyle.citiesLayout {
            Task { await refreshForecasts() }
            return
        }
        // Asked for only because a weather widget is on the shelf, and only
        // when no city has been typed in.
        if instance.config.string("city").trimmingCharacters(in: .whitespaces).isEmpty {
            LocationService.shared.start()
        }
        let city = city
        guard !city.isEmpty else { return }
        Task {
            await WeatherService.shared.setLocation(city: city)
            await refreshForecasts()
        }
    }

    /// Wind and the next sunrise or sunset: the two things the forecast
    /// already knows, or can work out, beyond the temperature. The caption
    /// option picks one of them or both.
    private func skyCaption(wind: Bool, sun: Bool) -> String {
        var parts: [String] = []
        if wind, let weather, let speed = weather.windSpeed {
            let force = Wind.beaufort(speed)
            parts.append(force == 0 ? tr("无风") : tr("\(Wind.direction(weather.windFrom ?? 0)) \(force) 级"))
        }
        if sun, let next = WeatherSun.next(after: context.now, preview: context.isPreview) {
            parts.append("\(next.rising ? tr("日出") : tr("日落")) \(WeatherSun.time(next.date, zone: next.zone))")
        }
        return parts.isEmpty ? placeCaption : parts.joined(separator: " · ")
    }

    /// Minutes until rain within the next two hours, from the hourly
    /// forecast the card already fetches; nil when it is dry or already raining.
    private var minutesUntilRain: Int? {
        WeatherStyle.minutesUntilRain(now: context.now, currentHourMM: weather?.precipitationMM,
                                      hours: hours.map { (start: $0.date, mm: $0.precipitationMM) })
    }

    // MARK: - 暖心提示

    /// 只有横排的“当前”样式有地方放一行提示。
    private var wantsTips: Bool {
        showTips && !context.position.isVertical && layout == WeatherStyle.currentLayout
    }

    /// 卡片上轮到的那一句，每 8 秒换下一句（`context.now` 每秒走一次，不另开定时器）。
    /// 副标题已经在说“约 40 分钟后有雨”时，降雨那句不再重复。
    private var cardTip: WeatherTips.Tip? {
        guard wantsTips, let weather else { return nil }
        let place = WeatherService.shared.place
        let nowcast = context.isPreview ? nil : place.flatMap { WeatherExtrasService.shared.nowcast(at: $0) }
        let aqi = context.isPreview ? nil : place.flatMap { WeatherExtrasService.shared.aqi(at: $0) }
        let zone = WeatherSun.place(preview: context.isPreview)?.zone ?? .current
        var tips = WeatherTips.tips(WeatherTipSource.input(weather: weather, nowcast: nowcast, aqi: aqi,
                                                           forecast: dailyForecast, now: context.now,
                                                           zone: zone, fahrenheit: fahrenheit))
        if minutesUntilRain != nil { tips.removeAll { $0.kind == .rain } }
        return WeatherTips.rotating(tips, now: context.now)
    }

    /// The Current layout's third line: rain on its way wins, then the chosen caption.
    private var currentCaption: String {
        if let minutes = minutesUntilRain { return WeatherStyle.rainSoonText(minutes: minutes) }
        switch captionChoice {
        case .city: return placeCaption
        case .condition: return weather?.condition ?? "-"
        case .wind, .sun, .sky: return skyCaption(wind: captionChoice.showsWind, sun: captionChoice.showsSun)
        }
    }

    // MARK: - Layouts

    /// The shelf's badge and reading: the condition's symbol in the square,
    /// the temperature over a caption beside it. The caption shrinks to one
    /// line like every other tile's, so a long condition reads smaller rather
    /// than pushing a second line out of the card.
    ///
    /// 暖心提示（`tip`）在下面加一行 13pt：先试整句，放不下换短句，再放不下就不显示，
    /// 不缩字、不挤上面的读数（ViewThatFits 只挑放得下的那一版）。
    @ViewBuilder private func wide(caption: String, tip: WeatherTips.Tip? = nil) -> some View {
        let row = HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge { icon(size: 19) }
            TileReading(value: weather.map { degrees($0.temperatureC) } ?? "--°", caption: caption)
            Spacer(minLength: 0)
        }
        if let tip {
            // 高度放不下第三行时整行不要；宽度上先整句、再短句，都放不下就空着。
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    row
                    ViewThatFits(in: .horizontal) {
                        tipLine(tip.text)
                        tipLine(tip.short)
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                row
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tip.text)
        } else {
            row
        }
    }

    private func tipLine(_ text: String) -> some View {
        WeatherTipLine(text: text)
            .id(text)
            .transition(.opacity)
    }

    /// The next few hours, each a small symbol over its temperature. Falls
    /// back to the single reading while the forecast is still empty.
    @ViewBuilder private var hourlyStrip: some View {
        if hours.isEmpty {
            wide(caption: placeCaption)
        } else {
            // Four ahead, not five, because the first cell is now.
            //
            // The series is filtered to times after the present, so this
            // strip showed five future hours and not the temperature
            // outside, which is the number anybody looking at a weather
            // widget wants first. Leading with it costs one forecast hour,
            // which is the cheapest thing on the row.
            let shown = Array(hours.prefix(4))
            // Only when there is something to say. A dry afternoon would
            // otherwise get five empty gutters, which is chrome pretending to
            // be data and costs the strip height it needs for the figures.
            let wet = shown.contains { $0.precipitationMM >= 0.1 }
            // Scaled to the heaviest hour on screen rather than to a fixed
            // ceiling: 2mm against a 10mm scale is a stub that reads as none
            // at all, and what the strip is for is the shape of the next few
            // hours against each other.
            let peak = max(0.2, shown.map(\.precipitationMM).max() ?? 0)
            HStack(spacing: 0) {
                if let weather {
                    VStack(spacing: 1) {
                        Text("现在")
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WidgetStyle.primary)
                            .font(.system(size: 15))
                        Text(degrees(weather.temperatureC))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                        // An empty gutter rather than none, so the row of
                        // figures keeps one baseline when the rest are wet.
                        if wet { rain(0, peak: peak) }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
                ForEach(shown, id: \.date) { hour in
                    VStack(spacing: 1) {
                        Text(hour.date.formatted(.dateTime.hour()))
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WidgetStyle.primary)
                            .font(.system(size: 15))
                        Text(degrees(hour.temperatureC))
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                        if wet { rain(hour.precipitationMM, peak: peak) }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// How much rain this hour is bringing, against the heaviest on screen.
    ///
    /// A track behind the fill, so an hour with none still reads as an hour
    /// that was asked rather than as a gap in the row. Floored at a sliver
    /// once there is any at all: a hair of drizzle rounding away to nothing
    /// would say "dry" for an hour that is not.
    private func rain(_ mm: Double, peak: Double) -> some View {
        let height: CGFloat = 5
        return Capsule()
            .fill(WidgetStyle.secondary.opacity(0.22))
            .frame(width: 14, height: height)
            .overlay(alignment: .bottom) {
                if mm >= 0.05 {
                    Capsule()
                        .fill(Self.rainBlue)
                        .frame(width: 14, height: max(1.5, height * min(1, mm / peak)))
                }
            }
            .accessibilityLabel(mm >= 0.05
                                ? "\(mm.formatted(.number.precision(.fractionLength(1))))mm"
                                : tr("无降水"))
    }

    private static let rainBlue = Color(hex: "#5AC8FA")

    /// 56pt of usable width: everything centred and stacked, the symbol
    /// smaller and the caption down to a single tight line.
    private var column: some View {
        VStack(spacing: 2) {
            icon(size: 21)
            temperature(weather?.temperatureC, size: 17)
            Text(columnCaption)
                .font(WidgetStyle.caption(10))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// What the third line says on a 76pt column.
    ///
    /// Hourly used to fall through to the city, so on a side shelf it was
    /// indistinguishable from Current and the style picker appeared to do
    /// nothing. Eight columns of forecast genuinely do not fit here, so it
    /// shows the part of the forecast that does: the next hour.
    private var columnCaption: String {
        switch layout {
        case WeatherStyle.hourlyLayout:
            guard let next = hours.first else { return city }
            let hour = next.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))
            return "\(hour)  \(degrees(next.temperatureC))"
        default:
            // 56pt 宽放不下“风 · 日出”，竖排只写城市或天气状况；快下雨时照样先说雨，用短文案。
            if let minutes = minutesUntilRain { return WeatherStyle.rainSoonShortText(minutes: minutes) }
            return captionChoice == .condition ? (weather?.condition ?? "-") : city
        }
    }

    // MARK: - Daily forecast and cities

    /// The multi-city card's places, cleaned and capped at three.
    private var cities: [String] {
        WeatherLayout.cities(instance.config.strings("cities", default: WeatherLayout.defaultCities))
    }

    /// The daily forecast for the shared city, the same place the other
    /// layouts report.
    private var dailyForecast: DailyForecast? {
        if context.isPreview { return Self.sampleForecast(now: context.now) }
        return WeatherService.shared.place.flatMap { ForecastService.shared.forecast(at: $0) }
    }

    private func cityForecast(_ city: String, index: Int) -> DailyForecast? {
        context.isPreview
            ? Self.sampleCityForecast(index, now: context.now)
            : ForecastService.shared.forecast(city: city)
    }

    /// A row of day columns, like the system's own weather turned on its
    /// side: the day, its symbol, high and low, and a bar placing the day's
    /// range on the scale of every day shown. Falls back to the single
    /// reading until the forecast lands.
    @ViewBuilder private var forecastRow: some View {
        let forecast = dailyForecast
        let shown = forecast?.upcoming(now: context.now, limit: WeatherLayout.days(instance.config)) ?? []
        if shown.isEmpty {
            wide(caption: placeCaption)
        } else {
            let today = forecast?.todayKey(now: context.now) ?? ""
            let scale = DailyForecast.scale(shown)
            HStack(spacing: 0) {
                ForEach(shown, id: \.key) { day in
                    VStack(spacing: 2) {
                        Text(DailyForecast.weekdayLabel(day.key, today: today))
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(day.key == today ? WidgetStyle.primary : WidgetStyle.secondary)
                        Image(systemName: WMOWeather.symbol(day.code))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WidgetStyle.primary)
                            .font(.system(size: 13))
                            .frame(height: 14)
                        HStack(spacing: 2) {
                            Text(degrees(day.highC))
                                .foregroundStyle(WidgetStyle.primary)
                            Text(degrees(day.lowC))
                                .foregroundStyle(WidgetStyle.secondary)
                        }
                        .font(WidgetStyle.label(11))
                        .monospacedDigit()
                        rangeBar(day, scale: scale, width: 28)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(DailyForecast.weekdayLabel(day.key, today: today))，"
                                        + "\(WMOWeather.condition(day.code))，"
                                        + tr("最高 \(degrees(day.highC))，最低 \(degrees(day.lowC))"))
                }
            }
        }
    }

    /// A 76pt column has room for a row per day and no columns: the day,
    /// its symbol and the high. Fewer days than the wide layout, so the tile
    /// stays a tile rather than a tower.
    @ViewBuilder private var forecastColumn: some View {
        let forecast = dailyForecast
        let shown = forecast?.upcoming(now: context.now, limit: WeatherLayout.columnDays(instance.config)) ?? []
        if shown.isEmpty {
            column
        } else {
            let today = forecast?.todayKey(now: context.now) ?? ""
            VStack(spacing: 0) {
                ForEach(shown, id: \.key) { day in
                    HStack(spacing: 2) {
                        Text(DailyForecast.weekdayLabel(day.key, today: today))
                            .font(WidgetStyle.caption(10))
                            .foregroundStyle(day.key == today ? WidgetStyle.primary : WidgetStyle.secondary)
                        Image(systemName: WMOWeather.symbol(day.code))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WidgetStyle.primary)
                            .font(WidgetStyle.note)
                            .frame(width: 14)
                        Spacer(minLength: 0)
                        Text(degrees(day.highC))
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: WeatherLayout.dayRowHeight)
                }
            }
        }
    }

    /// Up to three places side by side: symbol, city, the temperature now
    /// and today's high and low.
    private var citiesRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                cityCell(city, forecast: cityForecast(city, index: index))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func cityCell(_ city: String, forecast: DailyForecast?) -> some View {
        let now = forecast?.current
        let today = forecast?.today(now: context.now)
        return HStack(spacing: 5) {
            Image(systemName: citySymbol(forecast))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WidgetStyle.primary)
                .font(.system(size: 16))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(city)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(WidgetStyle.secondary)
                Text(now.map { degrees($0.temperatureC) } ?? "--°")
                    .font(WidgetStyle.value(16))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                Text(today.map { "\(degrees($0.highC))/\(degrees($0.lowC))" } ?? " ")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// The side-shelf version: each city its name over symbol and reading.
    private var citiesColumn: some View {
        VStack(spacing: 0) {
            ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                let forecast = cityForecast(city, index: index)
                VStack(spacing: 1) {
                    Text(city)
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: citySymbol(forecast))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WidgetStyle.primary)
                            .font(.system(size: 12))
                        Text(forecast?.current.map { degrees($0.temperatureC) } ?? "--°")
                            .font(WidgetStyle.title)
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: WeatherLayout.cityRowHeight)
            }
        }
    }

    /// Now if known, else today, else a neutral sky.
    private func citySymbol(_ forecast: DailyForecast?) -> String {
        if let now = forecast?.current { return WMOWeather.symbol(now.code, isDay: now.isDay) }
        if let day = forecast?.today(now: context.now) { return WMOWeather.symbol(day.code) }
        return "cloud.sun.fill"
    }

    /// The day's low to high, on the scale of every day shown. Cool to warm
    /// like the system's bar, so a cold day reads at a glance.
    private func rangeBar(_ day: DailyForecast.Day, scale: (low: Double, high: Double)?,
                          width: CGFloat) -> some View {
        let fractions: (start: Double, end: Double) = scale.map {
            DailyForecast.rangeFractions(low: day.lowC, high: day.highC, scaleLow: $0.low, scaleHigh: $0.high)
        } ?? (0, 1)
        let length = max(3, width * (fractions.end - fractions.start))
        let offset = min(width * fractions.start, width - length)
        return Capsule()
            .fill(WidgetStyle.secondary.opacity(0.22))
            .frame(width: width, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Self.rainBlue, Self.warm],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: length, height: 3)
                    .offset(x: offset)
            }
            .accessibilityHidden(true)
    }

    private static let warm = Color(hex: "#FF9F0A")

    // MARK: - Pieces

    private func icon(size: CGFloat) -> some View {
        // Hierarchical white rather than multicolour: a yellow sun and blue
        // rain were the loudest marks on a neutral shelf.
        Image(systemName: weather?.symbolName ?? "cloud.sun.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WidgetStyle.primary)
            .font(.system(size: size))
            .frame(height: size)
    }

    /// Big figure with a lighter degree mark riding on top of it. A missing
    /// reading shows dashes - never a zero that could pass for real weather.
    private func temperature(_ celsius: Double?, size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(celsius.map { String(Int(converted($0).rounded())) } ?? "--")
                .font(WidgetStyle.value(size))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
            Text("°")
                .font(WidgetStyle.value(size * 0.7))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func degrees(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))°"
    }

    private func converted(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// Ten days for the library, starting today on this Mac's calendar.
    static func sampleForecast(now: Date) -> DailyForecast {
        let offset = TimeZone.current.secondsFromGMT(for: now)
        let highs: [Double] = [19, 21, 22, 18, 15, 16, 20, 23, 22, 19]
        let lows: [Double] = [11, 12, 14, 12, 9, 8, 10, 13, 14, 12]
        let codes = [2, 0, 1, 61, 63, 3, 2, 0, 0, 80]
        let days = (0..<10).map { index in
            DailyForecast.Day(key: DailyForecast.dayKey(now.addingTimeInterval(Double(index) * 86_400),
                                                        utcOffsetSeconds: offset),
                              code: codes[index], highC: highs[index], lowC: lows[index])
        }
        return DailyForecast(current: .init(temperatureC: 18, code: 2), days: days, utcOffsetSeconds: offset)
    }

    /// Three different skies for the multi-city sample.
    static func sampleCityForecast(_ index: Int, now: Date) -> DailyForecast {
        let offset = TimeZone.current.secondsFromGMT(for: now)
        let samples: [(now: Double, code: Int, high: Double, low: Double)] = [
            (16, 0, 20, 9), (21, 2, 23, 17), (27, 61, 29, 23),
        ]
        let sample = samples[index % samples.count]
        let day = DailyForecast.Day(key: DailyForecast.dayKey(now, utcOffsetSeconds: offset),
                                    code: sample.code, highC: sample.high, lowC: sample.low)
        return DailyForecast(current: .init(temperatureC: sample.now, code: sample.code),
                             days: [day], utcOffsetSeconds: offset)
    }

    private static func sampleHours(from date: Date) -> [WeatherHour] {
        let temperatures: [Double] = [18, 19, 19, 17, 16]
        let symbols = ["cloud.sun.fill", "sun.max.fill", "cloud.sun.fill", "cloud.rain.fill", "cloud.fill"]
        return zip(temperatures, symbols).enumerated().map { index, pair in
            WeatherHour(date: date.addingTimeInterval(Double(index + 1) * 3600),
                        temperatureC: pair.0,
                        symbolName: pair.1)
        }
    }
}

/// Sun times for wherever the weather is for, on that place's own clock.
enum WeatherSun {
    struct Place {
        var lat: Double
        var lon: Double
        var zone: TimeZone
    }

    /// The library has no place, so its sample is Oslo.
    static let samplePlace = Place(lat: 59.9139, lon: 10.7522,
                                   zone: TimeZone(identifier: "Europe/Oslo") ?? .current)

    @MainActor
    static func place(preview: Bool) -> Place? {
        if preview { return samplePlace }
        guard let found = WeatherService.shared.place else { return nil }
        // The map lookup names the zone; without one, this Mac's is the
        // honest fallback rather than a guess from the longitude.
        let zone = found.zone.flatMap(TimeZone.init(identifier:)) ?? .current
        return Place(lat: found.lat, lon: found.lon, zone: zone)
    }

    @MainActor
    static func today(_ now: Date, preview: Bool) -> (day: SunTimes.Day, zone: TimeZone)? {
        guard let p = place(preview: preview),
              let day = SunTimes.on(now, latitude: p.lat, longitude: p.lon, zone: p.zone) else { return nil }
        return (day, p.zone)
    }

    /// Whichever of sunrise and sunset comes next, today or tomorrow.
    @MainActor
    static func next(after now: Date, preview: Bool) -> (rising: Bool, date: Date, zone: TimeZone)? {
        guard let p = place(preview: preview) else { return nil }
        for offset in 0...1 {
            let day = now.addingTimeInterval(Double(offset) * 86_400)
            guard case .normal(let rise, let set)? = SunTimes.on(day, latitude: p.lat, longitude: p.lon,
                                                                 zone: p.zone)
            else { continue }
            if rise > now { return (true, rise, p.zone) }
            if set > now { return (false, set, p.zone) }
        }
        return nil
    }

    /// "06:12" on the place's clock.
    static func time(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "（当地时间）" when the place keeps a different clock from this Mac.
    static func localNote(_ zone: TimeZone, at date: Date) -> String {
        zone.secondsFromGMT(for: date) == TimeZone.current.secondsFromGMT(for: date) ? "" : tr("（当地时间）")
    }
}
