import AppKit
import SwiftUI

/// 相册面板。标准和宽幅各一套浏览页，设置页共用：
///
/// - 标准：单张为主。大图优先完整画面（显示方式见设置），下面“第 12 / 300 张”
///   和真实剩余的换图时间，上一张 / 暂停 / 下一张，“接下来”4×2 八张小图。
/// - 宽幅：和宽幅小组件的胶片条一个样子，主图旁边上下两张接下来的小图；下面
///   拍摄日期、地点、那年今天（没有的字段不写），序号和倒计时、同样位置的三个
///   按钮，最底下一行露 4 张预览，横着滑看更多。
///
/// 两套都是：点照片在默认 App（多半是预览）里打开，拖出去就是文件；悬停缩略图
/// 右上角出一个小“…”，里面是排除 / 撤销排除、打开原图（刚排除的那张留在原位
/// 标“已排除”，点一下撤销）。
///
/// 设置：显示方式（完整显示 / 铺满裁切）、轮播的文件夹（可以多个，勾掉的暂时
/// 不放，右键移除或在访达中打开）、已排除的照片（点右上角恢复这张，“全部恢复”）、
/// 换一张的间隔、随机顺序、那年今天优先。
///
/// 轮到哪张、暂停、排除、显示方式都写在这张卡片自己的配置里（见 `PhotoRotation`、
/// `PhotoAlbumPanel`），卡片和面板永远是同一张，两张相册卡片互不串，重启后也
/// 接着放。标准、宽幅共用同一个锚点，换样式时正在放的那张和倒计时都不变。
struct PhotoFrameDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    private enum Mode { case browse, edit }

    @State private var mode: Mode = .browse
    /// 每写一次加一，面板跟着重读存着的配置。
    @State private var revision = 0
    /// 这次打开面板后刚排除的，在预览里留着标“已排除”，点一下撤销。
    @State private var justExcluded: [String] = []
    @State private var hovered: String?
    /// 加文件夹满了之类的一行提示。
    @State private var notice: String?

    private static let accentHex = "#FF8FB1"
    private static let inkHex = "#3A0716"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }

    /// 标准大图的高度。
    private static let pictureHeight: CGFloat = 210
    /// 宽幅胶片条的高度和右边小图的宽度。
    private static let stripHeight: CGFloat = 176
    private static let stripNextWidth: CGFloat = 78
    private static let gap: CGFloat = 6
    /// 宽幅底部横向预览一行的高度（约 4:3）。
    private static let previewRowHeight: CGFloat = 52

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance {
        _ = revision
        return WidgetWriter.current(instance.id) ?? instance
    }
    private var layout: PhotoAlbumPanel.Layout { PhotoAlbumPanel.layout(current.config) }
    private var album: PhotoAlbum { PhotoAlbum(config: current.config, wide: layout == .wide) }
    private var memories: PhotoMemories { PhotoMemories.shared }

    /// 面板跟浅色/深色外观走（液态玻璃底，不铺固定深色）；压在照片上的字和
    /// 小黑圆保持白字（底是照片不是玻璃）。
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
            var config = current.config
            if PhotoAlbumPanel.migrate(&config) { write { _ = PhotoAlbumPanel.migrate(&$0) } }
            album.start(now: context.now)
            for feed in album.feeds { feed.refresh(force: true) }
        }
        .onChange(of: album.activeFolders) { _, _ in
            if !context.isPreview { album.start(now: context.now) }
        }
        .onChange(of: layout) { _, _ in
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
        let now = context.now
        let position = PhotoRotation.position(at: now, order: order, state: album.state, interval: album.interval)
        let shown = position.flatMap { lookup[order[$0]] }

        AlbumHeader(title: PhotoAlbumPanel.title(layout), subtitle: subtitle(album, count: order.count)) {
            if !context.isPreview {
                AlbumHeaderButton(title: tr("设置")) { switchTo(.edit) }
                    .help(tr("显示方式、放哪些照片、多久换一张"))
            }
        }

        if context.isPreview {
            previewBrowse(album: album)
        } else if let position, let shown {
            switch layout {
            case .standard:
                standardPicture(shown, album: album)
            case .wide:
                wideStrip(shown, album: album, order: order, lookup: lookup, now: now)
                wideCaption(shown, now: now)
            }
            AlbumStatusRow(position: PhotoAlbumPanel.positionText(index: position, count: order.count),
                           status: status(album: album, count: order.count))
            controls(enabled: order.count > 1 || album.state.isPaused, paused: album.state.isPaused,
                     album: album, order: order)
            previews(album: album, order: order, lookup: lookup, now: now)
        } else {
            emptyContent(album: album)
        }
    }

    /// 添加小组件时的样子：不读磁盘，画示意图。
    @ViewBuilder
    private func previewBrowse(album: PhotoAlbum) -> some View {
        switch layout {
        case .standard:
            SamplePicture()
                .frame(height: Self.pictureHeight)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
        case .wide:
            HStack(spacing: 3) {
                SamplePicture().frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 3) {
                    SamplePicture(symbol: "sun.max.fill").frame(maxWidth: .infinity, maxHeight: .infinity)
                    SamplePicture(symbol: "leaf.fill").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: Self.stripNextWidth)
            }
            .frame(height: Self.stripHeight)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            captionLine(PhotoAlbumPanel.Caption(onThisDay: true, date: "2024.10.18", place: tr("杭州")))
        }
        AlbumStatusRow(position: PhotoAlbumPanel.positionText(index: 11, count: 248),
                       status: PhotoRotation.countdownText(480))
        controls(enabled: false, paused: false, album: album, order: [])
    }

    private func subtitle(_ album: PhotoAlbum, count: Int) -> String {
        if context.isPreview { return tr("图片 · 248 张") }
        let folders = album.activeFolders
        let name: String
        if folders.isEmpty {
            name = tr("那年今天")
        } else {
            name = folders.count == 1 ? PhotoAlbum.folderName(folders[0]) : tr("\(folders.count) 个文件夹")
        }
        if album.loading { return tr("\(name) · 正在读取") }
        return tr("\(name) · \(count) 张")
    }

    private func status(album: PhotoAlbum, count: Int) -> String? {
        PhotoAlbumPanel.statusText(
            paused: album.state.isPaused,
            secondsToNext: PhotoRotation.secondsToNext(at: context.now, count: count, state: album.state,
                                                       interval: album.interval))
    }

    // MARK: 标准：单张大图

    private func standardPicture(_ item: PhotoAlbum.Item, album: PhotoAlbum) -> some View {
        mainPicture(item, album: album)
            .frame(maxWidth: .infinity)
            .frame(height: Self.pictureHeight)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if case .memory = item {
                    Text(verbatim: tr("那年今天"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                }
            }
    }

    /// 正在放的这张：照显示方式画，点开原图，拖出去就是文件；说明放在工具提示里。
    private func mainPicture(_ item: PhotoAlbum.Item, album: PhotoAlbum) -> some View {
        let name = item.fileURL?.lastPathComponent ?? tr("那年今天")
        // 原来压在面板底部的一行说明，挪到工具提示里。
        let tip = name + "\n" + tr("点照片在预览里打开 · 拖出去就能用")
        return AlbumPicture(item: item, pixels: 720, fit: album.fit)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.6), value: item.id)
            .contentShape(.rect)
            .onTapGesture { open(item) }
            .onDrag { dragProvider(item) }
            .help(tip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: 宽幅：胶片条

    /// 和宽幅小组件一样的胶片条：左边主图，右边上下两张接下来要放的。
    private func wideStrip(_ item: PhotoAlbum.Item, album: PhotoAlbum, order: [String],
                           lookup: [String: PhotoAlbum.Item], now: Date) -> some View {
        let next = PhotoRotation.upcoming(at: now, order: order, state: album.state, interval: album.interval,
                                          count: PhotoAlbumPanel.stripNext)
        return HStack(spacing: 3) {
            mainPicture(item, album: album)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(spacing: 3) {
                ForEach(next, id: \.self) { id in
                    thumbCell(id: id, item: lookup[id], excluded: false, album: album, order: order,
                              aspect: nil, corner: 0)
                }
                // 只有一两张照片时，空出来的格子垫一层浅底，不留洞。
                ForEach(0..<max(0, PhotoAlbumPanel.stripNext - next.count), id: \.self) { _ in
                    Color.panelShade.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: Self.stripNextWidth)
        }
        .frame(height: Self.stripHeight)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    /// 拍摄日期、地点、那年今天；照片没带的字段不写，一个都没有时整行不占地方。
    @ViewBuilder
    private func wideCaption(_ item: PhotoAlbum.Item, now: Date) -> some View {
        let caption: PhotoAlbumPanel.Caption = {
            switch item {
            case .memory(let shown):
                let place = memories.place(key: shown.id, latitude: shown.latitude, longitude: shown.longitude)
                return PhotoAlbumPanel.caption(date: shown.date, place: place, today: now)
            case .file(let file):
                guard let meta = memories.meta(for: file.url) else { return PhotoAlbumPanel.Caption() }
                let place = memories.place(key: file.url.path, latitude: meta.latitude, longitude: meta.longitude)
                return PhotoAlbumPanel.caption(date: meta.date, place: place, today: now)
            }
        }()
        if !caption.isEmpty { captionLine(caption) }
    }

    private func captionLine(_ caption: PhotoAlbumPanel.Caption) -> some View {
        HStack(spacing: 8) {
            if caption.onThisDay {
                Text(verbatim: tr("那年今天"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(accent))
            }
            if let date = caption.date {
                Label {
                    Text(verbatim: date).monospacedDigit()
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(.panelPrimary)
            }
            if let place = caption.place {
                Label {
                    Text(verbatim: place)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .foregroundStyle(.panelSecondary)
                .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    // MARK: 控制

    private func controls(enabled: Bool, paused: Bool, album: PhotoAlbum, order: [String]) -> some View {
        HStack(spacing: Self.gap) {
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
    private func previews(album: PhotoAlbum, order: [String], lookup: [String: PhotoAlbum.Item],
                          now: Date) -> some View {
        // 刚排除的几张先当作还在，排在原来的位置上标“已排除”。
        let pending = justExcluded.filter { lookup[$0] != nil }
        let display = pending.isEmpty ? order : album.order(excluding: album.excluded.filter { !pending.contains($0) })
        let currentID = PhotoRotation.current(at: now, order: order, state: album.state, interval: album.interval)
        let others = max(0, display.count - 1)
        switch layout {
        case .standard:
            let ids = PhotoAlbumPanel.after(currentID, in: display,
                                            count: PhotoAlbumPanel.previewCount(.standard, others: others))
            if !ids.isEmpty {
                AlbumSection(label: tr("接下来"), right: tr("悬停点“…”可排除"))
                    .padding(.top, 2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap),
                                         count: PhotoAlbumPanel.gridColumns),
                          spacing: Self.gap) {
                    ForEach(ids, id: \.self) { id in
                        thumbCell(id: id, item: lookup[id], excluded: pending.contains(id), album: album,
                                  order: order, aspect: 4 / 3, corner: 7)
                    }
                }
            }
        case .wide:
            let offset = PhotoAlbumPanel.widePreviewOffset(others: others)
            let count = PhotoAlbumPanel.previewCount(.wide, others: others - offset)
            let ids = Array(PhotoAlbumPanel.after(currentID, in: display, count: offset + count).dropFirst(offset))
            if !ids.isEmpty {
                AlbumSection(label: tr("接下来"),
                             right: ids.count > PhotoAlbumPanel.wideVisible ? tr("横向滑动看更多") : nil)
                    .padding(.top, 2)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Self.gap) {
                        ForEach(ids, id: \.self) { id in
                            // 一行正好露 4 张，宽度跟面板走，高度固定。
                            thumbCell(id: id, item: lookup[id], excluded: pending.contains(id), album: album,
                                      order: order, aspect: nil, corner: 7)
                                .containerRelativeFrame(.horizontal, count: PhotoAlbumPanel.wideVisible,
                                                        spacing: Self.gap)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: Self.previewRowHeight)
            }
        }
    }

    /// 一张缩略图：点开原图（已排除的点一下撤销），拖出去就是文件；悬停时右上角
    /// 一个小“…”，不再盖一层大遮罩。`aspect` 为 nil 时撑满分到的地方（胶片条）。
    private func thumbCell(id: String, item: PhotoAlbum.Item?, excluded: Bool, album: PhotoAlbum,
                           order: [String], aspect: CGFloat?, corner: CGFloat) -> some View {
        let hover = hovered == id
        let name: String = item?.fileURL?.lastPathComponent ?? tr("那年今天")
        let tip: String = excluded ? tr("点一下撤销排除") : name
        let spoken: String = excluded ? tr("已排除") : name
        let actions = PhotoAlbumPanel.thumbActions(excluded: excluded, canOpen: item != nil)
        return AlbumThumb(item: item, pixels: 200)
            .albumAspect(aspect)
            .opacity(excluded ? 0.4 : 1)
            .clipShape(.rect(cornerRadius: corner, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if excluded {
                    Text(verbatim: tr("已排除"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .environment(\.colorScheme, .dark)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                AlbumThumbMenu(actions: actions) { action in
                    perform(action, id: id, item: item, album: album, order: order)
                }
                .padding(4)
                .opacity(hover ? 1 : 0)
                .allowsHitTesting(hover)
            }
            .contentShape(.rect(cornerRadius: corner))
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
            .accessibilityAction(named: Text(verbatim: excluded ? tr("撤销排除") : tr("排除"))) {
                if excluded { undoExclude(id) } else { exclude(id, album: album, order: order) }
            }
    }

    private func perform(_ action: PhotoAlbumPanel.ThumbAction, id: String, item: PhotoAlbum.Item?,
                         album: PhotoAlbum, order: [String]) {
        switch action {
        case .exclude: exclude(id, album: album, order: order)
        case .undo: undoExclude(id)
        case .open: if let item { open(item) }
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

    private var emptyHeight: CGFloat { layout == .wide ? Self.stripHeight : Self.pictureHeight }

    @ViewBuilder
    private func emptyContent(album: PhotoAlbum) -> some View {
        let failure = album.failure
        let empty = PhotoAlbumPanel.empty(activeFolders: album.activeFolders.count, loading: album.loading,
                                          failed: failure != nil, denied: failure?.denied ?? false,
                                          total: album.files.count + album.memories.count)
        switch empty {
        case .noFolder:
            VStack(spacing: 10) {
                AlbumNote(symbol: "folder", text: PhotoAlbumPanel.emptyText(empty))
                AlbumHeaderButton(title: tr("设置"), solid: true, accent: accent, ink: ink) { switchTo(.edit) }
            }
            .frame(height: emptyHeight)
        case .denied:
            AlbumNote(symbol: "lock", text: PhotoAlbumPanel.emptyText(empty), privacy: true)
                .frame(height: emptyHeight)
        case .failed:
            VStack(spacing: 10) {
                AlbumNote(symbol: "exclamationmark.triangle", text: failure?.text ?? PhotoAlbumPanel.emptyText(empty))
                AlbumHeaderButton(title: tr("换一个文件夹…"), solid: true, accent: accent, ink: ink, action: addFolder)
            }
            .frame(height: emptyHeight)
        case .loading:
            AlbumNote(symbol: "hourglass", text: PhotoAlbumPanel.emptyText(empty)).frame(height: emptyHeight)
        case .allExcluded:
            VStack(spacing: 10) {
                AlbumNote(symbol: "eye.slash", text: PhotoAlbumPanel.emptyText(empty))
                AlbumHeaderButton(title: tr("全部恢复"), solid: true, accent: accent, ink: ink) { restoreAll() }
            }
            .frame(height: emptyHeight)
        case .emptyFolder:
            PandaEmptyState(empty: .photos, title: tr("选择相册"), panel: true,
                            message: PhotoAlbumPanel.emptyText(empty), action: addFolder)
                .frame(minHeight: emptyHeight)
        }
    }

    // MARK: 设置

    @ViewBuilder
    private var edit: some View {
        let album = self.album
        AlbumHeader(title: tr("相册设置"), subtitle: PhotoAlbumPanel.title(layout)) {
            AlbumHeaderButton(title: tr("完成"), solid: true, accent: accent, ink: ink) { switchTo(.browse) }
        }
        .padding(.bottom, 4)

        let fit = album.fit
        AlbumSection(label: tr("显示方式"))
        AlbumSegmented(labels: PhotoAlbumPanel.Fit.allCases.map(PhotoAlbumPanel.fitTitle),
                       selected: PhotoAlbumPanel.Fit.allCases.firstIndex(of: fit),
                       accent: accent, ink: ink) { index in
            let chosen = PhotoAlbumPanel.Fit.allCases[index]
            write { $0.set(PhotoAlbumPanel.fitKey, .string(chosen.rawValue)) }
        }
        Text(verbatim: fit == .fit ? tr("整张照片都在，竖图两边垫一层同图模糊底，不裁人物")
                                   : tr("铺满画面，超出的边缘会被裁掉"))
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .fixedSize(horizontal: false, vertical: true)

        AlbumSection(label: tr("轮播文件夹"))
            .padding(.top, 6)
        VStack(spacing: 6) {
            ForEach(PhotoRotation.folders(album.config), id: \.self) { path in
                folderRow(path, config: album.config)
            }
            addFolderButton
            if let notice {
                Text(verbatim: notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
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
                .foregroundStyle(.panelSecondary)
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
                .foregroundStyle(.panelSecondary)
            } else if memories.access == .granted, memories.memories.isEmpty {
                Text(verbatim: tr("今天没有往年的照片，先放文件夹"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
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
                    .foregroundStyle(accent.panelGraphic.opacity(0.9))
                    .frame(width: 24)
                Text(verbatim: PhotoAlbum.folderName(path))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? .panelPrimary : .panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text(verbatim: count)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
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
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 24)
                Text(verbatim: tr("添加文件夹…"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.panelFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.panelQuaternary, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
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
        AlbumSection(label: tr("已排除 \(ids.count) 张"), right: right, rightColor: accent.panelReadable, rightAction: action)
            .padding(.top, 6)
        if ids.isEmpty {
            Text(verbatim: tr("浏览时悬停在缩略图上，点右上角“…”选“排除”，就不再轮到它"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
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
                .foregroundStyle(.panelSecondary)
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

private extension View {
    /// 网格和横向预览按 4:3 放；胶片条右边的小图撑满分到的地方，多出来的裁掉。
    @ViewBuilder
    func albumAspect(_ aspect: CGFloat?) -> some View {
        if let aspect {
            aspectRatio(aspect, contentMode: .fit).frame(maxWidth: .infinity)
        } else {
            frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }
    }
}
