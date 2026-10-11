import SwiftUI

/// A search field on the shelf: the web, or the files on this Mac.
///
/// The card is drawn as a field but is not one. Typing happens in its panel,
/// which opens focused on the click, for the same reason the sticky note is
/// written in its panel: a caret on the card would swallow the click that
/// opens it, and the shelf cannot take the keyboard.
struct SearchTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var files: Bool { instance.config.string("layout", default: "web") == "files" }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 6) {
                    TileBadge(size: 32) {
                        Image(systemName: files ? "folder" : "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WidgetStyle.primary)
                    }
                    Text(files ? "查找文件" : "搜索")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: files ? "folder" : "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text(files ? "查找文件…" : "搜索网页…")
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetStyle.primary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(WidgetStyle.primary.opacity(0.13)))
                }
            }
        }
    }
}
