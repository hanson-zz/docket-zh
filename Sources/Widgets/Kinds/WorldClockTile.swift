import SwiftUI

/// The clock tile pointed at another IANA zone, captioned with its city and a
/// hint when it is already a different day over there.
///
/// In a 76pt column that hint shrinks to a "+1" / "−1" beside the city: the
/// word "Tomorrow" does not fit next to a place name in 56pt.
struct WorldClockTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var zone: TimeZone {
        // An unknown identifier (renamed zone, hand-edited config) falls back
        // to local rather than rendering an empty tile.
        TimeZone(identifier: instance.config.string("zone", default: "Europe/London")) ?? .current
    }

    private var city: String { instance.config.string("city", default: "伦敦") }

    var body: some View {
        let name = city
        let hint = Self.dayHint(context.now, zone: zone)
        ClockReadout(
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

    /// "Tomorrow" / "Yesterday" when the zone's calendar day differs from the
    /// local one.
    static func dayHint(_ now: Date, zone: TimeZone) -> String? {
        switch dayOffset(now, zone: zone) {
        case let days where days > 0: "明天"
        case let days where days < 0: "昨天"
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
