import SwiftUI

/// Weather said at length: the reading the tile leads with, the condition and
/// the city behind it, and every hour MET published rather than the five a
/// card has room for.
///
/// Nothing here fetches from MET. The panel only ever opens from a tile that
/// has already pointed the service at a city and refreshed it, so this
/// renders whatever the service holds and admits it when that is nothing - a
/// refresh of its own would be refused by the 15-minute throttle anyway. The
/// one request it may make is the Open-Meteo daily forecast behind the
/// 10-day list, which only the forecast layouts fetch on their own and which
/// the service throttles to once per place per 30 minutes.
///
/// Only what `WeatherService` actually publishes: a temperature, a symbol, a
/// condition, wind and humidity from the same instant, and the hourly
/// series. Sunrise and sunset are worked out from the forecast's own
/// coordinates rather than asked for. No gusts, because the compact
/// endpoint carries none. The daily highs and lows come from Open-Meteo.
struct WeatherDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // The condition's own sky, with its symbol as the light source.
        DetailCard {
            WeatherBackdrop(symbol: weather?.symbolName ?? "cloud.fill")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if layout == "cities" {
                    citiesList
                } else if city.isEmpty {
                    noPlace
                } else if let weather {
                    now(weather)
                } else {
                    unavailable
                }

                if layout != "cities", !city.isEmpty, weather != nil {
                    extras
                }

                if layout != "cities", !days.isEmpty {
                    dayList
                }

                if layout != "cities", !hours.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        strip
                        range
                    }
                    .padding(10)
                    .glassPane()
                }

                // CC BY 4.0 asks for this wherever the data is shown, and the
                // tile is too small to carry it.
                VStack(alignment: .leading, spacing: 2) {
                    if layout != "cities" {
                        Text(WeatherService.attribution)
                    }
                    Text(WeatherService.forecastAttribution)
                }
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .task(id: placeKey) { await loadForecast() }
    }

    // MARK: Daily forecast

    private var layout: String { instance.config.string("layout", default: "current") }

    /// Changes when the shared place moves, so the list follows it.
    private var placeKey: String {
        if layout == "cities" { return cities.joined(separator: ",") }
        guard let place = WeatherService.shared.place else { return "" }
        return DailyForecast.cacheKey(lat: place.lat, lon: place.lon)
    }

    private func loadForecast() async {
        guard !context.isPreview else { return }
        if layout == "cities" {
            await ForecastService.shared.load(cities: cities)
        } else if let place = WeatherService.shared.place {
            await ForecastService.shared.refresh(place)
        }
    }

    private var forecast: DailyForecast? {
        if context.isPreview { return WeatherTile.sampleForecast(now: context.now) }
        return WeatherService.shared.place.flatMap { ForecastService.shared.forecast(at: $0) }
    }

    /// Ten days, or what the model published of them.
    private var days: [DailyForecast.Day] {
        forecast?.upcoming(now: context.now, limit: 10) ?? []
    }

    private var cities: [String] {
        WeatherLayout.cities(instance.config.strings("cities", default: WeatherLayout.defaultCities))
    }

    /// One row a day: name, symbol, chance of rain, low, the range bar on
    /// the scale of all ten days, and high, in the system's own order.
    private var dayList: some View {
        let today = forecast?.todayKey(now: context.now) ?? ""
        let scale = DailyForecast.scale(days)
        return VStack(alignment: .leading, spacing: 6) {
            Text(days.count == 1 ? "未来 1 天" : "未来 \(days.count) 天")
                .font(WidgetStyle.caption(12))
                .foregroundStyle(WidgetStyle.secondary)
            ForEach(days, id: \.key) { day in
                HStack(spacing: 8) {
                    Text(DailyForecast.weekdayLabel(day.key, today: today))
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.primary)
                        .frame(width: 34, alignment: .leading)
                    Image(systemName: WMOWeather.symbol(day.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13))
                        .frame(width: 22)
                    Text(rainChance(day))
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(Color(hex: "#5AC8FA"))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .leading)
                    Text(degrees(day.lowC))
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                    rangeBar(day, scale: scale)
                    Text(degrees(day.highC))
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(DailyForecast.weekdayLabel(day.key, today: today))，"
                                    + "\(WMOWeather.condition(day.code))，"
                                    + "最低 \(degrees(day.lowC))，最高 \(degrees(day.highC))")
            }
        }
        .padding(10)
        .glassPane()
    }

    /// Only worth a figure from 20% up; below that the column stays empty.
    private func rainChance(_ day: DailyForecast.Day) -> String {
        guard let chance = day.precipitationChance, chance >= 20 else { return "" }
        return "\(Int(chance.rounded()))%"
    }

    private func rangeBar(_ day: DailyForecast.Day, scale: (low: Double, high: Double)?) -> some View {
        let fractions: (start: Double, end: Double) = scale.map {
            DailyForecast.rangeFractions(low: day.lowC, high: day.highC, scaleLow: $0.low, scaleHigh: $0.high)
        } ?? (0, 1)
        return GeometryReader { proxy in
            let width = proxy.size.width
            let length = max(4, width * (fractions.end - fractions.start))
            Capsule()
                .fill(.white.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "#5AC8FA"), Color(hex: "#FF9F0A")],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: length)
                        .offset(x: min(width * fractions.start, width - length))
                }
        }
        .frame(height: 4)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The multi-city card's panel: each place with its reading now and
    /// today's range. The shared city is not this card's, so it is not shown.
    private var citiesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                let place: DailyForecast? = context.isPreview
                    ? WeatherTile.sampleCityForecast(index, now: context.now)
                    : ForecastService.shared.forecast(city: city)
                let today = place?.today(now: context.now)
                HStack(spacing: 10) {
                    Image(systemName: place?.current.map { WMOWeather.symbol($0.code, isDay: $0.isDay) }
                          ?? "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 18))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city)
                            .font(WidgetStyle.label(13))
                            .foregroundStyle(WidgetStyle.primary)
                        Text(place?.current.map { WMOWeather.condition($0.code) } ?? "暂无数据")
                            .font(WidgetStyle.caption(11))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(place?.current.map { degrees($0.temperatureC) } ?? "--°")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                        Text(today.map { "最高 \(degrees($0.highC)) 最低 \(degrees($0.lowC))" } ?? " ")
                            .font(WidgetStyle.caption(11))
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .padding(10)
                .glassPane()
            }
        }
    }

    // MARK: Data
    //
    // The tile's accessors, key for key: the panel must not disagree with the
    // card that opened it about which city it is reporting, or in which unit.

    /// An empty `city` means "wherever I am", same as on the tile.
    private var city: String {
        let stored = instance.config.string("city").trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty { return stored }
        return context.isPreview ? Self.sampleCity : (LocationService.shared.city ?? "")
    }

    private var fahrenheit: Bool { instance.config.bool("fahrenheit") }

    private var weather: WeatherNow? {
        context.isPreview ? Self.sample : WeatherService.shared.current
    }

    private var hours: [WeatherHour] {
        context.isPreview ? Self.sampleHours(from: context.now) : WeatherService.shared.hourly
    }

    // MARK: Now

    private func now(_ weather: WeatherNow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                // The city first, as the system's own weather does: the
                // number means nothing until you know where it is.
                Text(city)
                    .font(WidgetStyle.label(15))
                    .foregroundStyle(WidgetStyle.primary)
                temperature(weather.temperatureC)
                // The hourly layout shows neither the condition nor the city,
                // so on the shelf this widget is a bare number - both lines
                // are what the panel is for.
                Text(weather.condition)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.white.opacity(0.8))
            }
            // A city typed in full ("Thiruvananthapuram") truncates rather
            // than pushing the panel's fixed width around.
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    /// Big figure with a lighter degree mark, as on the tile.
    private func temperature(_ celsius: Double) -> some View {
        let reading = Int(converted(celsius).rounded())
        return HStack(alignment: .top, spacing: 0) {
            Text("\(reading)")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(reading)
            Text("°")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(WidgetStyle.primary)
        }
        .lineLimit(1)
    }

    // MARK: Wind, humidity, sun

    private var extras: some View {
        let sun = WeatherSun.today(context.now, preview: context.isPreview)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                         spacing: 6) {
            if let speed = weather?.windSpeed {
                HStack(spacing: 6) {
                    // Points the way the wind blows, which is away from where
                    // it comes from.
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees((weather?.windFrom ?? 0) + 180))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.12)))
                    StatChip(label: "风", value: Wind.summary(speed: speed, from: weather?.windFrom ?? 0))
                }
            }
            if let humidity = weather?.humidity {
                StatChip(label: "湿度", value: "\(Int(humidity.rounded()))%")
            }
            switch sun?.day {
            case .normal(let rise, let set)?:
                let zone = sun?.zone ?? .current
                let note = WeatherSun.localNote(zone, at: rise)
                StatChip(label: "日出" + note, value: WeatherSun.time(rise, zone: zone))
                StatChip(label: "日落" + note, value: WeatherSun.time(set, zone: zone))
            case .polarDay?:
                StatChip(label: "日照", value: "极昼")
            case .polarNight?:
                StatChip(label: "日照", value: "极夜")
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: Hours

    /// Every hour the service holds, where the tile's strip stops at five.
    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(hours, id: \.date) { hour in
                VStack(spacing: 2) {
                    // The hour alone. Twelve columns have no room for "2 PM",
                    // and read together they are an axis rather than a clock.
                    Text(hour.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                    Image(systemName: hour.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                    Text(degrees(hour.temperatureC))
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The span of the strip beside it, named with the hours it actually
    /// covers: MET's series thins into 6- and 12-hour buckets that carry no
    /// hourly symbol, so twelve is a ceiling and not a promise.
    @ViewBuilder private var range: some View {
        let temperatures = hours.map(\.temperatureC)
        if let low = temperatures.min(), let high = temperatures.max() {
            HStack(spacing: 12) {
                Text(hours.count == 1 ? "未来 1 小时" : "未来 \(hours.count) 小时")
                    .font(WidgetStyle.caption(12))
                    .foregroundStyle(WidgetStyle.secondary)
                Spacer(minLength: 0)
                Text(low == high ? degrees(low) : "\(degrees(low)) – \(degrees(high))")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
            }
            .lineLimit(1)
        }
    }

    // MARK: Empty states

    /// Nothing typed and nothing from CoreLocation - which, as the README
    /// records, is the usual outcome for an app that never becomes frontmost.
    /// Tell the two states apart the way the tile's caption does, and point at
    /// the field that settles both.
    private var noPlace: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(locating ? "正在定位…" : "未设置城市")
                .font(WidgetStyle.label(13))
                .foregroundStyle(WidgetStyle.primary)
            Text(locating
                 ? "正在等待获取你的位置。在“设置 ▸ 小组件”中输入城市即可跳过定位。"
                 : "请在“设置 ▸ 小组件”中输入城市。")
                .font(WidgetStyle.caption(11))
                .foregroundStyle(WidgetStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locating: Bool {
        guard !context.isPreview else { return false }
        let service = LocationService.shared
        return !service.denied && !service.unavailable
    }

    /// A missing reading is either a first fetch still in flight or one that
    /// failed with nothing cached behind it. The service keeps the last good
    /// values and reports no error, so it cannot tell those apart - and
    /// neither does this. The panel observes the service, so the number
    /// appears here the moment it lands.
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(city)
                .font(WidgetStyle.label(13))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("暂无数据。")
                .font(WidgetStyle.caption(11))
                .foregroundStyle(WidgetStyle.secondary)
        }
    }

    // MARK: Units

    private func degrees(_ celsius: Double) -> String {
        "\(Int(converted(celsius).rounded()))°"
    }

    private func converted(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    // MARK: Sample
    //
    // The library has no live data. The tile's own sample is private to it,
    // and these numbers only have to agree with it by eye.

    private static let sampleCity = "奥斯陆"

    private static let sample = WeatherNow(temperatureC: 18,
                                           symbolName: "cloud.sun.fill",
                                           condition: "多云",
                                           windSpeed: 4.2, windFrom: 45, humidity: 62)

    private static func sampleHours(from date: Date) -> [WeatherHour] {
        let temperatures: [Double] = [18, 19, 19, 17, 16, 16, 15, 14]
        let symbols = ["cloud.sun.fill", "sun.max.fill", "cloud.sun.fill", "cloud.rain.fill",
                       "cloud.fill", "cloud.fill", "cloud.moon.fill", "cloud.moon.fill"]
        return zip(temperatures, symbols).enumerated().map { index, pair in
            WeatherHour(date: date.addingTimeInterval(Double(index + 1) * 3600),
                        temperatureC: pair.0,
                        symbolName: pair.1)
        }
    }
}
