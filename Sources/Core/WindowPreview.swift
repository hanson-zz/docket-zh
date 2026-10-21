import CoreGraphics
import Foundation

/// 悬停扩展栏上正在运行的 App 格子时弹出的窗口预览（码头 Pro）：可测的部分。
///
/// - 悬停状态机 `WindowPreviewHover`：停够 `openDelay` 才弹；已经开着时移到
///   另一个正在运行的 App 直接换过去；离开格子和小窗后再等 `closeGrace` 才收，
///   让指针能从格子走到小窗上。拖动、改大小、别的小窗开着时一律不弹。
/// - 窗口排序和截断 `arrange`：没最小化的按系统给的先后（一般是最近用过的在前），
///   最小化的排在后面，最多 `maxWindows` 个。
/// - 小窗尺寸 `panelSize` 和弹出位置 `origin`：按扩展栏所在的边往屏幕里面弹，
///   夹在屏幕可见范围内。
public enum WindowPreview {

    /// 指针在格子上停多久才弹（秒）。
    public static let openDelay: TimeInterval = 0.5
    /// 离开格子和小窗后多久收起（秒），够指针走过格子和小窗之间的空隙。
    public static let closeGrace: TimeInterval = 0.3
    /// 最多列几个窗口，多出来的写「还有 N 个窗口」。
    public static let maxWindows = 8
    /// 截好的缩略图用多久（秒），再悬停同一个 App 不用重截。
    public static let cacheLifetime: TimeInterval = 4

    // MARK: 尺寸

    /// 缩略图框的大小（缩略图按窗口比例放在里面）。
    public static let thumbnailSize = CGSize(width: 184, height: 116)
    /// 缩略图下面的名字一行高（13pt）。
    public static let captionHeight: CGFloat = 20
    /// 没有屏幕录制权限时的文字卡高度（标题最多两行，加「已最小化」一行）。
    public static let textCardHeight: CGFloat = 64
    public static let spacing: CGFloat = 10
    public static let padding: CGFloat = 14
    /// 顶上一行「访达 · 3 个窗口」。
    public static let headerHeight: CGFloat = 22
    /// 底部一行权限说明和按钮。
    public static let noticeHeight: CGFloat = 30
    /// 一屏最多露出几张，再多横向滚动。
    public static let maxVisibleColumns = 4
    /// 小窗最窄，空列表或只有一个窗口时也放得下说明。
    public static let minWidth: CGFloat = 300
    /// 小窗离格子多远。
    public static let gap: CGFloat = 10
    /// 离屏幕可见范围边缘至少多远。
    public static let screenMargin: CGFloat = 6

    /// 一张卡片的高度：缩略图加名字，或文字卡。
    public static func cardHeight(thumbnails: Bool) -> CGFloat {
        thumbnails ? thumbnailSize.height + 6 + captionHeight : textCardHeight
    }

    /// 横排露出几列：窗口数、上限 4 列、屏幕宽度三者取小，至少 1 列。
    public static func visibleColumns(count: Int, visibleWidth: CGFloat) -> Int {
        let card = thumbnailSize.width
        let room = max(0, visibleWidth - 2 * screenMargin - 2 * padding + spacing)
        let fit = max(1, Int(room / (card + spacing)))
        return max(1, min(maxVisibleColumns, fit, max(1, count)))
    }

    /// 小窗大小。`notice` 是底部那行权限说明（没屏幕录制或没辅助功能时）。
    public static func panelSize(count: Int, thumbnails: Bool, notice: Bool,
                                 visibleWidth: CGFloat) -> CGSize {
        let columns = visibleColumns(count: count, visibleWidth: visibleWidth)
        let cards = CGFloat(columns) * thumbnailSize.width + CGFloat(columns - 1) * spacing
        let width = min(max(minWidth, cards + 2 * padding),
                        max(minWidth, visibleWidth - 2 * screenMargin))
        var height = 2 * padding + headerHeight + spacing
        height += count > 0 ? cardHeight(thumbnails: thumbnails) : textCardHeight
        if notice { height += spacing + noticeHeight }
        return CGSize(width: width, height: height)
    }

    /// 小窗左下角（AppKit 屏幕坐标）：按扩展栏所在的边往屏幕里面弹，在格子正中，
    /// 再夹进屏幕可见范围。底部扩展栏往上弹，顶部往下，左边往右，右边往左。
    public static func origin(edge: DockPosition, anchor: CGPoint, size: CGSize,
                              visible: CGRect) -> CGPoint {
        let raw = Geometry.popupOrigin(edge: edge, anchor: anchor, size: size, gap: gap)
        let minX = visible.minX + screenMargin
        let maxX = max(minX, visible.maxX - size.width - screenMargin)
        let minY = visible.minY + screenMargin
        let maxY = max(minY, visible.maxY - size.height - screenMargin)
        return CGPoint(x: min(max(raw.x, minX), maxX), y: min(max(raw.y, minY), maxY))
    }

    // MARK: 窗口列表

    /// 一个窗口，`index` 是它在系统给的列表里的位置。
    public struct Entry: Equatable, Sendable {
        public var index: Int
        public var title: String
        public var minimized: Bool

        public init(index: Int, title: String, minimized: Bool) {
            self.index = index
            self.title = title
            self.minimized = minimized
        }
    }

    /// 排好、截断后的列表，以及没列出来的个数。
    public static func arrange(_ entries: [Entry], limit: Int = maxWindows)
        -> (shown: [Entry], more: Int) {
        let ordered = entries.enumerated().sorted { a, b in
            if a.element.minimized != b.element.minimized { return !a.element.minimized }
            return a.offset < b.offset
        }.map(\.element)
        let cap = max(0, limit)
        return (Array(ordered.prefix(cap)), max(0, ordered.count - cap))
    }

    /// 卡片上的名字：去掉首尾空白，空的写「无标题窗口」。「已最小化」另起一个标记，
    /// 不拼进名字里。
    public static func displayTitle(_ raw: String?) -> String {
        let title = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? tr("无标题窗口") : title
    }

    /// 顶上一行：「访达 · 3 个窗口」。
    public static func header(appName: String, count: Int) -> String {
        tr("\(appName) · \(count) 个窗口")
    }

    /// AX 读到的窗口框和屏幕截图那边的窗口框是不是同一个窗口（都是左上角为原点的
    /// 全局坐标）。位置和大小各差不到 `tolerance` 点就算。
    public static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// 截图的像素大小：把窗口按比例缩进缩略图框，再乘屏幕倍数。窗口没有大小时用框本身。
    public static func captureSize(window: CGSize, scale: CGFloat) -> CGSize {
        let box = thumbnailSize
        guard window.width > 0, window.height > 0 else {
            return CGSize(width: box.width * scale, height: box.height * scale)
        }
        let ratio = min(box.width / window.width, box.height / window.height, 1)
        let s = max(1, scale)
        return CGSize(width: max(1, (window.width * ratio * s).rounded()),
                      height: max(1, (window.height * ratio * s).rounded()))
    }
}

/// 悬停的状态机。外面在指针变化时和定时器到点时调 `update`，按返回的动作开关小窗，
/// 按 `deadline` 决定下一次什么时候再调。纯值类型，不碰时钟。
public struct WindowPreviewHover: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case idle
        /// 指针停在 `id` 这个格子上，从 `since` 开始算。
        case pending(id: String, since: Date)
        case open(id: String)
        /// 开着，但指针已经离开格子和小窗，从 `since` 开始算。
        case leaving(id: String, since: Date)
    }

    public enum Action: Equatable, Sendable {
        case show(id: String)
        case hide
    }

    public private(set) var phase: Phase = .idle
    /// 刚点过（或刚关掉）的格子：指针不离开它就不再弹，和程序坞点了图标后一样。
    public private(set) var suppressedID: String?

    public init() {}

    /// 小窗现在是不是该开着、开的是哪个 App。
    public var openID: String? {
        switch phase {
        case .open(let id), .leaving(let id, _): id
        default: nil
        }
    }

    /// 下一次要调 `update` 的时间；不用等时是 nil。
    public var deadline: Date? {
        switch phase {
        case .pending(_, let since): since.addingTimeInterval(WindowPreview.openDelay)
        case .leaving(_, let since): since.addingTimeInterval(WindowPreview.closeGrace)
        case .idle, .open: nil
        }
    }

    /// - Parameters:
    ///   - tile: 指针下面那个可以预览的格子（正在运行的 App），不是就传 nil。
    ///   - overPopup: 指针在小窗上。
    ///   - blocked: 现在不能弹：设置关了、没 Pro、拖动或改大小中、别的小窗开着。
    public mutating func update(tile: String?, overPopup: Bool, blocked: Bool, now: Date) -> Action? {
        if blocked {
            let wasOpen = openID != nil
            phase = .idle
            return wasOpen ? .hide : nil
        }
        var tile = tile
        if let suppressed = suppressedID {
            if tile == suppressed, openID == nil {
                tile = nil
            } else if tile != suppressed {
                suppressedID = nil
            }
        }
        switch phase {
        case .idle:
            guard let tile else { return nil }
            phase = .pending(id: tile, since: now)
            return nil

        case .pending(let id, let since):
            guard let tile else {
                phase = .idle
                return nil
            }
            if tile != id {
                phase = .pending(id: tile, since: now)
                return nil
            }
            guard now.timeIntervalSince(since) >= WindowPreview.openDelay else { return nil }
            phase = .open(id: id)
            return .show(id: id)

        case .open(let id), .leaving(let id, _):
            if let tile, tile != id {
                // 已经开着时换到另一个 App，不用再等。
                phase = .open(id: tile)
                return .show(id: tile)
            }
            if tile == id || overPopup {
                phase = .open(id: id)
                return nil
            }
            if case .leaving(_, let since) = phase {
                guard now.timeIntervalSince(since) >= WindowPreview.closeGrace else { return nil }
                phase = .idle
                return .hide
            }
            phase = .leaving(id: id, since: now)
            return nil
        }
    }

    /// 外面直接关了小窗（点了缩略图、点了格子、别的小窗打开）。传了 `suppress`
    /// 时指针离开那个格子之前不再弹。
    public mutating func reset(suppress: String? = nil) {
        phase = .idle
        suppressedID = suppress
    }
}
