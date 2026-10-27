import SwiftUI
import WidgetKit

// 码头 · 时钟：小号一个城市的大号时间和日期；中号左边主城市，右边列世界时钟卡片里的
// 城市（最多三个）。没有快照也能用（主城市默认本机时间）。

struct ClockEntry: TimelineEntry {
    let date: Date
    let words: Words
    let main: SystemWidgetSnapshot.City?
    let cities: [SystemWidgetSnapshot.City]
}

struct ClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: .now, words: Words(lang: Shared.language(nil)), main: nil,
                   cities: Self.sampleCities(Words(lang: Shared.language(nil))))
    }

    func snapshot(for configuration: ClockConfigIntent, in context: Context) async -> ClockEntry {
        entry(configuration, at: .now, snapshot: Shared.snapshot())
    }

    /// 一分钟一条，排一小时，排完再要。
    func timeline(for configuration: ClockConfigIntent, in context: Context) async -> Timeline<ClockEntry> {
        let now = Date.now
        let start = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        let snapshot = Shared.snapshot()
        let entries = (0..<60).map {
            entry(configuration, at: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(_ configuration: ClockConfigIntent, at date: Date,
                       snapshot: SystemWidgetSnapshot?) -> ClockEntry {
        let words = Words(lang: Shared.language(snapshot))
        let main = configuration.city.map { SystemWidgetSnapshot.City(name: $0.name, zone: $0.zone) }
        let card = configuration.card.flatMap { picked in snapshot?.clocks.first { $0.id == picked.id } }
            ?? snapshot?.clocks.first
        let cities = card?.cities ?? Self.sampleCities(words)
        return ClockEntry(date: date, words: words, main: main,
                          cities: cities.filter { $0 != main })
    }

    static func sampleCities(_ words: Words) -> [SystemWidgetSnapshot.City] {
        [.init(name: words("伦敦"), zone: "Europe/London"),
         .init(name: words("纽约"), zone: "America/New_York"),
         .init(name: words("东京"), zone: "Asia/Tokyo")]
    }
}

struct ClockWidgetView: View {
    var entry: ClockEntry
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }
    private var zone: TimeZone { entry.main.flatMap { TimeZone(identifier: $0.zone) } ?? .current }
    private var name: String { entry.main?.name ?? words("本机时间") }

    var body: some View {
        Group {
            if family == .systemSmall {
                big
            } else {
                HStack(alignment: .center, spacing: 14) {
                    big
                    Divider()
                    list
                }
            }
        }
        .dockBackground()
    }

    private var big: some View {
        VStack(alignment: .leading, spacing: 4) {
            Caption(text: name, symbol: "clock.fill")
            Spacer(minLength: 0)
            Text(verbatim: words.time(entry.date, zone: zone))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
            Text(verbatim: words.dayLine(entry.date, zone: zone))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entry.cities.prefix(3).enumerated()), id: \.offset) { _, city in
                let tz = TimeZone(identifier: city.zone) ?? .current
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: city.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(verbatim: relativeDay(tz))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: words.time(entry.date, zone: tz))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 那个城市此刻是本机的今天、明天还是昨天。
    private func relativeDay(_ tz: TimeZone) -> String {
        var here = Calendar(identifier: .gregorian)
        here.timeZone = zone
        var there = Calendar(identifier: .gregorian)
        there.timeZone = tz
        let a = here.dateComponents([.year, .month, .day], from: entry.date)
        let b = there.dateComponents([.year, .month, .day], from: entry.date)
        guard let da = here.date(from: a), let db = here.date(from: b),
              let diff = here.dateComponents([.day], from: da, to: db).day else { return words("今天") }
        switch diff {
        case 1...: return words("明天")
        case ..<0: return words("昨天")
        default: return words("今天")
        }
    }
}

struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SystemWidgetStore.kindPrefix + "clock", intent: ClockConfigIntent.self,
                               provider: ClockProvider()) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 时钟")
        .description("本机和世界各地的时间。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
