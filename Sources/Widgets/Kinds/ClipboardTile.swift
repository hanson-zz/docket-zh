import SwiftUI

/// The last thing copied, and how many before it are a click away.
///
/// Placing this widget is what starts the history: nothing watches the
/// pasteboard on a shelf that does not have one.
struct ClipboardTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var history: ClipboardHistory { ClipboardHistory.shared }
    private var latest: ClipboardHistory.Entry? { context.isPreview ? nil : history.entries.first }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: WidgetStyle.columnSpacing) {
                    badge(size: WidgetStyle.badgeColumn)
                    Text(context.isPreview ? "8 条" : "\(history.entries.count) 条")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    TileReading(value: value, caption: caption, valueSize: 14)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { if !context.isPreview { history.start() } }
    }

    private var value: String {
        if context.isPreview { return "明天上午十点开会" }
        return latest?.preview ?? PandaEmpty.clipboard.line()
    }

    private var caption: String {
        let count = context.isPreview ? 8 : history.entries.count
        let starred = context.isPreview ? 3 : ClipboardPins.pins(instance.config).count
        var text = count == 0 ? "剪贴板" : "剪贴板 · \(count) 条"
        if starred > 0 { text += " · \(starred) 星标" }
        return text
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            if case .image(let image, _, _)? = latest?.content {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.26, style: .continuous))
            } else if !context.isPreview, history.entries.isEmpty {
                // 还没拷贝过：小熊猫打个盹。
                PandaEmptyBadge(empty: .clipboard, size: size, fallback: "list.clipboard")
            } else {
                Image(systemName: "list.clipboard")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            }
        }
    }
}
