import SwiftUI

/// Weather said at length: the reading the tile leads with, the condition and
/// the city behind it, and every hour MET published rather than the five a
/// card has room for.
///
/// Nothing here fetches. The panel only ever opens from a tile that has
/// already pointed the service at a city and refreshed it, so this renders
/// whatever the service holds and admits it when that is nothing - a refresh
/// of its own would be refused by the 15-minute throttle anyway.
///
/// Only what `WeatherService` actually publishes: a temperature, a symbol, a
/// condition and the hourly series. No humidity, wind, sunrise or daily high
/// and low, because the compact endpoint the service calls carries none of
/// them and a panel is not worth a second request.
struct WeatherDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // The condition's own sky, with its symbol as the light source.
        DetailCard {
            WeatherBackdrop(symbol: weather?.symbolName ?? "cloud.fill")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if city.isEmpty {
                    noPlace
                } else if let weather {
                    now(weather)
                } else {
                    unavailable
                }

                if !hours.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        strip
                        range
                    }
                    .padding(10)
                    .glassPane()
                }

                // CC BY 4.0 asks for this wherever the data is shown, and the
                // tile is too small to carry it.
                Text(WeatherService.attribution)
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.55))
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
                                           condition: "多云")

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
