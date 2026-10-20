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
///
/// 轮到哪张由 `PhotoRotation` 从时钟和面板写下的锚点算（面板的上一张、暂停、
/// 下一张、排除都写在配置里），卡片和面板永远是同一张。可以有多个文件夹；
/// “那年今天优先”开着时往年今天的照片排在最前面。
struct PhotoFrameTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var isWide: Bool { instance.config.string("layout", default: "standard") == "wide" }
    private var album: PhotoAlbum { PhotoAlbum(config: instance.config, wide: isWide) }
    private var memories: PhotoMemories { PhotoMemories.shared }

    var body: some View {
        WidgetSurface {
            frame.bleedingThroughSurfaceInset()
        }
        .onAppear {
            guard !context.isPreview else { return }
            album.start(now: context.now)
        }
        .onChange(of: album.activeFolders) { _, _ in if !context.isPreview { album.start(now: context.now) } }
        // 过了零点换一批“那年今天”。
        .onChange(of: PhotoMemory.dateText(context.now)) { _, _ in
            if !context.isPreview { album.start(now: context.now) }
        }
        .onChange(of: isWide) { _, _ in
            if !context.isPreview { album.start(now: context.now) }
        }
        .onChange(of: album.memoriesFirst) { _, _ in
            if !context.isPreview { album.start(now: context.now) }
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
        } else {
            let current = self.album
            let order = current.order()
            let lookup = current.lookup
            let position = PhotoRotation.position(at: context.now, order: order, state: current.state,
                                                  interval: current.interval)
            if let position, let item = lookup[order[position]] {
                ZStack {
                    AlbumThumb(item: item, pixels: 520)
                        .id(item.id)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.9), value: item.id)
                .background { warmNext(order: order, lookup: lookup, album: current) }
                .overlay(alignment: .bottomLeading) {
                    if isWide { itemCaption(item, index: position, count: order.count) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(item))
            } else {
                empty(current)
            }
        }
    }

    private func label(_ item: PhotoAlbum.Item) -> String {
        switch item {
        case .file(let file): tr("相册：\(file.name)")
        case .memory(let memory): tr("那年今天：\(PhotoMemory.caption(date: memory.date, place: nil))")
        }
    }

    // MARK: 宽幅：日期和地点

    @ViewBuilder
    private func itemCaption(_ item: PhotoAlbum.Item, index: Int, count: Int) -> some View {
        switch item {
        case .memory(let shown):
            let place = memories.place(key: shown.id, latitude: shown.latitude, longitude: shown.longitude)
            caption(headline: PhotoMemory.headline(date: shown.date, today: context.now),
                    line: PhotoMemory.caption(date: shown.date, place: place),
                    index: index, count: count)
        case .file(let file):
            if let meta = memories.meta(for: file.url), let date = meta.date {
                let place = memories.place(key: file.url.path, latitude: meta.latitude, longitude: meta.longitude)
                caption(headline: PhotoMemory.headline(date: date, today: context.now),
                        line: PhotoMemory.caption(date: date, place: place),
                        index: index, count: count)
            }
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

    /// Asks for the next picture a slot early, so the crossfade never fades
    /// into an icon while it is still being made.
    @ViewBuilder
    private func warmNext(order: [String], lookup: [String: PhotoAlbum.Item], album: PhotoAlbum) -> some View {
        let _ = prefetchNext(order: order, lookup: lookup, album: album)
        Color.clear
    }

    private func prefetchNext(order: [String], lookup: [String: PhotoAlbum.Item], album: PhotoAlbum) {
        guard order.count > 1, !album.state.isPaused,
              let next = PhotoRotation.upcoming(at: context.now, order: order, state: album.state,
                                                interval: album.interval, count: 1).first,
              let item = lookup[next] else { return }
        switch item {
        case .file(let file): _ = Thumbnails.shared.image(for: file.url, pixels: 520)
        case .memory(let memory): _ = memories.image(for: memory)
        }
    }

    @ViewBuilder
    private func empty(_ album: PhotoAlbum) -> some View {
        if album.activeFolders.isEmpty && album.memories.isEmpty {
            PandaEmptyTile(empty: .photos, title: tr("选择相册"), instance: instance, context: context)
        } else if album.failure != nil || album.loading {
            FeedStatusTile(symbol: "photo.on.rectangle.angled", failed: album.failure != nil, context: context)
        } else {
            PandaEmptyTile(empty: .photos, title: tr("选择相册"), instance: instance, context: context)
        }
    }
}
