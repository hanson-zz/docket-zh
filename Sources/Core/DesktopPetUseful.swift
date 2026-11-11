import Foundation

// 让小熊猫「有用」的三件事里的纯逻辑：
// 1. 拖文件到它身上就暂存：放进哪张卡片见 `DesktopPetDirector.shelfWidget`，等着接的动作见
//    `DesktopPetBrain.expecting`。
// 2. 连续打字太久提醒活动：`DesktopPetStretchClock` 按「多久没按键」算连续打字，满 50 分钟发
//    `.stretchReminder`。
// 3. 下载完成提示：`DesktopPetDownloadWatch` 看下载文件夹第一层，新文件（不是 .crdownload 这类
//    临时文件）大小 2 秒不变才算下好，发 `.downloadFinished`；3 秒内的合并成一批（`DesktopPetDownloads`）。

// MARK: - 常量和气泡上的话

extension DesktopPetAssist {
    /// 连续打字满这么多秒提醒一次。
    public static let stretchAfter: TimeInterval = 50 * 60
    /// 中间没按键超过这么多秒就不算连续，重新计时（离开电脑同样重置）。
    public static let stretchBreak: TimeInterval = 5 * 60
    /// 提醒过以后这么多秒内不再提醒。
    public static let stretchCooldown: TimeInterval = 50 * 60
    /// 活动提醒的气泡停几秒。
    public static let stretchBubble: TimeInterval = 6

    /// 下载的文件大小这么多秒不变才算下好。
    public static let downloadSettle: TimeInterval = 2
    /// 下载好了叼过来时跑多远（点，按大小设置缩放）。
    public static let fetchRun: Double = 70
    /// 下载提示的气泡停几秒。
    public static let downloadBubble: TimeInterval = 5
    /// 气泡里的文件名最多几个字，长了中间省略。
    public static let downloadNameLimit = 24

    /// 文件拖到身上时最多探着等多久（松手、移开会提前结束）。
    public static let expectHold: TimeInterval = 30

    /// 「起来活动一下吧」/ "Time to stretch"。
    public static var stretchText: String { tr("起来活动一下吧") }

    /// 「先在扩展栏添加文件暂存」/ 英文：文件拖到身上、码头上却没有文件暂存卡片时说。
    public static var needsShelfText: String { tr("先在扩展栏添加文件暂存") }

    /// 「下载好了：文件名」/ "Downloaded: name"；多个时「下载好了 N 个文件」/ "Downloaded N files"。
    public static func downloadedText(_ paths: [String]) -> String {
        if paths.count == 1, let path = paths.first {
            let name = shortName((path as NSString).lastPathComponent)
            return tr("下载好了：\(name)")
        }
        return tr("下载好了 \(max(0, paths.count)) 个文件")
    }

    /// 文件名太长时中间省略，尽量留住扩展名：「一份很长很长的…报告.pdf」。
    public static func shortName(_ name: String, limit: Int = downloadNameLimit) -> String {
        let chars = Array(name)
        guard chars.count > limit, limit >= 4 else { return name }
        let ext = (name as NSString).pathExtension
        // 尾巴留扩展名和它前面几个字，头上留剩下的。
        let tail = min(chars.count - 1, max(ext.isEmpty ? 0 : ext.count + 1, (limit - 1) / 3))
        let head = max(1, limit - 1 - tail)
        return String(chars.prefix(head)) + "…" + String(chars.suffix(tail))
    }
}

// MARK: - 下载好的一批

/// 刚报过的一批下载：3 秒内新下好的并进来，气泡改说「下载好了 N 个文件」。
public struct DesktopPetDownloads: Equatable, Sendable {
    /// 下好的文件，按先后，不重复。
    public var paths: [String]
    /// 最近一次并进来的时刻。
    public var lastAt: Date

    public init(paths: [String], lastAt: Date) {
        var seen = Set<String>()
        self.paths = paths.filter { seen.insert($0).inserted }
        self.lastAt = lastAt
    }

    public var text: String { DesktopPetAssist.downloadedText(paths) }

    /// 3 秒内的并进 `recent`，否则另起一批。
    public static func merged(_ paths: [String], into recent: DesktopPetDownloads?, now: Date) -> DesktopPetDownloads {
        if let recent, now >= recent.lastAt, now.timeIntervalSince(recent.lastAt) <= DesktopPetAssist.mergeWindow {
            return DesktopPetDownloads(paths: recent.paths + paths, lastAt: now)
        }
        return DesktopPetDownloads(paths: paths, lastAt: now)
    }
}

// MARK: - 活动提醒

/// 连续打字计时。不读按了什么键，只看系统「多久没按键」（不要辅助功能权限）。
/// 两次按键之间不超过 5 分钟算连续；专注计时走着时不算（专注结束后从头算）；
/// 离开电脑（锁屏、睡眠、空闲满 5 分钟）由外面调 `reset`。
public struct DesktopPetStretchClock: Equatable, Sendable {
    /// 这一段连续打字从什么时候开始；没在打字是 nil。
    public private(set) var activeSince: Date?
    /// 上一次提醒的时刻。
    public private(set) var lastReminded: Date?
    /// 上一次看的时刻：两次之间隔太久（睡眠、卡住）当中断。
    public private(set) var lastTick: Date?

    public init() {}

    /// 看一次。`keyIdle` 是多少秒没按键，`focusing` 是专注计时正在走。该提醒时返回 true。
    public mutating func tick(now: Date, keyIdle: TimeInterval, focusing: Bool) -> Bool {
        defer { lastTick = now }
        if let lastTick, now.timeIntervalSince(lastTick) >= DesktopPetAssist.stretchBreak { activeSince = nil }
        guard !focusing, keyIdle < DesktopPetAssist.stretchBreak else {
            activeSince = nil
            return false
        }
        let start = activeSince ?? now.addingTimeInterval(-max(0, keyIdle))
        activeSince = start
        guard now.timeIntervalSince(start) >= DesktopPetAssist.stretchAfter else { return false }
        if let lastReminded, now >= lastReminded,
           now.timeIntervalSince(lastReminded) < DesktopPetAssist.stretchCooldown { return false }
        lastReminded = now
        activeSince = now
        return true
    }

    /// 离开电脑了：这一段不算了。
    public mutating func reset() {
        activeSince = nil
    }
}

// MARK: - 下载完成

/// 看下载文件夹第一层：第一次看到的都算老文件；后来新出现的、不是临时文件（.crdownload、
/// .download、.part、.partial）也不是隐藏文件的，大小 2 秒不变才算下好，报一次。
/// 浏览器下完把临时文件改成真名，真名的文件就是新出现的。
public struct DesktopPetDownloadWatch: Equatable, Sendable {
    private struct Pending: Equatable, Sendable {
        var size: Int64
        /// 大小最后一次变的时刻。
        var since: Date
    }

    private var known: Set<String> = []
    private var pending: [String: Pending] = [:]
    public private(set) var primed = false

    public init() {}

    /// 还有新文件在等大小稳定：过 2 秒要再看一次。
    public var waiting: Bool { !pending.isEmpty }

    /// 不算下载的名字：临时文件和隐藏文件。
    public static func ignored(_ name: String) -> Bool {
        name.hasPrefix(".") || DownloadProgress.partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// 喂一次文件夹第一层（名字 → 大小，文件夹的大小随便给个稳定的数）。返回这次确认下好的名字。
    public mutating func observe(_ listing: [String: Int64], now: Date) -> [String] {
        guard primed else {
            primed = true
            known = Set(listing.keys)
            return []
        }
        known = known.filter { listing[$0] != nil }
        pending = pending.filter { listing[$0.key] != nil }
        var done: [String] = []
        for name in listing.keys.sorted() where !known.contains(name) && !Self.ignored(name) {
            let size = listing[name] ?? 0
            if let seen = pending[name] {
                if seen.size != size {
                    pending[name] = Pending(size: size, since: now)
                } else if now.timeIntervalSince(seen.since) >= DesktopPetAssist.downloadSettle {
                    pending[name] = nil
                    known.insert(name)
                    done.append(name)
                }
            } else {
                pending[name] = Pending(size: size, since: now)
            }
        }
        return done
    }
}
