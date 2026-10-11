import AppKit
import SwiftUI

/// Recent screenshots: the newest one large with its four actions, and the
/// rest as a grid that drags straight into a mail, a chat or a folder.
struct ScreenshotsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.blue))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "camera.viewfinder", title: "最近截图",
                            subtitle: context.isPreview ? "桌面" : "保存在“\(feed.folder.lastPathComponent)”")
                if context.isPreview {
                    SamplePicture(symbol: "macwindow").frame(height: 150)
                        .clipShape(.rect(cornerRadius: 10))
                } else if let error = feed.error {
                    PanelNote(symbol: "lock", text: error).frame(height: 236)
                } else if let latest = feed.files.first {
                    hero(latest)
                    if feed.files.count > 1 {
                        FileGrid(files: Array(feed.files.dropFirst()), columns: 4, height: 128,
                                 onTrash: { feed.trash($0) })
                    }
                } else {
                    PanelNote(symbol: "camera.viewfinder",
                              text: feed.loadedAt == nil ? "正在读取…" : "还没有截图。按 ⇧⌘3、⇧⌘4 或 ⇧⌘5 截取屏幕。")
                        .frame(height: 236)
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
        }
    }

    private func hero(_ file: ListedFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FileThumb(url: file.url, pixels: 720, fill: false)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.25))
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .contentShape(.rect(cornerRadius: 10))
                .onTapGesture { FileActions.open(file.url) }
                .onDrag { FileActions.dragProvider(file.url) }
                .contextMenu { FileMenu(file: file, onTrash: { feed.trash($0) }) }
                .help("点按打开，拖移到其他地方即可使用")
            Text("\(file.name) · \(RelativeAge.caption(file.date, now: context.now))")
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                PanelButton(title: "拷贝", symbol: "doc.on.doc", prominent: true) {
                    file.isImage ? FileActions.copyImage(file.url) : FileActions.copyFile(file.url)
                }
                PanelButton(title: "显示", symbol: "folder") { FileActions.reveal([file.url]) }
                PanelButton(title: "删除", symbol: "trash") { feed.trash(file) }
            }
        }
    }
}
