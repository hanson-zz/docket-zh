import SwiftUI

/// A scrap of paper on the shelf (160×100, always expanded).
///
/// The words are only shown here; they are written in the note's detail panel,
/// on paper the size of something you write on rather than glance at. A field
/// on the tile cannot coexist with that: the caret would swallow the click that
/// opens the panel, and the shelf is a non-activating panel, so a click on the
/// paper had to beg for key status before a single letter could land.
struct StickyNoteTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Every `PaperColor` is a light swatch in both appearances, so the ink is
    /// deliberately fixed dark rather than semantic - `Color.primary` would go
    /// white in dark mode and vanish into the paper.
    private var ink: Color { Color(hex: swatch.inkHex) }

    private var swatch: PaperColor {
        PaperColor(rawValue: instance.config.string("color", default: "yellow")) ?? .yellow
    }

    private var paper: Color {
        WidgetStyle.paper(swatch)
    }

    private var stored: String { instance.config.string("text") }

    private var text: String {
        guard stored.isEmpty else { return stored }
        // An empty note on the shelf stays empty; the library needs something
        // to show.
        return context.isPreview ? "买咖啡\n给小王回电话" : ""
    }

    var body: some View {
        // A column is the same paper card, just narrower and taller: smaller
        // ink, one more line, and the text shrinks a little rather than
        // trailing off in an ellipsis inside 56pt of usable width.
        let column = context.position.isVertical
        return WidgetSurface(fill: paper) {
            // An empty note is blank paper, not a blank widget.
            //
            // There was no prompt here at all, on the reasoning that grey
            // placeholder words on a sticky note read as a note someone
            // already wrote. That reasoning holds, and the conclusion did
            // not: an entirely empty yellow rectangle reads as a widget that
            // failed to load. Ruled lines and a pencil are the way out.
            // Nobody mistakes a ruling for handwriting, and paper you can
            // see the lines on is obviously paper waiting to be written on.
            if text.isEmpty {
                blankPaper(column: column)
            } else {
                Text(text)
                .font(.system(size: column ? 10 : 13, weight: .semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .lineLimit(column ? 5 : 4)
                .minimumScaleFactor(column ? 0.8 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, column ? 8 : 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // No button trait: the note itself is read, not activated -
                // writing is its own control and the card belongs to the shelf.
                .accessibilityLabel("便签：\(stored)")
            }
        }
    }

    /// Ruled lines under a pencil, at the weight of a watermark.
    ///
    /// Drawn in the ink colour rather than grey: every paper swatch is light
    /// in both appearances, so a semantic grey would go white in the dark and
    /// disappear. Opacity does the work instead, which keeps it a hint at any
    /// paper colour.
    private func blankPaper(column: Bool) -> some View {
        VStack(alignment: .leading, spacing: column ? 5 : 7) {
            Image(systemName: "pencil.line")
                .font(.system(size: column ? 11 : 13, weight: .semibold))
                .foregroundStyle(ink.opacity(0.28))
            ForEach(0..<(column ? 2 : 2), id: \.self) { line in
                Capsule()
                    .fill(ink.opacity(0.14))
                    // The second line is shorter, the way a written one runs
                    // out. Equal lines read as a loading skeleton.
                    .frame(width: line == 0 ? nil : 34, height: 2)
            }
        }
        .padding(.vertical, column ? 8 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("空白便签")
    }
}
