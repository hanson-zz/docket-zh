import AppKit
import SwiftUI

/// A row of links, each a lettered disc; a click opens it in the default
/// browser.
///
/// No favicons on the shelf: drawing one means a picture per link on every
/// redraw. A letter on a colour from the host tells them apart just as well.
/// Each page's title and summary are read once, when the link is first seen
/// (see `LinkPreview`), kept in the widget's config, and shown in the disc's
/// tooltip and in the panel; a link without a title of its own takes its
/// letter from the page's title.
struct BookmarksTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var links: [Bookmark] {
        Array(Bookmark.list(instance.config.strings("links")).prefix(8))
    }

    private var previews: [String: LinkPreview] { LinkPreview.stored(instance.config) }

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
                VStack(spacing: 3) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text("在设置中添加网址")
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else if column {
                LazyVGrid(columns: [GridItem(.fixed(30), spacing: 4), GridItem(.fixed(30), spacing: 4)],
                          spacing: 4) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in disc(link) }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in disc(link) }
                }
            }
        }
        .task(id: pending) {
            let urls = pending
            guard !urls.isEmpty else { return }
            let fetched = await LinkPreviewFetcher.fetch(urls)
            guard !Task.isCancelled, !fetched.isEmpty else { return }
            BookmarkPreviews.save(fetched, in: instance)
        }
    }

    private func disc(_ link: Bookmark) -> some View {
        let preview = previews[link.url.absoluteString]
        let title = link.displayTitle(preview)
        let summary = preview?.hasContent == true ? preview?.summary : nil
        return Button {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        } label: {
            BookmarkBadge(link: Bookmark(title: title, url: link.url), size: 30)
        }
        .buttonStyle(.plain)
        .help([title, summary, link.url.absoluteString].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel("打开 \(title)")
    }
}

/// Writes fetched previews back into a bookmarks widget's config.
@MainActor
enum BookmarkPreviews {
    static func save(_ fetched: [LinkPreview], in instance: WidgetInstance) {
        WidgetWriter.write(instance) { LinkPreview.store(fetched, in: &$0) }
    }
}

/// A link's letter on its colour.
struct BookmarkBadge: View {
    var link: Bookmark
    var size: CGFloat

    private static let palette: [PaletteColor] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo]

    var body: some View {
        let colour = WidgetStyle.tint(Self.palette[link.paletteIndex(count: Self.palette.count)])
        Text(link.initial)
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(colour.gradient))
            .contentShape(Circle())
    }
}
