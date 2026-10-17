import SwiftUI

// The one structure every tile is built from, taken from Now Playing's:
//
//     [ badge ]  Value          [control]
//                caption
//
// Before this, each tile had its own: some led with a glyph, some with
// nothing, AirDrop with an app icon over a label, and values and captions ran
// at a different size on almost every card. Side by side on the shelf
// nothing lined up. Now the badge is the same square in the same place on
// every card, the value and caption are the same two type styles, and a
// control is always `TileGlyph`.

/// The square a tile leads with: the widget's live mark on a pane of glass.
///
/// The same size as Now Playing's artwork, so a row of tiles has one left
/// edge for its pictures and one for its text. Neutral, like the card: what
/// is drawn in it carries the meaning, and any colour in it is an accent.
struct TileBadge<Content: View>: View {
    var size: CGFloat = CGFloat(DockMetrics.badge)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: CGFloat(DockMetrics.badgeCorner(Double(size))), style: .continuous)
                    .fill(WidgetStyle.primary.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: CGFloat(DockMetrics.badgeCorner(Double(size))), style: .continuous)
                            .strokeBorder(WidgetStyle.primary.opacity(0.1), lineWidth: 0.5)
                    }
            }
    }
}

/// A tile's value with its caption under it, in the two styles every tile
/// shares.
///
/// Values shrink to fit rather than truncate: "5:…" over "Count…" said
/// nothing, where a slightly smaller "5:00" over "Countdown" says it all.
struct TileReading: View {
    var value: String
    var caption: String
    var valueSize: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(DockMetrics.lineSpacing)) {
            Text(value)
                .font(.system(size: valueSize, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(value)
            Text(caption)
                .font(WidgetStyle.note)
                .foregroundStyle(WidgetStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A ring for a badge: a faint track and the part done over it.
struct TileRing: View {
    var progress: Double
    var tint: Color = WidgetStyle.primary
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(WidgetStyle.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(7)
    }
}
