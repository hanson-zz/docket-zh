import SwiftUI

/// Three ways to take a screenshot, one press each: a window, a region, the
/// whole screen. The card itself opens the system's Screenshot app, which is
/// where recording and the timer live.
struct CaptureTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 8) { buttons(size: 12) }
            } else {
                HStack(spacing: 10) { buttons(size: 12) }
            }
        }
    }

    @ViewBuilder
    private func buttons(size: CGFloat) -> some View {
        ForEach(ScreenCapture.Mode.allCases, id: \.self) { mode in
            TileGlyph(symbol: mode.symbol, size: size,
                      action: context.isPreview ? nil : { ScreenCapture.capture(mode) })
                .help(mode.title)
                .accessibilityLabel(mode.title)
        }
    }
}
