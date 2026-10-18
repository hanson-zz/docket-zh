import Foundation
import SwiftUI

/// 喝水：今天喝了多少。角色样式以一只杯子和它的水位为主，右边八个小杯是
/// 今天的进度，选的角色（默认小熊猫）站在杯子旁边，身上是原来的灰/彩水位
/// 效果，水位和杯子同步：喝一杯两边一起涨、举一下杯子，达标欢呼，提醒时段
/// 外打盹，很久没喝渴成骷髅（见 `WaterParched`）。电子
/// 宠物那边角色才是主角，两张卡片不再长得一样（见 `WaterPetCards`）。
///
/// Three styles. 角色 leads with the cup and its level; 圆环
/// is the Codex tile's ring with the percentage in the middle, for a shelf
/// that wants something quieter. Both have today's tally and a "+" that logs
/// one cup of water (`cupSize`). Like the other reminder tiles, the "+" is the only
/// control: the card's own click opens the panel, where other amounts and
/// drinks, the day's list, the goal and the history live.
///
/// The tile also keeps the reminder scheduled, the way the stand-up tile
/// does: one pending notification, moved whenever the next one changes.
struct WaterTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRing: Bool { instance.config.string("layout", default: "character") == "ring" }
    /// 液态：整张卡片是一杯水，水位是今天的进度（见 `LiquidLooks`）。
    private var isLiquid: Bool { LiquidLooks.waterIsLiquid(instance.config) }
    /// 很久没喝或进度很低时角色渴成骷髅（见 `WaterParched`），喝一杯就复活。
    private var parched: Bool {
        !context.isPreview && WaterParched.isParched(instance.config, now: context.now)
    }
    /// 只有角色样式画骷髅；刚喝下那几秒举着杯子，先不变。
    private var showsSkeleton: Bool { !isRing && !isLiquid && WaterCupPage.showsSkeleton(parched: parched, mood: mood) }
    private var ounces: Bool { WaterIntake.usesOunces(instance.config) }
    /// The library's preview draws the sample week against its own 2000 ml.
    private var goal: Int {
        context.isPreview ? WaterIntake.defaultGoal : WaterIntake.goal(instance.config, now: context.now)
    }
    /// A locked Pro 专属 character is drawn as the red panda; the library's
    /// preview shows the real one, as the clock's supporter faces do.
    private var character: WaterCharacter {
        WaterCharacter.shown(instance.config, unlocked: ProAccess.isUnlocked || context.isPreview)
    }

    /// Re-read every tick, so the cup goes down three seconds after a drink
    /// and the character dozes off when the reminder hours end.
    private var mood: WaterMood {
        context.isPreview ? .idle : WaterMood.at(context.now, config: instance.config)
    }

    private var today: WaterDay {
        if context.isPreview {
            return WaterIntake.today(WaterSamples.days(today: context.now), goal: goal, now: context.now)
        }
        return WaterIntake.today(instance.config, now: context.now)
    }

    private var missedDays: Int {
        WaterIntake.missedDays(WaterIntake.days(instance.config), goal: goal, today: context.now)
    }

    private func publishMissed() {
        guard !context.isPreview else { return }
        UserDefaults.standard.set(missedDays, forKey: VirtualPet.missedDaysDefault)
    }

    /// When the next reminder goes out, or nil for none.
    private var nextReminder: Date? {
        guard !context.isPreview else { return nil }
        return WaterReminder.next(instance.config, now: context.now)
    }

    var body: some View {
        let day = today
        let level = WaterIntake.progress(total: day.total, goal: day.goal)
        let done = day.isMet
        // 圆环样式超过目标时画第二圈，角色的水位照旧满了就停。
        let lap = RingLap.progress(total: day.total, goal: day.goal)
        return WidgetSurface {
            Group {
                if isLiquid {
                    liquid(day, done: done)
                } else if context.position.isVertical {
                    column(day, level: level, lap: lap, done: done)
                } else {
                    wide(day, level: level, lap: lap, done: done)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("喝水，\(showsSkeleton ? tr("渴成骷髅了，") : "")\(WaterIntake.tally(total: day.total, goal: day.goal, ounces: ounces))"))
        .onAppear { WaterNotifier.shared.update(instance, next: nextReminder) }
        .onChange(of: nextReminder) { _, next in WaterNotifier.shared.update(instance, next: next) }
        // The pet's 渴成骷髅 reads this; written from here so it needs no
        // way to find the 喝水 widget itself.
        .onAppear { publishMissed() }
        .onChange(of: missedDays) { _, _ in publishMissed() }
    }

    // MARK: Wide

    private func wide(_ day: WaterDay, level: Double, lap: Double, done: Bool) -> some View {
        Group {
            if isRing {
                ringWide(day, lap: lap, done: done)
            } else {
                cupWide(day, level: level, done: done)
            }
        }
    }

    /// 角色样式：大杯和水位在左，角色站在杯子旁边；右边大数字、目标和八个小杯。
    private func cupWide(_ day: WaterDay, level: Double, done: Bool) -> some View {
        HStack(spacing: 10) {
            WaterCupGauge(character: character, mood: mood, level: level, celebrating: done,
                          parched: showsSkeleton, height: 44, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(WaterIntake.figure(day.total, ounces: ounces))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(day.total)
                    Text(done ? tr("达标啦")
                         : showsSkeleton ? tr("渴成骷髅了")
                         : "/ \(WaterIntake.figure(day.goal, ounces: ounces)) \(WaterIntake.unitLabel(ounces: ounces))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(done ? WaterStyle.water
                                         : showsSkeleton ? Color(hex: PaletteColor.red.hex) : WidgetStyle.secondary)
                        .monospacedDigit()
                }
                WaterCupRow(filled: WaterPetCards.filledCups(total: day.total, goal: day.goal),
                            slots: WaterPetCards.cupSlots, cupWidth: 7, spacing: 3.5)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: day.total)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            drinkButton(size: 12)
        }
    }

    /// 圆环样式。
    private func ringWide(_ day: WaterDay, lap: Double, done: Bool) -> some View {
        HStack(spacing: 10) {
            ring(level: lap, done: done, diameter: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? tr("今天达标啦")
                     : showsSkeleton ? tr("渴成骷髅了 · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                     : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                    .font(.system(size: 12))
                    .foregroundStyle(done ? WaterStyle.water
                                     : showsSkeleton ? Color(hex: PaletteColor.red.hex) : WidgetStyle.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            drinkButton(size: 12)
        }
    }

    // MARK: Column

    /// 56pt across: the cup (or ring), the amount, the goal, the "+".
    private func column(_ day: WaterDay, level: Double, lap: Double, done: Bool) -> some View {
        VStack(spacing: 3) {
            if isRing {
                ring(level: lap, done: done, diameter: 34)
            } else {
                // 竖排只有 56 宽：角色小一点、多站到杯子前面一些。
                WaterCupGauge(character: character, mood: mood, level: level, celebrating: done,
                              parched: showsSkeleton, height: 34, reduceMotion: reduceMotion,
                              characterScale: 0.72, overlap: 0.35)
            }
            VStack(spacing: 0) {
                Text(WaterIntake.figure(day.total, ounces: ounces))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? tr("达标啦") : "/ \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(done ? WaterStyle.water : WidgetStyle.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            drinkButton(size: 10)
        }
    }

    // MARK: Liquid

    /// 整张卡片是一杯水：水位是今天的进度，满了水面盖过上沿，达标的那一刻
    /// 起水面闪几秒金光（和喝了一杯举杯子的时间一样）。数字和 + 浮在水上。
    private func liquid(_ day: WaterDay, done: Bool) -> some View {
        let level = LiquidLooks.waterLevel(total: day.total, goal: day.goal)
        let vertical = context.position.isVertical
        return ZStack {
            // 液态的水用卡片的颜色主题（喝水默认青蓝，见 `WidgetTint`）。
            LiquidWater(level: level, tint: theme?.main(dark: scheme == .dark) ?? WaterStyle.water,
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen,
                        golden: done && mood == .drink)
                .fillingCard()
            if vertical {
                VStack(spacing: 3) {
                    Text(WaterIntake.figure(day.total, ounces: ounces))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(day.total)
                    Text(done ? tr("达标啦") : "\(WaterIntake.percent(total: day.total, goal: day.goal))%")
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.primary.opacity(0.75))
                        .monospacedDigit()
                    drinkButton(size: 10)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                            .rollingValue(day.total)
                        Text(done ? tr("今天达标啦") : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetStyle.primary.opacity(0.75))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    drinkButton(size: 12)
                }
            }
        }
    }

    // MARK: Pieces

    /// The Codex tile's ring, in the water's blue, with the percentage inside;
    /// a check when the day is done. 超过目标时不封顶：满圈上面再画第二圈，
    /// `level` 是不封顶的进度（见 `RingLap`）。
    private func ring(level: Double, done: Bool, diameter: CGFloat) -> some View {
        let tint = WaterStyle.water
        return MetricProgressRing(progress: level, tint: tint, track: tint.opacity(0.16),
                                  diameter: diameter, lineWidth: diameter > 36 ? 4.5 : 4,
                                  laps: true) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.32, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: done)
            } else {
                Text("\(min(99, Int((level * 100).rounded(.down))))")
                    .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
    }

    /// One cup of water. The level rising is the confirmation, so the write
    /// is animated rather than the press.
    private func drinkButton(size: CGFloat) -> some View {
        let cup = WaterIntake.cupSize(instance.config)
        return TileGlyph(symbol: "plus", size: size, tint: WaterStyle.water, action: context.isPreview ? nil : {
            withAnimation(.snappy(duration: 0.35)) {
                WaterLog.drink(.water, amount: cup, in: instance)
            }
        })
        .help(tr("喝了一杯水（\(WaterIntake.amount(cup, ounces: ounces))）"))
        .accessibilityLabel(tr("记录一杯水，\(WaterIntake.amount(cup, ounces: ounces))"))
    }
}

/// The writes the tile and the panel both make, from the instance's current
/// log so the two can never disagree.
@MainActor
enum WaterLog {
    static func change(_ instance: WidgetInstance, _ edit: ([WaterDay], Int) -> [WaterDay]) {
        WidgetWriter.write(instance) { config in
            WaterIntake.store(edit(WaterIntake.days(config), WaterIntake.goal(config)), in: &config)
        }
    }

    static func drink(_ type: DrinkType, amount: Int, factor: Double? = nil, in instance: WidgetInstance) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            let days = WaterIntake.logging(type, amount: amount, factor: factor, in: WaterIntake.days(config),
                                           goal: WaterIntake.goal(config), now: now)
            WaterIntake.store(days, in: &config, now: now)
            // The log keeps minutes; the cup in the character's paws needs the second.
            config.set("loggedAt", .number(now.timeIntervalSince1970))
            // A drink answers a hand-picked reminder; the schedule resumes.
            config.set(WaterReminder.overrideKey, nil)
        }
        PetTreats.give(.water)
    }

    static func undo(_ instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.undoingLast(in: days, goal: goal, now: .now) }
    }

    static func remove(at index: Int, in instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.removing(at: index, in: days, goal: goal, now: .now) }
    }

    /// A goal picked by hand, replacing the recommendation.
    static func setGoal(_ goal: Int, in instance: WidgetInstance) {
        profile(instance) { config, _ in WaterGoal.settingManual(goal, in: &config) }
    }

    /// 恢复推荐: the hand-picked goal goes, the recommendation is back.
    static func useRecommended(in instance: WidgetInstance) {
        profile(instance) { config, _ in WaterGoal.followingRecommendation(in: &config) }
    }

    /// Changes something the goal is worked out from, then moves today's
    /// stored goal along with it so the day is frozen at the right number
    /// once it is over. Finished days are left alone.
    static func profile(_ instance: WidgetInstance, _ edit: (inout WidgetConfig, Date) -> Void) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            edit(&config, now)
            let goal = WaterIntake.goal(config, now: now)
            WaterIntake.store(WaterIntake.settingGoal(goal, in: WaterIntake.days(config), now: now),
                              in: &config, now: now)
        }
    }

    static func set(_ key: String, _ value: WidgetConfig.Value?, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, value) }
    }

    /// 复位: the personal details, the hand-picked goal and the reminder
    /// schedule back to the defaults, so the goal follows the recommendation
    /// again. The drink log, the character and the unit stay.
    static func resetSettings(in instance: WidgetInstance) {
        let defaults = WidgetCatalog.entry(.water)?.defaults ?? WidgetConfig()
        profile(instance) { config, _ in
            for key in ["remindEvery", "start", "end", "cupSize"] {
                config.set(key, defaults[key])
            }
            for key in WaterGoal.Key.profile { config.set(key, nil) }
            WaterGoal.followingRecommendation(in: &config)
            config.set(WaterReminder.overrideKey, nil)
        }
    }
}

/// What the library and the screenshots show: a believable morning and a
/// fortnight behind it, anchored to the day being drawn.
enum WaterSamples {
    static func days(today: Date) -> [WaterDay] {
        let calendar = WaterIntake.calendar
        let key = HabitTracker.dayKey(today, calendar: calendar)
        var days = [WaterDay(key: key, goal: 2000, entries: [
            WaterEntry(minute: 8 * 60 + 40, type: .water, amount: 300),
            WaterEntry(minute: 10 * 60 + 15, type: .coffee, amount: 250),
            WaterEntry(minute: 12 * 60 + 5, type: .water, amount: 500),
            WaterEntry(minute: 14 * 60 + 30, type: .tea, amount: 222),
        ])]
        let totals = [2100, 2350, 1600, 2000, 2250, 1900, 2400, 2050, 1200, 2200, 2000, 2300, 1750]
        for (back, total) in totals.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: -(back + 1), to: today) else { continue }
            days.append(WaterDay(key: HabitTracker.dayKey(date, calendar: calendar), goal: 2000, summary: total))
        }
        return days.sorted { $0.key < $1.key }
    }
}
