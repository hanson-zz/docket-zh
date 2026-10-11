import AppKit
import SwiftUI

/// The top of the Downloads folder, newest first. Click opens, drag carries
/// the file out, a secondary click reveals it or bins it.
struct DownloadsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var feed: FolderFeed { FolderFeed.shared(.downloads) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.blue))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "arrow.down.circle", title: "下载",
                            subtitle: context.isPreview ? "下载" : "\(feed.files.count) 个最近项目")
                if context.isPreview {
                    PanelNote(symbol: "arrow.down.circle", text: "最近下载的文件会显示在这里。")
                        .frame(height: 236)
                } else if let error = feed.error {
                    PanelNote(symbol: "lock", text: error).frame(height: 236)
                } else if feed.files.isEmpty {
                    PanelNote(symbol: "tray", text: feed.loadedAt == nil ? "正在读取…" : "“下载”文件夹是空的。")
                        .frame(height: 236)
                } else {
                    FileRows(files: feed.files, now: context.now, onTrash: { feed.trash($0) })
                }
                PanelButton(title: "打开“下载”文件夹", symbol: "folder", prominent: true) {
                    guard !context.isPreview else { return }
                    FileActions.openFolder(feed.folder)
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
        }
    }
}
