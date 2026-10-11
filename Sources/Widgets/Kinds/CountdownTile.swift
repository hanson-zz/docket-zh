import SwiftUI

/// Time left against a deadline, with what it is counting to underneath.
///
/// A click anywhere on the card belongs to the shelf, so starting sits on the
/// tile as a glyph the size of itself - begun in one click, without anything
/// opening - and only while the countdown is idle, since a gesture that would
/// decline the click still swallows it. Restarting a countdown in flight
/// throws away time already run and is the panel's alone rather than a stray
/// click on a card.
///
/// The deadline lives in the widget's own config, so it survives a relaunch and
/// follows the widget between profiles.
struct CountdownTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let duration = max(0, instance.config.double("duration", default: 300))
        let name = instance.config.string("name")
        let title = name.isEmpty ? "倒计时" : name

        WidgetSurface {
            if context.position.isVertical {
                // 76x62 column: no room for the timer symbol, so the clock
                // carries the tile and the name captions it. The glyph goes
                // under both - the clock already fills the column's width.
                VStack(spacing: 1) {
                    Text(docketClockString(remaining(duration: duration)))
                        .font(WidgetStyle.value(19))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(title)
                        .font(WidgetStyle.caption(9))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !isRunning { startButton(title: title, size: 9) }
                }
            } else {
                // 140pt is the narrowest card with a badge, so the badge runs
                // a little smaller here and the reading shrinks to fit rather
                // than cutting "5:00" to "5:…".
                // No badge: at 140pt a badge, a reading and the play control
                // left the name 38pt, which came out as "Countdo…". The
                // control is the tile's mark here, the way the artwork is
                // Now Playing's.
                HStack(spacing: 8) {
                    TileReading(value: docketClockString(remaining(duration: duration)),
                                caption: title)
                    Spacer(minLength: 0)
                    if !isRunning { startButton(title: title, size: 12) }
                }
            }
        }
    }

    /// Only ever as big as itself: the card's own click has to reach the shelf,
    /// so nothing here may spread to fill it. `TileGlyph` is the shelf-wide
    /// treatment for exactly that - see StopwatchTile.
    private func startButton(title: String, size: CGFloat) -> some View {
        TileGlyph(symbol: "play.fill", size: size,
                  action: context.isPreview ? nil : (start as () -> Void))
            .accessibilityLabel("开始“\(title)”")
    }

    /// A countdown is running only while it carries a deadline; idle it shows
    /// what it would count from, not 0:00.
    private func remaining(duration: TimeInterval) -> TimeInterval {
        guard !context.isPreview, instance.config["deadline"] != nil else { return duration }
        let deadline = instance.config.double("deadline")
        return max(0, min(deadline - context.now.timeIntervalSince1970, duration))
    }

    private var isRunning: Bool {
        !context.isPreview && instance.config.double("deadline") > context.now.timeIntervalSince1970
    }

    /// The deadline is stored rather than a remaining time, so the tile keeps
    /// counting down across a relaunch instead of resuming where it stopped.
    private func start() {
        guard !context.isPreview else { return }
        let duration = max(0, instance.config.double("duration", default: 300))
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(instance) { config in
                config.set("deadline", .number(Date.now.timeIntervalSince1970 + duration))
            }
        }
    }
}
