import AppKit
import SwiftUI

/// The emoji you reach for most, one click from the pasteboard, and a door
/// to the system's Character Viewer for the rest.
///
/// The set is the widget's `emoji` option, edited in the Widgets tab as a
/// comma separated list.
struct EmojiTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var copied: String?

    private var emoji: [String] {
        let stored = instance.config.strings("emoji", default: EmojiTile.defaults)
        return Array((stored.isEmpty ? EmojiTile.defaults : stored).prefix(9))
    }

    static let defaults = ["😂", "✨", "✅", "🔥", "🥹", "🙏", "💡", "🚀", "❤️"]

    var body: some View {
        let column = context.position.isVertical
        let perRow = column ? 2 : 5
        let cells = emoji.map { Optional($0) } + [nil]
        let rows = stride(from: 0, to: cells.count, by: perRow).map {
            Array(cells[$0..<min($0 + perRow, cells.count)])
        }
        return WidgetSurface {
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(rows[row].indices, id: \.self) { index in
                            cell(rows[row][index])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: String?) -> some View {
        if let item {
            Button {
                guard !context.isPreview else { return }
                ColorSampling.copy(item)
                copied = item
            } label: {
                Text(item)
                    .font(.system(size: 17))
                    .frame(width: 26, height: 24)
                    .background(WidgetStyle.primary.opacity(copied == item ? 0.16 : 0),
                                in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("拷贝 \(item)"))
        } else {
            Button {
                guard !context.isPreview else { return }
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("表情与符号")
        }
    }
}
