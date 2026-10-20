import Foundation

/// 相册轮播：放哪些照片、现在是哪张、下一张什么时候换、上一张/暂停/下一张。
///
/// 现在是哪张不靠计时器，照样从时钟算（卡片每秒重画）：配置里记一个“锚点”，
/// 某张照片（`anchor`）从某个时刻（`anchorAt`）开始显示，之后每过一个间隔往后
/// 走一张。没存过锚点的老卡片锚在参考日期的第 0 张，和原来按时钟分格一样一直
/// 在转，不用写任何配置。
///
/// - 下一张、上一张：锚到那张，从现在起重新计时。
/// - 暂停：记下暂停的时刻（`pausedAt`），之后一直显示那一刻的照片；继续时锚到
///   这张、从现在起重新计时。
/// - 排除一张：先锚到正在显示的这张、保留倒计时，再把它去掉，这样排除后面的
///   照片不会让正在看的这张跳走。
///
/// 顺序：文件按文件夹读到的顺序（新的在前）；随机顺序按照片名字的哈希排，
/// 去掉或加进一张时其余照片的先后不变。“那年今天优先”时照片图库里往年今天
/// 的照片排在最前面（id 以 `memoryPrefix` 开头），之后才是文件夹。
public enum PhotoRotation {

    // MARK: 配置键

    public static let folderKey = "folder"
    public static let foldersKey = "folders"
    public static let foldersOffKey = "foldersOff"
    public static let excludedKey = "excluded"
    public static let intervalKey = "interval"
    public static let shuffleKey = "shuffle"
    public static let memoriesFirstKey = "memoriesFirst"
    public static let anchorKey = "anchor"
    public static let anchorAtKey = "anchorAt"
    public static let pausedAtKey = "pausedAt"

    /// 照片图库里的照片在轮播里的 id 前缀，后面接 PHAsset 的 localIdentifier。
    public static let memoryPrefix = "photos:"

    /// 面板里的四档间隔：1 分钟、10 分钟、1 小时、每天。
    public static let intervalChoices: [Double] = [60, 600, 3_600, 86_400]
    /// 新放的相册默认 10 分钟换一张。
    public static let defaultInterval: Double = 600
    /// 老卡片存过 30 秒这样的短间隔，照旧认，只是不低于 5 秒。
    public static let minimumInterval: Double = 5
    public static let maximumInterval: Double = 86_400
    /// “接下来”网格露几张。
    public static let upcomingCount = 8
    /// 最多记多少张排除的照片，再多就丢最早的。
    public static let maxExcluded = 500
    /// 最多几个文件夹。
    public static let maxFolders = 12

    public static func interval(_ config: WidgetConfig) -> Double {
        let raw = config.double(intervalKey, default: defaultInterval)
        guard raw.isFinite else { return defaultInterval }
        return min(max(raw, minimumInterval), maximumInterval)
    }

    /// 面板上四档里选中的是哪档；老卡片存的不在四档里时是 nil。
    public static func choiceIndex(_ interval: Double) -> Int? {
        intervalChoices.firstIndex { abs($0 - interval) < 0.5 }
    }

    public static func intervalTitle(_ seconds: Double) -> String {
        switch seconds {
        case 86_400...: tr("每天")
        case 3_600...: tr("\(Int(seconds / 3_600)) 小时")
        case 60...: tr("\(Int(seconds / 60)) 分钟")
        default: tr("\(Int(seconds)) 秒")
        }
    }

    // MARK: 文件夹

    /// 轮播的文件夹：第一个是原来那一个 `folder`（空是“图片”文件夹，卡片设置和
    /// 右键“选择文件夹…”改的也是它），后面是面板里加的 `folders`。路径原样返回。
    public static func folders(_ config: WidgetConfig) -> [String] {
        let first = config.string(folderKey)
        var seen: Set<String> = [first]
        return [first] + config.strings(foldersKey).filter { seen.insert($0).inserted }
    }

    /// 打着勾、真正在轮播的文件夹。全都取消了勾时返回空，面板提示勾一个。
    public static func activeFolders(_ config: WidgetConfig) -> [String] {
        let off = Set(config.strings(foldersOffKey))
        return folders(config).filter { !off.contains($0) }
    }

    public static func isFolderOn(_ path: String, _ config: WidgetConfig) -> Bool {
        !config.strings(foldersOffKey).contains(path)
    }

    /// 加一个文件夹。已经在里面的只打上勾；超过上限不加，返回 false。
    @discardableResult
    public static func addFolder(_ path: String, to config: inout WidgetConfig) -> Bool {
        let list = folders(config)
        if !list.contains(path) {
            guard list.count < maxFolders else { return false }
            write(list + [path], to: &config)
        }
        setFolder(path, on: true, in: &config)
        return true
    }

    public static func setFolder(_ path: String, on: Bool, in config: inout WidgetConfig) {
        var off = config.strings(foldersOffKey).filter { $0 != path }
        if !on { off.append(path) }
        config.set(foldersOffKey, .list(off.map { .string($0) }))
    }

    /// 去掉一个文件夹。去掉第一个时第二个顶上；去掉最后一个时回到“图片”文件夹。
    public static func removeFolder(_ path: String, from config: inout WidgetConfig) {
        var list = folders(config).filter { $0 != path }
        if list.isEmpty { list = [""] }
        write(list, to: &config)
        setFolder(path, on: true, in: &config)
    }

    private static func write(_ list: [String], to config: inout WidgetConfig) {
        config.set(folderKey, .string(list.first ?? ""))
        config.set(foldersKey, .list(list.dropFirst().map { .string($0) }))
    }

    // MARK: 排除

    public static func excluded(_ config: WidgetConfig) -> [String] {
        config.strings(excludedKey)
    }

    public static func exclude(_ id: String, in config: inout WidgetConfig) {
        var list = excluded(config).filter { $0 != id }
        list.append(id)
        if list.count > maxExcluded { list.removeFirst(list.count - maxExcluded) }
        config.set(excludedKey, .list(list.map { .string($0) }))
    }

    public static func restore(_ id: String, in config: inout WidgetConfig) {
        let list = excluded(config).filter { $0 != id }
        config.set(excludedKey, .list(list.map { .string($0) }))
    }

    public static func restoreAll(in config: inout WidgetConfig) {
        config.set(excludedKey, .list([]))
    }

    // MARK: 顺序

    /// 轮播的顺序。`memories` 是照片图库里往年今天的照片（已带前缀），
    /// `files` 是文件夹里的图片路径；排除的都去掉，重复的只留第一次。
    public static func order(memories: [String], files: [String], excluded: [String],
                             shuffle: Bool, memoriesFirst: Bool) -> [String] {
        let skip = Set(excluded)
        var seen = Set<String>()
        func clean(_ ids: [String]) -> [String] {
            ids.filter { !skip.contains($0) && seen.insert($0).inserted }
        }
        let lead = memoriesFirst ? clean(memories) : []
        let rest = clean(files)
        guard shuffle else { return lead + rest }
        return shuffled(lead) + shuffled(rest)
    }

    /// 按哈希排：每台 Mac、每次重画都一样，加减一张时其余照片的先后不变。
    static func shuffled(_ ids: [String]) -> [String] {
        let keyed: [(id: String, key: UInt64)] = ids.map { id in (id: id, key: hash(id)) }
        let sorted = keyed.sorted { (a: (id: String, key: UInt64), b: (id: String, key: UInt64)) -> Bool in
            if a.key != b.key { return a.key < b.key }
            return a.id < b.id
        }
        return sorted.map { $0.id }
    }

    /// FNV-1a 64 位，`hashValue` 每次启动都不一样，不能用。
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100_0000_01b3
        }
        // 再搅一下，名字相近的文件（IMG_0001、IMG_0002）不至于挨着。
        value ^= value >> 33
        value = value &* 0xff51_afd7_ed55_8ccd
        value ^= value >> 33
        return value
    }

    // MARK: 锚点

    public struct State: Equatable, Sendable {
        /// 从 `anchorAt` 起显示的那张；nil 是第 0 张。
        public var anchor: String?
        /// 参考日期起的秒数。
        public var anchorAt: Double
        /// 暂停的时刻；nil 是在转。
        public var pausedAt: Double?

        public init(anchor: String? = nil, anchorAt: Double = 0, pausedAt: Double? = nil) {
            self.anchor = anchor
            self.anchorAt = anchorAt
            self.pausedAt = pausedAt
        }

        public var isPaused: Bool { pausedAt != nil }
    }

    public static func state(_ config: WidgetConfig) -> State {
        let anchor = config.string(anchorKey)
        let at = config.double(anchorAtKey)
        let paused = config.double(pausedAtKey)
        return State(anchor: anchor.isEmpty ? nil : anchor,
                     anchorAt: at.isFinite ? at : 0,
                     pausedAt: paused.isFinite && paused > 0 ? paused : nil)
    }

    public static func write(_ state: State, to config: inout WidgetConfig) {
        config.set(anchorKey, .string(state.anchor ?? ""))
        config.set(anchorAtKey, .number(state.anchorAt))
        config.set(pausedAtKey, .number(state.pausedAt ?? 0))
    }

    /// 从锚点起走了几格（不小于 0）。
    static func steps(at date: Date, state: State, interval: Double) -> Int {
        let step = max(minimumInterval, interval.isFinite ? interval : defaultInterval)
        let now = state.pausedAt ?? date.timeIntervalSinceReferenceDate
        let elapsed = now - state.anchorAt
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let count = (elapsed / step).rounded(.down)
        // 时钟被拨得离谱时也不溢出。
        return Int(min(count, 1e12))
    }

    /// 现在显示 `order` 里的第几张；空列表是 nil。
    public static func position(at date: Date, order: [String], state: State, interval: Double) -> Int? {
        guard !order.isEmpty else { return nil }
        let base = state.anchor.flatMap { order.firstIndex(of: $0) } ?? 0
        let steps = steps(at: date, state: state, interval: interval)
        return (base + steps % order.count) % order.count
    }

    public static func current(at date: Date, order: [String], state: State, interval: Double) -> String? {
        position(at: date, order: order, state: state, interval: interval).map { order[$0] }
    }

    /// 还有几秒换下一张；暂停时或只有一张时是 nil。
    public static func secondsToNext(at date: Date, count: Int, state: State, interval: Double) -> Double? {
        guard state.pausedAt == nil, count > 1 else { return nil }
        let step = max(minimumInterval, interval.isFinite ? interval : defaultInterval)
        let elapsed = date.timeIntervalSinceReferenceDate - state.anchorAt
        guard elapsed.isFinite else { return step }
        // 时钟往回拨过：下一张在锚点之后一个间隔。
        if elapsed < 0 { return step - elapsed }
        return step - elapsed.truncatingRemainder(dividingBy: step)
    }

    /// “8 分钟后换下一张”；不到 1 分钟写秒，超过 1 小时写几小时。
    public static func countdownText(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded(.up)))
        if total < 60 { return tr("\(total) 秒后换下一张") }
        let minutes = Int((Double(total) / 60).rounded(.up))
        if minutes < 60 { return tr("\(minutes) 分钟后换下一张") }
        let hours = Int((Double(minutes) / 60).rounded(.down))
        return tr("约 \(hours) 小时后换下一张")
    }

    /// 往前或往后走 `by` 张，从现在起重新计时；暂停着的继续暂停在新的那张。
    public static func stepped(_ by: Int, at date: Date, order: [String], state: State,
                               interval: Double) -> State {
        guard let here = position(at: date, order: order, state: state, interval: interval) else { return state }
        let count = order.count
        let next = ((here + by) % count + count) % count
        let now = date.timeIntervalSinceReferenceDate
        return State(anchor: order[next], anchorAt: now, pausedAt: state.isPaused ? now : nil)
    }

    public static func paused(at date: Date, order: [String], state: State, interval: Double) -> State {
        guard !state.isPaused else { return state }
        var result = state
        result.pausedAt = date.timeIntervalSinceReferenceDate
        // 锚到正在显示的这张，之后列表变了也停在这张。
        if let here = current(at: date, order: order, state: state, interval: interval) {
            result.anchor = here
            result.anchorAt = result.pausedAt ?? 0
        }
        return result
    }

    public static func resumed(at date: Date, order: [String], state: State, interval: Double) -> State {
        guard state.isPaused else { return state }
        let here = current(at: date, order: order, state: state, interval: interval)
        return State(anchor: here ?? state.anchor, anchorAt: date.timeIntervalSinceReferenceDate, pausedAt: nil)
    }

    /// 锚到正在显示的这张、保留离下一张还剩的时间。排除照片、换顺序之前先调它。
    /// 要去掉的正是这张时锚到下一张（从现在起重新计时）。
    public static func reanchored(at date: Date, order: [String], state: State, interval: Double,
                                  removing: String? = nil) -> State {
        guard let here = position(at: date, order: order, state: state, interval: interval) else { return state }
        let step = max(minimumInterval, interval.isFinite ? interval : defaultInterval)
        let now = date.timeIntervalSinceReferenceDate
        if let removing, order[here] == removing {
            let rest = order.filter { $0 != removing }
            guard !rest.isEmpty else { return State(anchor: nil, anchorAt: now, pausedAt: state.pausedAt) }
            // 原来顺序里这张之后第一张还在的。
            var next: String?
            for offset in 1...order.count where order[(here + offset) % order.count] != removing {
                next = order[(here + offset) % order.count]
                break
            }
            return State(anchor: next, anchorAt: now, pausedAt: state.isPaused ? now : nil)
        }
        if state.isPaused {
            return State(anchor: order[here], anchorAt: state.pausedAt ?? now, pausedAt: state.pausedAt)
        }
        let steps = Double(steps(at: date, state: state, interval: interval))
        let slotStart = state.anchorAt + steps * step
        return State(anchor: order[here], anchorAt: slotStart.isFinite ? slotStart : now, pausedAt: nil)
    }

    /// “接下来”：正在显示的这张之后的几张（不含这张，不重复，不超过列表里其余的张数）。
    public static func upcoming(at date: Date, order: [String], state: State, interval: Double,
                                count: Int = upcomingCount) -> [String] {
        guard let here = position(at: date, order: order, state: state, interval: interval) else { return [] }
        let n = min(max(0, count), order.count - 1)
        guard n > 0 else { return [] }
        return (1...n).map { order[(here + $0) % order.count] }
    }
}
