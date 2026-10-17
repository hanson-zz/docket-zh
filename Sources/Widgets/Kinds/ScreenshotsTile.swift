import SwiftUI

/// The newest screenshot, as large as the card allows.
///
/// The picture is the card, the way a cover is Now Playing's card, with its
/// age along the bottom on a gradient so it reads on any capture. Dragging
/// and copying live in the panel: the card's own drag belongs to the shelf,
/// which is how a tile is moved.
struct ScreenshotsTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }

    private var latest: ListedFile? { context.isPreview ? nil : feed.files.first }

    var body: some View {
        WidgetSurface {
            Group {
                if context.isPreview {
                    picture(SamplePicture(symbol: "macwindow"), caption: tr("2 分钟前"))
                } else if let latest {
                    picture(FileThumb(url: latest.url, pixels: 480).id(latest.url),
                            caption: RelativeAge.caption(latest.date, now: context.now))
                        .accessibilityLabel(tr("最近截图：\(latest.name)"))
                } else {
                    empty
                }
            }
            .bleedingThroughSurfaceInset()
        }
        .onAppear { if !context.isPreview { feed.start() } }
    }

    private func picture(_ image: some View, caption: String) -> some View {
        let column = context.position.isVertical
        return image
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                    if !column {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
    }

    private var empty: some View {
        let column = context.position.isVertical
        return VStack(spacing: 4) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: column ? 15 : 16, weight: .medium))
                .foregroundStyle(WidgetStyle.secondary)
            Text(feed.error != nil ? tr("无法访问") : tr("没有截图"))
                .font(WidgetStyle.note)
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
