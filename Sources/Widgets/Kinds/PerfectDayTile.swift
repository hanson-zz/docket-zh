import Foundation
import Observation
import SwiftUI

/// 小熊猫的竹篮：today's bamboo leaf (a dashed outline until one is earned)
/// and the three items as little rings. The card's own click opens the panel
/// with the month's basket, the calendar and the badges. See `PerfectDay`
/// for the rule.
///
/// It reads 喝水 and 习惯打卡 from their own widgets, on whichever layout they
/// sit, and 专注 from the app's `FocusLog` and its daily goal, both kept by
/// `FocusLogStore` (the 专注计时 panel's 近七天). Nothing here writes to those widgets, and nothing here gives the
/// pet a treat: the pet already gets one for each glass, habit and session
/// from the sources themselves, and a leaf is not a fourth.
struct PerfectDayTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme

    private var center: PerfectDayCenter { .shared }

    private var isRings: Bool { TodayRings.isRings(instance.config) }

    private var progress: [PerfectDayProgress] {
        if context.isPreview { return isRings ? TodayRings.sample : PerfectDayCenter.sampleProgress }
        return center.progress(now: context.now)
    }

    var body: some View {
        let items = progress
        let tier = PerfectDay.record(items, key: "").tier
        return WidgetSurface {
            Group {
                if items.isEmpty {
                    PandaEmptyState(empty: .basket, title: tr("添加小组件"), compact: context.position.isVertical) {
                        guard !context.isPreview else { return }
                        LibraryWindow.shared.openFromEmptyState()
                    }
                } else if isRings {
                    // 今日三环：同一份数据的另一种外观，见 TodayRings。
                    TodayRingsTileBody(items: items, card: TodayRings.card(instance.config),
                                       vertical: context.position.isVertical)
                } else if LiquidLooks.basketLook(instance.config) == .liquid {
                    liquid(items, tier: tier)
                } else if context.position.isVertical {
                    column(items, tier: tier)
                } else {
                    wide(items, tier: tier)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRings
            ? tr("今日三环，\(TodayRings.percent(items))%，\(TodayRings.cardCaption(items))")
            : tr("小熊猫的竹篮，今天\(tier.map { tr("收到\($0.leafName)") } ?? tr("还没有竹叶"))"))
        .onAppear { if !context.isPreview { center.refresh(now: context.now) } }
    }

    private func wide(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        HStack(spacing: 10) {
            LeafGlyph(tier: tier, size: 42)
                .animation(.smooth(duration: 0.4), value: tier)
            VStack(alignment: .leading, spacing: 5) {
                Text(PerfectDay.headline(tier))
                    .font(WidgetStyle.label(14))
                    .foregroundStyle(tier == nil ? WidgetStyle.secondary : WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 7) {
                    ForEach(items) { item in PerfectItemRing(progress: item, size: 17) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 液态：整张卡片是一篮竹叶色的水，水位是今天参加的几项的平均进度，
    /// 满了水面盖过上沿（满篮那天就是满的）。竹叶、标题和三个小圆环浮在水上。
    /// 不闪金光：满篮会持续一整天，一直 30 帧太费电。只在卡片可见时动，
    /// 见 `LiquidWater`。
    private func liquid(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        let vertical = context.position.isVertical
        return ZStack {
            // 默认竹叶色；颜色面板里选过颜色时用选的。
            LiquidWater(level: LiquidLooks.basketLevel(items),
                        tint: theme?.isChosen == true ? theme!.main(dark: scheme == .dark) : Color(hex: PerfectDay.bambooHex),
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen)
                .fillingCard()
            Group {
                if vertical {
                    column(items, tier: tier)
                } else {
                    wide(items, tier: tier)
                }
            }
            // 水铺满到卡片边，字离边至少 12pt。
            .liquidTextInset()
        }
    }

    private func column(_ items: [PerfectDayProgress], tier: PerfectDayTier?) -> some View {
        VStack(spacing: 5) {
            LeafGlyph(tier: tier, size: 40)
            Text(PerfectDay.headline(tier))
                .font(WidgetStyle.caption(9))
                .foregroundStyle(tier == nil ? WidgetStyle.secondary : WidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                ForEach(items) { item in PerfectItemRing(progress: item, size: 14) }
            }
        }
    }
}

/// Keeps 小熊猫的竹篮's history: reads the three sources, settles the days into
/// `perfect-day.json` beside the app's state file, and dates the badges.
///
/// One for the app rather than one per widget, like `PodcastService`: two
/// 竹篮 widgets on two layouts are the same days. History is written only
/// while a 竹篮 widget is placed somewhere, so it starts the day the
/// widget is first added. Focus minutes are `FocusLogStore`'s, logged from
/// launch whether or not this widget is placed.
@MainActor @Observable
final class PerfectDayCenter {
    static let shared = PerfectDayCenter()

    /// Every widget on every layout. Wired at launch; empty in the shot tool.
    @ObservationIgnored var widgets: @MainActor () -> [WidgetInstance] = { [] }

    private(set) var archive: PerfectDayArchive

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let url: URL

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.docket-zh.app"
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "perfect-day.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PerfectDayArchive.self, from: data) {
            archive = decoded
        } else {
            archive = PerfectDayArchive()
        }
    }

    /// Settles now and then once a minute, so a day is closed off at
    /// midnight whether or not the panel is open.
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { PerfectDayCenter.shared.refresh() }
        }
    }

    // MARK: Sources

    private struct Sources {
        var water: [WidgetConfig]
        var habits: [WidgetConfig]
        var hasTimer: Bool
        var focusMinutes: [String: Int]
        var focusGoal: Int
        var placed: Bool
    }

    private func sources() -> Sources {
        let all = widgets()
        let perfect = all.first { $0.kind == .perfectDay }
        return Sources(water: all.filter { $0.kind == .water }.map(\.config),
                       habits: all.filter { $0.kind == .habit }.map(\.config),
                       hasTimer: all.contains { $0.kind == .timer },
                       focusMinutes: FocusLog.minutes(FocusLogStore.shared.lines),
                       focusGoal: FocusLogStore.goal,
                       placed: perfect != nil)
    }

    private func progress(_ s: Sources, on date: Date, now: Date) -> [PerfectDayProgress] {
        PerfectDay.progress(water: s.water, habits: s.habits, focusMinutes: s.focusMinutes,
                            focusGoal: s.focusGoal, hasTimer: s.hasTimer, on: date, today: now)
    }

    /// Today's three items, read live.
    func progress(now: Date) -> [PerfectDayProgress] {
        progress(sources(), on: now, now: now)
    }

    /// The settled days with today's live reading on top.
    func records(now: Date) -> [PerfectDayRecord] {
        let key = HabitTracker.dayKey(now)
        var records = archive.records.filter { $0.key != key }
        records.append(PerfectDay.record(progress(now: now), key: key))
        return records.sorted { $0.key < $1.key }
    }

    func focusGoal() -> Int { FocusLogStore.goal }

    /// 几天的三项读数（今日三环面板的近 7 天小格），按天的 key。只读一次来源。
    func progress(days: [Date], now: Date) -> [String: [PerfectDayProgress]] {
        let s = sources()
        var result: [String: [PerfectDayProgress]] = [:]
        for day in days { result[HabitTracker.dayKey(day)] = progress(s, on: day, now: now) }
        return result
    }

    /// Every minute ever focused, for the 专注 badges.
    var focusMinutes: Int { FocusLogStore.shared.lifetimeMinutes }

    /// 徽章用到的累计数字：专注分钟、喝水杯数、深夜专注、清早第一杯水。
    func badgeInput(archive: PerfectDayArchive? = nil) -> PerfectBadgeInput {
        let water = widgets().filter { $0.kind == .water }.flatMap { WaterIntake.days($0.config) }
        return PerfectBadgeInput(focusMinutes: focusMinutes,
                                 waterCups: (archive ?? self.archive).cupCount,
                                 lateFocus: FocusLogStore.shared.hasLateNightFocus,
                                 earlyDrink: PerfectBadges.hasEarlyFirstDrink(water))
    }

    // MARK: Writing

    func refresh(now: Date = .now) {
        let s = sources()
        guard s.placed else { return }
        var next = archive
        let records = PerfectDay.settled(archive.records, today: now) { date in
            PerfectDay.record(progress(s, on: date, now: now), key: HabitTracker.dayKey(date))
        }
        next.setRecords(records)
        let water = s.water.flatMap { WaterIntake.days($0) }
        let cups = PerfectBadges.countingCups(folded: next.cupsFolded, days: next.cupDays, water: water, today: now)
        next.cupsFolded = cups.folded
        next.cupDays = cups.days
        next.earned = PerfectBadges.earning(next.earned, records: records, input: badgeInput(archive: next),
                                            today: now)
        next.festivalYears = PerfectBadges.festivalYears(next.festivalYears, records: records, today: now)
        guard next != archive else { return }
        archive = next
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(archive).write(to: url, options: .atomic)
        } catch {
            NSLog("小熊猫的竹篮：无法写入 \(url.path)：\(error.localizedDescription)")
        }
    }

    // MARK: Samples

    /// The library's card: two of three met.
    static let sampleProgress: [PerfectDayProgress] = [
        PerfectDayProgress(item: .water, mark: .met, fraction: 1, detail: tr("2000/2000 毫升")),
        PerfectDayProgress(item: .habit, mark: .met, fraction: 1, detail: tr("3/3 项")),
        PerfectDayProgress(item: .focus, mark: .missed, fraction: 0.6, detail: tr("30/50 分钟")),
    ]
}
