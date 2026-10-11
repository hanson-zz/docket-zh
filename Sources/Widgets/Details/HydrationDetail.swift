import Foundation
import SwiftUI

/// The hydration reminder in wall-clock terms, plus a button big enough to
/// press without aiming at it.
///
/// The widget stores two things and only two: how long a cycle is
/// (`duration`) and when the last drink was logged (`lastDrink`). There is no
/// count of glasses, no daily goal and no log - one timestamp is overwritten
/// by the next - so this panel draws no tally, no goal ring and no week's
/// chart. Inventing any of them would be inventing the data behind them.
///
/// What it can say that the tile cannot: the clock time the next drink is due
/// at rather than a countdown to it, when the last one actually went in, the
/// interval those two are separated by, and - the tile's blind spot, since its
/// countdown floors at 0:00 - how long a drink has been overdue.
struct HydrationDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // Seconds, to agree with the tile's own clock. It has to be a schedule
        // rather than `context.now`: the panel's root view is assigned once
        // when it opens, so that clock is frozen and the countdown would sit
        // perfectly still for as long as the panel stayed up.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private func content(now: Date) -> some View {
        let left = remaining(now: now)
        // The glass behind the card is full the moment a drink goes in and
        // drains as the next one comes due: the level is the interval, which
        // is the one thing the model actually measures. Not a day's tally,
        // which it has no record of.
        return DetailCard {
            ZStack(alignment: .bottom) {
                MeshBackdrop(color: accent)
                Water(level: left / duration,
                      phase: now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4,
                      colour: accent)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(left > 0 ? "下次喝水时间" : "该喝水了")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))
                    // A time of day, which is the thing the tile's countdown is
                    // not: "2:49 PM" is a moment you can plan around, "17:22" is
                    // one you have to do arithmetic on.
                    Text(left > 0 ? clock(now.addingTimeInterval(left)) : "喝口水吧")
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(headlineCaption(left, now: now))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    StatChip(label: "上次喝水", value: lastDrinkLine(now: now))
                    StatChip(label: "间隔", value: interval)
                        .frame(width: 96)
                }

                drinkButton
            }
        }
    }

    // MARK: Action

    /// The tile's "+" is 13pt across because a card's own click belongs to the
    /// shelf and nothing on it may spread. The panel has no such contest, so
    /// the one action this widget has gets the full width.
    private var drinkButton: some View {
        Button {
            // The tile animates its water rising on a drink; the same write
            // redraws this panel, so it is animated from here too.
            withAnimation(.snappy(duration: 0.35)) { drink() }
        } label: {
            Label("记录喝水", systemImage: "drop.fill")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(.white.opacity(0.24)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("记录喝水")
    }

    // MARK: Lines

    /// Under the headline: the countdown the tile shows when there is one, and
    /// how far past due it is when there is not. The tile clamps at 0:00 and
    /// stays there, which says a drink is due but never that it has been due
    /// for half an hour.
    private func headlineCaption(_ left: TimeInterval, now: Date) -> String {
        guard left <= 0 else { return "还有 \(docketClockString(left))" }
        let last = instance.config.double("lastDrink")
        guard !context.isPreview, last > 0 else { return "该喝水了" }
        let over = now.timeIntervalSince1970 - last - duration
        return over >= 60 ? "已超时 \(spelled(over))" : "该喝水了"
    }

    /// The one fact only the stored timestamp holds. A widget that has never
    /// been tapped has no last drink - its cycle is anchored to the reference
    /// date instead - so it says so rather than dressing the anchor up as one.
    private func lastDrinkLine(now: Date) -> String {
        let last = instance.config.double("lastDrink")
        guard !context.isPreview, last > 0 else { return "尚未记录" }
        let date = Date(timeIntervalSince1970: last)
        let since = max(0, now.timeIntervalSince(date))
        return since < 60 ? "\(clock(date))，刚刚"
                          : "\(clock(date))，\(spelled(since))前"
    }

    // MARK: Data
    //
    // The tile's accessors, key for key, so the card and the panel cannot
    // disagree about when the next drink is due.

    /// Guard against a zero or negative stored interval: it would divide by
    /// zero below and NaN the whole path.
    private var duration: TimeInterval {
        max(60, instance.config.double("duration", default: 2700))
    }

    private var interval: String { spelled(duration) }

    /// Seconds until the next drink, counted from the last one once there has
    /// been one and from the reference date until then - the tile's rule,
    /// re-read against the schedule's clock rather than the frozen one.
    private func remaining(now: Date) -> TimeInterval {
        // The tile's sample value, so a library preview of the two agrees.
        if context.isPreview { return 1800 }
        let period = duration
        let last = instance.config.double("lastDrink")
        if last > 0 {
            return max(0, period - max(0, now.timeIntervalSince1970 - last))
        }
        let into = now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period)
        return period - into
    }

    private func drink() {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { config in
            config.set("lastDrink", .number(Date.now.timeIntervalSince1970))
        }
    }

    private var accent: Color {
        WidgetCatalog.accentHex(.hydration).map { Color(hex: $0) } ?? WidgetStyle.primary
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Hours and minutes in words - "45 min", "1 hr 30 min". The m:ss clock is
    /// right for a countdown that is ticking and wrong for a span that is
    /// merely long.
    private func spelled(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Water filling the card to `level`, its surface a slow double wave.
private struct Water: View {
    var level: Double
    /// 0…1 through one swell, so the surface moves with the panel's tick.
    var phase: Double
    var colour: Color

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let top = size.height * (1 - min(1, max(0.04, level)))
            ZStack {
                surface(size, top: top, shift: phase + 0.5, amplitude: 5)
                    .fill(MeshBackdrop.muted(colour).opacity(0.5))
                surface(size, top: top + 3, shift: phase, amplitude: 4)
                    .fill(LinearGradient(colors: [MeshBackdrop.muted(colour, by: 0.62),
                                                  MeshBackdrop.muted(colour, by: 0.85)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .animation(.smooth(duration: 0.8), value: level)
        }
        .accessibilityHidden(true)
    }

    private func surface(_ size: CGSize, top: CGFloat, shift: Double, amplitude: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0, through: size.width, by: 4) {
                let angle = (Double(x / max(size.width, 1)) + shift) * 2 * .pi * 1.5
                p.addLine(to: CGPoint(x: x, y: top + amplitude * CGFloat(sin(angle))))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
        }
    }
}
