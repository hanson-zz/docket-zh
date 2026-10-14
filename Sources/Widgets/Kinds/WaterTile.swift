import Foundation
import SwiftUI

/// 喝水：the red panda fills up as today's glasses go in.
///
/// Two styles. 角色 leads with the character and the water inside it; 圆环
/// is the Codex tile's ring with the percentage in the middle, for a shelf
/// that wants something quieter. Both have today's tally and a "+" that logs
/// one cup of water (`cupSize`). Like the hydration tile, the "+" is the only
/// control: the card's own click opens the panel, where other amounts and
/// drinks, the day's list, the goal and the history live.
///
/// The tile also keeps the reminder scheduled, the way the stand-up tile
/// does: one pending notification, moved whenever the next one changes.
struct WaterTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var isRing: Bool { instance.config.string("layout", default: "character") == "ring" }
    private var ounces: Bool { WaterIntake.usesOunces(instance.config) }
    private var goal: Int { WaterIntake.goal(instance.config) }

    private var today: WaterDay {
        if context.isPreview {
            return WaterIntake.today(WaterSamples.days(today: context.now), goal: goal, now: context.now)
        }
        return WaterIntake.today(instance.config, now: context.now)
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
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(day, level: level, done: done)
                } else {
                    wide(day, level: level, done: done)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("喝水，\(WaterIntake.tally(total: day.total, goal: day.goal, ounces: ounces))")
        .onAppear { WaterNotifier.shared.update(instance, next: nextReminder) }
        .onChange(of: nextReminder) { _, next in WaterNotifier.shared.update(instance, next: next) }
    }

    // MARK: Wide

    private func wide(_ day: WaterDay, level: Double, done: Bool) -> some View {
        HStack(spacing: 10) {
            if isRing {
                ring(level: level, done: done, diameter: 40)
            } else {
                WaterPanda(level: level, celebrating: done, height: 40)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? "今天达标啦" : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                    .font(.system(size: 12))
                    .foregroundStyle(done ? WaterStyle.water : WidgetStyle.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            drinkButton(size: 12)
        }
    }

    // MARK: Column

    /// 56pt across: the character (or ring), the amount, the goal, the "+".
    private func column(_ day: WaterDay, level: Double, done: Bool) -> some View {
        VStack(spacing: 3) {
            if isRing {
                ring(level: level, done: done, diameter: 34)
            } else {
                WaterPanda(level: level, celebrating: done, height: 34)
            }
            VStack(spacing: 0) {
                Text(WaterIntake.figure(day.total, ounces: ounces))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? "达标啦" : "/ \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(done ? WaterStyle.water : WidgetStyle.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            drinkButton(size: 10)
        }
    }

    // MARK: Pieces

    /// The Codex tile's ring, in the water's blue, with the percentage inside;
    /// a check when the day is done.
    private func ring(level: Double, done: Bool, diameter: CGFloat) -> some View {
        let tint = WaterStyle.water
        return MetricProgressRing(progress: level, tint: tint, track: tint.opacity(0.16),
                                  diameter: diameter, lineWidth: diameter > 36 ? 4.5 : 4) {
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
        .help("喝了一杯水（\(WaterIntake.amount(cup, ounces: ounces))）")
        .accessibilityLabel("记录一杯水，\(WaterIntake.amount(cup, ounces: ounces))")
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
        change(instance) { days, goal in
            WaterIntake.logging(type, amount: amount, factor: factor, in: days, goal: goal, now: .now)
        }
    }

    static func undo(_ instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.undoingLast(in: days, goal: goal, now: .now) }
    }

    static func remove(at index: Int, in instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.removing(at: index, in: days, goal: goal, now: .now) }
    }

    static func setGoal(_ goal: Int, in instance: WidgetInstance) {
        let clamped = WaterIntake.clampGoal(goal)
        WidgetWriter.write(instance) { config in
            config.set("goal", .number(Double(clamped)))
            WaterIntake.store(WaterIntake.settingGoal(clamped, in: WaterIntake.days(config), now: .now), in: &config)
        }
    }

    static func set(_ key: String, _ value: WidgetConfig.Value, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, value) }
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
