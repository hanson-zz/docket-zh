import SwiftUI
import WidgetKit

// 码头 · 天气：码头天气卡片那个城市的实时天气（数据由主 App 从 MET Norway 取来写进
// 快照，扩展不联网）。小号温度、天气和最高最低；中号再加接下来几个小时。

struct WeatherEntry: TimelineEntry {
    let date: Date
    let words: Words
    let hasApp: Bool
    let weather: SystemWidgetSnapshot.Weather?
}

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        let words = Words(lang: Shared.language(nil))
        return WeatherEntry(date: .now, words: words, hasApp: true,
                     weather: .init(city: words("北京"), temperatureC: 18, symbol: "sun.max.fill", condition: words("晴"),
                                    highC: 22, lowC: 11, asOf: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(context.isPreview && Shared.snapshot()?.weather == nil ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        // 主 App 每次拿到新天气都会让小组件重画；这里只是兜底，半小时看一次快照。
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry() -> WeatherEntry {
        let snapshot = Shared.snapshot()
        return WeatherEntry(date: .now, words: Words(lang: Shared.language(snapshot)),
                            hasApp: snapshot != nil, weather: snapshot?.weather)
    }
}

struct WeatherWidgetView: View {
    var entry: WeatherEntry
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    var body: some View {
        Group {
            if let weather = entry.weather {
                if family == .systemSmall {
                    now(weather)
                } else {
                    HStack(spacing: 14) {
                        now(weather)
                        hours(weather)
                    }
                }
            } else if entry.hasApp {
                EmptyHint(words: words, line: words("在扩展栏添加「天气」卡片并设好城市"))
            } else {
                EmptyHint.noApp(words)
            }
        }
        .dockBackground()
    }

    private func degrees(_ celsius: Double, _ weather: SystemWidgetSnapshot.Weather) -> String {
        let value = weather.fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    private func now(_ weather: SystemWidgetSnapshot.Weather) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Caption(text: weather.city, symbol: "location.fill")
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: degrees(weather.temperatureC, weather))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: weather.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                    .widgetAccentable()
            }
            Text(verbatim: weather.condition)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
            if let high = weather.highC, let low = weather.lowC {
                Text(verbatim: words("最高 %@ 最低 %@", degrees(high, weather), degrees(low, weather)))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if entry.date.timeIntervalSince(weather.asOf) > 3 * 3600 {
                Text(verbatim: words("更新于 %@", words.time(weather.asOf)))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func hours(_ weather: SystemWidgetSnapshot.Weather) -> some View {
        let upcoming = weather.hours.filter { $0.time > entry.date.addingTimeInterval(-1800) }.prefix(4)
        return HStack(spacing: 6) {
            ForEach(Array(upcoming.enumerated()), id: \.offset) { _, hour in
                VStack(spacing: 6) {
                    Text(verbatim: words.hour(hour.time))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: hour.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 18))
                        .frame(height: 22)
                    Text(verbatim: degrees(hour.temperatureC, weather))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SystemWidgetStore.kindPrefix + "weather", provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 天气")
        .description("码头天气卡片那个城市的实时天气。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
