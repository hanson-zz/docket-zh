import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 壁纸面板，照第二批效果图分两个状态：
///
/// - 浏览：当前壁纸大图（左上“当前”，右上星星收藏这张），上一张 / 随机 /
///   下一张，“全部 / 收藏”两个标签（收藏标签只看收藏的，三个键也只在收藏里
///   换），三列小图点一下设为壁纸、点星星收藏，最下面“选择文件夹…”。
/// - 自动换（Pro）：右上“自动换”进入。按时间自动换的开关，早上、中午、晚上
///   三个时刻（点时刻改，点右边的小图换成现在的壁纸，右键从文件选），到点放
///   固定的那张或从收藏随机，跟着日出日落走（早上跟日出、晚上跟日落，用天气
///   的定位），所有显示器一起换。
///
/// 壁纸整种免费，自动换是 Pro：没解锁时设置照样列出、带 Pro 标，开关和改动弹
/// 付费墙；已经打开的不换，配置不改写，解锁或试用后自动恢复（`WallpaperAutoDriver`
/// 从启动起看着每个布局里的壁纸卡片，见 `ProLicenseGate.wallpaperAutoChangeActive`）。
struct WallpaperDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private enum Mode { case browse, auto }
    private enum Tab { case all, favorites }

    @State private var mode: Mode = .browse
    @State private var tab: Tab = .all
    @State private var revision = 0
    /// 正在改时刻的那一段。
    @State private var editingSlot: WallpaperSchedule.Slot?
    @State private var notice: String?

    private static let accentHex = "#4FD1C5"
    private static let inkHex = "#032B27"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }
    private var unlocked: Bool { licenseUnlocked || supporter || context.isPreview }

    private var current: WidgetInstance {
        _ = revision
        return WidgetWriter.current(instance.id) ?? instance
    }
    private var config: WidgetConfig { current.config }
    private var folderPath: String { config.string("folder") }
    private var feed: FolderFeed { FolderFeed.shared(.pictures(folderPath)) }
    private var wallpaper: WallpaperService { WallpaperService.shared }
    private var allScreens: Bool { config.bool("allScreens", default: true) }
    private var favorites: [String] { WallpaperSchedule.favorites(config) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: Color(hex: Self.accentHex))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .browse: browse
                case .auto: auto
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            wallpaper.start()
            feed.start()
            feed.refresh(force: true)
        }
        .onChange(of: folderPath) { _, _ in if !context.isPreview { feed.start() } }
    }

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        let item = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(item, change)
        revision += 1
    }

    private func switchTo(_ next: Mode) {
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            editingSlot = nil
            notice = nil
        }
    }

    // MARK: 浏览

    /// 收藏标签里看到的：收藏了且还在文件夹里的，加上收藏了但在别处的（换过文件夹）。
    private var shownFiles: [URL] {
        let files = feed.files.map(\.url)
        guard tab == .favorites else { return files }
        let set = Set(favorites)
        let inFolder = files.filter { set.contains($0.path) }
        let known = Set(inFolder.map(\.path))
        let elsewhere = favorites.filter { !known.contains($0) && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        return inFolder + elsewhere
    }

    @ViewBuilder
    private var browse: some View {
        AlbumHeader(title: tr("壁纸"), subtitle: subtitle) {
            if !context.isPreview {
                AlbumHeaderButton(title: tr("自动换")) { switchTo(.auto) }
                    .help(tr("早中晚各一张，到点自己换（Pro）"))
            }
        }
        currentPicture
        let files = shownFiles
        HStack(spacing: 6) {
            ForEach(WallpaperCycle.Step.allCases, id: \.self) { step in
                AlbumControlButton(title: WallpaperTile.title(step), symbol: nil,
                                   prominent: step == .next, accent: accent, ink: ink,
                                   enabled: context.isPreview || !files.isEmpty) {
                    guard !context.isPreview else { return }
                    wallpaper.step(step, in: files, allScreens: allScreens)
                }
            }
        }
        tabs
        grid(files)
        AlbumControlButton(title: tr("选择文件夹…"), symbol: nil, accent: accent, ink: ink, action: choose)
            .contextMenu {
                Button(tr("在访达中打开")) { FileActions.openFolder(feed.folder) }
                if !folderPath.isEmpty {
                    Button(tr("改回“图片”文件夹")) { write { $0.set("folder", .string("")) } }
                }
            }
        if let error = wallpaper.lastError {
            Text(verbatim: error)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var subtitle: String {
        if context.isPreview { return tr("收藏 8 张 · 所有显示器") }
        let screens = allScreens ? tr("所有显示器") : tr("主显示器")
        if !favorites.isEmpty { return tr("收藏 \(favorites.count) 张 · \(screens)") }
        let name = feed.folder.lastPathComponent
        guard feed.loadedAt != nil else { return tr("\(name) · 正在读取") }
        return tr("\(name) · \(feed.files.count) 张 · \(screens)")
    }

    @ViewBuilder
    private var currentPicture: some View {
        Group {
            if context.isPreview {
                SamplePicture(symbol: "photo.fill")
            } else if let url = wallpaper.current {
                FileThumb(url: url, pixels: 720)
                    .id(url)
            } else {
                Color.white.opacity(0.06)
                    .overlay {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 162)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(verbatim: tr("当前"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if let url = wallpaper.current, !context.isPreview {
                starButton(url.path, size: 28)
                    .padding(10)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(wallpaper.current.map { tr("当前壁纸：\($0.lastPathComponent)") } ?? tr("当前壁纸"))
    }

    private func starButton(_ path: String, size: CGFloat) -> some View {
        let on = favorites.contains(path)
        return Button {
            var added = true
            write { added = WallpaperSchedule.toggleFavorite(path, in: &$0) }
            notice = added ? nil : tr("最多收藏 \(WallpaperSchedule.maxFavorites) 张")
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(on ? accent : .white.opacity(0.9))
                .frame(width: size, height: size)
                .background(Circle().fill(.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? tr("取消收藏") : tr("收藏"))
        .accessibilityLabel(on ? tr("取消收藏") : tr("收藏"))
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabChip(tr("全部 \(context.isPreview ? 32 : feed.files.count)"), on: tab == .all) { tab = .all }
            tabChip(tr("收藏 \(context.isPreview ? 8 : favorites.count)"), on: tab == .favorites) { tab = .favorites }
            Spacer(minLength: 0)
            Text(verbatim: notice ?? tr("点星星收藏"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.top, 4)
    }

    private func tabChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? ink : .white.opacity(0.9))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(on ? accent : .white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.16), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private static let cellAspect: CGFloat = 1 / 0.62

    @ViewBuilder
    private func grid(_ files: [URL]) -> some View {
        if context.isPreview {
            SamplePicture(symbol: "photo.fill")
                .frame(height: 120)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
        } else if let error = feed.error, tab == .all {
            AlbumNote(symbol: "lock", text: error, privacy: feed.accessDenied).frame(height: 120)
        } else if files.isEmpty {
            let text: String = {
                if tab == .favorites { return tr("还没有收藏。点小图右上角的星星收藏") }
                return feed.loadedAt == nil ? tr("正在读取…") : tr("这个文件夹里没有图片。点按“选择文件夹…”换一个。")
            }()
            AlbumNote(symbol: tab == .favorites ? "star" : "photo", text: text)
                .frame(height: 120)
        } else {
            // 两行的高度，多了就滚动。
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(files, id: \.self) { url in
                        cell(url)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: files.count > 3 ? 120 : 57)
        }
    }

    private func cell(_ url: URL) -> some View {
        FileThumb(url: url, pixels: 240)
            .aspectRatio(Self.cellAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .overlay {
                if isCurrent(url) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: 7))
            .onTapGesture { wallpaper.set(url, allScreens: allScreens) }
            .overlay(alignment: .topTrailing) {
                starButton(url.path, size: 20)
                    .padding(4)
            }
            .help(tr("设为壁纸：\(url.lastPathComponent)"))
            .contextMenu {
                Button(tr("设为壁纸")) { wallpaper.set(url, allScreens: allScreens) }
                Button(tr("在访达中显示")) { FileActions.reveal([url]) }
            }
    }

    private func isCurrent(_ url: URL) -> Bool {
        wallpaper.current?.standardizedFileURL == url.standardizedFileURL
    }

    private func choose() {
        guard !context.isPreview else { return }
        let item = WidgetWriter.current(instance.id) ?? instance
        guard let url = FileActions.chooseFolder(title: tr("选择壁纸所在的文件夹"), startingAt: feed.folder) else { return }
        WidgetWriter.write(item) { $0.set("folder", .string(url.path)) }
        revision += 1
    }

    // MARK: 自动换（Pro）

    private var autoOn: Bool { config.bool(WallpaperSchedule.autoChangeKey) }

    /// 没解锁时弹付费墙，不写。
    private func proWrite(_ change: (inout WidgetConfig) -> Void) {
        guard unlocked else {
            PaywallWindow.shared.show()
            return
        }
        write(change)
    }

    /// 天气定位的那天的日出日落（分钟），没有定位或极昼极夜时是 nil。
    private var sunMinutes: (rise: Int, set: Int)? {
        guard let place = WeatherService.shared.place else { return nil }
        return WallpaperAutoDriver.sunMinutes(on: context.now, latitude: place.lat, longitude: place.lon)
    }

    @ViewBuilder
    private var auto: some View {
        AlbumHeader(title: tr("自动换壁纸"), subtitle: tr("早中晚各一张，到点自己换"), titlePro: true) {
            AlbumHeaderButton(title: tr("完成"), solid: true, accent: accent, ink: ink) { switchTo(.browse) }
        }
        if !unlocked {
            Text(verbatim: tr("按时间自动换是码头 Pro 功能，解锁后到点自己换。"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        AlbumToggleRow(label: tr("按时间自动换"), isOn: autoOn, accent: accent) { on in
            proWrite { $0.set(WallpaperSchedule.autoChangeKey, .bool(on)) }
        }
        let sun = sunMinutes
        let followSun = config.bool(WallpaperSchedule.followSunKey)
        let minutes = WallpaperSchedule.effectiveMinutes(config, sunrise: sun?.rise, sunset: sun?.set)
        let source = WallpaperSchedule.source(config)
        VStack(spacing: 6) {
            ForEach(WallpaperSchedule.Slot.allCases, id: \.self) { slot in
                slotRow(slot, minutes: minutes[slot] ?? slot.defaultMinutes,
                        bySun: followSun && sun != nil && slot != .noon, source: source)
            }
        }
        .padding(.top, 2)

        AlbumSection(label: tr("到点放哪张"))
            .padding(.top, 6)
        AlbumSegmented(labels: WallpaperSchedule.Source.allCases.map(\.title),
                       selected: WallpaperSchedule.Source.allCases.firstIndex(of: source),
                       accent: accent, ink: ink) { index in
            let picked = WallpaperSchedule.Source.allCases[index]
            proWrite { $0.set(WallpaperSchedule.autoSourceKey, .string(picked.rawValue)) }
        }
        if source == .favorites, favorites.isEmpty {
            Text(verbatim: tr("还没有收藏，到点不会换。先在浏览里点星星收藏几张"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }

        AlbumToggleRow(label: tr("跟着日出日落走"),
                       sub: followSun && sun == nil && !context.isPreview
                           ? tr("天气还没有定位，先按上面的时刻")
                           : tr("按所在城市的日出日落时间"),
                       isOn: followSun, accent: accent) { on in
            proWrite { $0.set(WallpaperSchedule.followSunKey, .bool(on)) }
        }
        .padding(.top, 2)
        AlbumToggleRow(label: tr("所有显示器一起换"), isOn: allScreens, accent: accent) { on in
            write { $0.set("allScreens", .bool(on)) }
        }
    }

    private func slotRow(_ slot: WallpaperSchedule.Slot, minutes: Int, bySun: Bool,
                         source: WallpaperSchedule.Source) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(slot))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: slot.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                timeChip(slot, minutes: minutes, bySun: bySun)
            }
            Spacer(minLength: 0)
            slotPicture(slot, source: source)
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(height: 64)
        .glassPane(cornerRadius: 12)
    }

    private static func symbol(_ slot: WallpaperSchedule.Slot) -> String {
        switch slot {
        case .morning: "sunrise.fill"
        case .noon: "sun.max.fill"
        case .evening: "moon.fill"
        }
    }

    @ViewBuilder
    private func timeChip(_ slot: WallpaperSchedule.Slot, minutes: Int, bySun: Bool) -> some View {
        let text = WallpaperSchedule.text(minutes)
        let chip = HStack(spacing: 4) {
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if bySun {
                Text(verbatim: slot == .morning ? tr("日出") : tr("日落"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.6))
        if bySun {
            chip.help(tr("跟着日出日落走时按天气定位的城市算"))
        } else {
            Button {
                guard unlocked else { PaywallWindow.shared.show(); return }
                editingSlot = slot
            } label: { chip.contentShape(.rect) }
                .buttonStyle(.plain)
                .help(tr("改时刻"))
                .popover(isPresented: Binding(get: { editingSlot == slot },
                                              set: { if !$0 { editingSlot = nil } })) {
                    timeEditor(slot, minutes: minutes)
                }
        }
    }

    private func timeEditor(_ slot: WallpaperSchedule.Slot, minutes: Int) -> some View {
        let day = Calendar.current.startOfDay(for: .now)
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: tr("\(slot.title)几点换"))
                .font(.system(size: 13, weight: .semibold))
            DatePicker("", selection: Binding(
                get: { date },
                set: { picked in
                    let value = WallpaperSchedule.minuteOfDay(picked)
                    write { $0.set(slot.timeKey, .string(WallpaperSchedule.text(value))) }
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
        }
        .padding(12)
    }

    @ViewBuilder
    private func slotPicture(_ slot: WallpaperSchedule.Slot, source: WallpaperSchedule.Source) -> some View {
        let path = config.string(slot.pictureKey)
        if source == .favorites {
            VStack(spacing: 2) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .bold))
                Text(verbatim: tr("收藏随机"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 92, height: 46)
            .glassPane(cornerRadius: 7)
        } else {
            Button {
                guard unlocked else { PaywallWindow.shared.show(); return }
                guard let now = wallpaper.current else { return }
                write { $0.set(slot.pictureKey, .string(now.path)) }
            } label: {
                Group {
                    if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                        FileThumb(url: URL(fileURLWithPath: path), pixels: 200)
                    } else if context.isPreview {
                        SamplePicture(symbol: "photo.fill")
                    } else {
                        Text(verbatim: path.isEmpty ? tr("用当前") : tr("找不到了"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }
                    }
                }
                .frame(width: 92, height: 46)
                .clipShape(.rect(cornerRadius: 7, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("点一下用现在的壁纸，右键从文件选"))
            .contextMenu {
                Button(tr("用现在的壁纸")) {
                    guard unlocked else { PaywallWindow.shared.show(); return }
                    if let now = wallpaper.current { write { $0.set(slot.pictureKey, .string(now.path)) } }
                }
                Button(tr("从文件选择…")) {
                    guard unlocked else { PaywallWindow.shared.show(); return }
                    if let url = Self.chooseImage(start: feed.folder) {
                        write { $0.set(slot.pictureKey, .string(url.path)) }
                    }
                }
                if !path.isEmpty {
                    Button(tr("清除")) { write { $0.set(slot.pictureKey, .string("")) } }
                }
            }
        }
    }

    /// 选一张图片，和选文件夹一样先把码头提到前面。
    private static func chooseImage(start: URL?) -> URL? {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }
        let panel = NSOpenPanel()
        panel.message = tr("选一张到点放的图片")
        panel.prompt = tr("选择")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }
}
