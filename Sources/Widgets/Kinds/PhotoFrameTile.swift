import SwiftUI

/// A picture frame: the pictures in a folder, one at a time, edge to edge.
///
/// The slideshow is a function of the clock rather than a timer of its own.
/// `context.now` already ticks once a second for every tile, so which picture
/// shows is simply which slot of `interval` seconds it is, and the change is
/// a crossfade between two thumbnails that are both already in memory.
///
/// 相册标准仍是一张纯照片。相册宽幅有自己的重点：照片加“那年今天”和拍摄日期、
/// 地点。照片图库里有往年今天拍的照片时轮播它们（`PhotoMemories`），没有或没给
/// 权限时轮播文件夹，图片自带拍摄日期时同样写在下沿；地点反查不到就只写日期。
struct PhotoFrameTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var folderPath: String { instance.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var interval: Double { max(5, instance.config.double("interval", default: 30)) }
    private var shuffle: Bool { instance.config.bool("shuffle") }
    private var isWide: Bool { instance.config.string("layout", default: "standard") == "wide" }
    private var memories: PhotoMemories { PhotoMemories.shared }

    var body: some View {
        WidgetSurface {
            frame.bleedingThroughSurfaceInset()
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            if isWide { memories.start(now: context.now) }
        }
        .onChange(of: folderPath) { _, _ in if !context.isPreview { feed.start() } }
        // 过了零点换一批“那年今天”。
        .onChange(of: PhotoMemory.dateText(context.now)) { _, _ in
            if !context.isPreview, isWide { memories.start(now: context.now) }
        }
        .onChange(of: isWide) { _, wide in
            if !context.isPreview, wide { memories.start(now: context.now) }
        }
    }

    @ViewBuilder
    private var frame: some View {
        if context.isPreview {
            SamplePicture()
                .overlay(alignment: .bottomLeading) {
                    if isWide {
                        caption(headline: tr("那年今天"), line: tr("2024.10.18 · 杭州"), index: 1, count: 5)
                    }
                }
        } else if isWide, !memories.memories.isEmpty {
            memory
        } else if let current {
            ZStack {
                FileThumb(url: current.url, pixels: 520)
                    .id(current.url)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.9), value: current.url)
            .background { warmNext }
            .overlay(alignment: .bottomLeading) {
                if isWide { fileCaption(current) }
            }
            .accessibilityLabel(tr("相册：\(current.name)"))
        } else {
            empty
        }
    }

    // MARK: 宽幅：那年今天

    @ViewBuilder
    private var memory: some View {
        let list = memories.memories
        let index = Slideshow.index(at: context.now, interval: interval, count: list.count, shuffle: shuffle)
        let shown = list[min(index, list.count - 1)]
        ZStack {
            Group {
                if let image = memories.image(for: shown) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.25)
                }
            }
            .id(shown.id)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.9), value: shown.id)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            let place = memories.place(key: shown.id, latitude: shown.latitude, longitude: shown.longitude)
            caption(headline: PhotoMemory.headline(date: shown.date, today: context.now),
                    line: PhotoMemory.caption(date: shown.date, place: place),
                    index: index, count: list.count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("那年今天：\(PhotoMemory.caption(date: shown.date, place: nil))"))
    }

    @ViewBuilder
    private func fileCaption(_ file: ListedFile) -> some View {
        if let meta = memories.meta(for: file.url), let date = meta.date {
            let place = memories.place(key: file.url.path, latitude: meta.latitude, longitude: meta.longitude)
            caption(headline: PhotoMemory.headline(date: date, today: context.now),
                    line: PhotoMemory.caption(date: date, place: place),
                    index: position, count: files.count)
        }
    }

    /// 照片下沿：一层渐暗，上面“那年今天”，下面“2024.10.18 · 杭州”，右边轮播圆点。
    private func caption(headline: String?, line: String, index: Int, count: Int) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                if let headline {
                    Text(headline)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text(line)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if count > 1 {
                let dots = min(count, PhotoMemory.maxDots)
                let lit = PhotoMemory.dot(index: index, count: count)
                HStack(spacing: 3) {
                    ForEach(0..<dots, id: \.self) { dot in
                        Circle()
                            .fill(.white.opacity(dot == lit ? 1 : 0.4))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .padding(.bottom, 3)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: 文件夹

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

    @ViewBuilder
    private var empty: some View {
        if feed.error != nil || feed.loadedAt == nil {
            FeedStatusTile(symbol: "photo.on.rectangle.angled", failed: feed.error != nil, context: context)
        } else {
            PandaEmptyTile(empty: .photos, title: tr("选择相册"), instance: instance, context: context)
        }
    }
}
