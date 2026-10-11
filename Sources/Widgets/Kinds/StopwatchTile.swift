import SwiftUI

/// Elapsed time plus a one-word state.
///
/// Already a stack, so the 76pt column is the same thing in smaller type.
///
/// A click on the card opens Clock, so the card belongs to the shelf. Starting
/// and stopping stays on the tile as a glyph the size of itself - a run begun
/// in one click, without anything opening, is worth the room - and clearing a
/// stopped run sits beside it, because nothing else can zero the count: the
/// Stopwatch has no panel and no settings of its own.
///
/// The state is `started` and `elapsed` in the widget's own config, so it
/// survives a relaunch and follows the widget between profiles.
struct StopwatchTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let state = state
        WidgetSurface {
            if context.position.isVertical {
                // 76x62: a 56pt-wide column has no room beside the readout, so
                // the glyphs go under it.
                VStack(spacing: 2) {
                    readout(state, value: 17, caption: 9, alignment: .center)
                    controls(state, size: 9)
                }
            } else {
                HStack(spacing: instance.expanded ? 10 : 6) {
                    // The badge only where there is room for it: the compact
                    // card is 120pt, and a dial there would leave the count
                    // no width at all.
                    if instance.expanded {
                        TileBadge {
                            Image(systemName: state.running ? "stopwatch.fill" : "stopwatch")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(WidgetStyle.primary.opacity(0.85))
                        }
                    }
                    // The readout takes the width so the glyphs stay pinned to
                    // the trailing edge: the count ticks every second and
                    // widens to h:mm:ss past the hour, and a control that slid
                    // along with it would be a moving target.
                    TileReading(value: Self.format(state.elapsed), caption: state.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    controls(state, size: 11)
                }
            }
        }
    }

    private func readout(_ state: State, value: CGFloat, caption: CGFloat,
                         alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(Self.format(state.elapsed))
                .font(WidgetStyle.value(value))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(state.caption)
                .font(WidgetStyle.caption(caption))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                // The glyphs have taken the width the caption used to spread
                // into, and "Running" is the longest of the three words.
                .minimumScaleFactor(0.7)
        }
    }

    /// Only ever as big as themselves: the card's own click has to reach the
    /// shelf, which is what opens Clock, so nothing here may spread to fill it.
    private func controls(_ state: State, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            TileGlyph(symbol: state.running ? "pause.fill" : "play.fill",
                      size: size, action: context.isPreview ? nil : (toggle as () -> Void))
                .accessibilityLabel(state.running ? "停止秒表" : "启动秒表")
            // A run can only be cleared once it has stopped - which is also
            // the only moment this pair changes shape, since a reset that
            // appeared and vanished under the pointer as the seconds ran would
            // be a trap. Nothing to clear means no glyph at all: a control
            // that did nothing would still swallow the click the card owes
            // the shelf.
            if !state.running, state.elapsed > 0 {
                TileGlyph(symbol: "arrow.counterclockwise", size: size,
                          tint: WidgetStyle.secondary,
                          action: context.isPreview ? nil : (reset as () -> Void))
                    .accessibilityLabel("重置秒表")
            }
        }
    }

    /// Banks what has run so far when stopping, so restarting continues rather
    /// than beginning again.
    private func toggle() {
        guard !context.isPreview else { return }
        let started = instance.config.double("started")
        let banked = instance.config.double("elapsed")
        WidgetWriter.write(instance) { config in
            if started > 0 {
                config.set("elapsed", .number(banked + max(0, Date.now.timeIntervalSince1970 - started)))
                config.set("started", .number(0))
            } else {
                config.set("started", .number(Date.now.timeIntervalSince1970))
            }
        }
    }

    private func reset() {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { config in
            config.set("started", .number(0))
            config.set("elapsed", .number(0))
        }
    }

    /// Carries `running` rather than leaving the glyphs to read it back out of
    /// `caption`: both of them hang off it, and a displayed word is no place
    /// to keep state.
    private typealias State = (elapsed: TimeInterval, caption: String, running: Bool)

    private var state: State {
        let started = instance.config.double("started")
        let banked = instance.config.double("elapsed")
        if started > 0 {
            return (banked + max(0, context.now.timeIntervalSince1970 - started), "正在计时", true)
        }
        if banked > 0 { return (banked, "已暂停", false) }
        // The library has no running stopwatch, so show a plausible one.
        return context.isPreview ? (83, "已暂停", false) : (0, "就绪", false)
    }

    static func format(_ elapsed: TimeInterval) -> String {
        let seconds = Int(max(0, elapsed))
        let duration = Duration.seconds(seconds)
        return seconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }
}
