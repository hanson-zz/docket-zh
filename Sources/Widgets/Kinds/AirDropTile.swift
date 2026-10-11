import SwiftUI

/// Presentational for now - the drop target lands with file handling.
struct AirDropTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // A column is narrower, not different: same glyph over the same
        // caption, just sized for 56pt of usable width.
        let column = context.position.isVertical
        return WidgetSurface {
            // Stacked, not side by side: at 100pt wide there is no room for a
            // badge and a reading in a row. The badge is the shelf's neutral
            // glass, not Apple's blue app icon, which was the only saturated
            // block on an otherwise quiet shelf.
            VStack(spacing: 6) {
                TileBadge(size: column ? 32 : 36) {
                    // SF Symbols has no AirDrop glyph; this is the closest.
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: column ? 15 : 16, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary)
                }
                Text("隔空投送")
                    .font(.system(size: column ? 12 : 13, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
