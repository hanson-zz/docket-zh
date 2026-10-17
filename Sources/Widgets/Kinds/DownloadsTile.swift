import SwiftUI

/// The newest thing in Downloads: its picture, its name and how long ago.
struct DownloadsTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var feed: FolderFeed { FolderFeed.shared(.downloads) }
    private var latest: ListedFile? { context.isPreview ? nil : feed.files.first }
    /// 正在下载时卡片显示它，图标上画进度。
    private var active: ActiveDownload? { context.isPreview ? nil : feed.downloading.first }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: WidgetStyle.columnSpacing) {
                    badge(size: WidgetStyle.badgeColumn)
                    Text(title)
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    TileReading(value: title, caption: caption, valueSize: 14)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { if !context.isPreview { feed.start() } }
    }

    /// 读完了、没出错、也没有文件。
    private var isEmpty: Bool {
        !context.isPreview && active == nil && latest == nil && feed.loadedAt != nil && feed.error == nil
    }

    private var title: String {
        if context.isPreview { return tr("发票.pdf") }
        if let active { return active.finalName }
        if let latest { return latest.name }
        return feed.error != nil ? tr("无法访问") : tr("下载")
    }

    private var caption: String {
        if context.isPreview { return tr("下载 · 刚刚") }
        if let active { return DownloadProgress.tileCaption(active.fraction) }
        guard let latest else { return feed.loadedAt == nil ? tr("正在读取") : PandaEmpty.downloads.line() }
        return tr("下载 · \(RelativeAge.caption(latest.date, now: context.now))")
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            if let active {
                DownloadProgressIcon(download: active, size: size * 0.86)
            } else if let latest {
                FileThumb(url: latest.url, pixels: 120, fill: latest.isImage)
                    .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
                    .padding(latest.isImage ? 0 : 2)
            } else if isEmpty {
                // 下载文件夹空着：小熊猫歇着。
                PandaEmptyBadge(empty: .downloads, size: size, fallback: "arrow.down.circle")
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: size * CGFloat(DockMetrics.badgeGlyphRatio), weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            }
        }
    }
}
