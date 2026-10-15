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

    private var center: PerfectDayCenter { .shared }

    private var progress: [PerfectDayProgress] {
        if context.isPreview { return PerfectDayCenter.sampleProgress }
        return center.progress(now: context.now)
    }

    var body: some View {
        let items = progress
        let tier = PerfectDay.record(items, key: "").tier
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(items, tier: tier)
                } else {
                    wide(items, tier: tier)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("小熊猫的竹篮，今天\(tier.map { "收到\($0.leafName)" } ?? "还没有竹叶")")
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

    /// Every minute ever focused, for the 专注 badges.
    var focusMinutes: Int { FocusLogStore.shared.lifetimeMinutes }

    // MARK: Writing

    func refresh(now: Date = .now) {
        let s = sources()
        guard s.placed else { return }
        var next = archive
        let records = PerfectDay.settled(archive.records, today: now) { date in
            PerfectDay.record(progress(s, on: date, now: now), key: HabitTracker.dayKey(date))
        }
        next.setRecords(records)
        next.earned = PerfectBadges.earning(next.earned, records: records, focusMinutes: focusMinutes,
                                            today: now)
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
        PerfectDayProgress(item: .water, mark: .met, fraction: 1, detail: "2000/2000 毫升"),
        PerfectDayProgress(item: .habit, mark: .met, fraction: 1, detail: "3/3 项"),
        PerfectDayProgress(item: .focus, mark: .missed, fraction: 0.6, detail: "30/50 分钟"),
    ]
}
