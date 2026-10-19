import SwiftUI

/// The radio in the "弧光调谐" (arc tuner) look of meowRadio: a big channel
/// number and the station's name, an arc dial with a mark for every
/// favourite, the volume, a sleep timer, the favourites, and a search of the
/// Radio Browser directory.
///
/// The favourites and the tuned channel are written to the widget's config,
/// so the tile and this panel always show the same station.
struct RadioDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Tab: Hashable { case favourites, search }

    private var player: RadioPlayer { RadioPlayer.shared }

    @State private var tab: Tab = .favourites
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

    private var accent: Color { RadioIcon.glow }
    private static let needle = Color(hex: "#FF453A")

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                readout
                RadioArcDial(count: stations.count, index: index, accent: accent, needle: Self.needle) { target in
                    guard !context.isPreview else { return }
                    RadioRemote.tune(instance, to: target)
                }
                .frame(height: 92)
                transport
                volumeRow
                timerRow(now: now)
                Picker("", selection: $tab) {
                    Text(tr("我的收藏 \(stations.count)")).tag(Tab.favourites)
                    Text("搜索电台").tag(Tab.search)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                switch tab {
                case .favourites: favourites
                case .search: search
                }
                Link(destination: RadioBrowser.homepage) {
                    HStack(spacing: 3) {
                        Text(RadioBrowser.attribution)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Readout

    private var header: some View {
        HStack(spacing: 6) {
            Text("网络电台")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if playing {
                RadioBars(active: !context.isPreview, color: accent, barWidth: 2, height: 10)
            }
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(playing ? 0.85 : 0.55))
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
                        Text("0").foregroundStyle(.white.opacity(0.3))
                        Text(station.map { _ in RadioDial.channelText(index) } ?? "--")
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: index)
                    }
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CH")
                        Text(codecBadge)
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                }
                Text(station?.name ?? tr("还没有电台"))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subline)
                    .font(.system(size: 11))
                    .foregroundStyle(player.problem != nil && playing ? accent : .white.opacity(0.6))
                    .lineLimit(1)
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
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(filled ? 0.2 : 0.08)))
                .overlay(Circle().strokeBorder(.white.opacity(filled ? 0.3 : 0.12), lineWidth: 0.5))
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
                .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.6))
            Text("\(Int(volume.rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func timerRow(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("定时关闭")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let end = player.stopAt, player.isPlaying, !context.isPreview {
                    Text(tr("\(RadioSleep.remaining(until: end, now: now)) 后停止"))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            HStack(spacing: 5) {
                ForEach(RadioSleep.choices, id: \.self) { minutes in timerChip(minutes) }
            }
        }
    }

    private func timerChip(_ minutes: Int) -> some View {
        let on = player.timerMinutes == minutes
        return Button {
            guard !context.isPreview else { return }
            player.setTimer(minutes: minutes)
        } label: {
            Text(RadioSleep.title(minutes))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(on ? accent.opacity(0.4) : .white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Favourites

    private var favourites: some View {
        Group {
            if stations.isEmpty {
                PandaEmptyState(empty: .radio, title: tr("搜索电台"), panel: true) { tab = .search }
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(stations.enumerated()), id: \.element.id) { offset, item in
                            favouriteRow(item, offset: offset)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .scrollIndicators(.never)
            }
        }
    }

    private func favouriteRow(_ item: RadioStation, offset: Int) -> some View {
        let tuned = offset == index
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                RadioRemote.tune(instance, to: offset, play: true)
            } label: {
                HStack(spacing: 8) {
                    Text(RadioDial.channelText(offset))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tuned ? accent : .white.opacity(0.45))
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 13, weight: tuned ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
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

            Button {
                guard !context.isPreview else { return }
                remove(item, at: offset)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("从收藏中移除 \(item.name)"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tuned ? accent.opacity(0.14) : .white.opacity(0.05)))
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

    // MARK: Search

    private var typedURL: URL? { RadioDial.streamURL(query) }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var search: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                TextField("", text: $query, prompt: Text("电台名称，或粘贴 http(s) 串流地址"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .onSubmit { typedURL == nil ? run() : addCustom() }
                    .disabled(context.isPreview)
                if searching { ProgressView().controlSize(.mini) }
                if !query.isEmpty, !context.isPreview {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassPane(cornerRadius: 10)

            if typedURL != nil {
                customRow
            } else {
                regionRow
                HStack(spacing: 6) {
                    Text(listTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
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
        HStack(spacing: 4) {
            ForEach(RadioRegion.allCases) { option in regionChip(option) }
        }
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
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(on ? accent.opacity(0.4) : .white.opacity(0.08)))
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
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .glassPane(cornerRadius: 8)
                .onSubmit(addCustom)
            chip(tr("添加自定义地址"), action: addCustom)
        }
    }

    private func resultRow(_ result: RadioStation) -> some View {
        let saved = stations.contains { $0.url == result.url }
        return HStack(spacing: 8) {
            Button {
                guard !context.isPreview else { return }
                addAndListen(result)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(result.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
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
                    .foregroundStyle(saved ? accent : .white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(saved ? 0 : 0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(saved ? tr("已在收藏中") : tr("加入收藏"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    /// Lists the region's top stations when the field is empty, otherwise
    /// searches names inside the region. A newer request wins over one still
    /// on its way.
    private func run(in chosen: RadioRegion? = nil) {
        guard !context.isPreview, typedURL == nil else { return }
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

    private func addCustom() {
        guard !context.isPreview, let custom = RadioDial.custom(name: customName, url: query) else { return }
        addAndListen(custom)
        query = ""
        customName = ""
        tab = .favourites
    }

    /// Adds the station unless it is already a favourite, tunes the dial to
    /// it, and starts it.
    private func addAndListen(_ station: RadioStation) {
        let current = stations
        let list = RadioDial.adding(station, to: current)
        guard let target = list.firstIndex(where: { $0.url == station.url }) else { return }
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
                    context.fill(face, with: .color(.white.opacity(0.05)))

                    for tick in 0...60 {
                        let angle = .pi + Double(tick) / 60 * .pi
                        let long = tick % 5 == 0
                        var line = Path()
                        line.move(to: point(angle, radius - (long ? 10 : 5)))
                        line.addLine(to: point(angle, radius))
                        context.stroke(line, with: .color(.white.opacity(long ? 0.45 : 0.18)),
                                       lineWidth: long ? 1.2 : 0.8)
                    }
                    for station in 0..<marks {
                        let at = point(Self.angle(station, count: marks), radius - 20)
                        let dot = CGRect(x: at.x - 2.5, y: at.y - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: dot),
                                     with: .color(station == shown ? tint : .white.opacity(0.4)))
                    }
                    let hub = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.stroke(Path(ellipseIn: hub), with: .color(.white.opacity(0.35)), lineWidth: 1)
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
