import AppKit
import SwiftUI

/// 「最近截图」面板，照第二批效果图：
/// - 浏览：搜索（文件名或日期）、全部/今天/本周/录屏筛选；最新一张大图，下面
///   「拷贝 / 标注 / 删除」；更早的排成网格，拖出去就能用。
/// - 多选：和「下载」共用 `FileSelectList`：勾选、双击改名、批量移到/压缩/删除。
/// - 标注：箭头、框、马赛克、文字，4 种颜色，可撤销；画完拷贝或存为新图，原图不动
///   （`ScreenshotMarkupView`）。
/// 删除都进废纸篓。
struct ScreenshotsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }

    private enum Mode: Equatable {
        case browse, select
        case markup(URL)
    }

    @State private var mode: Mode = .browse
    @State private var query = ""
    @State private var filter: ShotFilter = .all
    @State private var selection = MultiSelection<URL>()
    @State private var renaming: URL?
    @State private var heroSize: CGSize?
    @State private var copied: URL?

    private var palette: FilePanelPalette {
        FilePanelPalette(accent: panelTint.accent(or: Color(hex: "#B9A0FF")),
                         ink: panelTint.ink(or: Color(hex: "#1B0B3D")))
    }

    private var shown: [ListedFile] {
        FileQuery.filter(feed.files, query: query).filter { filter.matches($0, now: context.now) }
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.purple))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .markup(let url):
                    ScreenshotMarkupView(url: url, palette: palette, feed: feed) {
                        withAnimation(.snappy(duration: 0.25)) { mode = .browse }
                    }
                case .browse, .select:
                    header
                    content
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
        }
        .onChange(of: feed.files.map(\.url)) { _, urls in
            // 正在标注的那张被删了或移走了，回到浏览。
            if case .markup(let url) = mode, !urls.contains(url) { mode = .browse }
        }
    }

    private var header: some View {
        let selecting = mode == .select
        let subtitle: String
        if selecting {
            subtitle = tr("点行勾选 · 双击名字改名")
        } else if context.isPreview {
            subtitle = tr("桌面")
        } else {
            let folder = FileManager.default.displayName(atPath: feed.folder.path)
            subtitle = tr("\(feed.totalCount) 张 · 存在「\(folder)」")
        }
        let canSelect = !context.isPreview && feed.error == nil && !feed.files.isEmpty
        return FilePanelHeader(
            title: selecting ? tr("已选 \(selection.ordered(shown.map(\.url)).count) 个") : tr("最近截图"),
            subtitle: subtitle,
            button: selecting ? tr("完成") : (canSelect ? tr("多选") : nil),
            prominent: selecting,
            palette: palette
        ) {
            withAnimation(.snappy(duration: 0.25)) {
                mode = selecting ? .browse : .select
                selection.clear()
                renaming = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if context.isPreview {
            SamplePicture(symbol: "macwindow").frame(height: 150)
                .clipShape(.rect(cornerRadius: 10))
        } else if let error = feed.error {
            FeedErrorNote(text: error, denied: feed.accessDenied).frame(height: 220)
        } else if feed.loadedAt == nil, feed.files.isEmpty {
            PanelNote(symbol: "hourglass", text: tr("正在读取…")).frame(height: 200)
        } else if feed.files.isEmpty {
            PandaEmptyState(empty: .screenshots, title: tr("截取屏幕"), panel: true) {
                WidgetDetailWindow.shared.close()
                ScreenCapture.capture(.region)
            }
            .frame(height: 220)
        } else {
            FileSearchField(text: $query, prompt: tr("搜索：按文件名或日期"), palette: palette)
            FileFilterChips(items: ShotFilter.allCases, title: \.title, selected: $filter, palette: palette)
            if mode == .select {
                FileSelectList(files: shown, selection: $selection, renaming: $renaming, feed: feed,
                               icon: .thumbnail, palette: palette, now: context.now,
                               emptyText: tr("没有符合的截图"))
            } else if let latest = shown.first {
                hero(latest)
                if shown.count > 1 { grid(Array(shown.dropFirst())) }
            } else {
                Text(verbatim: tr("没有符合的截图"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    // MARK: 最新一张

    private func hero(_ file: ListedFile) -> some View {
        let recording = ShotFilter.isRecording(file)
        return VStack(alignment: .leading, spacing: 10) {
            FileThumb(url: file.url, pixels: 720, fill: false)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.25))
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .center) {
                    if recording {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
                .contentShape(.rect(cornerRadius: 10))
                .onTapGesture { FileActions.open(file.url) }
                .onDrag { FileActions.dragProvider(file.url) }
                .contextMenu { menu(file) }
                .help(tr("点按打开，拖移到其他地方即可使用"))
            Text(verbatim: caption(file))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                pill(copied == file.url ? tr("已拷贝") : tr("拷贝"), solid: true) {
                    file.isImage ? FileActions.copyImage(file.url) : FileActions.copyFile(file.url)
                    withAnimation(.snappy(duration: 0.2)) { copied = file.url }
                }
                pill(tr("标注"), disabled: !file.isImage) {
                    withAnimation(.snappy(duration: 0.25)) { mode = .markup(file.url) }
                }
                .help(file.isImage ? tr("加箭头、框、马赛克或文字") : tr("录屏不能标注"))
                pill(tr("删除"), tint: FilePanelPalette.red) { trash([file.url]) }
            }
        }
        .task(id: file.url) {
            heroSize = nil
            copied = nil
            let url = file.url
            guard file.isImage else { return }
            heroSize = await Task.detached(priority: .utility) { MarkupRenderer.pixelSize(url) }.value
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = nil
        }
    }

    private func caption(_ file: ListedFile) -> String {
        let kind = ShotFilter.isRecording(file) ? tr("录屏") : tr("截屏")
        var text = "\(kind) \(FileDate.short(file.date, now: context.now))"
        if let heroSize {
            text += " · \(Int(heroSize.width)) × \(Int(heroSize.height))"
        } else if let size = FileActions.size(file.size) {
            text += " · \(size)"
        }
        return text
    }

    private func pill(_ title: String, solid: Bool = false, tint: Color = .white,
                      disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? palette.ink : tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(solid ? palette.accent : .white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.14), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: 更早

    private func grid(_ files: [ListedFile]) -> some View {
        let rows = CGFloat((files.count + 3) / 4)
        // 一格约 69 × 44，最多露出三排，再多在里面滚。
        let height = min(rows, 3) * 50 - 6
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: tr("更早"))
                Spacer(minLength: 0)
                Text(verbatim: tr("拖出去就能用"))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(files) { file in
                        FileThumb(url: file.url, pixels: 240, fill: file.isImage)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06))
                            .clipShape(.rect(cornerRadius: 6, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                if ShotFilter.isRecording(file) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                        .padding(3)
                                }
                            }
                            .contentShape(.rect(cornerRadius: 6))
                            .onTapGesture { FileActions.open(file.url) }
                            .onDrag { FileActions.dragProvider(file.url) }
                            .contextMenu { menu(file) }
                            .help(file.name)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: max(44, height))
        }
    }

    @ViewBuilder
    private func menu(_ file: ListedFile) -> some View {
        Button(tr("打开")) { FileActions.open(file.url) }
        Button(tr("在访达中显示")) { FileActions.reveal([file.url]) }
        Divider()
        if file.isImage {
            Button(tr("拷贝图像")) { FileActions.copyImage(file.url) }
            Button(tr("标注")) { mode = .markup(file.url) }
        }
        Button(tr("拷贝文件")) { FileActions.copyFile(file.url) }
        Button(tr("重命名")) {
            withAnimation(.snappy(duration: 0.25)) {
                mode = .select
                selection.clear()
                renaming = file.url
            }
        }
        Divider()
        Button(tr("移到废纸篓")) { trash([file.url]) }
    }

    private func trash(_ urls: [URL]) {
        let outcome = FileBatch.trash(urls)
        feed.forget(Set(outcome.done))
    }
}
