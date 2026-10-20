import SwiftUI

/// The clock tile pointed at another IANA zone, captioned with its city and a
/// hint when it is already a different day over there.
///
/// In a 76pt column that hint shrinks to a "+1" / "−1" beside the city: the
/// word "Tomorrow" does not fit next to a place name in 56pt.
///
/// 城市列表（`WorldClockList`）有多个时，卡片显示前 2 到 3 个，顺序和面板
/// 一样：扩展栏 168×58 三个以上分三列，两个时两行、左边地标小图标；只有
/// 一个时保持原来的样子。竖排最多三个，上下排。收起的窄卡片只显示第一个。
struct WorldClockTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var cities: [WorldCity] { WorldClockList.tileCities(instance.config) }

    var body: some View {
        let list = cities
        let vertical = context.position.isVertical
        if list.count > 1, vertical {
            column(list)
        } else if list.count > 2, instance.expanded {
            threeColumns(list)
        } else if list.count == 2, instance.expanded {
            twoRows(list)
        } else {
            single(list.first ?? WorldClockList.legacyCity(instance.config))
        }
    }

    // MARK: 一个城市

    private func single(_ city: WorldCity) -> some View {
        // An unknown identifier (renamed zone, hand-edited config) falls back
        // to local rather than rendering an empty tile.
        let zone = city.timeZone ?? .current
        let name = city.name
        let hint = Self.dayHint(context.now, zone: zone)
        return ClockReadout(
            now: context.now,
            zone: zone,
            caption: hint.map { "\(name) · \($0)" } ?? name,
            compactCaption: name,
            expanded: instance.expanded,
            vertical: context.position.isVertical,
            columnLabel: name,
            columnBadge: Self.dayBadge(context.now, zone: zone)
        )
    }

    // MARK: 三列

    private func threeColumns(_ list: [WorldCity]) -> some View {
        WidgetSurface {
            HStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0 {
                        Rectangle()
                            .fill(WidgetStyle.secondary.opacity(0.25))
                            .frame(width: 0.5)
                            .padding(.vertical, 6)
                    }
                    VStack(spacing: 1) {
                        label(city, size: 10)
                        time(city, size: 17)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: 两行

    private func twoRows(_ list: [WorldCity]) -> some View {
        WidgetSurface {
            VStack(spacing: 2) {
                ForEach(list) { city in
                    HStack(spacing: 6) {
                        CityLandmarkBadge(city: city, now: context.now, size: 20, inkOpacity: 0.85)
                        label(city, size: 11)
                        Spacer(minLength: 2)
                        time(city, size: 15)
                    }
                }
            }
        }
    }

    // MARK: 竖排

    private func column(_ list: [WorldCity]) -> some View {
        WidgetSurface {
            VStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0 {
                        Rectangle()
                            .fill(WidgetStyle.secondary.opacity(0.25))
                            .frame(height: 0.5)
                            .padding(.horizontal, 8)
                    }
                    VStack(spacing: 1) {
                        label(city, size: 10)
                        time(city, size: 15)
                    }
                }
            }
        }
    }

    // MARK: 零件

    /// 城市名，不是同一天时后面跟 “+1” / “−1”。
    private func label(_ city: WorldCity, size: CGFloat) -> some View {
        let zone = city.timeZone ?? .current
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: city.name)
                .font(WidgetStyle.caption(size))
                .foregroundStyle(WidgetStyle.secondary)
            if let badge = Self.dayBadge(context.now, zone: zone) {
                Text(verbatim: badge)
                    .font(WidgetStyle.label(size - 2))
                    .foregroundStyle(WidgetStyle.secondary.opacity(0.8))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// 时间不带上午下午（12 小时制时也是），三列放得下。
    private func time(_ city: WorldCity, size: CGFloat) -> some View {
        let text = ClockFormat.compactTime(context.now, zone: city.timeZone ?? .current).time
        return Text(verbatim: text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(WidgetStyle.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "Tomorrow" / "Yesterday" when the zone's calendar day differs from the
    /// local one.
    static func dayHint(_ now: Date, zone: TimeZone) -> String? {
        switch dayOffset(now, zone: zone) {
        case let days where days > 0: tr("明天")
        case let days where days < 0: tr("昨天")
        default: nil
        }
    }

    /// The same thing as a signed count, for the column.
    static func dayBadge(_ now: Date, zone: TimeZone) -> String? {
        let days = dayOffset(now, zone: zone)
        guard days != 0 else { return nil }
        // U+2212, so the minus sits on the digit's own baseline weight.
        return days > 0 ? "+\(days)" : "\u{2212}\(-days)"
    }

    /// Days the zone's civil date is ahead of the local one. Compared as dates
    /// normalised to UTC so month and year boundaries behave.
    static func dayOffset(_ now: Date, zone: TimeZone) -> Int {
        guard zone != .current else { return 0 }
        var there = Calendar.current
        there.timeZone = zone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let fields: Set<Calendar.Component> = [.year, .month, .day]
        guard let local = utc.date(from: Calendar.current.dateComponents(fields, from: now)),
              let remote = utc.date(from: there.dateComponents(fields, from: now)),
              let days = utc.dateComponents([.day], from: local, to: remote).day
        else { return 0 }
        return days
    }
}
