import AppKit
import SwiftUI

/// Every picture in the wallpaper folder; a click makes it the desktop.
struct WallpaperDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var folderPath: String { instance.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var wallpaper: WallpaperService { WallpaperService.shared }
    private var allScreens: Bool { instance.config.bool("allScreens", default: true) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.teal))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "photo.on.rectangle", title: tr("壁纸"), subtitle: subtitle)
                content
                HStack(spacing: 6) {
                    ForEach(WallpaperCycle.Step.allCases, id: \.self) { step in
                        PanelButton(title: WallpaperTile.title(step),
                                    symbol: WallpaperTile.symbol(step),
                                    prominent: step == .next) {
                            guard !context.isPreview else { return }
                            wallpaper.step(step, in: feed.files.map(\.url), allScreens: allScreens)
                        }
                    }
                }
                HStack(spacing: 6) {
                    PanelButton(title: tr("选择文件夹…"), symbol: "folder", action: choose)
                    PanelButton(title: tr("在访达中打开"), symbol: nil) {
                        guard !context.isPreview else { return }
                        FileActions.openFolder(feed.folder)
                    }
                }
                if let error = wallpaper.lastError {
                    Text(error)
                        .font(WidgetStyle.caption(11))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            wallpaper.start()
            feed.start()
            feed.refresh(force: true)
        }
    }

    private var subtitle: String {
        if context.isPreview { return tr("图片 · 6 张") }
        let name = feed.folder.lastPathComponent
        guard feed.loadedAt != nil else { return tr("\(name) · 正在读取") }
        return tr("\(name) · \(feed.files.count) 张 · \(allScreens ? tr("所有显示器") : tr("主显示器"))")
    }

    @ViewBuilder
    private var content: some View {
        if context.isPreview {
            SamplePicture(symbol: "photo.fill").frame(height: 200).clipShape(.rect(cornerRadius: 10))
        } else if let error = feed.error {
            PanelNote(symbol: "lock", text: error).frame(height: 200)
        } else if feed.files.isEmpty {
            PanelNote(symbol: "photo",
                      text: feed.loadedAt == nil ? tr("正在读取…") : tr("这个文件夹里没有图片。点按“选择文件夹…”换一个。"))
                .frame(height: 200)
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                          spacing: 6) {
                    ForEach(feed.files) { file in
                        FileThumb(url: file.url, pixels: 240)
                            .aspectRatio(1.5, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 7, style: .continuous))
                            .overlay {
                                if isCurrent(file.url) {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(.white, lineWidth: 2)
                                }
                            }
                            .contentShape(.rect(cornerRadius: 7))
                            .onTapGesture { wallpaper.set(file.url, allScreens: allScreens) }
                            .help(tr("设为壁纸：\(file.name)"))
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 200)
        }
    }

    private func isCurrent(_ url: URL) -> Bool {
        wallpaper.current?.standardizedFileURL == url.standardizedFileURL
    }

    private func choose() {
        guard !context.isPreview else { return }
        let item = instance
        guard let url = FileActions.chooseFolder(title: tr("选择壁纸所在的文件夹"), startingAt: feed.folder) else { return }
        WidgetWriter.write(item) { $0.set("folder", .string(url.path)) }
    }
}
