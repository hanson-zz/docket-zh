import AppKit
import SwiftUI

/// Every link with its title and address. A click opens it; a secondary
/// click copies the address.
struct BookmarksDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var links: [Bookmark] { Bookmark.list(instance.config.strings("links")) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.orange))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "bookmark", title: "书签", subtitle: "\(links.count) 个网址 · 用默认浏览器打开")
                if links.isEmpty {
                    PanelNote(symbol: "bookmark", text: "还没有网址。在 设置 ▸ 小组件 中添加，用逗号分隔，例如“必应 cn.bing.com”。")
                        .frame(height: 140)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in row(link) }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(236, CGFloat(links.count) * 46))
                }
                Text("在 设置 ▸ 小组件 中编辑网址：每项可写成“标题 网址”，用逗号分隔。")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ link: Bookmark) -> some View {
        HStack(spacing: 10) {
            BookmarkBadge(link: link, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.title)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(link.url.absoluteString)
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        }
        .contextMenu {
            Button("打开") { NSWorkspace.shared.open(link.url) }
            Button("拷贝网址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            }
        }
    }
}
