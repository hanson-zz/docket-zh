import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A row of links, each a disc; a click opens it in the default browser.
///
/// 每个圆画书签自己选的图标（文字图标、上传的图片，见 `BookmarkIcons`）；没选过
/// 时有本地缓存的网站图标就画图标，没有就是原来的首字色块。图片都是
/// `BookmarkIconStore` 内存里的 `NSImage`，重画不联网、不读盘：第一次见到某个
/// 网站时读一次缓存文件，没有才联网取一次（网页预览读到之后，先试页面自己写的
/// icon），取到的缩小存盘，下次启动直接用。
/// Each page's title and summary are read once, when the link is first seen
/// (see `LinkPreview`), kept in the widget's config, and shown in the disc's
/// tooltip and in the panel; a link without a title of its own takes its
/// letter from the page's title.
struct BookmarksTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var links: [Bookmark] {
        Array(Bookmark.list(instance.config.strings("links")).prefix(Bookmark.tileLimit))
    }

    private var previews: [String: LinkPreview] { LinkPreview.stored(instance.config) }
    private var icons: [String: BookmarkIcon] { BookmarkIcons.stored(instance.config) }

    /// 拖着链接停在卡片上。
    @State private var targeted = false

    /// Every web link in the list with no preview yet, or whose last attempt
    /// failed long enough ago. The fetch below re-runs when this changes.
    private var pending: [URL] {
        guard !context.isPreview else { return [] }
        let stored = previews
        var seen = Set<String>()
        return Bookmark.list(instance.config.strings("links")).map(\.url).filter { url in
            seen.insert(url.absoluteString).inserted
                && LinkPreview.needsFetch(url, stored: stored[url.absoluteString], now: context.now)
        }
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if links.isEmpty {
                PandaEmptyTile(empty: .bookmarks, title: tr("添加书签"), instance: instance, context: context)
            } else if column {
                let stored = previews, chosen = icons
                LazyVGrid(columns: [GridItem(.fixed(30), spacing: 4), GridItem(.fixed(30), spacing: 4)],
                          spacing: 4) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in disc(link, stored, chosen) }
                }
            } else {
                let stored = previews, chosen = icons
                HStack(spacing: 6) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in disc(link, stored, chosen) }
                }
            }
        }
        // 拖链接过来：青色虚线框写“加一条书签”，松手加在最后，标题由链接预览取。
        .dropTargetOutline(targeted, prompt: .bookmark, compact: column)
        .onDrop(of: [.url, .plainText], delegate: ContentDropDelegate(
            types: [.url, .plainText],
            enabled: !context.isPreview,
            targeted: { targeted = $0 },
            receive: { things in
                withAnimation(.snappy(duration: 0.3)) { BookmarkDrop.add(things, to: instance) }
            }))
        .task(id: pending) {
            let urls = pending
            guard !urls.isEmpty else { return }
            let fetched = await LinkPreviewFetcher.fetch(urls)
            guard !Task.isCancelled, !fetched.isEmpty else { return }
            BookmarkPreviews.save(fetched, in: instance)
        }
    }

    private func disc(_ link: Bookmark, _ previews: [String: LinkPreview],
                      _ icons: [String: BookmarkIcon]) -> some View {
        let preview = previews[link.url.absoluteString]
        let title = link.displayTitle(preview)
        let summary = preview?.hasContent == true ? preview?.summary : nil
        return Button {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        } label: {
            BookmarkBadge(link: Bookmark(title: title, url: link.url), size: 30,
                          icon: BookmarkIcons.icon(for: link.url, in: icons), pageIcon: preview?.icon,
                          autoFetch: !context.isPreview && !LinkPreview.needsFetch(link.url, stored: preview))
        }
        .buttonStyle(.plain)
        .help([title, summary, link.url.absoluteString].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel(tr("打开 \(title)"))
    }
}

/// Writes fetched previews back into a bookmarks widget's config.
@MainActor
enum BookmarkPreviews {
    static func save(_ fetched: [LinkPreview], in instance: WidgetInstance) {
        WidgetWriter.write(instance) { LinkPreview.store(fetched, in: &$0) }
    }
}

/// 卡片上的一个圆：书签选的图标、缓存的网站图标，或者首字色块（见 `BookmarkGlyph`）。
struct BookmarkBadge: View {
    var link: Bookmark
    var size: CGFloat
    var icon: BookmarkIcon? = nil
    var pageIcon: String? = nil
    var autoFetch: Bool = false

    var body: some View {
        BookmarkGlyph(link: link, icon: icon, pageIcon: pageIcon, size: size, round: true, autoFetch: autoFetch)
    }
}
