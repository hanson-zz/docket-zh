import SwiftUI

/// The radio in the "弧光调谐" (arc tuner) look of meowRadio: a big channel
/// number and the station's name, an arc dial with a mark for every
/// favourite, the volume, a sleep timer, the favourites, and a search of the
/// Radio Browser directory.
///
/// The favourites and the tuned channel are written to the widget's config,
/// so the tile and this panel always show the same station.
///
/// 下半截“我的收藏”“搜索电台”“定时关闭”三页用一条分段切换，同时只开一页。
/// 没记过时（新用户）默认打开“我的收藏”，其余收起；再点一下打开的那页就收起，
/// 打开哪页（或都收起）记住。
///
/// 收藏上面一排“添加电台”（贴地址或导入 .m3u / .m3u8 / .pls，见
/// `RadioAddFlow`）和“检查”（试连收藏，见 `RadioStationCheck`）。有电台所有
/// 地址都连不上时顶部出一条可关闭的提示，点开列出来，确认后才删。
struct RadioDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    /// 下半截的三页。面板统一限高后可以全部收起：再点一下打开的那页就收起，
    /// 打开哪页（或都收起）记住；没记过时打开收藏，见 `DetailPanelSections.openPage`。
    private enum Tab: String, CaseIterable { case favourites, search, timer }

    private var player: RadioPlayer { RadioPlayer.shared }
    private var addFlow: RadioAddFlow { RadioAddFlow.shared }
    private var healthCheck: RadioStationCheck { RadioStationCheck.shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSlot

    /// 记着的那页；nil 是从没记过，空字符串是用户收起了。
    @AppStorage(DetailPanelSections.pageKey(.radio)) private var storedTab: String?
    /// 打开着的那页，nil 是都收起。没记过时是收藏。
    private var tab: Tab? {
        DetailPanelSections.openPage(stored: storedTab, available: Tab.allCases, initial: .favourites)
    }
    @State private var query = ""
    @State private var customName = ""
    @State private var results: [RadioStation] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var searched = false
    /// What the shown results answer, so the list can say what it is.
    @State private var shownQuery: RadioDirectory.Query?
    /// Bumped for every request; an answer that comes back after a newer
    /// request was made is dropped.
    @State private var requestID = 0
    /// The region picked in this panel, until the config written for it
    /// comes back.
    @State private var pickedRegion: RadioRegion?
    /// The slider's own value while dragging, so the profile is saved once
    /// at the end of the drag rather than sixty times during it.
    @State private var dragging: Double?
    /// 收藏行实际高度，见 `favouriteRowHeight`。
    @State private var classicRowHeight: CGFloat?
    @State private var retroRowHeight: CGFloat?
    /// 正在改名的收藏和输入框里的字。
    @State private var renamingID: String?
    @State private var renameText = ""
    /// “N 个电台连不上”提示展开着、正在问“确定删除？”。
    @State private var healthOpen = false
    @State private var confirmingDelete = false
    /// 关掉提示时记下的那一批（见 `RadioHealth.dismissToken`）。
    @State private var dismissedHealth: String?

    private var stations: [RadioStation] {
        context.isPreview ? RadioDial.presets : RadioDial.stations(instance.config)
    }
    private var index: Int {
        context.isPreview ? 0 : RadioDial.index(instance.config, count: stations.count)
    }
    private var station: RadioStation? { stations.isEmpty ? nil : stations[index] }
    private var volume: Double { dragging ?? instance.config.double("volume", default: 60) }
    private var playing: Bool { context.isPreview || player.plays(station) }
    private var region: RadioRegion {
        if let pickedRegion { return pickedRegion }
        return context.isPreview ? RadioRegion.fallback : RadioRegion.stored(instance.config)
    }

    /// 实际画的皮肤：经典以外都是 Pro，没解锁时画回经典（预览照常画）。
    private var skin: RadioSkin {
        ProLicenseGate.radioSkin(config: instance.config,
                                 unlocked: licenseUnlocked || supporterUnlocked || context.isPreview)
    }
    private var retro: Bool { skin.isRetro }
    /// 五款新外观（烟晶、灯阵、瓷白圆盘、掌机像素、墨白直尺），上半部分画在
    /// RadioSkins/ 下各自的文件里。
    private var modern: Bool { skin.isModern }
    /// 面板一律用新外观的暗色版（卡片才跟扩展栏深浅），下半截收藏列表也跟着暗色画。
    private var tone: RadioSkinTone { .dark }
    /// 新外观这一版的配色，经典和复古皮肤是 nil。
    private var palette: RadioSkinPalette? { RadioSkinPalette.palette(skin, tone: tone) }
    /// 面板里的字色：新外观跟调色板（浅色版是深色字），其余照旧白字。
    private var fg: Color { palette.map { Color(code: $0.text) } ?? .white }
    /// 新外观浅色版：卡片里的系统控件也要按浅色画。
    private var lightSkin: Bool { palette?.isLight ?? false }

    /// 复古皮肤用自己的琥珀、红、VFD 绿；新外观跟调色板；经典照旧跟颜色面板走。
    private var accent: Color {
        if let palette { return Color(code: palette.accent) }
        return retro ? skin.accent : panelTint.accent(or: RadioIcon.glow)
    }
    /// 压在深色底上的小字用的强调色：晶体管的红换浅一档；经典跟主题色时
    /// 按深色面板卡片调亮到 4.5:1，本来就够的颜色原样用。
    private var accentText: Color {
        if let palette { return Color(code: palette.accentText) }
        if retro { return skin.textAccent }
        guard let code = WidgetTintPicker.code(accent) else { return accent }
        return Color(code: WidgetTint.readable(code, dark: true, minimum: 4.5))
    }
    /// 收藏/搜索切换选中那一段：复古皮肤是皮肤强调色，经典跟主题色；字深色。
    private var segmentInk: Color {
        if let palette { return Color(code: palette.ink) }
        return retro ? skin.ink : panelTint.ink(or: RadioRetroInk.inkMetal)
    }
    private static let needle = Color(hex: "#FF453A")

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
        .onAppear {
            guard !context.isPreview else { return }
            dismissedHealth = RadioStationCheck.dismissed(instance.id)
            // 每天最多自动检查一次，在后台跑，不挡操作。
            healthCheck.checkIfDue(instance)
        }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            if let model = skinModel {
                RadioModernBackdrop(model: model)
            } else {
                MeshBackdrop(color: accent)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if showsHealthBanner { healthBanner }
                if let model = skinModel {
                    RadioModernPanel(model: model)
                } else if retro {
                    retroTop
                } else {
                    header
                    readout
                    RadioArcDial(count: stations.count, index: index, accent: accent, needle: Self.needle) { target in
                        guard !context.isPreview else { return }
                        RadioRemote.tune(instance, to: target)
                    }
                    .frame(height: 92)
                    transport
                    volumeRow
                }
                tabSwitch(now: now)
                switch tab {
                case .favourites?: favourites
                case .search?: search
                case .timer?: timerRow(now: now)
                case nil: EmptyView()
                }
                Link(destination: RadioBrowser.homepage) {
                    HStack(spacing: 3) {
                        Text(RadioBrowser.attribution)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(fg.opacity(0.62))
                }
                .buttonStyle(.plain)
            }
            // DetailCard 把内容固定成深色；新外观浅色版换回浅色，输入框、菜单按浅底画。
            .environment(\.colorScheme, lightSkin ? .light : .dark)
        }
    }

    // MARK: New looks

    /// 交给新外观的数据和回调（见 RadioSkinKit.swift），经典和复古皮肤是 nil。
    private var skinModel: RadioSkinModel? {
        guard modern, let palette else { return nil }
        return RadioSkinModel(
            skin: skin, tone: tone, palette: palette, stations: stations, index: index,
            playing: playing, buffering: !context.isPreview && playing && player.isBuffering,
            status: statusText, detail: retroSubline,
            detailIsProblem: player.problem != nil && playing && !context.isPreview,
            caption: statusText, volume: volume, isPreview: context.isPreview,
            onTune: { target in
                guard !context.isPreview else { return }
                RadioRemote.tune(instance, to: target)
            },
            onPrevious: {
                guard !context.isPreview, stations.count > 1 else { return }
                RadioRemote.tune(instance, to: RadioDial.previous(index, count: stations.count))
            },
            onNext: {
                guard !context.isPreview, stations.count > 1 else { return }
                RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
            },
            onToggle: {
                guard !context.isPreview, let station else { return }
                player.toggle(station, volume: volume, stations: stations, owner: instance.id)
            },
            onVolume: { value in
                guard !context.isPreview else { return }
                dragging = value
                player.setVolume(value)
            },
            onVolumeEnd: {
                if let value = dragging {
                    save { $0.set("volume", .number(value.rounded())) }
                    dragging = nil
                }
            })
    }

    // MARK: Tabs

    /// 收藏/搜索/定时关闭切换：胶囊分段，选中那段实心强调色、深色字，13pt。
    /// 一段都没选时下半截收起；定时关闭在走时那一段写剩下的时间。
    private func tabSwitch(now: Date) -> some View {
        HStack(spacing: 2) {
            tabSegment(.favourites, title: tr("我的收藏 \(stations.count)"))
            tabSegment(.search, title: tr("搜索电台"))
            tabSegment(.timer, title: timerTitle(now: now))
        }
        .padding(2)
        .background(Capsule().fill(fg.opacity(0.08)))
        .overlay(Capsule().strokeBorder(fg.opacity(0.1), lineWidth: 0.5))
    }

    private func tabSegment(_ value: Tab, title: String) -> some View {
        let on = tab == value
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                storedTab = DetailPanelSections.toggled(value, open: tab)
            }
        } label: {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? segmentInk : fg.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    if on {
                        Capsule().fill(accent).matchedGeometryEffect(id: "tab", in: tabSlot)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(on ? tr("再点一下收起") : "")
    }

    /// 定时关闭那一段的字：在走时写剩下的时间，收起时也看得到。
    private func timerTitle(now: Date) -> String {
        if let end = player.stopAt, player.isPlaying, !context.isPreview {
            return tr("定时 \(RadioSleep.remaining(until: end, now: now))")
        }
        return tr("定时关闭")
    }

    /// 一排小胶囊：一行放得下就一行等宽，放不下就按 `columns` 列折行，字不缩。
    private func chipRow<Item: Hashable, Chip: View>(_ items: [Item], columns: Int,
                                                     @ViewBuilder chip: @escaping (Item) -> Chip) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(items, id: \.self) { chip($0) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
                ForEach(items, id: \.self) { chip($0) }
            }
        }
    }

    // MARK: Retro skins

    /// 复古皮肤的上半部分：头一行、机身、大字台名、走带键、音量。
    @ViewBuilder private var retroTop: some View {
        retroHeader
        RadioRetroFace(skin: skin, count: stations.count, index: index, playing: playing, volume: volume,
                       stationName: station?.name ?? tr("还没有电台"), animated: !context.isPreview,
                       onTune: { target in
                           guard !context.isPreview else { return }
                           RadioRemote.tune(instance, to: target)
                       },
                       onNext: {
                           guard !context.isPreview, stations.count > 1 else { return }
                           RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
                       })
        .frame(maxWidth: .infinity, alignment: .center)
        RadioRetroReadout(name: station?.name ?? tr("还没有电台"), detail: retroSubline,
                          detailColor: player.problem != nil && playing && !context.isPreview
                              ? accentText : fg.opacity(0.6))
        RadioRetroTransport(skin: skin, playing: playing, canPlay: station != nil, canStep: stations.count > 1,
                            onPrevious: {
                                guard !context.isPreview else { return }
                                RadioRemote.tune(instance, to: RadioDial.previous(index, count: stations.count))
                            },
                            onToggle: {
                                guard !context.isPreview, let station else { return }
                                player.toggle(station, volume: volume, stations: stations, owner: instance.id)
                            },
                            onNext: {
                                guard !context.isPreview else { return }
                                RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
                            })
        RadioRetroVolume(skin: skin, value: volume, enabled: !context.isPreview,
                         onChange: { value in
                             dragging = value
                             player.setVolume(value)
                         },
                         onEnd: {
                             if let value = dragging {
                                 save { $0.set("volume", .number(value.rounded())) }
                                 dragging = nil
                             }
                         })
    }

    private var retroHeader: some View {
        HStack(spacing: 6) {
            Text("网络电台")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fg.opacity(0.72))
            Spacer()
            Circle()
                .fill(playing ? accent : fg.opacity(0.35))
                .frame(width: 6.4, height: 6.4)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(fg.opacity(playing ? 0.88 : 0.55))
        }
    }

    /// “MP3 · 64 kbps · 频道 03 / 05”；播放中有问题或有节目名时换成那一句。
    private var retroSubline: String {
        guard let station else { return tr("在“搜索电台”里找一个，或粘贴串流地址") }
        if !context.isPreview, playing {
            if let problem = player.problem { return problem }
            if let title = player.nowTitle { return tr("正在播放：\(title)") }
        }
        return "\(station.detail) · \(RadioDial.channelOfTotal(index, count: stations.count))"
    }

    // MARK: Readout

    private var header: some View {
        HStack(spacing: 6) {
            Text("网络电台")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fg.opacity(0.72))
            Spacer()
            if playing {
                RadioBars(active: !context.isPreview, color: accent, barWidth: 2, height: 10)
            }
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(fg.opacity(playing ? 0.88 : 0.62))
        }
    }

    private var statusText: String {
        if context.isPreview { return tr("正在收听") }
        guard playing else { return tr("已暂停") }
        if player.isBuffering { return tr("正在连接…") }
        return tr("正在收听")
    }

    private var readout: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(spacing: 0) {
                        Text("0").foregroundStyle(fg.opacity(0.3))
                        Text(station.map { _ in RadioDial.channelText(index) } ?? "--")
                            .foregroundStyle(fg)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: index)
                    }
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // CH 和编码是装饰性角标，12pt 等宽，两行叠在大数字旁边。
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CH")
                        Text(codecBadge)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentText)
                    .fixedSize()
                }
                Text(station?.name ?? tr("还没有电台"))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(13.0 / 19.0)
                // 第二行 13pt，长的（连接出错、节目名）折到两行，不缩字。
                Text(subline)
                    .font(.system(size: 13))
                    .foregroundStyle(player.problem != nil && playing ? accentText : fg.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            RadioIcon(size: 64, playing: playing, animated: !context.isPreview)
        }
    }

    private var codecBadge: String {
        guard let station else { return "" }
        let codec = station.codec.uppercased()
        if !codec.isEmpty, codec != "UNKNOWN" { return String(codec.prefix(4)) }
        return station.url.lowercased().contains(".m3u8") ? "HLS" : "FM"
    }

    private var subline: String {
        guard let station else { return tr("在“搜索电台”里找一个，或粘贴串流地址") }
        if !context.isPreview, playing {
            if let problem = player.problem { return problem }
            if let title = player.nowTitle { return tr("正在播放：\(title)") }
        }
        return station.detail
    }

    // MARK: Controls

    private var transport: some View {
        HStack(spacing: 22) {
            Spacer()
            roundButton("backward.end.fill", size: 34, label: tr("上一个电台")) {
                RadioRemote.tune(instance, to: RadioDial.previous(index, count: stations.count))
            }
            .disabled(stations.count < 2)
            roundButton(playing ? "pause.fill" : "play.fill", size: 48, label: playing ? tr("暂停") : tr("收听"),
                        filled: true) {
                if let station { player.toggle(station, volume: volume, stations: stations, owner: instance.id) }
            }
            .disabled(station == nil)
            roundButton("forward.end.fill", size: 34, label: tr("下一个电台")) {
                RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
            }
            .disabled(stations.count < 2)
            Spacer()
        }
    }

    private func roundButton(_ symbol: String, size: CGFloat, label: String, filled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(Circle().fill(fg.opacity(filled ? 0.2 : 0.08)))
                .overlay(Circle().strokeBorder(fg.opacity(filled ? 0.3 : 0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(fg.opacity(0.6))
            Slider(value: Binding(
                get: { volume },
                set: { value in
                    dragging = value
                    if !context.isPreview { player.setVolume(value) }
                }), in: 0...100, onEditingChanged: { editing in
                    if !editing, let value = dragging {
                        save { $0.set("volume", .number(value.rounded())) }
                        dragging = nil
                    }
                })
                .controlSize(.small)
                .tint(accent)
                .disabled(context.isPreview)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(fg.opacity(0.6))
            Text("\(Int(volume.rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(fg.opacity(0.78))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func timerRow(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("定时关闭")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(fg.opacity(0.65))
                Spacer()
                if let end = player.stopAt, player.isPlaying, !context.isPreview {
                    Text(tr("\(RadioSleep.remaining(until: end, now: now)) 后停止"))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accentText)
                }
            }
            chipRow(RadioSleep.choices, columns: 3) { minutes in timerChip(minutes) }
        }
    }

    private func timerChip(_ minutes: Int) -> some View {
        let on = player.timerMinutes == minutes
        return Button {
            guard !context.isPreview else { return }
            player.setTimer(minutes: minutes)
        } label: {
            Text(RadioSleep.title(minutes))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? fg : fg.opacity(0.7))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(on ? accent.opacity(0.4) : fg.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Favourites

    private var favourites: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !context.isPreview, addFlow.draft(instance.id).open {
                addForm
            } else {
                favouritesToolbar
            }
            favouriteList
        }
    }

    private var favouriteList: some View {
        Group {
            if stations.isEmpty {
                PandaEmptyState(empty: .radio, title: tr("搜索电台"), panel: true) {
                    storedTab = Tab.search.rawValue
                }
            } else {
                // 高度按行数自适应：最多露 5 行，超过才滚动，少于 5 行不留空白。
                // 行高量出来的（经典、复古皮肤不同），没量到时先用估计值。
                ScrollView {
                    VStack(spacing: RadioFavouriteList.rowSpacing) {
                        ForEach(Array(stations.enumerated()), id: \.element.id) { offset, item in
                            if renamingID == item.id {
                                renameRow(item)
                            } else {
                                favouriteRow(item, offset: offset)
                                    .onGeometryChange(for: CGFloat.self) { proxy in
                                        proxy.size.height
                                    } action: { height in
                                        noteRowHeight(height)
                                    }
                                    .contextMenu { rowMenu(item, offset: offset) }
                            }
                        }
                    }
                }
                .frame(height: RadioFavouriteList.height(rowCount: stations.count, rowHeight: favouriteRowHeight))
                .scrollDisabled(!RadioFavouriteList.scrolls(rowCount: stations.count))
                .scrollIndicators(.never)
            }
        }
    }

    /// 量到的收藏行高，经典和复古分开记，换皮肤不会拿错。
    private var favouriteRowHeight: CGFloat {
        (tallRows ? retroRowHeight : classicRowHeight) ?? RadioFavouriteList.fallbackRowHeight(retro: tallRows)
    }

    private func noteRowHeight(_ height: CGFloat) {
        guard height > 1 else { return }
        let rounded = (height * 2).rounded(.up) / 2
        if tallRows {
            if retroRowHeight.map({ abs($0 - rounded) > 0.5 }) ?? true { retroRowHeight = rounded }
        } else {
            if classicRowHeight.map({ abs($0 - rounded) > 0.5 }) ?? true { classicRowHeight = rounded }
        }
    }

    /// 复古皮肤和新外观的收藏行都是固定 34pt 的单行。
    private var tallRows: Bool { retro || modern }

    @ViewBuilder
    private func favouriteRow(_ item: RadioStation, offset: Int) -> some View {
        if let palette {
            modernFavouriteRow(item, offset: offset, palette: palette)
        } else if retro {
            retroFavouriteRow(item, offset: offset)
        } else {
            classicFavouriteRow(item, offset: offset)
        }
    }

    /// 新外观的收藏行：编号、台名，当前那一行右边写“正在听”。当前行的标法跟
    /// `RadioSkinPalette.rowStyle`：圆角强调底加竖条、直角强调底加爱心，或只在
    /// 下面画一根强调色细线。
    private func modernFavouriteRow(_ item: RadioStation, offset: Int, palette: RadioSkinPalette) -> some View {
        let tuned = offset == index
        let style = palette.rowStyle
        let corner: CGFloat = style == .round ? 9 : 0
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                RadioRemote.tune(instance, to: offset, play: true)
            } label: {
                HStack(spacing: 10) {
                    Text(verbatim: RadioDial.channelText(offset))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(fg.opacity(tuned ? 0.9 : palette.secondaryOpacity))
                        .frame(width: 22, alignment: .leading)
                    Text(item.name)
                        .font(.system(size: 15, weight: tuned ? .semibold : .medium))
                        .foregroundStyle(fg.opacity(tuned ? 1 : 0.9))
                        .lineLimit(1)
                    stationTags(item)
                    Spacer(minLength: 0)
                    if tuned {
                        Text(tr("正在听"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("收听 \(item.name)"))

            if item.isCustom { renameButton(item) }
            removeButton(item, offset: offset)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background {
            if tuned {
                if style == .line {
                    Rectangle().fill(fg.opacity(0.05))
                } else {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(accent.opacity(palette.highlightOpacity))
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(accent.opacity(0.5), lineWidth: 0.6))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if tuned, style == .line {
                Rectangle().fill(accentText).frame(height: 1.5)
            } else if !tuned {
                Rectangle().fill(Color(code: palette.line).opacity(0.08)).frame(height: 0.5).padding(.horizontal, 10)
            }
        }
        .overlay(alignment: .leading) {
            if tuned {
                switch style {
                case .round:
                    Capsule().fill(accentText).frame(width: 3, height: 16).padding(.leading, 6)
                case .square:
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(accentText)
                        .padding(.leading, 3)
                        .accessibilityHidden(true)
                case .line:
                    EmptyView()
                }
            }
        }
    }

    /// 复古皮肤的收藏行：编号、台名、右边按收藏顺序排的“FM 98.0”；当前那一行
    /// 淡淡一层强调色，左边一道竖条。
    private func retroFavouriteRow(_ item: RadioStation, offset: Int) -> some View {
        let tuned = offset == index
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                RadioRemote.tune(instance, to: offset, play: true)
            } label: {
                HStack(spacing: 10) {
                    Text(verbatim: RadioDial.channelText(offset))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(fg.opacity(tuned ? 0.9 : 0.62))
                        .frame(width: 22, alignment: .leading)
                    Text(item.name)
                        .font(.system(size: 15, weight: tuned ? .semibold : .medium))
                        .foregroundStyle(fg.opacity(tuned ? 1 : 0.88))
                        .lineLimit(1)
                    stationTags(item)
                    Spacer(minLength: 0)
                    Text(verbatim: RadioDial.fmText(offset, count: stations.count))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(tuned ? accentText : fg.opacity(0.65))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("收听 \(item.name)"))

            if item.isCustom { renameButton(item) }
            removeButton(item, offset: offset)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tuned ? accent.opacity(0.15) : fg.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accent.opacity(tuned ? 0.45 : 0), lineWidth: 0.6))
        }
        .overlay(alignment: .leading) {
            if tuned {
                Capsule().fill(accent).frame(width: 3, height: 16).padding(.leading, 6)
            }
        }
    }

    private func classicFavouriteRow(_ item: RadioStation, offset: Int) -> some View {
        let tuned = offset == index
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                RadioRemote.tune(instance, to: offset, play: true)
            } label: {
                HStack(spacing: 8) {
                    Text(RadioDial.channelText(offset))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tuned ? accentText : fg.opacity(0.62))
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 13, weight: tuned ? .semibold : .regular))
                            .foregroundStyle(fg.opacity(0.95))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            stationTags(item)
                            Text(item.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(fg.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if tuned, playing {
                        RadioBars(active: !context.isPreview, color: accent, barWidth: 2, height: 10)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("收听 \(item.name)"))

            if item.isCustom { renameButton(item) }
            removeButton(item, offset: offset)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tuned ? accent.opacity(0.14) : fg.opacity(0.05)))
    }

    private func remove(_ item: RadioStation, at offset: Int) {
        let wasTuned = offset == index
        if wasTuned, player.plays(item) { player.pause() }
        withAnimation(.snappy(duration: 0.3)) {
            RadioRemote.edit(instance) { list, current in
                list = RadioDial.removing(item.id, from: list)
                current = RadioDial.index(afterRemoving: offset, current: current, count: list.count + 1)
            }
        }
    }

    // MARK: Custom stations

    /// “自定义”“可能失效”小标签。
    @ViewBuilder
    private func stationTags(_ item: RadioStation) -> some View {
        if item.isCustom { tag(tr("自定义"), warn: false) }
        if item.mayBeDead { tag(tr("可能失效"), warn: true) }
    }

    private func tag(_ text: String, warn: Bool) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(warn ? accentText : fg.opacity(0.75))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(Capsule().fill(warn ? accent.opacity(0.16) : fg.opacity(0.1)))
    }

    private func renameButton(_ item: RadioStation) -> some View {
        Button {
            guard !context.isPreview else { return }
            startRename(item)
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fg.opacity(0.55))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("改名"))
        .accessibilityLabel(tr("给 \(item.name) 改名"))
    }

    private func removeButton(_ item: RadioStation, offset: Int) -> some View {
        Button {
            guard !context.isPreview else { return }
            remove(item, at: offset)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fg.opacity(0.55))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("从收藏中移除 \(item.name)"))
    }

    @ViewBuilder
    private func rowMenu(_ item: RadioStation, offset: Int) -> some View {
        if !context.isPreview {
            Button(tr("改名")) { startRename(item) }
            Button(tr("从收藏中移除"), role: .destructive) { remove(item, at: offset) }
        }
    }

    private func startRename(_ item: RadioStation) {
        renameText = item.name
        renamingID = item.id
    }

    private func commitRename(_ item: RadioStation) {
        let name = RadioPlaylist.cleanName(renameText)
        renamingID = nil
        guard !name.isEmpty, name != item.name else { return }
        RadioRemote.edit(instance) { list, _ in
            if let at = list.firstIndex(where: { $0.id == item.id }) { list[at].name = name }
        }
    }

    /// 改名那一行：和收藏行一样高，回车或“完成”保存，Esc 或“取消”放弃。
    private func renameRow(_ item: RadioStation) -> some View {
        HStack(spacing: 6) {
            TextField("", text: $renameText, prompt: Text(verbatim: item.name))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(fg)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .glassPane(cornerRadius: 8)
                .onSubmit { commitRename(item) }
                .onExitCommand { renamingID = nil }
            toolChip(tr("完成"), filled: true) { commitRename(item) }
            toolChip(tr("取消")) { renamingID = nil }
        }
        .padding(.horizontal, 8)
        .frame(height: favouriteRowHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fg.opacity(0.05)))
    }

    /// 收藏上面一排：“添加电台”和“检查”。
    private var favouritesToolbar: some View {
        let checking = healthCheck.isRunning(instance.id)
        return HStack(spacing: 6) {
            toolChip(tr("添加电台"), symbol: "plus") { addFlow.open(instance.id) }
            Spacer(minLength: 0)
            if checking {
                ProgressView().controlSize(.mini)
                Text(verbatim: tr("正在检查…"))
                    .font(.system(size: 13))
                    .foregroundStyle(fg.opacity(0.65))
            } else {
                if !context.isPreview, healthCheck.reports[instance.id] == 0 {
                    Text(verbatim: tr("都连得上"))
                        .font(.system(size: 13))
                        .foregroundStyle(fg.opacity(0.6))
                } else if !context.isPreview, healthCheck.offline.contains(instance.id) {
                    Text(verbatim: tr("可能没联网"))
                        .font(.system(size: 13))
                        .foregroundStyle(fg.opacity(0.6))
                        .lineLimit(1)
                        .help(tr("一个电台也连不上，多半是没联网，没有标记失效"))
                }
                toolChip(tr("检查"), symbol: "antenna.radiowaves.left.and.right") {
                    dismissedHealth = nil
                    RadioStationCheck.clearDismissed(instance.id)
                    healthCheck.check(instance)
                }
                .help(tr("逐个试连收藏的电台，找出连不上的"))
                .disabled(stations.isEmpty)
            }
        }
    }

    private var addressBinding: Binding<String> {
        Binding(get: { addFlow.draft(instance.id).address },
                set: { value in addFlow.update(instance.id) { $0.address = value } })
    }

    private var nameBinding: Binding<String> {
        Binding(get: { addFlow.draft(instance.id).name },
                set: { value in addFlow.update(instance.id) { $0.name = value } })
    }

    /// 添加电台：地址、名称、导入文件；试连的结果和“仍然保存”在下面。
    private var addForm: some View {
        let draft = addFlow.draft(instance.id)
        let busy: Bool = {
            if case .working = draft.status { return true }
            return false
        }()
        let canAdd = !busy && !draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: tr("添加电台"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fg.opacity(0.72))
            formField(addressBinding, prompt: tr("直播地址：http(s) 音频流或 .m3u8"))
            formField(nameBinding, prompt: tr("名称（可选）"))
            addStatus(draft)
            HStack(spacing: 6) {
                toolChip(tr("导入文件…"), symbol: "doc.badge.plus") { addFlow.importFile(instance.id) }
                    .help(tr("导入 .m3u、.m3u8 或 .pls 播放列表"))
                    .disabled(busy)
                    .opacity(busy ? 0.45 : 1)
                Spacer(minLength: 0)
                toolChip(tr("取消")) { addFlow.close(instance.id) }
                toolChip(tr("添加"), filled: true) { addFlow.submit(instance.id) }
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.45)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fg.opacity(0.05)))
    }

    private func formField(_ text: Binding<String>, prompt: String) -> some View {
        TextField("", text: text, prompt: Text(verbatim: prompt))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .glassPane(cornerRadius: 8)
            .onSubmit { addFlow.submit(instance.id) }
    }

    @ViewBuilder
    private func addStatus(_ draft: RadioAddFlow.Draft) -> some View {
        switch draft.status {
        case .idle:
            note(tr("也可以导入 .m3u、.m3u8、.pls 播放列表。同名的地址并成一个电台，主地址连不上时按顺序换备用。"))
        case .working(let text):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(verbatim: text)
                    .font(.system(size: 13))
                    .foregroundStyle(fg.opacity(0.7))
            }
        case .message(let text):
            note(text)
        case .failed(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: text)
                    .font(.system(size: 13))
                    .foregroundStyle(accentText)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { saveAnywayChips(draft) }
                    VStack(alignment: .leading, spacing: 6) { saveAnywayChips(draft) }
                }
            }
        }
    }

    @ViewBuilder
    private func saveAnywayChips(_ draft: RadioAddFlow.Draft) -> some View {
        if !draft.working.isEmpty {
            toolChip(tr("只保存连得上的 \(draft.working.count) 个")) {
                addFlow.saveAnyway(instance.id, onlyWorking: true)
            }
        }
        toolChip(tr("仍然保存")) { addFlow.saveAnyway(instance.id, onlyWorking: false) }
    }

    /// 小胶囊按钮；实心的用强调色底、深色字。
    private func toolChip(_ title: String, symbol: String? = nil, filled: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(filled ? segmentInk : fg.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(filled ? accent : fg.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Health banner

    private var deadStations: [RadioStation] {
        context.isPreview ? [] : RadioHealth.dead(stations)
    }

    private var showsHealthBanner: Bool {
        RadioHealth.bannerVisible(dead: deadStations, dismissed: dismissedHealth)
    }

    /// “N 个电台连不上”：点开列出来；“保留”或叉号关掉，确认后才删除。
    private var healthBanner: some View {
        let dead = deadStations
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        healthOpen.toggle()
                        confirmingDelete = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(accentText)
                        Text(verbatim: tr("\(dead.count) 个电台连不上"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(fg.opacity(0.92))
                            .lineLimit(1)
                        Image(systemName: healthOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(fg.opacity(0.6))
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(healthOpen ? tr("收起") : tr("查看连不上的电台"))

                Button {
                    dismissHealth(dead)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("关闭提示"))
            }
            if healthOpen {
                Text(verbatim: tr("每条地址都试过，都连不上。可能只是暂时离线，确认后才会删除。"))
                    .font(.system(size: 13))
                    .foregroundStyle(fg.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dead) { item in
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(fg.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            tag(tr("可能失效"), warn: true)
                        }
                    }
                }
                HStack(spacing: 6) {
                    if confirmingDelete {
                        Text(verbatim: tr("确定删除？"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(fg.opacity(0.85))
                        Spacer(minLength: 0)
                        toolChip(tr("取消")) { confirmingDelete = false }
                        toolChip(tr("删除 \(dead.count) 个"), filled: true) { removeDead(dead) }
                    } else {
                        toolChip(tr("保留")) { dismissHealth(dead) }
                        Spacer(minLength: 0)
                        toolChip(tr("删除这些电台")) { confirmingDelete = true }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fg.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(fg.opacity(0.1), lineWidth: 0.5))
    }

    private func dismissHealth(_ dead: [RadioStation]) {
        RadioStationCheck.dismiss(instance.id, dead: dead)
        dismissedHealth = RadioHealth.dismissToken(dead)
        healthOpen = false
        confirmingDelete = false
    }

    /// 用户确认后删掉连不上的电台；正在播的是其中一台就先停。
    private func removeDead(_ dead: [RadioStation]) {
        let ids = Set(dead.map(\.id))
        if let station, ids.contains(station.id), player.plays(station) { player.pause() }
        withAnimation(.snappy(duration: 0.3)) {
            RadioRemote.edit(instance) { list, current in
                let before = list
                list = RadioHealth.removing(ids, from: before)
                current = RadioHealth.index(afterRemoving: ids, from: before, current: current)
            }
        }
        healthOpen = false
        confirmingDelete = false
    }

    // MARK: Search

    /// 搜索框里贴的是地址（包括不支持的协议，交给添加流程说明），不是电台名。
    private var typedAddress: Bool { RadioAddress(query) != .invalid }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var search: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(fg.opacity(0.65))
                TextField("", text: $query, prompt: Text("电台名称，或粘贴 http(s) 串流地址"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(fg)
                    .onSubmit { typedAddress ? addCustom() : run() }
                    .disabled(context.isPreview)
                if searching { ProgressView().controlSize(.mini) }
                if !query.isEmpty, !context.isPreview {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(fg.opacity(0.55))
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassPane(cornerRadius: 10)

            if typedAddress {
                customRow
            } else {
                regionRow
                HStack(spacing: 6) {
                    Text(listTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.65))
                        .lineLimit(1)
                    Spacer()
                    if !trimmedQuery.isEmpty { chip(tr("搜索")) { run() } }
                }
            }

            if searchFailed {
                note(tr("连不上电台目录，请检查网络后再试。"))
            } else if searched, results.isEmpty, !searching {
                note(shownQuery?.name.isEmpty == false
                     ? tr("\((shownQuery?.region ?? region).title)里没有找到这个电台，换个关键词或地区试试。")
                     : tr("\((shownQuery?.region ?? region).title)暂时没有可收听的电台。"))
            } else if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results) { result in resultRow(result) }
                    }
                }
                .frame(maxHeight: 170)
                .scrollIndicators(.never)
            }
        }
        .onAppear {
            if !searched, !searching, trimmedQuery.isEmpty { run() }
        }
        .onChange(of: trimmedQuery) { _, words in
            // Clearing the field goes back to the region's top stations.
            if words.isEmpty, shownQuery?.name.isEmpty == false { run() }
        }
    }

    /// "中文电台 · 热门电台" for the top list, "“音乐” · 香港" for a search.
    private var listTitle: String {
        let shown = shownQuery ?? RadioDirectory.Query(name: "", region: region)
        if shown.name.isEmpty { return tr("\(shown.region.title) · 热门电台") }
        return "“\(shown.name)” · \(shown.region.title)"
    }

    private var regionRow: some View {
        chipRow(RadioRegion.allCases, columns: 3) { option in regionChip(option) }
    }

    private func regionChip(_ option: RadioRegion) -> some View {
        let on = option == region
        return Button {
            guard !context.isPreview, option != region else { return }
            pickedRegion = option
            save { RadioRegion.store(option, in: &$0) }
            run(in: option)
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? fg : fg.opacity(0.7))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(on ? accent.opacity(0.4) : fg.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(option == .global ? tr("不限地区和语言") : tr("只看\(option.title)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var customRow: some View {
        HStack(spacing: 6) {
            TextField("", text: $customName, prompt: Text("名称（可选）"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(fg)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .glassPane(cornerRadius: 8)
                .onSubmit(addCustom)
            chip(tr("添加自定义地址"), action: addCustom)
        }
    }

    private func resultRow(_ result: RadioStation) -> some View {
        let saved = stations.contains { $0.matches(result) }
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                addAndListen(result)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(size: 13))
                        .foregroundStyle(fg.opacity(0.95))
                        .lineLimit(1)
                    Text(result.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(fg.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("添加并收听")

            Button {
                guard !context.isPreview, !saved else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    RadioRemote.edit(instance) { list, _ in list = RadioDial.adding(result, to: list) }
                }
            } label: {
                Image(systemName: saved ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(saved ? accentText : fg.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(fg.opacity(saved ? 0 : 0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved ? tr("已在收藏中") : tr("加入收藏"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fg.opacity(0.05)))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fg.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(fg.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(fg.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    /// Lists the region's top stations when the field is empty, otherwise
    /// searches names inside the region. A newer request wins over one still
    /// on its way.
    private func run(in chosen: RadioRegion? = nil) {
        guard !context.isPreview, !typedAddress else { return }
        let request = RadioDirectory.Query(name: trimmedQuery, region: chosen ?? region)
        requestID += 1
        let id = requestID
        searching = true
        searchFailed = false
        Task {
            let found = await RadioDirectory.fetch(request)
            guard id == requestID else { return }
            searching = false
            searched = true
            searchFailed = found == nil
            results = found ?? []
            shownQuery = request
        }
    }

    /// 搜索框里贴的地址交给“添加电台”：试连、标“自定义”，结果在收藏页上方显示。
    private func addCustom() {
        guard !context.isPreview, typedAddress else { return }
        let id = instance.id
        let address = query
        let name = customName
        addFlow.update(id) { draft in
            draft.open = true
            draft.address = address
            draft.name = name
        }
        addFlow.submit(id)
        query = ""
        customName = ""
        storedTab = Tab.favourites.rawValue
    }

    /// Adds the station unless it is already a favourite, tunes the dial to
    /// it, and starts it.
    private func addAndListen(_ station: RadioStation) {
        let current = stations
        let list = RadioDial.adding(station, to: current)
        guard let target = list.firstIndex(where: { $0.matches(station) }) else { return }
        RadioRemote.edit(instance) { stored, index in
            stored = list
            index = target
        }
        player.play(list[target], volume: volume, stations: list, owner: instance.id)
    }

    private func save(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance, change)
    }
}

/// The arc tuner: a half dial of ticks with a mark for each favourite and a
/// red needle on the tuned one. Dragging or clicking along it tunes to the
/// nearest mark.
struct RadioArcDial: View {
    var count: Int
    var index: Int
    var accent: Color
    var needle: Color
    /// 刻度、表面和未选中的点的颜色；深色面板上是白色，新外观的浅色版传深色字。
    var ink: Color = .white
    var onTune: (Int) -> Void

    @State private var dragIndex: Int?

    /// The stations spread over the middle of the arc, clear of its feet.
    nonisolated private static let span = (start: 0.08, length: 0.84)

    nonisolated static func angle(_ station: Int, count: Int) -> Double {
        guard count > 1 else { return .pi * 1.5 }
        let fraction = span.start + span.length * Double(station) / Double(count - 1)
        return .pi + fraction * .pi
    }

    nonisolated static func geometry(_ size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height - 2)
        return (center, max(10, min(size.width / 2 - 8, size.height - 8)))
    }

    nonisolated static func nearest(_ point: CGPoint, size: CGSize, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let (center, _) = geometry(size)
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        var angle: Double
        if dy >= 0 {
            angle = dx < 0 ? .pi : 2 * .pi
        } else {
            angle = atan2(dy, dx) + 2 * .pi
        }
        angle = min(max(angle, .pi), 2 * .pi)
        let fraction = (angle - .pi) / .pi
        let position = (fraction - span.start) / span.length * Double(count - 1)
        return min(max(0, Int(position.rounded())), count - 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shown = dragIndex ?? index
            let marks = count
            let tint = accent
            let ink = self.ink
            ZStack {
                Canvas { context, size in
                    let (center, radius) = Self.geometry(size)
                    func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
                        CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    }
                    var face = Path()
                    face.addArc(center: center, radius: radius - 14, startAngle: .radians(.pi),
                                endAngle: .radians(2 * .pi), clockwise: false)
                    face.closeSubpath()
                    context.fill(face, with: .color(ink.opacity(0.05)))

                    for tick in 0...60 {
                        let angle = .pi + Double(tick) / 60 * .pi
                        let long = tick % 5 == 0
                        var line = Path()
                        line.move(to: point(angle, radius - (long ? 10 : 5)))
                        line.addLine(to: point(angle, radius))
                        context.stroke(line, with: .color(ink.opacity(long ? 0.45 : 0.18)),
                                       lineWidth: long ? 1.2 : 0.8)
                    }
                    for station in 0..<marks {
                        let at = point(Self.angle(station, count: marks), radius - 20)
                        let dot = CGRect(x: at.x - 2.5, y: at.y - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: dot),
                                     with: .color(station == shown ? tint : ink.opacity(0.4)))
                    }
                    let hub = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.stroke(Path(ellipseIn: hub), with: .color(ink.opacity(0.35)), lineWidth: 1)
                }
                if count > 0 {
                    DialNeedle(angle: Self.angle(shown, count: count))
                        .stroke(needle, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: needle.opacity(0.6), radius: 3)
                        .animation(.spring(duration: 0.45, bounce: 0.25), value: shown)
                }
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard count > 0 else { return }
                    dragIndex = Self.nearest(value.location, size: size, count: count)
                }
                .onEnded { value in
                    guard count > 0 else { return }
                    let target = Self.nearest(value.location, size: size, count: count)
                    dragIndex = nil
                    if target != index { onTune(target) }
                })
        }
        .help("拖动刻度换台")
        .accessibilityElement()
        .accessibilityLabel("调谐刻度")
        .accessibilityValue(count > 0 ? tr("第 \(index + 1) 个电台，共 \(count) 个") : tr("没有电台"))
    }
}

private struct DialNeedle: Shape {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (center, radius) = RadioArcDial.geometry(rect.size)
        var path = Path()
        path.move(to: CGPoint(x: center.x + 6 * cos(angle), y: center.y + 6 * sin(angle)))
        path.addLine(to: CGPoint(x: center.x + (radius + 2) * cos(angle),
                                 y: center.y + (radius + 2) * sin(angle)))
        return path
    }
}
