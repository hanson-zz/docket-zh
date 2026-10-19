import AppKit
import SwiftUI

/// Every picture the frame is cycling through, and where they come from.
///
/// A click opens the picture in its default app (Preview, for most people),
/// a drag carries the file out, and the folder is changed here rather than
/// typed into Settings, because nobody remembers a path.
struct PhotoFrameDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var folderPath: String { instance.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.pink))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "photo.on.rectangle.angled",
                            title: tr("相册"),
                            subtitle: subtitle)
                content
                if instance.config.string("layout", default: "standard") == "wide" { memoriesNote }
                HStack(spacing: 8) {
                    PanelButton(title: tr("选择文件夹…"), symbol: "folder", prominent: true, action: choose)
                    PanelButton(title: tr("在访达中打开"), symbol: nil) {
                        guard !context.isPreview else { return }
                        FileActions.openFolder(feed.folder)
                    }
                }
                if !folderPath.isEmpty {
                    Button("改回“图片”文件夹") {
                        WidgetWriter.write(instance) { $0.set("folder", .string("")) }
                    }
                    .buttonStyle(.plain)
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
        }
    }

    private var subtitle: String {
        let name = feed.folder.lastPathComponent
        if context.isPreview { return tr("图片") }
        guard feed.loadedAt != nil else { return tr("\(name) · 正在读取") }
        return tr("\(name) · \(feed.files.count) 张图片")
    }

    @ViewBuilder
    private var content: some View {
        if context.isPreview {
            SamplePicture().frame(height: 236).clipShape(.rect(cornerRadius: 10))
        } else if let error = feed.error {
            PanelNote(symbol: "lock", text: error).frame(height: 236)
        } else if feed.files.isEmpty {
            PandaEmptyState(empty: .photos, title: tr("选择相册"), panel: true, action: choose)
                .frame(height: 236)
        } else {
            FileGrid(files: feed.files)
        }
    }

    /// 宽幅卡片的“那年今天”从照片图库来，这里说清楚现在是哪种情况。
    @ViewBuilder
    private var memoriesNote: some View {
        let memories = PhotoMemories.shared
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
            if context.isPreview || memories.access == .granted {
                Text(memories.memories.isEmpty && !context.isPreview
                     ? tr("那年今天：照片图库里今天没有往年的照片，先轮播这个文件夹")
                     : tr("那年今天：宽幅卡片在轮播照片图库里往年今天拍的照片"))
            } else {
                Text(tr("那年今天要读取照片图库"))
                Button(tr("打开隐私设置")) { memories.openPrivacySettings() }
                    .buttonStyle(.plain)
                    .underline()
            }
        }
        .font(WidgetStyle.caption(11))
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(2)
    }

    private func choose() {
        guard !context.isPreview else { return }
        let start = feed.folder
        let item = instance
        // The panel closes on the click that lands in the open panel; the
        // choice is written back to the widget either way.
        guard let url = FileActions.chooseFolder(title: tr("选择相册要轮播的文件夹"), startingAt: start) else { return }
        WidgetWriter.write(item) { $0.set("folder", .string(url.path)) }
    }
}
