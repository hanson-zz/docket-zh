import SwiftUI

/// One shortcut, one click.
///
/// The card's own click opens the panel, which is where a shortcut is chosen
/// and where a failure is explained, so the glyph is the only thing on the
/// tile that acts. Same division as the focus timer: the thing you do
/// constantly stays on the shelf, the thing you do once lives in the panel.
///
/// A running shortcut shows a stop glyph rather than a spinner. There is no
/// progress to report and no way to get any, so the honest offer is the one
/// thing the app can actually do about it.
struct ShortcutTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // A column is narrower, not different: the same glyph over the same
        // caption, sized for 56pt of usable width.
        let column = context.position.isVertical
        let name = resolvedName
        let running = isRunning(name)

        return WidgetSurface {
            if column {
                VStack(spacing: 5) {
                    glyph(running: running, name: name, size: 13)
                    caption(name, size: 11)
                }
            } else {
                // The glyph is the badge here: it is both the shortcut's mark
                // and the one thing on the tile that acts.
                HStack(spacing: 10) {
                    glyph(running: running, name: name, size: 12)
                    TileReading(value: name.isEmpty ? tr("选择") : name,
                                caption: running ? tr("正在运行") : tr("快捷指令"),
                                valueSize: 15)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Pieces

    /// Only ever as big as itself, so the card's own click still reaches the
    /// shelf and opens the panel. See StopwatchTile for the same treatment.
    private func glyph(running: Bool, name: String, size: CGFloat) -> some View {
        TileGlyph(symbol: running ? "stop.fill" : "play.fill",
                  size: size,
                  action: context.isPreview || name.isEmpty ? nil : { act(running: running, name: name) })
            .accessibilityLabel(running ? tr("停止“\(name)”") : name.isEmpty ? tr("未选择快捷指令") : tr("运行“\(name)”"))
    }

    private func caption(_ name: String, size: CGFloat) -> some View {
        Text(name.isEmpty ? tr("选择") : name)
            .font(WidgetStyle.label(size))
            .foregroundStyle(name.isEmpty ? WidgetStyle.secondary : WidgetStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func act(running: Bool, name: String) {
        if running {
            ShortcutsService.shared.stop()
        } else {
            ShortcutsService.shared.run(name)
        }
    }

    /// The library has no shortcut to point at and must not run one, so it
    /// shows a representative name instead of an empty card.
    private var resolvedName: String {
        context.isPreview ? tr("晨间例程") : instance.config.string("name")
    }

    private func isRunning(_ name: String) -> Bool {
        guard !context.isPreview, !name.isEmpty else { return false }
        return ShortcutsService.shared.running == name
    }
}
