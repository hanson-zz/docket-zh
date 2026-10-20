import AppKit
import SwiftUI

/// 相册面板，照第二批效果图分两个状态：
///
/// - 浏览：大图（卡片正在放的那张，左下“8 分钟后换下一张”），上一张 / 暂停 /
///   下一张，“接下来”八张小图，悬停一张点“排除”就不再轮到它（刚排除的那张
///   标“已排除”，再点一下撤销）。点照片在默认 App（多半是预览）里打开，拖出去
///   就是文件。
/// - 设置：右上“设置”进入。轮播的文件夹（可以多个，免费；勾掉的暂时不放，
///   右键移除或在访达中打开），“添加文件夹…”，已排除的照片（点右上角恢复这张，
///   “全部恢复”），换一张的间隔（1 分钟、10 分钟、1 小时、每天），随机顺序，
///   那年今天优先（照片图库里往年今天拍的排在最前面）。
///
/// 轮到哪张、暂停、排除都写在卡片配置里（见 `PhotoRotation`），卡片和面板永远
/// 是同一张，重启后也接着放。
struct PhotoFrameDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    private enum Mode { case browse, edit }

    @State private var mode: Mode = .browse
    /// 每写一次加一，面板跟着重读存着的配置。
    @State private var revision = 0
    /// 这次打开面板后刚排除的，在“接下来”里留着标“已排除”，点一下撤销。
    @State private var justExcluded: [String] = []
    @State private var hovered: String?
    /// 加文件夹满了之类的一行提示。
    @State private var notice: String?

    private static let accentHex = "#FF8FB1"
    private static let inkHex = "#3A0716"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }

    private static let pictureHeight: CGFloat = 196

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance {
        _ = revision
        return WidgetWriter.current(instance.id) ?? instance
    }
    private var album: PhotoAlbum {
        PhotoAlbum(config: current.config, wide: current.config.string("layout", default: "standard") == "wide")
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: Color(hex: Self.accentHex))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .browse: browse
                case .edit: edit
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            album.start(now: context.now)
            for feed in album.feeds { feed.refresh(force: true) }
        }
        .onChange(of: album.activeFolders) { _, _ in
            if !context.isPreview { album.start(now: context.now) }
        }
    }

    // MARK: 写

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        let item = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(item, change)
        revision += 1
    }

    /// 改顺序之前先锚到正在显示的这张（保留倒计时），改完它还在就接着放它。
    private func writeKeepingCurrent(_ change: (inout WidgetConfig) -> Void) {
        let before = album
        let state = PhotoRotation.reanchored(at: .now, order: before.order(), state: before.state,
                                             interval: before.interval)
        write { config in
            PhotoRotation.write(state, to: &config)
            change(&config)
        }
    }

    private func switchTo(_ next: Mode) {
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            hovered = nil
            notice = nil
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private var browse: some View {
        let album = self.album
        let order = album.order()
        let lookup = album.lookup
        let state = album.state
        let now = context.now
        let position = PhotoRotation.position(at: now, order: order, state: state, interval: album.interval)
        let shown = position.flatMap { lookup[order[$0]] }

        AlbumHeader(title: tr("相册"), subtitle: subtitle(album, count: order.count)) {
            if !context.isPreview {
                AlbumHeaderButton(title: tr("设置")) { switchTo(.edit) }
                    .help(tr("放哪些照片、多久换一张"))
            }
        }

        if context.isPreview {
            SamplePicture()
                .frame(height: Self.pictureHeight)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            controls(enabled: false, paused: false, album: album, order: order)
        } else if let shown {
            bigPicture(shown, album: album, order: order)
            controls(enabled: order.count > 1 || state.isPaused, paused: state.isPaused, album: album, order: order)
            upcoming(album: album, order: order, lookup: lookup, now: now)
            Text(verbatim: tr("点照片在预览里打开 · 拖出去就能用"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        } else {
            emptyContent(album: album)
        }
    }

    private func subtitle(_ album: PhotoAlbum, count: Int) -> String {
        if context.isPreview { return tr("图片 · 248 张") }
        let folders = album.activeFolders
        let name = folders.count == 1 ? PhotoAlbum.folderName(folders[0]) : tr("\(folders.count) 个文件夹")
        if album.loading { return tr("\(name) · 正在读取") }
        return tr("\(name) · \(count) 张")
    }

    private func bigPicture(_ item: PhotoAlbum.Item, album: PhotoAlbum, order: [String]) -> some View {
        AlbumThumb(item: item, pixels: 720)
            .id(item.id)
            .transition(.opacity)
            .frame(maxWidth: .infinity)
            .frame(height: Self.pictureHeight)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.6), value: item.id)
            .overlay(alignment: .bottomLeading) {
                badge(album: album, count: order.count, item: item)
                    .padding(10)
            }
            .contentShape(.rect(cornerRadius: 12))
            .onTapGesture { open(item) }
            .onDrag { dragProvider(item) }
            .help(item.fileURL?.lastPathComponent ?? tr("那年今天"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.fileURL?.lastPathComponent ?? tr("那年今天"))
            .accessibilityAddTraits(.isButton)
    }

    /// 大图左下的小胶囊：几分钟后换下一张，暂停时写“已暂停”。
    @ViewBuilder
    private func badge(album: PhotoAlbum, count: Int, item: PhotoAlbum.Item) -> some View {
        let text: String? = {
            if album.state.isPaused { return tr("已暂停") }
            guard let left = PhotoRotation.secondsToNext(at: context.now, count: count, state: album.state,
                                                         interval: album.interval) else { return nil }
            return PhotoRotation.countdownText(left)
        }()
        if let text {
            HStack(spacing: 5) {
                if case .memory = item {
                    Text(verbatim: tr("那年今天"))
                        .font(.system(size: 13, weight: .bold))
                    Text(verbatim: "·").opacity(0.6)
                }
                Text(verbatim: text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(.black.opacity(0.45)))
            .environment(\.colorScheme, .dark)
        }
    }

    private func controls(enabled: Bool, paused: Bool, album: PhotoAlbum, order: [String]) -> some View {
        HStack(spacing: 6) {
            AlbumControlButton(title: tr("上一张"), symbol: nil, accent: accent, ink: ink,
                               enabled: enabled && order.count > 1) { step(-1, album: album, order: order) }
            AlbumControlButton(title: paused ? tr("继续") : tr("暂停"), symbol: nil, accent: accent, ink: ink,
                               enabled: enabled) { togglePause(album: album, order: order) }
            AlbumControlButton(title: tr("下一张"), symbol: nil, prominent: true, accent: accent, ink: ink,
                               enabled: enabled && order.count > 1) { step(1, album: album, order: order) }
        }
    }

    private func step(_ by: Int, album: PhotoAlbum, order: [String]) {
        let next = PhotoRotation.stepped(by, at: .now, order: order, state: album.state, interval: album.interval)
        write { PhotoRotation.write(next, to: &$0) }
    }

    private func togglePause(album: PhotoAlbum, order: [String]) {
        let next = album.state.isPaused
            ? PhotoRotation.resumed(at: .now, order: order, state: album.state, interval: album.interval)
            : PhotoRotation.paused(at: .now, order: order, state: album.state, interval: album.interval)
        write { PhotoRotation.write(next, to: &$0) }
    }

    // MARK: 接下来

    @ViewBuilder
    private func upcoming(album: PhotoAlbum, order: [String], lookup: [String: PhotoAlbum.Item], now: Date) -> some View {
        // 刚排除的几张先当作还在，排在原来的位置上标“已排除”。
        let pending = justExcluded.filter { lookup[$0] != nil }
        let display = pending.isEmpty ? order : album.order(excluding: album.excluded.filter { !pending.contains($0) })
        let currentID = PhotoRotation.current(at: now, order: order, state: album.state, interval: album.interval)
        let ids = Self.after(currentID, in: display, count: PhotoRotation.upcomingCount)
        if !ids.isEmpty {
            AlbumSection(label: tr("接下来"), right: tr("悬停可排除"))
                .padding(.top, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    upcomingCell(id: id, item: lookup[id], excluded: pending.contains(id), album: album, order: order)
                }
            }
        }
    }

    /// `display` 里 `id` 之后的几张（不含它自己）。
    private static func after(_ id: String?, in display: [String], count: Int) -> [String] {
        guard !display.isEmpty else { return [] }
        let start = id.flatMap { display.firstIndex(of: $0) } ?? -1
        let n = min(count, display.count - (start >= 0 ? 1 : 0))
        guard n > 0 else { return [] }
        return (1...n).map { display[(start + $0 + display.count) % display.count] }
    }

    private func upcomingCell(id: String, item: PhotoAlbum.Item?, excluded: Bool,
                              album: PhotoAlbum, order: [String]) -> some View {
        let hover = hovered == id
        let name: String = item?.fileURL?.lastPathComponent ?? tr("那年今天")
        let tip: String = excluded ? tr("点一下撤销排除") : name
        let spoken: String = excluded ? tr("已排除") : name
        let actionName: String = excluded ? tr("撤销") : tr("排除")
        return AlbumThumb(item: item, pixels: 200)
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if excluded {
                    Color.black.opacity(0.7)
                    Text(verbatim: tr("已排除"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                } else if hover {
                    Color.black.opacity(0.5)
                }
            }
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .bottom) {
                if hover, !excluded {
                    Button { exclude(id, album: album, order: order) } label: {
                        Text(verbatim: tr("排除"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#222222"))
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(Capsule().fill(.white.opacity(0.92)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 6)
                    .help(tr("不再轮到这张，可在设置里恢复"))
                }
            }
            .contentShape(.rect(cornerRadius: 7))
            .onHover { inside in
                if inside { hovered = id } else if hovered == id { hovered = nil }
            }
            .onTapGesture {
                if excluded {
                    undoExclude(id)
                } else if let item {
                    open(item)
                }
            }
            .onDrag { dragProvider(item) }
            .help(tip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAction(named: Text(verbatim: actionName)) {
                if excluded { undoExclude(id) } else { exclude(id, album: album, order: order) }
            }
    }

    private func exclude(_ id: String, album: PhotoAlbum, order: [String]) {
        let state = PhotoRotation.reanchored(at: .now, order: order, state: album.state,
                                             interval: album.interval, removing: id)
        write { config in
            PhotoRotation.write(state, to: &config)
            PhotoRotation.exclude(id, in: &config)
        }
        hovered = nil
        if !justExcluded.contains(id) { justExcluded.append(id) }
    }

    private func undoExclude(_ id: String) {
        writeKeepingCurrent { PhotoRotation.restore(id, in: &$0) }
        justExcluded.removeAll { $0 == id }
    }

    // MARK: 空的时候

    @ViewBuilder
    private func emptyContent(album: PhotoAlbum) -> some View {
        if album.activeFolders.isEmpty {
            AlbumNote(symbol: "folder", text: tr("没有勾选的文件夹。点“设置”勾选一个，或添加文件夹。"))
                .frame(height: Self.pictureHeight)
        } else if let failure = album.failure {
            AlbumNote(symbol: "lock", text: failure.text, privacy: failure.denied).frame(height: Self.pictureHeight)
        } else if album.loading {
            AlbumNote(symbol: "hourglass", text: tr("正在读取…")).frame(height: Self.pictureHeight)
        } else if !album.files.isEmpty || !album.memories.isEmpty {
            // 有图片，但都排除了。
            VStack(spacing: 10) {
                AlbumNote(symbol: "eye.slash", text: tr("这里的照片都排除了"))
                AlbumHeaderButton(title: tr("全部恢复"), solid: true, accent: accent, ink: ink) {
                    writeKeepingCurrent { PhotoRotation.restoreAll(in: &$0) }
                    justExcluded = []
                }
            }
            .frame(height: Self.pictureHeight)
        } else {
            PandaEmptyState(empty: .photos, title: tr("选择相册"), panel: true, action: addFolder)
                .frame(height: Self.pictureHeight)
        }
    }

    // MARK: 设置

    @ViewBuilder
    private var edit: some View {
        let album = self.album
        AlbumHeader(title: tr("相册设置"), subtitle: tr("放哪些照片 · 多久换一张")) {
            AlbumHeaderButton(title: tr("完成"), solid: true, accent: accent, ink: ink) { switchTo(.browse) }
        }
        .padding(.bottom, 4)

        AlbumSection(label: tr("轮播文件夹"))
        VStack(spacing: 6) {
            ForEach(PhotoRotation.folders(album.config), id: \.self) { path in
                folderRow(path, config: album.config)
            }
            addFolderButton
            if let notice {
                Text(verbatim: notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }

        excludedSection(album)

        AlbumSection(label: tr("换一张的间隔"))
            .padding(.top, 6)
        AlbumSegmented(labels: PhotoRotation.intervalChoices.map(PhotoRotation.intervalTitle),
                       selected: PhotoRotation.choiceIndex(album.interval),
                       accent: accent, ink: ink) { index in
            setInterval(PhotoRotation.intervalChoices[index], album: album)
        }
        if PhotoRotation.choiceIndex(album.interval) == nil {
            Text(verbatim: tr("现在是每 \(PhotoRotation.intervalTitle(album.interval)) 换一张"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
        }

        AlbumToggleRow(label: tr("随机顺序"), isOn: album.shuffle, accent: accent) { on in
            writeKeepingCurrent { $0.set(PhotoRotation.shuffleKey, .bool(on)) }
        }
        .padding(.top, 2)
        AlbumToggleRow(label: tr("那年今天优先"), sub: tr("照片图库里往年今天拍的"),
                       isOn: album.memoriesFirst, accent: accent) { on in
            writeKeepingCurrent { $0.set(PhotoRotation.memoriesFirstKey, .bool(on)) }
            if on { PhotoMemories.shared.requestIfNeeded(now: .now) }
        } note: {
            memoriesNote(album)
        }
    }

    @ViewBuilder
    private func memoriesNote(_ album: PhotoAlbum) -> some View {
        let memories = PhotoMemories.shared
        if album.memoriesFirst, !context.isPreview {
            if memories.access == .denied {
                HStack(spacing: 4) {
                    Text(verbatim: tr("没有照片图库的权限"))
                    Button(tr("打开隐私设置")) { memories.openPrivacySettings() }
                        .buttonStyle(.plain)
                        .underline()
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
            } else if memories.access == .granted, memories.memories.isEmpty {
                Text(verbatim: tr("今天没有往年的照片，先放文件夹"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private func folderRow(_ path: String, config: WidgetConfig) -> some View {
        let on = PhotoRotation.isFolderOn(path, config)
        let feed = FolderFeed.shared(.pictures(path))
        let count: String = {
            guard !context.isPreview else { return "" }
            if feed.error != nil { return tr("无法访问") }
            guard feed.loadedAt != nil else { return on ? tr("正在读取") : "" }
            return tr("\(feed.files.count) 张")
        }()
        return Button {
            writeKeepingCurrent { PhotoRotation.setFolder(path, on: !on, in: &$0) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accent.opacity(0.9))
                    .frame(width: 24)
                Text(verbatim: PhotoAlbum.folderName(path))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(on ? 1 : 0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text(verbatim: count)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: 0)
                AlbumCheck(on: on, accent: accent, ink: ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassPane(cornerRadius: 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(FolderFeed.folder(for: .pictures(path)).path)
        .onAppear { if on, !context.isPreview { feed.start() } }
        .contextMenu {
            Button(tr("在访达中打开")) { FileActions.openFolder(FolderFeed.folder(for: .pictures(path))) }
            Button(tr("移除这个文件夹"), role: .destructive) {
                writeKeepingCurrent { PhotoRotation.removeFolder(path, from: &$0) }
            }
        }
    }

    private var addFolderButton: some View {
        Button(action: addFolder) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24)
                Text(verbatim: tr("添加文件夹…"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    @ViewBuilder
    private func excludedSection(_ album: PhotoAlbum) -> some View {
        let ids: [String] = album.excluded
        let lookup = album.lookup
        let right: String? = ids.isEmpty ? nil : tr("全部恢复")
        let action: (() -> Void)? = ids.isEmpty ? nil : { restoreAll() }
        AlbumSection(label: tr("已排除 \(ids.count) 张"), right: right, rightColor: accent, rightAction: action)
            .padding(.top, 6)
        if ids.isEmpty {
            Text(verbatim: tr("浏览时悬停在照片上点“排除”，就不再轮到它"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let rows = (ids.count + 4) / 5
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(ids.reversed(), id: \.self) { id in
                        excludedCell(id, item: lookup[id])
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: rows > 1 ? 2 * 44 + 6 : 44)
            Text(verbatim: tr("点右上角恢复这张"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func restoreAll() {
        writeKeepingCurrent { PhotoRotation.restoreAll(in: &$0) }
        justExcluded = []
    }

    private func excludedCell(_ id: String, item: PhotoAlbum.Item?) -> some View {
        let tip: String
        if let item {
            tip = item.fileURL?.lastPathComponent ?? tr("那年今天")
        } else {
            tip = tr("找不到这张了")
        }
        return AlbumThumb(item: item, pixels: 160)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .overlay { Color.black.opacity(0.55) }
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    writeKeepingCurrent { PhotoRotation.restore(id, in: &$0) }
                    justExcluded.removeAll { $0 == id }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: "#222222"))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.9)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(3)
                .help(tr("恢复这张"))
                .accessibilityLabel(tr("恢复这张"))
            }
            .help(tip)
    }

    private func setInterval(_ seconds: Double, album: PhotoAlbum) {
        // 从现在起按新间隔算，正在看的这张不跳。
        let order = album.order()
        let here = PhotoRotation.current(at: .now, order: order, state: album.state, interval: album.interval)
        let now = Date.now.timeIntervalSinceReferenceDate
        let state = PhotoRotation.State(anchor: here, anchorAt: now,
                                        pausedAt: album.state.isPaused ? now : nil)
        write { config in
            PhotoRotation.write(state, to: &config)
            config.set(PhotoRotation.intervalKey, .number(seconds))
        }
    }

    // MARK: 打开、拖出、加文件夹

    private func open(_ item: PhotoAlbum.Item) {
        guard !context.isPreview else { return }
        switch item {
        case .file(let file): FileActions.open(file.url)
        case .memory:
            // 照片图库里的照片在“照片”App 里看。
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func dragProvider(_ item: PhotoAlbum.Item?) -> NSItemProvider {
        guard let url = item?.fileURL else { return NSItemProvider() }
        return FileActions.dragProvider(url)
    }

    private func addFolder() {
        guard !context.isPreview else { return }
        let start = album.activeFolders.first.map { FolderFeed.folder(for: .pictures($0)) }
        // 面板会在点进打开面板时收起，选好的照样写回卡片。
        guard let url = FileActions.chooseFolder(title: tr("选择相册要轮播的文件夹"), startingAt: start) else { return }
        var added = true
        writeKeepingCurrent { added = PhotoRotation.addFolder(url.path, to: &$0) }
        notice = added ? nil : tr("最多 \(PhotoRotation.maxFolders) 个文件夹")
    }
}
