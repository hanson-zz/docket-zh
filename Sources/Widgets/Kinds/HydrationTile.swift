import Foundation
import SwiftUI

/// A drop that fills up between drinks.
///
/// It was a whole card of light blue water, the one tile on the shelf with a
/// colour of its own, and it read as a sticker among graphite cards. The
/// water is now the mark in the tile's badge: the same rising level, on the
/// same neutral card as every other tile.
///
/// A click on the card belongs to the shelf, so logging a drink is a "+" beside
/// the readout rather than the whole glass: the card is what opens the widget,
/// and a tile-wide tap would take that click before the shelf ever saw it.
struct HydrationTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Guard against a zero or negative stored interval: it would divide by
    /// zero below and NaN the whole path.
    private var duration: TimeInterval {
        max(60, instance.config.double("duration", default: 2700))
    }

    /// Seconds until the next drink.
    ///
    /// Counted from the last drink once there has been one.
    ///
    /// Until then the cycle is anchored to the reference date, so a widget
    /// that has never been tapped still agrees with every other shelf about
    /// where in the interval it is.
    private var remaining: TimeInterval {
        // Sample value chosen to match the library reference render.
        if context.isPreview { return 1800 }
        let period = duration
        let last = instance.config.double("lastDrink")
        if last > 0 {
            let since = max(0, context.now.timeIntervalSince1970 - last)
            return max(0, period - since)
        }
        let into = context.now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period)
        return period - into
    }

    /// Logs a drink: the glass empties and starts filling again.
    private func drink() {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { config in
            config.set("lastDrink", .number(Date.now.timeIntervalSince1970))
        }
    }

    /// Height of the water, 0…1, as elapsed progress toward the next drink.
    private var level: Double {
        // The reference preview shows a near-full glass; keep the library card
        // looking like the widget rather than like an empty one.
        if context.isPreview { return 0.75 }
        return min(1, max(0, 1 - remaining / duration))
    }

    private var clock: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                // 76x88: drop, clock, and the control under them.
                VStack(spacing: 4) {
                    TileBadge(size: 34) { drop(size: 17) }
                    Text(clock)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    drinkButton(size: 10)
                }
            } else {
                HStack(spacing: 10) {
                    TileBadge { drop(size: 20) }
                    TileReading(value: clock, caption: "下次喝水")
                    Spacer(minLength: 0)
                    drinkButton(size: 12)
                }
            }
        }
    }

    /// The drop's outline, with the water filled in up to the level: a muted
    /// steel blue, the accent and nothing louder.
    private func drop(size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "drop")
                .foregroundStyle(WidgetStyle.secondary)
            Image(systemName: "drop.fill")
                .foregroundStyle(Color(hex: PaletteColor.blue.hex).mix(with: WidgetStyle.primary, by: 0.6))
                .mask {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().frame(height: geo.size.height * level)
                        }
                    }
                }
                .animation(.snappy(duration: 0.35), value: level)
        }
        .font(.system(size: size, weight: .regular))
    }

    /// Only ever as big as itself: the card's own click has to reach the shelf,
    /// so nothing here may spread to fill it. `TileGlyph` is the shelf-wide
    /// treatment for exactly that - see StopwatchTile. The plain "+" replaces
    /// `plus.circle.fill`, which would have drawn a disc inside a disc.
    ///
    /// The fill rising is the only confirmation a drink registered, which is
    /// why the write is animated rather than the press.
    private func drinkButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "plus", size: size, action: context.isPreview ? nil : {
            withAnimation(.snappy(duration: 0.35)) { drink() }
        })
        .accessibilityLabel("记录喝水")
    }
}
