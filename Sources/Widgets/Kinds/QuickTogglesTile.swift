import SwiftUI

/// A row of round buttons for the things done many times a day: Dark Mode,
/// locking, the screen saver and emptying the Trash (which asks first).
struct QuickTogglesTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) { buttons }
            } else {
                HStack(spacing: 8) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(QuickActions.Action.allCases, id: \.self) { action in
            TileGlyph(symbol: action.symbol, size: 11,
                      tint: action == .darkMode && !context.isPreview && QuickActions.isDark
                        ? .orange : WidgetStyle.primary,
                      action: context.isPreview ? nil : { QuickActions.perform(action) })
                .help(action.title)
                .accessibilityLabel(action.title)
        }
    }
}
