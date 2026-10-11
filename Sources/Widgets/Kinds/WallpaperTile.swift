import SwiftUI

/// The desktop picture, with a step back, a shuffle and a step forward.
///
/// The picture is the card, as on the photo frame, and the three controls
/// sit over it on discs. The card itself opens the panel, where any picture
/// in the folder can be chosen directly.
struct WallpaperTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var folderPath: String { instance.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var wallpaper: WallpaperService { WallpaperService.shared }
    private var allScreens: Bool { instance.config.bool("allScreens", default: true) }

    var body: some View {
        WidgetSurface {
            picture
                .overlay(alignment: context.position.isVertical ? Alignment.bottom : Alignment.trailing) { controls }
                .bleedingThroughSurfaceInset()
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            wallpaper.start()
        }
        .onChange(of: folderPath) { _, _ in if !context.isPreview { feed.start() } }
    }

    @ViewBuilder
    private var picture: some View {
        if context.isPreview {
            SamplePicture(symbol: "photo.fill")
        } else if let url = wallpaper.current {
            FileThumb(url: url, pixels: 480)
                .id(url)
                .accessibilityLabel("当前壁纸：\(url.lastPathComponent)")
        } else {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WidgetStyle.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        let column = context.position.isVertical
        let layout = column ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            if column {
                glyph(.previous)
                glyph(.random)
                glyph(.next)
            } else {
                HStack(spacing: 3) {
                    glyph(.previous)
                    glyph(.next)
                }
                glyph(.random)
            }
        }
        .padding(column ? 4 : 5)
        // White on whatever the picture is, with enough shade behind it.
        .environment(\.colorScheme, .dark)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.45)],
                           startPoint: column ? .top : .leading,
                           endPoint: column ? .bottom : .trailing)
        }
    }

    private func glyph(_ step: WallpaperCycle.Step) -> some View {
        TileGlyph(symbol: Self.symbol(step), size: 9, tint: .white,
                  action: context.isPreview || feed.files.isEmpty ? nil : {
                      wallpaper.step(step, in: feed.files.map(\.url), allScreens: allScreens)
                  })
            .help(Self.title(step))
            .accessibilityLabel(Self.title(step))
    }

    static func symbol(_ step: WallpaperCycle.Step) -> String {
        switch step {
        case .previous: "chevron.left"
        case .next: "chevron.right"
        case .random: "shuffle"
        }
    }

    static func title(_ step: WallpaperCycle.Step) -> String {
        switch step {
        case .previous: "上一张"
        case .next: "下一张"
        case .random: "随机"
        }
    }
}
