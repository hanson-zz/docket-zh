import SwiftUI

/// A picture frame: the pictures in a folder, one at a time, edge to edge.
///
/// The slideshow is a function of the clock rather than a timer of its own.
/// `context.now` already ticks once a second for every tile, so which picture
/// shows is simply which slot of `interval` seconds it is, and the change is
/// a crossfade between two thumbnails that are both already in memory.
struct PhotoFrameTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var folderPath: String { instance.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var interval: Double { max(5, instance.config.double("interval", default: 30)) }
    private var shuffle: Bool { instance.config.bool("shuffle") }

    var body: some View {
        WidgetSurface {
            frame.bleedingThroughSurfaceInset()
        }
        .onAppear { if !context.isPreview { feed.start() } }
        .onChange(of: folderPath) { _, _ in if !context.isPreview { feed.start() } }
    }

    @ViewBuilder
    private var frame: some View {
        if context.isPreview {
            SamplePicture()
        } else if let current {
            ZStack {
                FileThumb(url: current.url, pixels: 520)
                    .id(current.url)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.9), value: current.url)
            .background { warmNext }
            .accessibilityLabel(tr("相册：\(current.name)"))
        } else {
            empty
        }
    }

    private var files: [ListedFile] { feed.files }

    private var position: Int {
        Slideshow.index(at: context.now, interval: interval, count: files.count, shuffle: shuffle)
    }

    private var current: ListedFile? {
        files.isEmpty ? nil : files[min(position, files.count - 1)]
    }

    /// Asks for the next picture a slot early, so the crossfade never fades
    /// into an icon while it is still being made.
    @ViewBuilder
    private var warmNext: some View {
        if files.count > 1 {
            let next = Slideshow.index(at: context.now.addingTimeInterval(interval),
                                       interval: interval, count: files.count, shuffle: shuffle)
            let _ = Thumbnails.shared.image(for: files[min(next, files.count - 1)].url, pixels: 520)
        }
        Color.clear
    }

    private var empty: some View {
        let column = context.position.isVertical
        let message = feed.error != nil ? tr("无法访问") : feed.loadedAt == nil ? tr("正在读取") : tr("没有图片")
        return VStack(spacing: 4) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: column ? 15 : 16, weight: .medium))
                .foregroundStyle(WidgetStyle.secondary)
            Text(message)
                .font(WidgetStyle.note)
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
