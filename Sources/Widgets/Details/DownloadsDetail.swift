import AppKit
import SwiftUI

/// 「下载」面板，照第二批效果图：
/// - 浏览：搜索文件名，按图片/文档/安装包/压缩包筛；正在下载的一张张卡片写进度和
///   还剩多久，右边的叉取消（再点一次确认）；下面按今天、昨天、更早分组，点开、
///   拖出去用，悬停出「在访达中显示」和「删除」，右键还能拷贝、重命名。
/// - 多选：右上「多选」进入，点行勾选、双击名字改名，底下批量移到、压缩、删除
///   （共用 `FileSelectList`，和「最近截图」一样）。
/// 删除都进废纸篓。
struct DownloadsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var feed: FolderFeed { FolderFeed.shared(.downloads) }

    @State private var selecting = false
    @State private var query = ""
    @State private var kind: DownloadKind = .all
    @State private var selection = MultiSelection<URL>()
    @State private var renaming: URL?
    /// 点了一次叉、等确认取消的那个下载。
    @State private var confirmCancel: URL?
    @State private var cancelling: Set<URL> = []

    private var palette: FilePanelPalette {
        FilePanelPalette(accent: panelTint.accent(or: Color(hex: "#62CBD9")),
                         ink: panelTint.ink(or: Color(hex: "#032227")))
    }

    private var shown: [ListedFile] {
        FileQuery.filter(feed.files, query: query).filter { kind.matches($0) }
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.teal))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                if context.isPreview {
                    PanelNote(symbol: "arrow.down.circle", text: tr("最近下载的文件会显示在这里。"))
                        .frame(height: 200)
                } else if let error = feed.error {
                    FeedErrorNote(text: error, denied: feed.accessDenied).frame(height: 220)
                } else if feed.loadedAt == nil, feed.files.isEmpty {
                    PanelNote(symbol: "hourglass", text: tr("正在读取…")).frame(height: 200)
                } else {
                    FileSearchField(text: $query, prompt: tr("搜索文件名"), palette: palette)
                    FileFilterChips(items: DownloadKind.allCases, title: \.title, selected: $kind, palette: palette)
                    if selecting {
                        FileSelectList(files: shown, selection: $selection, renaming: $renaming, feed: feed,
                                       icon: .badge, palette: palette, now: context.now,
                                       emptyText: tr("没有符合的文件"))
                    } else {
                        browse
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: feed.downloading.map(\.id))
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
        }
        .task(id: confirmCancel) {
            // 确认取消的叉 4 秒没点就收回去。
            guard confirmCancel != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            confirmCancel = nil
        }
    }

    private var header: some View {
        let subtitle: String
        if selecting {
            subtitle = tr("点行勾选 · 双击名字改名")
        } else if context.isPreview {
            subtitle = tr("下载")
        } else {
            let size = FileActions.size(feed.totalBytes) ?? ""
            subtitle = feed.totalBytes > 0 ? tr("\(feed.totalCount) 个项目 · \(size)") : tr("\(feed.totalCount) 个项目")
        }
        let canSelect = !context.isPreview && feed.error == nil && !feed.files.isEmpty
        return FilePanelHeader(
            title: selecting ? tr("已选 \(selection.ordered(shown.map(\.url)).count) 个") : tr("下载"),
            subtitle: subtitle,
            button: selecting ? tr("完成") : (canSelect ? tr("多选") : nil),
            prominent: selecting,
            palette: palette
        ) {
            withAnimation(.snappy(duration: 0.25)) {
                selecting.toggle()
                selection.clear()
                renaming = nil
            }
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private var browse: some View {
        if !feed.downloading.isEmpty {
            VStack(spacing: 6) {
                ForEach(feed.downloading.prefix(3)) { download in downloadingCard(download) }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
        if feed.files.isEmpty {
            if feed.downloading.isEmpty {
                PandaEmptyState(empty: .downloads, title: tr("打开“下载”文件夹"), panel: true) {
                    FileActions.openFolder(feed.folder)
                }
                .frame(height: 180)
            }
        } else if shown.isEmpty {
            Text(verbatim: tr("没有符合的文件"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            sections
        }
        openFolderButton
    }

    private func downloadingCard(_ download: ActiveDownload) -> some View {
        let asking = confirmCancel == download.id
        let busy = cancelling.contains(download.id)
        return HStack(spacing: 10) {
            DownloadProgressIcon(download: download, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: download.finalName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressTrack(fraction: download.fraction, accent: palette.accent)
                Text(verbatim: busy ? tr("正在取消…") : feed.progressLine(download, now: context.now))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if asking { cancel(download) } else { confirmCancel = download.id }
            } label: {
                Group {
                    if asking {
                        Text(verbatim: tr("取消下载"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FilePanelPalette.red)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(.panelFill))
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.panelFill))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .help(asking ? tr("再点一次取消这个下载") : tr("取消下载"))
            .accessibilityLabel(tr("取消下载"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassPane(cornerRadius: 12)
    }

    private func cancel(_ download: ActiveDownload) {
        confirmCancel = nil
        cancelling.insert(download.id)
        let url = download.id
        Task {
            let ok = await FileBatch.cancelDownload(url)
            cancelling.remove(url)
            if !ok { NSSound.beep() }
            feed.forget([url])
        }
    }

    private var sections: some View {
        let groups = FileDayGroup.sections(shown, now: context.now)
        let count = shown.count + groups.count
        // 一屏大约 6 行，再多就在里面滚。
        let height = min(CGFloat(count) * 46, 330)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    Text(verbatim: group.group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .padding(.top, group.group == groups.first?.group ? 0 : 6)
                    ForEach(group.files) { file in
                        DownloadRow(file: file, now: context.now,
                                    onTrash: { trash(file) },
                                    onRename: { startRename(file) })
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: max(120, height))
    }

    private var openFolderButton: some View {
        Button {
            guard !context.isPreview else { return }
            FileActions.openFolder(feed.folder)
        } label: {
            Text(verbatim: tr("打开“下载”文件夹"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func trash(_ file: ListedFile) {
        let outcome = FileBatch.trash([file.url])
        feed.forget(Set(outcome.done))
    }

    /// 右键「重命名」：进多选，直接在那一行改。
    private func startRename(_ file: ListedFile) {
        withAnimation(.snappy(duration: 0.25)) {
            selecting = true
            selection.clear()
            renaming = file.url
        }
    }
}

/// 正在下载那张卡上的细进度条；不知道进度时一段光来回走。
private struct ProgressTrack: View {
    var fraction: Double?
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.panelTrack)
                if let fraction {
                    Capsule().fill(accent)
                        .frame(width: max(5, proxy.size.width * min(max(fraction, 0), 1)))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: fraction)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tick in
                        let phase = reduceMotion ? 0.35
                            : tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        Capsule().fill(accent.opacity(0.85))
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: proxy.size.width * (phase * 1.3 - 0.3))
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 5)
    }
}

/// 浏览态的一行：类型小标、名字、大小和时间；悬停出两个圆钮。
private struct DownloadRow: View {
    var file: ListedFile
    var now: Date
    var onTrash: () -> Void
    var onRename: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            FileTypeBadgeView(file: file)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: FileRowCaption.text(file, now: now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovered {
                circleButton("folder", help: tr("在访达中显示")) { FileActions.reveal([file.url]) }
                circleButton("trash", help: tr("移到废纸篓"), action: onTrash)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovered ? Color.panelSelected : Color.panelFill)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.panelStroke, lineWidth: 0.6))
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { hovered = $0 }
        .onTapGesture { FileActions.open(file.url) }
        .onDrag { FileActions.dragProvider(file.url) }
        .contextMenu {
            Button(tr("打开")) { FileActions.open(file.url) }
            Button(tr("在访达中显示")) { FileActions.reveal([file.url]) }
            Divider()
            if file.isImage {
                Button(tr("拷贝图像")) { FileActions.copyImage(file.url) }
            }
            Button(tr("拷贝文件")) { FileActions.copyFile(file.url) }
            Button(tr("重命名"), action: onRename)
            Divider()
            Button(tr("移到废纸篓"), action: onTrash)
        }
        .help(file.name)
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
