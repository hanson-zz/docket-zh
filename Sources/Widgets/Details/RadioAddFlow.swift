import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// 收音机面板“添加电台”的状态和流程：贴直播地址或导入 .m3u / .m3u8 / .pls，
/// 先试连一次，连上了直接存进收藏（标“自定义”），连不上提示但可以仍然保存。
///
/// 状态放在这里而不是面板的 @State：导入文件时面板会先收起（打开面板要到
/// 前台），选完再打开回来，填了一半的和试连结果都还在。
@MainActor @Observable
final class RadioAddFlow {
    static let shared = RadioAddFlow()

    enum Status: Equatable {
        case idle
        /// 正在读列表或试连，带一句说明。
        case working(String)
        /// 一句提示（地址不对、不支持、已在收藏里）。
        case message(String)
        /// 试连失败，可以“仍然保存”。
        case failed(String)
    }

    struct Draft {
        var open = false
        var address = ""
        var name = ""
        var status: Status = .idle
        /// 等用户决定的电台（试连有失败的）。
        var pending: [RadioStation] = []
        /// 其中试连成功的。
        var working: [RadioStation] = []
        /// 播放列表里跳过的不支持协议的地址个数。
        var skipped = 0
        /// 每次提交换一个，旧的试连结果回来时对不上就丢掉。
        var token = UUID()
    }

    private(set) var drafts: [UUID: Draft] = [:]

    private init() {}

    func draft(_ id: UUID) -> Draft { drafts[id] ?? Draft() }

    func update(_ id: UUID, _ change: (inout Draft) -> Void) {
        var draft = drafts[id] ?? Draft()
        change(&draft)
        drafts[id] = draft
    }

    func open(_ id: UUID) {
        update(id) { $0.open = true }
    }

    func close(_ id: UUID) {
        drafts[id] = nil
    }

    // MARK: Submitting

    /// 点“添加”：按地址的种类分流。
    func submit(_ id: UUID) {
        let draft = self.draft(id)
        switch RadioAddress(draft.address) {
        case .invalid:
            setStatus(id, .message(tr("请填 http:// 或 https:// 开头的直播地址。")))
        case .unsupported(let scheme):
            setStatus(id, .message(tr("不支持 \(scheme) 地址：只能播 http(s) 音频流和 HLS（.m3u8）。")))
        case .stream(let url):
            guard let station = RadioDial.custom(name: draft.name, url: url.absoluteString) else { return }
            probe([station], id: id, skipped: 0)
        case .playlist(let url):
            let token = restart(id, status: tr("正在读取播放列表…"))
            let typed = draft.name
            Task {
                let text = await RadioProbeClient.fetchPlaylist(url, timeout: RadioProbe.addTimeout)
                guard self.draft(id).token == token else { return }
                guard let text else {
                    self.setStatus(id, .message(tr("取不到这个播放列表，请检查地址。")))
                    return
                }
                if RadioPlaylist.isHLSManifest(text) {
                    // 其实是 HLS 流本身，直接当直播地址。
                    guard let station = RadioDial.custom(name: typed, url: url.absoluteString) else { return }
                    self.probe([station], id: id, skipped: 0)
                    return
                }
                self.handle(RadioPlaylist.parse(text, fallbackName: url.deletingPathExtension().lastPathComponent),
                            id: id, typedName: typed)
            }
        }
    }

    /// “导入文件…”：系统的打开面板。码头是辅助应用，不临时升到前台的话打开面板
    /// 会被别的窗口挡住；电台面板在它上面一层，开着会挡住它，所以先收起，选完
    /// （或取消）再打开回来。
    func importFile(_ id: UUID) {
        WidgetDetailWindow.shared.close()
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = tr("选择 .m3u、.m3u8 或 .pls 播放列表")
        panel.prompt = tr("导入")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["m3u", "m3u8", "pls"].compactMap { UTType(filenameExtension: $0) }
        let picked = panel.runModal() == .OK ? panel.url : nil
        update(id) { $0.open = true }
        WidgetPanelOpener.shared.open(id)
        guard let picked else { return }

        guard let data = try? Data(contentsOf: picked), data.count < 1_000_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            setStatus(id, .message(tr("读不了这个文件。")))
            return
        }
        handle(RadioPlaylist.parse(text, fallbackName: picked.deletingPathExtension().lastPathComponent),
               id: id, typedName: draft(id).name)
    }

    private func handle(_ parsed: RadioPlaylist.Parsed, id: UUID, typedName: String) {
        if parsed.isHLSManifest {
            setStatus(id, .message(tr("这是 HLS 流本身的清单，不是电台列表，请粘贴它的网址。")))
            return
        }
        guard !parsed.stations.isEmpty else {
            setStatus(id, .message(parsed.unsupported > 0
                                   ? tr("播放列表里只有不支持的地址（RTMP、RTSP、MMS 这类）。")
                                   : tr("播放列表里没有找到 http(s) 直播地址。")))
            return
        }
        var stations = parsed.stations
        let name = RadioPlaylist.cleanName(typedName)
        if stations.count == 1, !name.isEmpty { stations[0].name = name }
        probe(stations, id: id, skipped: parsed.unsupported)
    }

    /// 每个电台试连一次（主地址不行再试备用），同时最多 4 个。
    private func probe(_ stations: [RadioStation], id: UUID, skipped: Int) {
        let token = restart(id, status: stations.count == 1
                            ? tr("正在试连…") : tr("正在试连 \(stations.count) 个电台…"))
        update(id) { $0.skipped = skipped }
        Task {
            let alive = await Self.reachable(stations)
            guard self.draft(id).token == token else { return }
            let working = stations.filter { alive.contains($0.id) }
            if working.count == stations.count {
                self.save(stations, id: id)
                return
            }
            self.update(id) { draft in
                draft.pending = stations
                draft.working = working
                draft.status = .failed(stations.count == 1
                    ? tr("试连没有收到声音：地址可能有误，或者电台暂时离线。")
                    : tr("\(stations.count) 个电台里有 \(stations.count - working.count) 个试连不上。"))
            }
        }
    }

    /// 试连失败后用户选“仍然保存”或“只保存连得上的”。
    func saveAnyway(_ id: UUID, onlyWorking: Bool) {
        let draft = self.draft(id)
        let list = onlyWorking ? draft.working : draft.pending
        guard !list.isEmpty else { return }
        save(list, id: id)
    }

    private func save(_ list: [RadioStation], id: UUID) {
        guard let instance = WidgetWriter.current(id), instance.kind == .radio else { return }
        let existing = RadioDial.stations(instance.config)
        var merged = existing
        for station in list { merged = RadioDial.adding(station, to: merged) }
        guard merged.count > existing.count else {
            setStatus(id, .message(existing.count >= RadioDial.maxStations
                                   ? tr("收藏最多 \(RadioDial.maxStations) 个电台，先删掉一些再添加。")
                                   : tr("已经在收藏里了。")))
            return
        }
        let target = existing.count
        RadioRemote.edit(instance) { stored, index in
            stored = merged
            index = target
        }
        let player = RadioPlayer.shared
        if player.isPlaying {
            player.play(merged[target], volume: instance.config.double("volume", default: 60),
                        stations: merged, owner: id)
        }
        let added = merged.count - existing.count
        let skipped = draft(id).skipped
        if skipped > 0 {
            update(id) { draft in
                draft = Draft()
                draft.open = true
                draft.status = .message(tr("已添加 \(added) 个电台，跳过 \(skipped) 条不支持的地址。"))
            }
        } else {
            close(id)
        }
    }

    // MARK: Helpers

    private func setStatus(_ id: UUID, _ status: Status) {
        update(id) { $0.status = status }
    }

    /// 开始新一轮：换 token，清掉上次的结果。
    private func restart(_ id: UUID, status: String) -> UUID {
        let token = UUID()
        update(id) { draft in
            draft.token = token
            draft.status = .working(status)
            draft.pending = []
            draft.working = []
        }
        return token
    }

    /// 连得上的电台 id：任一条地址连得上就算。
    private nonisolated static func reachable(_ stations: [RadioStation]) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self) { group in
            var alive = Set<String>()
            var next = 0
            while next < min(RadioProbe.maxConcurrent, stations.count) {
                let station = stations[next]
                group.addTask { (station.id, await anyAddress(station)) }
                next += 1
            }
            while let (id, ok) = await group.next() {
                if ok { alive.insert(id) }
                if next < stations.count {
                    let station = stations[next]
                    group.addTask { (station.id, await anyAddress(station)) }
                    next += 1
                }
            }
            return alive
        }
    }

    private nonisolated static func anyAddress(_ station: RadioStation) async -> Bool {
        for address in station.addresses {
            if await RadioProbeClient.check(address, timeout: RadioProbe.addTimeout) { return true }
        }
        return false
    }
}
