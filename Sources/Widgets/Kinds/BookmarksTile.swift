import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        Array(Bookmark.list(instance.config.strings("links")).prefix(Bookmark.tileLimit))
    }

    private var previews: [String: LinkPreview] { LinkPreview.stored(instance.config) }

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
