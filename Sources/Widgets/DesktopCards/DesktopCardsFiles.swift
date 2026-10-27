import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 钉在桌面 · Files 组
//
// 下载、文件暂存、剪贴板、书签、截图工具、相册、最近截图、壁纸、摸鱼时钟、音量在桌面卡片
// 小 160×160 / 中 340×160 / 大 340×340 三档的专属布局。每档一眼看清、常用操作直接点、
// 不截断、不滚动。数据和扩展栏是同一份（`FolderFeed`、`ClipboardHistory`、卡片配置……），
// 改动走原来的写法，两边同步。每档显示几条、网格几行几列在 Core 的 `DesktopCardsFilesPlan`。
//
// 卡片底是液态玻璃（`DesktopCard` 画），这里用面板语义色，浅色深色都可读；照片、截图、
// 壁纸铺满整张卡片，压在图上的字和圆钮保持白字黑底（和相册、壁纸面板一样的例外）。
// 摸鱼时钟沿用卡片自己的配色和背景图（设置里选的外观）。

@MainActor
enum DesktopCardsFiles {
    /// 本组的种类返回专属视图，其余返回 nil 走通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsFilesPlan.handles(widget.kind) else { return nil }
        switch widget.kind {
        case .downloads: return AnyView(DCFDownloads(widget: widget, size: size, now: now))
        case .fileShelf: return AnyView(DCFFileShelf(widget: widget, size: size, now: now))
        case .clipboard: return AnyView(DCFClipboard(widget: widget, size: size, now: now))
        case .bookmarks: return AnyView(DCFBookmarks(widget: widget, size: size))
        case .capture: return AnyView(DCFCapture(widget: widget, size: size, now: now))
        case .photos: return AnyView(DCFPhotos(widget: widget, size: size))
        case .screenshots: return AnyView(DCFScreenshots(widget: widget, size: size, now: now))
        case .wallpaper: return AnyView(DCFWallpaper(widget: widget, size: size))
        case .slacker: return AnyView(DCFSlacker(widget: widget, size: size))
        case .volume: return AnyView(DCFVolume(widget: widget, size: size))
        default: return nil
        }
    }
}

// MARK: - 共用的小零件

enum DCF {
    /// 卡片内边距。
    static let pad: CGFloat = 14
    static let rowCorner: CGFloat = 10
}

/// 卡片顶上一行：图标、标题，右边一句小字或一个按钮。
private struct DCFHeader<Trailing: View>: View {
    var symbol: String
    var title: String
    var accent: Color
    var big = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: big ? 16 : 14, weight: .semibold))
                .foregroundStyle(accent.panelReadable)
            Text(verbatim: title)
                .font(.system(size: big ? 17 : 15, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension DCFHeader where Trailing == DCFDetailText {
    init(symbol: String, title: String, accent: Color, big: Bool = false, detail: String?) {
        self.init(symbol: symbol, title: title, accent: accent, big: big) { DCFDetailText(text: detail) }
    }
}

/// 标题右边的灰色小字（13pt）。
private struct DCFDetailText: View {
    var text: String?

    var body: some View {
        if let text {
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
        }
    }
}

/// 玻璃上的一行底：薄填充加细边。
private struct DCFRowBackground: View {
    var highlighted = false
    var corner: CGFloat = DCF.rowCorner

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(highlighted ? Color.panelSelected : Color.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.panelStroke, lineWidth: 0.6)
            }
    }
}

/// 胶囊按钮：「打开文件夹」「清空」。
private struct DCFPill: View {
    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.panelPrimary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(.panelFill))
            .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// 压在照片上的圆钮：白图标、半透明黑底（照片上的例外，不跟随浅色）。
private struct DCFPhotoButton: View {
    var symbol: String
    var help: String
    var side: CGFloat = 32
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: max(13, side * 0.42), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 照片下沿的渐暗，上面放白字。
private struct DCFPhotoShade: View {
    var body: some View {
        LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

/// 空着、读不了、正在读：图标（或小熊猫）加一句话，居中。
private struct DCFNote: View {
    var panda: PandaEmpty?
    var symbol: String
    var text: String
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            if let panda {
                PandaEmptyBadge(empty: panda, size: compact ? 52 : 68, fallback: symbol)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 24 : 30, weight: .medium))
                    .foregroundStyle(.panelTertiary)
            }
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 一个文件的缩略图：图片裁满，其余画整个图标。点一下打开，能直接拖出去。
private struct DCFFileThumb: View {
    var file: ListedFile
    var side: CGFloat
    var corner: CGFloat = 12

    var body: some View {
        FileThumb(url: file.url, pixels: Int(side * 2), fill: file.isImage)
            .padding(file.isImage ? 0 : side * 0.08)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.panelFill))
            .clipShape(.rect(cornerRadius: corner, style: .continuous))
            .contentShape(.rect(cornerRadius: corner))
            .id(file.url)
    }
}

/// 文件的点按、拖出和右键：打开、在访达中显示、拷贝。
private struct DCFFileActions: ViewModifier {
    var url: URL

    func body(content: Content) -> some View {
        content
            .onTapGesture { FileActions.open(url) }
            .onDrag { FileActions.dragProvider(url) }
            .contextMenu {
                Button(tr("打开")) { FileActions.open(url) }
                Button(tr("在访达中显示")) { FileActions.reveal([url]) }
                Button(tr("拷贝文件")) { FileActions.copyFile(url) }
            }
            .help(url.lastPathComponent)
    }
}

private extension View {
    func dcfFile(_ url: URL) -> some View { modifier(DCFFileActions(url: url)) }

    /// 卡片的大小和内边距。
    func dcfCard(_ size: DesktopPinSize, padding: CGFloat = DCF.pad) -> some View {
        self.padding(padding)
            .frame(width: size.size.width, height: size.size.height, alignment: .topLeading)
    }
}

/// 细进度条；不知道进度时画三成。
private struct DCFProgressBar: View {
    var fraction: Double?
    var accent: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.panelTrack)
                Capsule().fill(accent.panelGraphic)
                    .frame(width: max(height, proxy.size.width * min(max(fraction ?? 0.3, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// 「+N」格：虚线框里写还有几个。
private struct DCFMoreCell: View {
    var count: Int
    var corner: CGFloat = 12
    var onPhoto = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(onPhoto ? Color.black.opacity(0.35) : Color.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(onPhoto ? Color.white.opacity(0.3) : Color.panelStroke,
                                  style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            }
            .overlay {
                Text(verbatim: "+\(count)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(onPhoto ? Color.white : Color.panelSecondary)
            }
            .accessibilityLabel(tr("还有 \(count) 个"))
    }
}

// MARK: - 下载

/// 小：最新一个文件的缩略图、名字和多久以前（正在下载时是进度）。点开、拖走。
/// 中：左边最新一个的大缩略图，右边再列 3 个。
/// 大：标题和「打开文件夹」，正在下载的卡片（最多 2 张）写进度，下面列最近的文件。
private struct DCFDownloads: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint
    private var feed: FolderFeed { FolderFeed.shared(.downloads) }
    private var accent: Color { panelTint.accent(or: Color(hex: "#62CBD9")) }

    var body: some View {
        Group {
            if let note {
                VStack(alignment: .leading, spacing: 8) {
                    if size != .small { header }
                    note
                }
            } else {
                switch size {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .dcfCard(size)
        .onAppear {
            feed.start()
            feed.refresh(force: false)
        }
    }

    private var note: DCFNote? {
        if let error = feed.error { return DCFNote(symbol: "exclamationmark.triangle", text: error, compact: size == .small) }
        if feed.loadedAt == nil, feed.files.isEmpty { return DCFNote(symbol: "hourglass", text: tr("正在读取…"), compact: true) }
        if feed.files.isEmpty, feed.downloading.isEmpty {
            return DCFNote(panda: .downloads, symbol: "arrow.down.circle", text: PandaEmpty.downloads.line(),
                           compact: size != .large)
        }
        return nil
    }

    private var header: some View {
        let detail = feed.totalCount > 0 ? tr("\(feed.totalCount) 个项目") : nil
        return DCFHeader(symbol: "arrow.down.circle.fill", title: tr("下载"), accent: accent,
                         big: size == .large, detail: detail)
    }

    // 小

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = feed.downloading.first {
                DownloadProgressIcon(download: active, size: 64)
                    .frame(width: 64, height: 64)
                Spacer(minLength: 0)
                Text(verbatim: active.finalName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: DownloadProgress.tileCaption(active.fraction))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            } else if let latest = feed.files.first {
                DCFFileThumb(file: latest, side: 70, corner: 14)
                    .dcfFile(latest.url)
                Spacer(minLength: 0)
                Text(verbatim: latest.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: tr("下载 · \(RelativeAge.caption(latest.date, now: now))"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中

    private var medium: some View {
        let active = feed.downloading.first
        let rest = active == nil ? Array(feed.files.dropFirst()) : feed.files
        let rows = Array(rest.prefix(DesktopCardsFilesPlan.rows(.downloads, size: .medium)))
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if let active {
                    VStack(spacing: 8) {
                        DownloadProgressIcon(download: active, size: 60)
                            .frame(width: 60, height: 60)
                        Text(verbatim: DownloadProgress.tileCaption(active.fraction))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 132, height: 132)
                    .background(DCFRowBackground(corner: 16))
                    .help(active.finalName)
                } else if let latest = feed.files.first {
                    DCFFileThumb(file: latest, side: 132, corner: 16)
                        .overlay(alignment: .bottomLeading) {
                            Text(verbatim: RelativeAge.caption(latest.date, now: now))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                        .dcfFile(latest.url)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                header
                    .padding(.bottom, 2)
                ForEach(rows) { file in
                    DCFCompactFileRow(file: file, now: now)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // 大

    private var large: some View {
        let downloading = Array(feed.downloading.prefix(DesktopCardsFilesPlan.maxDownloadingCards))
        let count = DesktopCardsFilesPlan.rows(.downloads, size: .large, downloading: downloading.count)
        return VStack(alignment: .leading, spacing: 8) {
            DCFHeader(symbol: "arrow.down.circle.fill", title: tr("下载"), accent: accent, big: true) {
                DCFPill(title: tr("打开文件夹"), symbol: "folder") { FileActions.openFolder(feed.folder) }
            }
            .frame(height: 30)
            ForEach(downloading) { download in
                HStack(spacing: 10) {
                    DownloadProgressIcon(download: download, size: 30)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: download.finalName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(verbatim: DownloadProgress.tileCaption(download.fraction))
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(.panelSecondary)
                                .lineLimit(1)
                        }
                        DCFProgressBar(fraction: download.fraction, accent: accent)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 50)
                .background(DCFRowBackground())
            }
            ForEach(Array(feed.files.prefix(count))) { file in
                HStack(spacing: 10) {
                    FileTypeBadgeView(file: file, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
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
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(DCFRowBackground())
                .contentShape(.rect(cornerRadius: DCF.rowCorner))
                .dcfFile(file.url)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 中号右边的一行：类型小标、名字、多久以前。
private struct DCFCompactFileRow: View {
    var file: ListedFile
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            FileTypeBadgeView(file: file, size: 22)
            Text(verbatim: file.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(verbatim: RelativeAge.caption(file.date, now: now))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(DCFRowBackground(corner: 9))
        .contentShape(.rect(cornerRadius: 9))
        .dcfFile(file.url)
    }
}

// MARK: - 文件暂存

/// 整张卡片都能接文件（只记位置，原文件不动）。
/// 小：叠着的两个图标、几个文件；点一下在访达里选中全部，拖走第一个。
/// 中：一排 4 格（图标和名字），放不下最后一格写「+N」。
/// 大：4×3 格，右上「清空」（只清清单），悬停一格出「×」移出暂存。
private struct DCFFileShelf: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @State private var targeted = false
    @State private var dragged = 0
    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Color(hex: "#5AC8C8")) }

    private var files: [ListedFile] { FileShelf.files(widget) }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium, .large: grid
            }
        }
        .dropHidden(targeted)
        .dcfCard(size)
        .dropTargetOutline(targeted, corner: DesktopCard.corner, prompt: .fileShelf(files: dragged),
                           compact: size == .small)
        .onDrop(of: FileDropDelegate.types, delegate: FileDropDelegate(
            enabled: true,
            update: { inside, count in
                targeted = inside
                dragged = count
            },
            receive: { urls in _ = FileShelf.add(urls, to: widget) }))
    }

    private var small: some View {
        let files = self.files
        return Group {
            if let first = files.first {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                        if files.count > 1 {
                            Image(nsImage: Thumbnails.shared.icon(for: files[1].url))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 54, height: 54)
                                .rotationEffect(.degrees(-10))
                                .offset(x: -10, y: 2)
                        }
                        Image(nsImage: Thumbnails.shared.icon(for: first.url))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .offset(x: files.count > 1 ? 8 : 0)
                    }
                    .frame(width: 84, height: 66, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { FileActions.reveal(files.map(\.url)) }
                    .onDrag { FileActions.dragProvider(first.url) }
                    .help(tr("点一下在访达中显示，拖出第一个文件"))
                    Spacer(minLength: 0)
                    Text(verbatim: tr("\(files.count) 个文件"))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    Text(verbatim: tr("文件暂存"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                DCFNote(panda: .fileShelf, symbol: "tray.and.arrow.down", text: PandaEmpty.fileShelf.line(), compact: true)
            }
        }
    }

    private var grid: some View {
        let files = self.files
        let plan = DesktopCardsFilesPlan.shelfGrid(size)
        let slots = DesktopCardsFilesPlan.slots(total: files.count, capacity: plan.capacity)
        let shown = Array(files.prefix(slots.shown))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: plan.columns)
        return VStack(alignment: .leading, spacing: 8) {
            DCFHeader(symbol: "tray.full.fill", title: tr("文件暂存"), accent: accent, big: size == .large) {
                HStack(spacing: 8) {
                    DCFDetailText(text: files.isEmpty ? nil : tr("\(files.count) 个"))
                    if size == .large, !files.isEmpty {
                        DCFPill(title: tr("清空"), symbol: nil) { FileShelf.clear(widget) }
                            .help(tr("只清空清单，原文件不动"))
                    }
                }
            }
            .frame(height: 28)
            if files.isEmpty {
                DCFNote(panda: .fileShelf, symbol: "tray.and.arrow.down", text: tr("把文件拖到这里，原文件不动"),
                        compact: size == .medium)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(shown) { file in
                        DCFShelfCell(file: file, removable: size == .large) { FileShelf.remove(file.url, from: widget) }
                    }
                    if slots.more > 0 {
                        DCFMoreCell(count: slots.more)
                            .frame(height: 76)
                            .help(tr("其余的在扩展栏的文件暂存面板里"))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 暂存的一格：图标和名字；点开、拖走；大号悬停出「×」。
private struct DCFShelfCell: View {
    var file: ListedFile
    var removable: Bool
    var onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            FileThumb(url: file.url, pixels: 120, fill: file.isImage)
                .frame(width: 50, height: 50)
                .clipShape(.rect(cornerRadius: 9, style: .continuous))
            Text(verbatim: file.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(DCFRowBackground(highlighted: hovered, corner: 12))
        .contentShape(.rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if removable, hovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.panelRaised).panelLift())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(3)
                .help(tr("从暂存中移出"))
                .accessibilityLabel(tr("从暂存中移出"))
            }
        }
        .onHover { hovered = $0 }
        .dcfFile(file.url)
    }
}

// MARK: - 剪贴板

/// 小：最近拷贝的那条（文字最多 4 行，图片铺开）和条数。
/// 中：最近 3 条，点一行就再拷贝一次。
/// 大：星标（最多 3 条）在上，最近的在下，点一行拷贝，悬停最近的一行能加星标。
private struct DCFClipboard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @State private var copied: String?
    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Color(hex: "#A78BFA")) }
    private var history: ClipboardHistory { ClipboardHistory.shared }
    private var pins: [String] { ClipboardPins.pins(widget.config) }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium, .large: list
            }
        }
        .dcfCard(size)
        .onAppear { history.start() }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { copied = nil }
        }
    }

    private var countText: String? {
        history.entries.isEmpty ? nil : tr("\(history.entries.count) 条")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            DCFHeader(symbol: "list.clipboard.fill", title: tr("剪贴板"), accent: accent, detail: countText)
            if let latest = history.entries.first {
                switch latest.content {
                case .image(let image, _, _):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(latest.preview)
                case .text(let text):
                    Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .files(let urls):
                    VStack(alignment: .leading, spacing: 6) {
                        if let first = urls.first {
                            Image(nsImage: Thumbnails.shared.icon(for: first))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                        }
                        Text(verbatim: latest.preview)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                DCFNote(panda: .clipboard, symbol: "list.clipboard", text: PandaEmpty.clipboard.line(), compact: true)
            }
        }
    }

    private var list: some View {
        let pins = self.pins
        let recent = history.entries.filter { entry in
            if case .text(let text) = entry.content, ClipboardPins.isPinned(text, in: pins) { return false }
            return true
        }
        let split = DesktopCardsFilesPlan.clipboardSplit(pins: pins.count, recent: recent.count, size: size)
        return VStack(alignment: .leading, spacing: 5) {
            DCFHeader(symbol: "list.clipboard.fill", title: tr("剪贴板"), accent: accent, big: size == .large,
                      detail: countText)
                .padding(.bottom, 3)
            if pins.isEmpty && recent.isEmpty {
                DCFNote(panda: .clipboard, symbol: "list.clipboard", text: PandaEmpty.clipboard.line(),
                        compact: size == .medium)
            } else {
                if split.pins > 0 {
                    section(tr("星标"))
                    ForEach(Array(pins.prefix(split.pins)), id: \.self) { pin in
                        DCFClipRow(symbol: "star.fill", text: pin.replacingOccurrences(of: "\n", with: " "),
                                   trailing: copied == "pin:" + pin ? tr("已拷贝") : nil,
                                   accent: accent, starred: true, canStar: false) {
                            history.copyText(pin)
                            withAnimation(.easeIn(duration: 0.15)) { copied = "pin:" + pin }
                        } onStar: {}
                    }
                }
                if split.recent > 0 {
                    if size == .large { section(tr("最近")) }
                    ForEach(Array(recent.prefix(split.recent))) { entry in
                        recentRow(entry, pins: pins)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .frame(height: 18)
            .padding(.top, 2)
    }

    private func recentRow(_ entry: ClipboardHistory.Entry, pins: [String]) -> some View {
        let id = entry.id.uuidString
        let symbol: String
        let text: String?
        switch entry.content {
        case .text(let words):
            symbol = "text.alignleft"
            text = words
        case .image:
            symbol = "photo"
            text = nil
        case .files:
            symbol = "doc"
            text = nil
        }
        let trailing = copied == id ? tr("已拷贝") : RelativeAge.caption(entry.date, now: now)
        return DCFClipRow(symbol: symbol, text: entry.preview, trailing: trailing, accent: accent,
                          starred: false, canStar: size == .large && text != nil) {
            history.copy(entry)
            withAnimation(.easeIn(duration: 0.15)) { copied = id }
        } onStar: {
            guard let text else { return }
            let current = WidgetWriter.current(widget.id) ?? widget
            let next = ClipboardPins.toggling(text, in: ClipboardPins.pins(current.config))
            withAnimation(.snappy(duration: 0.25)) {
                WidgetWriter.write(current) { ClipboardPins.store(next, in: &$0) }
            }
        }
    }
}

/// 剪贴板的一行：小图标、一行字、右边时间或「已拷贝」。
private struct DCFClipRow: View {
    var symbol: String
    var text: String
    var trailing: String?
    var accent: Color
    var starred: Bool
    var canStar: Bool
    var onCopy: () -> Void
    var onStar: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(starred ? accent.panelReadable : Color.panelSecondary)
                .frame(width: 16)
            Text(verbatim: text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if canStar, hovered {
                Button(action: onStar) {
                    Image(systemName: "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("加星标"))
                .accessibilityLabel(tr("加星标"))
            } else if let trailing {
                Text(verbatim: trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(trailing == tr("已拷贝") ? accent.panelReadable : Color.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(DCFRowBackground(highlighted: hovered, corner: 9))
        .contentShape(.rect(cornerRadius: 9))
        .onHover { hovered = $0 }
        .onTapGesture(perform: onCopy)
        .help(tr("点一下拷贝"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: tr("拷贝"), onCopy)
    }
}

// MARK: - 书签

/// 小：2×2 个大圆和名字；中：4×2；大：一列 6 行（圆、标题、网址）。点一下用默认浏览器打开，
/// 放不下的最后一格写「+N」。拖链接到卡片上加一条。
private struct DCFBookmarks: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @State private var targeted = false
    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Color(hex: "#4F8EF7")) }

    private var links: [Bookmark] { Bookmark.list(widget.config.strings("links")) }
    private var previews: [String: LinkPreview] { LinkPreview.stored(widget.config) }

    var body: some View {
        Group {
            if links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if size != .small { DCFHeader(symbol: "bookmark.fill", title: tr("书签"), accent: accent, detail: nil) }
                    DCFNote(panda: .bookmarks, symbol: "bookmark", text: tr("把链接拖到这里"), compact: size != .large)
                }
            } else if size == .large {
                list
            } else {
                grid
            }
        }
        .dropHidden(targeted)
        .dcfCard(size)
        .dropTargetOutline(targeted, corner: DesktopCard.corner, prompt: .bookmark, compact: size == .small)
        .onDrop(of: [.url, .plainText], delegate: ContentDropDelegate(
            types: [.url, .plainText],
            enabled: true,
            targeted: { targeted = $0 },
            receive: { things in
                withAnimation(.snappy(duration: 0.3)) { BookmarkDrop.add(things, to: widget) }
            }))
    }

    private func title(_ link: Bookmark) -> String { link.displayTitle(previews[link.url.absoluteString]) }

    private func open(_ link: Bookmark) { NSWorkspace.shared.open(link.url) }

    private var grid: some View {
        let plan = DesktopCardsFilesPlan.bookmarkGrid(size)
        let all = links
        let slots = DesktopCardsFilesPlan.slots(total: all.count, capacity: plan.capacity)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: plan.columns)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(all.prefix(slots.shown).enumerated()), id: \.offset) { _, link in
                let name = title(link)
                Button { open(link) } label: {
                    VStack(spacing: 4) {
                        BookmarkBadge(link: Bookmark(title: name, url: link.url), size: 40)
                        Text(verbatim: name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help(name + "\n" + link.url.absoluteString)
                .accessibilityLabel(tr("打开 \(name)"))
            }
            if slots.more > 0 {
                DCFMoreCell(count: slots.more)
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .help(tr("其余的在扩展栏的书签面板里"))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var list: some View {
        let plan = DesktopCardsFilesPlan.bookmarkGrid(.large)
        let all = links
        let slots = DesktopCardsFilesPlan.slots(total: all.count, capacity: plan.rows)
        return VStack(alignment: .leading, spacing: 5) {
            DCFHeader(symbol: "bookmark.fill", title: tr("书签"), accent: accent, big: true,
                      detail: tr("\(all.count) 个"))
                .frame(height: 24)
                .padding(.bottom, 3)
            ForEach(Array(all.prefix(slots.shown).enumerated()), id: \.offset) { _, link in
                let name = title(link)
                Button { open(link) } label: {
                    HStack(spacing: 10) {
                        BookmarkBadge(link: Bookmark(title: name, url: link.url), size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .lineLimit(1)
                            Text(verbatim: Bookmark.shortHost(link.url))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.panelSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelTertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(DCFRowBackground())
                    .contentShape(.rect(cornerRadius: DCF.rowCorner))
                }
                .buttonStyle(.plain)
                .help(link.url.absoluteString)
                .accessibilityLabel(tr("打开 \(name)"))
            }
            if slots.more > 0 {
                Text(verbatim: tr("还有 \(slots.more) 个，在扩展栏的书签面板里"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(DCFRowBackground())
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 截图工具

/// 小：排第一的那个按钮画大，下面写上一张截图是多久以前（录屏时写计时）。
/// 中：一排全部按钮（最多 4 个，图标加名字）。大：一排按钮，下面最近 3 张截图，点开、拖走。
/// 识字是码头 Pro：没解锁时画暗、带小锁，点一下弹付费墙。录屏时按钮变红，再点停止。
private struct DCFCapture: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Color(hex: "#5E9EFF")) }
    private var recording: ScreenRecording { ScreenRecording.shared }
    private var shots: FolderFeed { FolderFeed.shared(.screenshots) }
    private var actions: [CaptureAction] { Array(CaptureButtons.from(widget.config).prefix(4)) }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .dcfCard(size)
        .onAppear { shots.start() }
    }

    private func isLocked(_ action: CaptureAction) -> Bool {
        guard let toggle = action.quickToggle else { return false }
        return !ProLicenseGate.canUseTool(toggle, isOn: false, unlocked: licenseUnlocked || supporter)
    }

    private func isLive(_ action: CaptureAction) -> Bool { action.isRecording && recording.isRecording }

    private func run(_ action: CaptureAction) {
        if isLocked(action) {
            PaywallWindow.shared.show()
        } else {
            ScreenCapture.perform(action, options: CaptureOptions(config: widget.config), widget: widget.id)
        }
    }

    /// 上一张截图多久以前；录屏时是计时（每秒走）。
    @ViewBuilder
    private var status: some View {
        if recording.isRecording, let started = recording.startedAt {
            TimelineView(.periodic(from: started, by: 1)) { timeline in
                Label {
                    Text(verbatim: RecordingClock.text(timeline.date.timeIntervalSince(started)))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "record.circle")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#E5484D"))
                .lineLimit(1)
            }
        } else if let latest = shots.files.first {
            Text(verbatim: tr("上一张 \(RelativeAge.caption(latest.date, now: now))"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
        }
    }

    private var small: some View {
        VStack(spacing: 8) {
            if let action = actions.first {
                DCFCaptureButton(action: action, locked: isLocked(action), live: isLive(action), accent: accent,
                                 big: true) { run(action) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                status
                    .frame(height: 18)
            } else {
                DCFNote(symbol: "camera.viewfinder", text: tr("在设置里选截图按钮"), compact: true)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            DCFHeader(symbol: "camera.viewfinder", title: tr("截图"), accent: accent) { status }
                .frame(height: 22)
            buttons
                .frame(maxHeight: .infinity)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                DCFCaptureButton(action: action, locked: isLocked(action), live: isLive(action), accent: accent,
                                 big: false) { run(action) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var large: some View {
        let recent = Array(shots.files.prefix(DesktopCardsFilesPlan.captureRecentShots))
        return VStack(alignment: .leading, spacing: 10) {
            DCFHeader(symbol: "camera.viewfinder", title: tr("截图"), accent: accent, big: true) { status }
                .frame(height: 24)
            buttons
                .frame(height: 96)
            Text(verbatim: tr("最近截图"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.top, 2)
            if recent.isEmpty {
                DCFNote(panda: .screenshots, symbol: "photo.on.rectangle", text: tr("截完的图会出现在这里"),
                        compact: true)
            } else {
                HStack(spacing: 8) {
                    ForEach(recent) { file in
                        FileThumb(url: file.url, pixels: 320)
                            .id(file.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text(verbatim: RelativeAge.caption(file.date, now: now))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.45)))
                                    .padding(6)
                                    .allowsHitTesting(false)
                            }
                            .contentShape(.rect(cornerRadius: 12))
                            .dcfFile(file.url)
                    }
                    ForEach(recent.count..<DesktopCardsFilesPlan.captureRecentShots, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.panelFill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

/// 截图工具的一个按钮：玻璃方块，大图标加名字；录屏中变红、写「停止」。
private struct DCFCaptureButton: View {
    var action: CaptureAction
    var locked: Bool
    var live: Bool
    var accent: Color
    var big: Bool
    var perform: () -> Void
    @State private var hovered = false

    private static let red = Color(hex: "#E5484D")

    var body: some View {
        Button(action: perform) {
            VStack(spacing: big ? 8 : 6) {
                Image(systemName: live ? "stop.fill" : action.symbol)
                    .font(.system(size: big ? 34 : 24, weight: .semibold))
                    .foregroundStyle(live ? Self.red : (locked ? Color.panelTertiary : accent.panelReadable))
                    .overlay(alignment: .bottomTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
                                .offset(x: 8, y: 6)
                        }
                    }
                Text(verbatim: live ? tr("停止") : action.title)
                    .font(.system(size: big ? 15 : 13, weight: .semibold))
                    .foregroundStyle(locked ? Color.panelSecondary : Color.panelPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: big ? 22 : 16, style: .continuous)
                    .fill(live ? Self.red.opacity(0.16) : (hovered ? Color.panelSelected : Color.panelFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: big ? 22 : 16, style: .continuous)
                            .strokeBorder(live ? Self.red.opacity(0.5) : Color.panelStroke, lineWidth: 0.8)
                    }
            }
            .contentShape(.rect(cornerRadius: big ? 22 : 16))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(locked ? tr("\(action.title)：码头 Pro 专属，点一下解锁") : (live ? tr("正在录屏，点一下停止") : action.help))
        .accessibilityLabel(action.title)
        .accessibilityValue(locked ? ProFeatures.label : (live ? tr("正在录屏") : ""))
    }
}

// MARK: - 相册

/// 照片铺满整张卡片，按相册设置的间隔轮播（和扩展栏、面板同一张，见 `PhotoRotation`）。
/// 小：只有照片，点一下换下一张。
/// 中：下沿写「那年今天」或拍摄日期和地点（没有就写文件名），右边上一张、暂停、下一张。
/// 大：同中号，再多一行几分钟后换下一张；点照片打开原图，能拖出去。
private struct DCFPhotos: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var isWide: Bool { widget.config.string("layout", default: "standard") == "wide" }
    private var album: PhotoAlbum { PhotoAlbum(config: widget.config, wide: isWide) }

    var body: some View {
        let album = self.album
        let order = album.order()
        let tick = DesktopCardsFilesPlan.photoTick(interval: album.interval, count: order.count,
                                                   paused: album.state.isPaused)
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: tick)) { timeline in
            photo(album: album, order: order, now: timeline.date)
        }
        .frame(width: size.size.width, height: size.size.height)
        .onAppear { album.start(now: .now) }
        .onChange(of: album.activeFolders) { _, _ in album.start(now: .now) }
    }

    @ViewBuilder
    private func photo(album: PhotoAlbum, order: [String], now: Date) -> some View {
        let lookup = album.lookup
        if let position = PhotoRotation.position(at: now, order: order, state: album.state, interval: album.interval),
           let item = lookup[order[position]] {
            ZStack {
                AlbumThumb(item: item, pixels: size == .small ? 400 : 720)
                    .id(item.id)
                    .transition(.opacity)
            }
            .frame(width: size.size.width, height: size.size.height)
            .clipped()
            .animation(.easeInOut(duration: 0.9), value: item.id)
            .contentShape(.rect)
            .onTapGesture {
                if size == .small {
                    step(1, album: album, order: order)
                } else if let url = item.fileURL {
                    FileActions.open(url)
                }
            }
            .modifier(DCFOptionalDrag(url: size == .small ? nil : item.fileURL))
            .overlay(alignment: .bottom) {
                if size != .small {
                    bar(item: item, album: album, order: order, position: position, now: now)
                }
            }
            .help(size == .small ? tr("点一下换下一张") : (item.fileURL?.lastPathComponent ?? tr("那年今天")))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label(item))
        } else {
            empty(album)
        }
    }

    private func label(_ item: PhotoAlbum.Item) -> String {
        switch item {
        case .file(let file): tr("相册：\(file.name)")
        case .memory(let memory): tr("那年今天：\(PhotoMemory.caption(date: memory.date, place: nil))")
        }
    }

    /// 下沿：标题、日期和地点、倒计时，右边三个圆钮。
    private func bar(item: PhotoAlbum.Item, album: PhotoAlbum, order: [String], position: Int, now: Date) -> some View {
        let caption = captionLines(item, now: now)
        let large = size == .large
        let paused = album.state.isPaused
        let canStep = order.count > 1
        return HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let headline = caption.headline {
                    Text(verbatim: headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(verbatim: caption.line)
                    .font(.system(size: large ? 16 : 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if large {
                    Text(verbatim: countdown(album: album, count: order.count, now: now))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                DCFPhotoButton(symbol: "chevron.left", help: tr("上一张"), side: large ? 36 : 30, enabled: canStep) {
                    step(-1, album: album, order: order)
                }
                DCFPhotoButton(symbol: paused ? "play.fill" : "pause.fill", help: paused ? tr("继续") : tr("暂停"),
                               side: large ? 36 : 30) {
                    togglePause(album: album, order: order)
                }
                DCFPhotoButton(symbol: "chevron.right", help: tr("下一张"), side: large ? 36 : 30, enabled: canStep) {
                    step(1, album: album, order: order)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, large ? 40 : 28)
        .frame(maxWidth: .infinity)
        .background(DCFPhotoShade())
    }

    private func captionLines(_ item: PhotoAlbum.Item, now: Date) -> (headline: String?, line: String) {
        let memories = PhotoMemories.shared
        switch item {
        case .memory(let shown):
            let place = memories.place(key: shown.id, latitude: shown.latitude, longitude: shown.longitude)
            return (PhotoMemory.headline(date: shown.date, today: now), PhotoMemory.caption(date: shown.date, place: place))
        case .file(let file):
            if let meta = memories.meta(for: file.url), let date = meta.date {
                let place = memories.place(key: file.url.path, latitude: meta.latitude, longitude: meta.longitude)
                return (PhotoMemory.headline(date: date, today: now), PhotoMemory.caption(date: date, place: place))
            }
            return (nil, file.name)
        }
    }

    private func countdown(album: PhotoAlbum, count: Int, now: Date) -> String {
        if album.state.isPaused { return tr("已暂停") }
        guard let left = PhotoRotation.secondsToNext(at: now, count: count, state: album.state,
                                                     interval: album.interval) else {
            return tr("\(count) 张")
        }
        return PhotoRotation.countdownText(left)
    }

    private func write(_ state: PhotoRotation.State) {
        let current = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(current) { PhotoRotation.write(state, to: &$0) }
    }

    private func step(_ by: Int, album: PhotoAlbum, order: [String]) {
        guard order.count > 1 else { return }
        write(PhotoRotation.stepped(by, at: .now, order: order, state: album.state, interval: album.interval))
    }

    private func togglePause(album: PhotoAlbum, order: [String]) {
        let next = album.state.isPaused
            ? PhotoRotation.resumed(at: .now, order: order, state: album.state, interval: album.interval)
            : PhotoRotation.paused(at: .now, order: order, state: album.state, interval: album.interval)
        write(next)
    }

    @ViewBuilder
    private func empty(_ album: PhotoAlbum) -> some View {
        Group {
            if album.loading {
                DCFNote(symbol: "hourglass", text: tr("正在读取…"), compact: true)
            } else if let failure = album.failure {
                DCFNote(symbol: "exclamationmark.triangle", text: failure.text, compact: size != .large)
            } else {
                DCFNote(panda: .photos, symbol: "photo.on.rectangle.angled",
                        text: tr("在扩展栏的相册面板里选文件夹"), compact: size != .large)
            }
        }
        .dcfCard(size)
    }
}

/// 有文件时才能拖。
private struct DCFOptionalDrag: ViewModifier {
    var url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.onDrag { FileActions.dragProvider(url) }
        } else {
            content
        }
    }
}

// MARK: - 最近截图

/// 小：最新一张铺满，下沿写多久以前。中：最新一张画大，右边 2×2 后面几张。
/// 大：最新一张在上，下面 3×2。放不下时最后一格写「+N」。点开，拖进聊天、邮件或文件夹。
private struct DCFScreenshots: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }

    var body: some View {
        Group {
            if let latest = feed.files.first {
                switch size {
                case .small: hero(latest, caption: 13)
                case .medium: medium(latest)
                case .large: large(latest)
                }
            } else {
                Group {
                    if let error = feed.error {
                        DCFNote(symbol: "exclamationmark.triangle", text: error, compact: size != .large)
                    } else if feed.loadedAt == nil {
                        DCFNote(symbol: "hourglass", text: tr("正在读取…"), compact: true)
                    } else {
                        DCFNote(panda: .screenshots, symbol: "camera.viewfinder", text: tr("截完的图会出现在这里"),
                                compact: size != .large)
                    }
                }
                .dcfCard(size)
            }
        }
        .frame(width: size.size.width, height: size.size.height)
        .onAppear { feed.start() }
    }

    private func hero(_ file: ListedFile, caption: CGFloat) -> some View {
        FileThumb(url: file.url, pixels: size == .small ? 400 : 720)
            .id(file.url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: RelativeAge.caption(file.date, now: now))
                    .font(.system(size: caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DCFPhotoShade())
                    .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .dcfFile(file.url)
            .accessibilityLabel(tr("最近截图：\(file.name)"))
    }

    private func cells(_ grid: DesktopCardsFilesPlan.Grid) -> (files: [ListedFile], more: Int) {
        let rest = Array(feed.files.dropFirst())
        let slots = DesktopCardsFilesPlan.slots(total: rest.count, capacity: grid.capacity)
        return (Array(rest.prefix(slots.shown)), slots.more)
    }

    private func thumbGrid(_ grid: DesktopCardsFilesPlan.Grid, cellHeight: CGFloat) -> some View {
        let plan = cells(grid)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: grid.columns)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(plan.files) { file in
                FileThumb(url: file.url, pixels: 240)
                    .id(file.url)
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    .contentShape(.rect(cornerRadius: 9))
                    .dcfFile(file.url)
            }
            if plan.more > 0 {
                DCFMoreCell(count: plan.more, corner: 9)
                    .frame(height: cellHeight)
                    .help(tr("其余的在扩展栏的最近截图面板里"))
            }
            ForEach(0..<max(0, grid.capacity - plan.files.count - (plan.more > 0 ? 1 : 0)), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.panelFill)
                    .frame(height: cellHeight)
            }
        }
    }

    private func medium(_ latest: ListedFile) -> some View {
        HStack(spacing: 6) {
            hero(latest, caption: 13)
                .frame(width: 186)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            thumbGrid(DesktopCardsFilesPlan.shotGrid(.medium), cellHeight: 67)
        }
        .padding(10)
    }

    private func large(_ latest: ListedFile) -> some View {
        VStack(spacing: 6) {
            hero(latest, caption: 14)
                .frame(height: 176)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
            thumbGrid(DesktopCardsFilesPlan.shotGrid(.large), cellHeight: 64)
        }
        .padding(12)
    }
}

// MARK: - 壁纸

/// 小：当前壁纸铺满，下沿一个「下一张」。中：铺满，下沿写文件名，右边上一张、随机、下一张。
/// 大：当前壁纸在上（带三个圆钮），下面一排排文件夹里的图，点一下设为壁纸。
private struct DCFWallpaper: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Color(hex: "#5E9EFF")) }
    private var folderPath: String { widget.config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var wallpaper: WallpaperService { WallpaperService.shared }
    private var allScreens: Bool { widget.config.bool("allScreens", default: true) }

    var body: some View {
        Group {
            switch size {
            case .small:
                picture
                    .overlay(alignment: .bottom) {
                        disc(.next, side: 36)
                            .padding(.bottom, 12)
                    }
            case .medium:
                picture
                    .overlay(alignment: .bottom) { bar(side: 30) }
            case .large:
                large
            }
        }
        .frame(width: size.size.width, height: size.size.height)
        .onAppear {
            feed.start()
            wallpaper.start()
        }
        .onChange(of: folderPath) { _, _ in feed.start() }
    }

    @ViewBuilder
    private var picture: some View {
        if let url = wallpaper.current {
            FileThumb(url: url, pixels: size == .small ? 400 : 720)
                .id(url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel(tr("当前壁纸：\(url.lastPathComponent)"))
        } else {
            DCFNote(symbol: "photo.on.rectangle", text: tr("读不到当前壁纸"), compact: true)
        }
    }

    private func disc(_ step: WallpaperCycle.Step, side: CGFloat) -> some View {
        DCFPhotoButton(symbol: WallpaperTile.symbol(step), help: WallpaperTile.title(step), side: side,
                       enabled: !feed.files.isEmpty) {
            wallpaper.step(step, in: feed.files.map(\.url), allScreens: allScreens)
        }
    }

    private func bar(side: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: tr("壁纸"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(verbatim: wallpaper.current?.deletingPathExtension().lastPathComponent ?? "")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                disc(.previous, side: side)
                disc(.random, side: side)
                disc(.next, side: side)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
        .background(DCFPhotoShade())
    }

    private var large: some View {
        let files = feed.files
        let grid = DesktopCardsFilesPlan.wallpaperGrid
        let slots = DesktopCardsFilesPlan.slots(total: files.count, capacity: grid.capacity)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: grid.columns)
        let current = wallpaper.current?.standardizedFileURL
        return VStack(alignment: .leading, spacing: 8) {
            picture
                .overlay(alignment: .bottom) { bar(side: 34) }
                .frame(height: 190)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
            HStack {
                Text(verbatim: tr("点一张设为壁纸"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 4)
                DCFDetailText(text: files.isEmpty ? nil : tr("\(files.count) 张"))
            }
            .frame(height: 18)
            if files.isEmpty {
                DCFNote(symbol: "folder", text: tr("在扩展栏的壁纸面板里选文件夹"), compact: true)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(files.prefix(slots.shown))) { file in
                        let selected = file.url.standardizedFileURL == current
                        FileThumb(url: file.url, pixels: 200)
                            .id(file.url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? accent.panelGraphic : Color.panelStroke,
                                                  lineWidth: selected ? 2 : 0.6)
                            }
                            .contentShape(.rect(cornerRadius: 8))
                            .onTapGesture { wallpaper.set(file.url, allScreens: allScreens) }
                            .help(tr("设为壁纸：\(file.name)"))
                            .accessibilityLabel(tr("设为壁纸：\(file.name)"))
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                    if slots.more > 0 {
                        DCFMoreCell(count: slots.more, corner: 8)
                            .frame(height: 42)
                            .help(tr("其余的在扩展栏的壁纸面板里"))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - 摸鱼时钟

/// 沿用卡片自己的底色、背景图、字体和液态水（设置里选的外观），每秒走。
/// 小：「距离下班」和大字 02:35:18，右下角小熊猫。
/// 中：一行大标题、下面一排小格（最多 4 个），右边小熊猫。
/// 大：大字倒计时和小熊猫，上班中加今天的进度条和「已上 · 还有」，工作时间，下面 2×2 小格。
private struct DCFSlacker: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { timeline in
            face(now: timeline.date)
        }
        .frame(width: size.size.width, height: size.size.height)
        .onAppear { HolidayService.shared.refresh() }
    }

    private func face(now: Date) -> some View {
        let settings = SlackerClock.Settings(config: widget.config)
        let reading = SlackerClock.reading(now: now, settings: settings, known: HolidayService.shared.known)
        let look = SlackerLook(config: widget.config, art: reading.art)
        return ZStack {
            look.background
            if let image = look.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.size.width, height: size.size.height)
                    .clipped()
                Color.black.opacity(0.18)
            }
            if SlackerClock.look(widget.config) == .liquid {
                SlackerWater(phase: reading.phase, level: SlackerClock.waterLevel(reading.phase, settings: settings),
                             animates: true,
                             tint: WidgetTintStyle.chosenColor(kind: .slacker, config: widget.config) ?? .white)
            }
            Group {
                switch size {
                case .small: small(reading, look)
                case .medium: medium(reading, look)
                case .large: large(reading, look, settings: settings)
                }
            }
            .foregroundStyle(look.text)
            .padding(DCF.pad)
        }
        .frame(width: size.size.width, height: size.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SlackerLook.spoken(reading))
    }

    private func titleBlock(_ reading: SlackerClock.Reading, _ look: SlackerLook, top: CGFloat, clock: CGFloat) -> some View {
        let lines = SlackerClock.titleLines(reading.phase)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: lines.top)
                .font(look.font(size: lines.bottom == nil ? clock * 0.62 : top, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let bottom = lines.bottom {
                Text(verbatim: bottom)
                    .font(look.font(size: clock, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
    }

    private func small(_ reading: SlackerClock.Reading, _ look: SlackerLook) -> some View {
        ZStack(alignment: .bottomTrailing) {
            SlackerPanda(art: reading.art)
                .frame(width: 78, height: 78)
                .offset(x: 6, y: 8)
            titleBlock(reading, look, top: 15, clock: 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func metrics(_ size: DesktopPinSize) -> SlackerMetrics {
        switch size {
        case .large:
            SlackerMetrics(title: 24, cellWidth: 150, cellHeight: 56, cellLabel: 13, cellValue: 22,
                           cellSpacing: 8, panda: 112, pandaDrop: 0)
        default:
            SlackerMetrics(title: 24, cellWidth: 50, cellHeight: 46, cellLabel: 13, cellValue: 17,
                           cellSpacing: 4, panda: 96, pandaDrop: 8)
        }
    }

    private func medium(_ reading: SlackerClock.Reading, _ look: SlackerLook) -> some View {
        let m = metrics(.medium)
        let cells = Array(reading.cells.prefix(DesktopCardsFilesPlan.slackerCells(.medium, available: reading.cells.count)))
        return HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: reading.title)
                    .font(look.font(size: m.title, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                if !cells.isEmpty {
                    HStack(spacing: m.cellSpacing) {
                        ForEach(cells) { cell in
                            SlackerCellView(cell: cell, look: look, metrics: m)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SlackerPanda(art: reading.art)
                .frame(width: m.panda, height: m.panda)
                .offset(y: m.pandaDrop)
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ reading: SlackerClock.Reading, _ look: SlackerLook, settings: SlackerClock.Settings) -> some View {
        let m = metrics(.large)
        let cells = Array(reading.cells.prefix(DesktopCardsFilesPlan.slackerCells(.large, available: reading.cells.count)))
        let progress = SlackerClock.progress(reading.phase, settings: settings)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                titleBlock(reading, look, top: 17, clock: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SlackerPanda(art: reading.art)
                    .frame(width: m.panda, height: m.panda)
                    .offset(x: 6, y: -6)
            }
            .frame(height: 104)
            VStack(alignment: .leading, spacing: 6) {
                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.22))
                            Capsule().fill(look.text.opacity(0.9))
                                .frame(width: max(10, proxy.size.width * progress.fraction))
                        }
                    }
                    .frame(height: 10)
                    Text(verbatim: SlackerClock.progressLine(done: progress.done, left: progress.left))
                        .font(look.font(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Text(verbatim: SlackerClock.hoursLine(settings))
                    .font(look.font(size: 13, weight: .medium))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !cells.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: m.cellSpacing),
                                    GridItem(.flexible(), spacing: m.cellSpacing)],
                          spacing: m.cellSpacing) {
                    ForEach(cells) { cell in
                        SlackerCellView(cell: cell, look: look, metrics: m)
                    }
                }
            }
        }
    }
}

// MARK: - 音量

/// 小：大字百分比和现在的输出设备，下面静音键和音量条。
/// 中：百分比和设备名，一排输出设备（最多 4 个，多的收进「…」），下面音量条。
/// 大：百分比和设备名、音量条，下面列出输出设备，点一行就切过去。
private struct DCFVolume: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint
    private var audio: AudioOutput { AudioOutput.shared }
    /// 选中的输出设备：原来的粉，颜色面板里选过颜色就换成选的。
    private var accent: Color { panelTint.accent(or: Color(hex: PaletteColor.pink.hex)) }

    private var current: OutputDevice? { audio.devices.first { $0.id == audio.currentID } }
    private var name: String {
        let value = current?.name ?? audio.deviceName
        return value.isEmpty ? tr("无输出设备") : value
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .dcfCard(size)
        .onAppear { audio.start() }
    }

    private var percent: String {
        guard let level = audio.volume else { return "--" }
        return OutputDevices.percentText(audio.muted ? 0 : level)
    }

    private var speaker: String {
        guard let level = audio.volume, !audio.muted else { return "speaker.slash.fill" }
        switch level {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func bigPercent(_ points: CGFloat) -> some View {
        Text(verbatim: percent)
            .font(.system(size: points, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(audio.muted ? Color.panelSecondary : Color.panelPrimary)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    private func deviceLine(_ points: CGFloat) -> some View {
        HStack(spacing: 5) {
            if let current {
                Image(systemName: OutputDevices.symbol(for: current))
                    .font(.system(size: points, weight: .semibold))
            }
            Text(verbatim: name)
                .font(.system(size: points, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.panelSecondary)
    }

    private func muteButton(side: CGFloat) -> some View {
        Button { audio.setMuted(!audio.muted) } label: {
            Image(systemName: speaker)
                .font(.system(size: max(13, side * 0.44), weight: .semibold))
                .foregroundStyle(audio.muted ? Color(hex: PaletteColor.red.hex) : Color.panelPrimary)
                .frame(width: side, height: side)
                .background(Circle().fill(.panelFill))
                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(audio.muted ? tr("取消静音") : tr("静音"))
        .accessibilityLabel(audio.muted ? tr("取消静音") : tr("静音"))
    }

    @ViewBuilder
    private func sliderRow(side: CGFloat) -> some View {
        HStack(spacing: 10) {
            muteButton(side: side)
            if let level = audio.volume {
                Slider(value: Binding(get: { audio.muted ? 0 : level }, set: { audio.set(volume: $0) }), in: 0...1)
                    .controlSize(size == .large ? .regular : .small)
                    .tint(accent)
                    .accessibilityLabel(tr("总音量"))
            } else {
                Text(verbatim: tr("此设备不支持调节音量"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            deviceLine(13)
            bigPercent(40)
            Spacer(minLength: 0)
            sliderRow(side: 30)
        }
    }

    private var medium: some View {
        let picked = OutputDevices.visible(audio.devices, current: audio.currentID,
                                           limit: DesktopCardsFilesPlan.rows(.volume, size: .medium))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                bigPercent(34)
                deviceLine(14)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(picked.shown) { device in
                    deviceChip(device)
                }
                if picked.overflow > 0 {
                    Button { OutputMenu.popUp(devices: audio.devices, current: audio.currentID) } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.panelSecondary)
                            .frame(width: 40, height: 36)
                            .background(DCFRowBackground())
                            .contentShape(.rect(cornerRadius: DCF.rowCorner))
                    }
                    .buttonStyle(.plain)
                    .help(tr("全部输出设备"))
                    .accessibilityLabel(tr("全部输出设备"))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            sliderRow(side: 30)
        }
    }

    private func deviceChip(_ device: OutputDevice) -> some View {
        let selected = device.id == audio.currentID
        return Button {
            if !selected { audio.select(device) }
        } label: {
            Image(systemName: OutputDevices.symbol(for: device))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                .frame(width: 52, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: DCF.rowCorner, style: .continuous)
                        .fill(selected ? accent.opacity(0.28) : Color.panelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: DCF.rowCorner, style: .continuous)
                                .strokeBorder(selected ? accent.opacity(0.6) : Color.panelStroke, lineWidth: 0.8)
                        }
                }
                .contentShape(.rect(cornerRadius: DCF.rowCorner))
        }
        .buttonStyle(.plain)
        .help(device.name)
        .accessibilityLabel(selected ? tr("\(device.name)（正在使用）") : tr("切换到 \(device.name)"))
    }

    private var large: some View {
        let limit = DesktopCardsFilesPlan.rows(.volume, size: .large)
        let all = audio.devices
        let picked = OutputDevices.visible(all, current: audio.currentID, limit: all.count > limit ? limit - 1 : limit)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                bigPercent(40)
                deviceLine(14)
                Spacer(minLength: 0)
            }
            .frame(height: 48)
            sliderRow(side: 34)
            Text(verbatim: tr("输出设备"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.top, 2)
            VStack(spacing: 4) {
                ForEach(picked.shown) { device in
                    deviceRow(device)
                }
                if picked.overflow > 0 {
                    Button { OutputMenu.popUp(devices: all, current: audio.currentID) } label: {
                        HStack {
                            Text(verbatim: tr("全部输出设备…"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.panelPrimary)
                            Spacer(minLength: 0)
                            Text(verbatim: "+\(picked.overflow)")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.panelSecondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(DCFRowBackground())
                        .contentShape(.rect(cornerRadius: DCF.rowCorner))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func deviceRow(_ device: OutputDevice) -> some View {
        let selected = device.id == audio.currentID
        return Button {
            if !selected { audio.select(device) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: OutputDevices.symbol(for: device))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? accent.panelReadable : Color.panelSecondary)
                    .frame(width: 20)
                Text(verbatim: device.name)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent.panelReadable)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(DCFRowBackground(highlighted: selected))
            .contentShape(.rect(cornerRadius: DCF.rowCorner))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? tr("\(device.name)（正在使用）") : tr("切换到 \(device.name)"))
    }
}
