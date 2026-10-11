import AppKit
import SwiftUI

/// A row of links, each a lettered disc; a click opens it in the default
/// browser.
///
/// No favicons: fetching one means asking every site for a picture whenever
/// the shelf draws, which is a network request per link that nobody asked
/// for. A letter on a colour from the host tells them apart just as well.
struct BookmarksTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var links: [Bookmark] {
        Array(Bookmark.list(instance.config.strings("links")).prefix(8))
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
    }

    private func disc(_ link: Bookmark) -> some View {
        Button {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        } label: {
            BookmarkBadge(link: link, size: 30)
        }
        .buttonStyle(.plain)
        .help("\(link.title)\n\(link.url.absoluteString)")
        .accessibilityLabel("打开 \(link.title)")
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
