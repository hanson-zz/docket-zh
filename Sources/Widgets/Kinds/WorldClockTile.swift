import SwiftUI

/// The clock tile pointed at another IANA zone, captioned with its city and a
/// hint when it is already a different day over there.
///
/// In a 76pt column that hint shrinks to a "+1" / "−1" beside the city: the
/// word "Tomorrow" does not fit next to a place name in 56pt.
///
/// 城市列表（`WorldClockList`）有多个时，卡片显示前 2 到 3 个，顺序和面板
/// 一样：扩展栏 168×58 三个以上分三列，两个时上下两行；竖排最多三个，上下排。
/// 多个城市时每个城市一格（`WorldClockSkyCell`），名字旁红黄绿圆点说明现在适不适合
/// 联系。格子外观存在 `look`（`WorldClockLook`）：普通免费、新卡片默认，透出卡片的
/// 液态玻璃；天空是 Pro，底色是当地此刻的天空，右下角小地标线稿。没解锁时天空画成
/// 普通，不盖锁、不改配置，解锁或试用后自动回来。只有一个城市时保持原来的样子，
/// 收起的窄卡片只显示第一个。
struct WorldClockTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    // 和纪念日一样读 @AppStorage：购买或试用到期时卡片马上换外观。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false

    private var cities: [WorldCity] { WorldClockList.tileCities(instance.config) }

    /// 实际画的格子外观。库里的预览按卡片自己的配置画（新卡片是普通）。
    private var look: WorldClockLook {
        ProLicenseGate.worldClockLook(config: instance.config,
                                      unlocked: licenseUnlocked || supporterUnlocked || context.isPreview)
    }

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

    /// 每个城市一格，格子铺满卡片（不留卡片内边距）。天空格子靠底色分开，普通格子
    /// 之间画一条细分隔线。
    private func threeColumns(_ list: [WorldCity]) -> some View {
        skySurface {
            HStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0 { separator(vertical: true) }
                    cell(city, shape: .stacked, timeSize: 18)
                }
            }
        }
    }

    // MARK: 两行

    private func twoRows(_ list: [WorldCity]) -> some View {
        skySurface {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0 { separator(vertical: false) }
                    cell(city, shape: .row, timeSize: 16)
                }
            }
        }
    }

    // MARK: 竖排

    private func column(_ list: [WorldCity]) -> some View {
        skySurface {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, city in
                    if index > 0 { separator(vertical: false) }
                    cell(city, shape: .stacked, timeSize: 16)
                }
            }
        }
    }

    /// 卡片外壳照旧（圆角、描边、悬停），里面的格子抵消掉卡片的左右内边距，
    /// 一直铺到卡片边上。天空格子自己有底，卡片底透明；普通格子用卡片本身的
    /// 液态玻璃底（和一个城市的卡片、颜色与背景一致）。
    private func skySurface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        WidgetSurface(fill: look == .sky ? .clear : nil) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 先按卡片的圆角裁，再抵消内边距，天空格子的四角跟卡片一样圆。
                .clipShape(RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous))
                .padding(.horizontal, -WidgetStyle.inset)
        }
    }

    private func cell(_ city: WorldCity, shape: WorldClockSkyCell.Arrangement, timeSize: CGFloat) -> some View {
        WorldClockSkyCell(city: city, now: context.now, shape: shape, timeSize: timeSize,
                          showsDot: city.id != WorldCities.reference()?.id,
                          dayBadge: Self.dayBadge(context.now, zone: city.timeZone ?? .current),
                          look: look)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 普通格子之间的细线（主文字色 12%，浅色深色都看得见又不抢字）；天空格子不画。
    @ViewBuilder
    private func separator(vertical: Bool) -> some View {
        if look == .plain {
            Rectangle()
                .fill(WidgetStyle.primary.opacity(0.12))
                .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
                .padding(vertical ? .vertical : .horizontal, 8)
        }
    }

    // MARK: 零件

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
