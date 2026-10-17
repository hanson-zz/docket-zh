import SwiftUI

/// A row of round buttons for the things done many times a day, chosen in
/// the widget's settings (`actions`). Switches with a state, like Keep Awake
/// or hidden files, are lit while on; actions that cannot be undone, like
/// emptying the Trash or quitting apps, ask first.
struct QuickTogglesTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var actions: QuickActions { QuickActions.shared }
    private var chosen: [QuickToggle] { QuickToggle.chosen(instance.config) }

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
        ForEach(chosen) { toggle in
            let on = !context.isPreview && toggle.hasState && actions.isOn(toggle)
            TileGlyph(symbol: toggle.symbol, size: 11,
                      tint: on ? .orange : WidgetStyle.primary,
                      action: context.isPreview ? nil : { actions.perform(toggle) })
                .help(on ? tr("\(toggle.title)：已打开") : toggle.help)
                .accessibilityLabel(toggle.title)
                .accessibilityValue(toggle.hasState ? (on ? tr("开") : tr("关")) : "")
        }
    }
}
