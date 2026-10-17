import Foundation
import SwiftUI

/// A stand-up reminder, built the way the old drink reminder was: a ring that
/// fills while you sit, a countdown, and a check to log a break.
///
/// The card's own click opens the panel; logging is the check beside the
/// reading, so it never takes the card's click.
struct PostureTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var schedule: PostureSchedule { PostureSchedule(config: instance.config) }

    private var lastBreak: Date? {
        let raw = instance.config.double("lastBreak")
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    private var active: Bool { context.isPreview || schedule.isActive(context.now) }

    private var remaining: TimeInterval {
        if context.isPreview { return 1260 }
        return schedule.remaining(lastBreak: lastBreak, now: context.now)
    }

    private var progress: Double {
        if context.isPreview { return 0.3 }
        return schedule.progress(lastBreak: lastBreak, now: context.now)
    }

    private var breaksToday: Int {
        if context.isPreview { return 3 }
        return PostureTally.today(storedDay: instance.config.string("breakDay"),
                                  count: instance.config.int("breakCount"), now: context.now)
    }

    private var value: String {
        guard active else { return "--:--" }
        guard remaining > 0 else { return "起身" }
        let seconds = max(0, Int(remaining.rounded(.up)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var caption: String {
        guard active else { return "不在提醒时段" }
        return remaining > 0 ? "今日已起身 \(breaksToday) 次" : "该起身活动了"
    }

    /// When the next notification goes out, or nil when there should be none.
    private var nextReminder: Date? {
        guard !context.isPreview else { return nil }
        return schedule.nextReminder(lastBreak: lastBreak, now: context.now)
    }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: WidgetStyle.badgeCompact) { mark(size: 13) }
                    Text(value)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    breakButton(size: 10)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge { mark(size: 15) }
                    TileReading(value: value, caption: caption)
                    Spacer(minLength: 0)
                    breakButton(size: 12)
                }
            }
        }
        .onAppear { PostureNotifier.shared.update(instance, next: nextReminder) }
        .onChange(of: nextReminder) { _, next in PostureNotifier.shared.update(instance, next: next) }
        .onChange(of: instance.config.bool("notify", default: true)) { _, _ in
            PostureNotifier.shared.update(instance, next: nextReminder)
        }
    }

    private func mark(size: CGFloat) -> some View {
        ZStack {
            TileRing(progress: active ? progress : 0, tint: tint)
            Image(systemName: "figure.stand")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active && remaining <= 0 ? tint : WidgetStyle.primary)
        }
    }

    /// The accent once a break is due, white until then.
    private var tint: Color {
        active && remaining <= 0
            ? Color(hex: PaletteColor.green.hex).mix(with: WidgetStyle.primary, by: 0.35)
            : WidgetStyle.primary
    }

    private func breakButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "checkmark", size: size, action: context.isPreview ? nil : {
            withAnimation(.snappy(duration: 0.35)) { PostureLog.logBreak(instance) }
        })
        .help("我起身活动了")
        .accessibilityLabel("记录一次起身")
    }
}

/// The one write both the tile and the panel make.
@MainActor
enum PostureLog {
    static func logBreak(_ instance: WidgetInstance, now: Date = .now) {
        let tally = PostureTally.logging(storedDay: instance.config.string("breakDay"),
                                         count: instance.config.int("breakCount"), now: now)
        WidgetWriter.write(instance) { config in
            config.set("lastBreak", .number(now.timeIntervalSince1970))
            config.set("breakDay", .string(tally.day))
            config.set("breakCount", .number(Double(tally.count)))
        }
    }
}
