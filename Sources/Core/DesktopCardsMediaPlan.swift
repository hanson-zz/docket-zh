import Foundation

// MARK: - 钉在桌面 · 媒体组的专属布局
//
// 正在播放、播客、收音机、复古卡带、录音、麦克风、环境音、应用音量钉在桌面时不再是
// 放大的扩展栏卡片或塞进去的面板，而是按小 160×160 / 中 340×160 / 大 340×340 专门排的
// 布局（视图在 Sources/Widgets/DesktopCards/DesktopCardsMedia.swift）。这里放纯判断：
// 哪几种有专属布局、每档放哪些键、列表放几行、电台列表从哪一台开始、拖音量条落在多少。

public enum DesktopCardsMediaPlan {
    /// 媒体组负责的小组件。三档都有专属布局，小号总能放下。
    public static let kinds: Set<WidgetKind> = [
        .music, .podcast, .radio, .cassette, .recorder, .microphone, .ambient, .appVolume,
    ]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 有专属布局的种类三档都提供（大号照旧是 Pro，见 `DesktopPinGate`）。
    public static func sizes(_ kind: WidgetKind) -> [DesktopPinSize] {
        handles(kind) ? DesktopPinSize.allCases : []
    }

    // MARK: 播放键

    /// 卡片上的一个播放控制键。
    public enum Key: String, Equatable, Sendable {
        /// 快退若干秒（正在播放的设置秒数，播客 15 秒）。
        case back
        case previous
        case playPause
        case next
        /// 快进若干秒（正在播放的设置秒数，播客 30 秒）。
        case forward
    }

    /// 正在播放、复古卡带：小号只有播放暂停；中号加上一首 / 下一首（设置里关掉的不放）；
    /// 大号再加快退快进（来源能拖进度时）。网页视频只有播放暂停。
    public static func musicKeys(_ size: DesktopPinSize, skips: Bool, canSeek: Bool,
                                 previous: Bool = true, next: Bool = true) -> [Key] {
        guard size != .small, skips else { return [.playPause] }
        var keys: [Key] = []
        if size == .large, canSeek { keys.append(.back) }
        if previous { keys.append(.previous) }
        keys.append(.playPause)
        if next { keys.append(.next) }
        if size == .large, canSeek { keys.append(.forward) }
        return keys
    }

    /// 播客：小号只有播放暂停；中号、大号是后退 15 / 播放 / 前进 30（正在放这一集时）。
    public static func podcastKeys(_ size: DesktopPinSize, current: Bool) -> [Key] {
        guard size != .small, current else { return [.playPause] }
        return [.back, .playPause, .forward]
    }

    /// 收音机：小号只有播放暂停；中号、大号收藏不止一台时加上一台 / 下一台。
    public static func radioKeys(_ size: DesktopPinSize, stations: Int) -> [Key] {
        guard size != .small, stations > 1 else { return [.playPause] }
        return [.previous, .playPause, .next]
    }

    // MARK: 列表行数

    /// 各种卡片每档列几行（不列表的是 0）。按卡片高度排好的，放得下不滚动。
    /// - 应用音量：小 1 个、中 3 个、大 6 个应用。
    /// - 收音机：大号列 4 台收藏。
    /// - 播客：大号列 3 个单集。
    /// - 录音：中号 1 条最近录音（没在录时）、大号 3 条。
    /// - 麦克风：大号列 3 个正在用麦克风的应用。
    public static func listRows(_ kind: WidgetKind, size: DesktopPinSize) -> Int {
        switch (kind, size) {
        case (.appVolume, .small): 1
        case (.appVolume, .medium): 3
        case (.appVolume, .large): 6
        case (.radio, .large): 4
        case (.podcast, .large): 3
        case (.recorder, .medium): 1
        case (.recorder, .large): 3
        case (.microphone, .large): 3
        default: 0
        }
    }

    /// 列表放 `rows` 行，`count` 个里显示几个、还剩几个没显示（写「还有 N 个」）。
    public static func split(count: Int, rows: Int) -> (shown: Int, more: Int) {
        let total = max(0, count), room = max(0, rows)
        let shown = min(total, room)
        return (shown, total - shown)
    }

    /// 应用音量：改过音量或静音的排前面（免得被挤出卡片），同类保持原来的顺序；
    /// 取前 `rows` 个，返回显示的和剩下几个。
    public static func appVolumeRows<T>(_ rows: [T], size: DesktopPinSize,
                                        changed: (T) -> Bool) -> (shown: [T], more: Int) {
        let ordered = rows.filter(changed) + rows.filter { !changed($0) }
        let room = listRows(.appVolume, size: size)
        let shown = Array(ordered.prefix(room))
        return (shown, rows.count - shown.count)
    }

    /// 收音机大号的收藏列表：一共 `count` 台，放 `rows` 行，正在收听的那台尽量放在第二行
    /// （上面露出前一台，往下看得到接下来的），到头到尾时贴边，不留空行。
    public static func stationWindow(current: Int, count: Int, rows: Int) -> Range<Int> {
        guard count > 0, rows > 0 else { return 0..<0 }
        guard count > rows else { return 0..<count }
        let index = min(max(0, current), count - 1)
        let start = min(max(0, index - 1), count - rows)
        return start..<(start + rows)
    }

    // MARK: 进度

    /// 中号、大号在有时长时画进度条和两头的时间；小号不画（160 宽只放核心）。
    public static func showsProgress(_ size: DesktopPinSize, duration: Double) -> Bool {
        size != .small && duration.isFinite && duration > 0
    }

    /// 进度条的比例，0...1；时长不对时是 0。
    public static func fraction(elapsed: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// 点进度条上的位置跳过去：横向位置换成秒数（0 到时长）。
    public static func seekTarget(x: Double, width: Double, duration: Double) -> Double? {
        guard width > 0, duration.isFinite, duration > 0, x.isFinite else { return nil }
        return min(1, max(0, x / width)) * duration
    }

    // MARK: 应用音量

    /// 点或拖音量条：位置直接就是音量（整条 0 到 150%，100% 在三分之二处），靠近 100% 吸过去。
    public static func appVolumePercent(x: Double, width: Double) -> Double {
        guard width > 0, x.isFinite else { return AppVolume.unity }
        let ratio = min(1, max(0, x / width))
        return AppVolume.snapped(ratio * AppVolume.range.upperBound)
    }

    // MARK: 环境音

    /// 环境音大号的声音格子每行几个（七种声音排两行）。
    public static let ambientColumns = 4

    /// 点一种声音：在组合里就拿掉，不在就加到最后。最后一种不让拿掉（拿掉就没声音可放了）。
    public static func toggling(_ sound: AmbientSound, in sounds: [AmbientSound]) -> [AmbientSound] {
        if sounds.contains(sound) {
            guard sounds.count > 1 else { return sounds }
            return sounds.filter { $0 != sound }
        }
        return sounds + [sound]
    }

    // MARK: 时间小字

    /// 「已 12 分钟」：麦克风列表里某个应用用了多久，按分钟取整，不到一分钟写「刚刚」。
    public static func usedFor(since: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(since)) / 60)
        if minutes < 1 { return tr("刚刚") }
        if minutes < 60 { return tr("已 \(minutes) 分钟") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? tr("已 \(hours) 小时") : tr("已 \(hours) 小时 \(rest) 分")
    }
}
