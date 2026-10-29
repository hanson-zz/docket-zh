import Foundation

// MARK: - 钉在桌面
//
// 扩展栏上的小组件拖到桌面（或右键「钉在桌面」）变成一张独立的桌面卡片：窗口层级在
// 所有窗口之后，像桌面上的东西。卡片只是同一个小组件的另一个视图，数据和扩展栏是
// 同一份（`WidgetInstance` 的配置），这里只存「钉了哪张、多大、放在哪」。
//
// 这里放纯逻辑：尺寸、20pt 网格吸附、按屏幕 displayID + 相对坐标存位置、屏幕断开收回
// 主屏、找空位、免费上限判定、便签单页的标识、刷新节奏。窗口、视图和拖动在 App 层。

/// 桌面卡片的三档尺寸。
public enum DesktopPinSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    public var width: Double { self == .small ? 160 : 340 }
    public var height: Double { self == .large ? 340 : 160 }
    public var size: CGSize { CGSize(width: width, height: height) }

    /// 大号是码头 Pro。
    public var isPro: Bool { self == .large }

    public var title: String {
        switch self {
        case .small: tr("小")
        case .medium: tr("中")
        case .large: tr("大")
        }
    }

    /// 菜单和空位里写的「中 340×160」。
    public var label: String { "\(title) \(Int(width))×\(Int(height))" }
}

/// 切换桌面（Space）时卡片跟不跟着走。
public enum DesktopPinSpaces: String, Codable, Sendable, CaseIterable {
    /// 所有桌面：canJoinAllSpaces + stationary。
    case all
    /// 仅当前桌面：卡片只留在钉它时的那个桌面。
    case current
}

/// 窗口盖住桌面卡片时怎么办。
public enum DesktopPinCovered: String, Codable, Sendable, CaseIterable {
    /// 照常留在窗口后面。
    case stay
    /// 被窗口盖住就隐藏，窗口挪开或最小化后再出现。
    case autoHide
}

/// 一张钉在桌面上的卡片。
public struct DesktopPin: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 钉的是哪个小组件（任何布局里的都行，文件夹里的也算）。
    public var widgetID: UUID
    /// 便签单独钉出来的那一张（`StickySheet.id`）；不是便签或钉整张便签时是 nil。
    public var sheetID: String?
    public var size: DesktopPinSize
    /// 钉在哪块屏幕上（`CGDirectDisplayID`）。nil 或这块屏幕不在时放主屏。
    public var displayID: UInt32?
    /// 相对坐标：卡片左上角在屏幕可用区域里能放的范围内的位置，0 是最左 / 最上，
    /// 1 是最右 / 最下。存相对值，分辨率变了也大致在原来的地方。
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), widgetID: UUID, sheetID: String? = nil, size: DesktopPinSize,
                displayID: UInt32? = nil, x: Double = 0, y: Double = 0) {
        self.id = id
        self.widgetID = widgetID
        self.sheetID = sheetID
        self.size = size
        self.displayID = displayID
        self.x = DesktopPinLayout.unit(x)
        self.y = DesktopPinLayout.unit(y)
    }

    private enum CodingKeys: String, CodingKey { case id, widgetID, sheetID, size, displayID, x, y }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        widgetID = try c.decode(UUID.self, forKey: .widgetID)
        sheetID = try? c.decodeIfPresent(String.self, forKey: .sheetID)
        size = (try? c.decodeIfPresent(DesktopPinSize.self, forKey: .size)) ?? .medium
        displayID = try? c.decodeIfPresent(UInt32.self, forKey: .displayID)
        x = DesktopPinLayout.unit((try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0)
        y = DesktopPinLayout.unit((try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0)
    }

    /// 是不是钉着这一个（小组件 + 便签的哪一张）。
    public func matches(widget: UUID, sheet: String?) -> Bool {
        widgetID == widget && sheetID == sheet
    }
}

/// 设置 ▸ 小组件 ▸ 桌面卡片，和已钉的卡片。
public struct DesktopPinSettings: Codable, Equatable, Sendable {
    /// 总开关。关掉后桌面卡片全部收起，位置记着。
    public var enabled = true
    public var spaces: DesktopPinSpaces = .all
    public var covered: DesktopPinCovered = .stay
    /// 卡片外观：跟随系统（码头的外观设置）、浅色、深色。
    public var appearance: AppAppearance = .system
    /// 按钉上去的先后排。没解锁时只显示第一张（见 `DesktopPinGate.shown`）。
    public var pins: [DesktopPin] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, spaces, covered, appearance, pins }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        spaces = (try? c.decodeIfPresent(DesktopPinSpaces.self, forKey: .spaces)) ?? .all
        covered = (try? c.decodeIfPresent(DesktopPinCovered.self, forKey: .covered)) ?? .stay
        appearance = (try? c.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? .system
        // 一张坏了不连累别的。
        if let raw = try? c.decodeIfPresent([FailableDesktopPin].self, forKey: .pins) {
            pins = raw.compactMap(\.pin)
        }
    }

    public func pin(_ id: UUID) -> DesktopPin? { pins.first { $0.id == id } }

    /// 这个小组件（便签的这一张）已经钉着的那张。
    public func pin(widget: UUID, sheet: String?) -> DesktopPin? {
        pins.first { $0.matches(widget: widget, sheet: sheet) }
    }

    /// 这个小组件有没有任何一张钉在桌面（便签的任何一页都算）。
    public func hasPins(widget: UUID) -> Bool { pins.contains { $0.widgetID == widget } }

    /// 钉上一张。同一个小组件（便签的同一张）已经钉着就不重复，换成新的尺寸和位置。
    public mutating func add(_ pin: DesktopPin) {
        if let index = pins.firstIndex(where: { $0.matches(widget: pin.widgetID, sheet: pin.sheetID) }) {
            var replaced = pin
            replaced.id = pins[index].id
            pins[index] = replaced
        } else {
            pins.append(pin)
        }
    }

    public mutating func remove(_ id: UUID) { pins.removeAll { $0.id == id } }

    public mutating func removeAll() { pins.removeAll() }

    public mutating func update(_ id: UUID, _ change: (inout DesktopPin) -> Void) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        change(&pins[index])
    }

    /// 小组件从所有布局里删掉了，或便签那一张撕掉了：它的卡片跟着取消钉。
    /// `sheetExists` 问某个小组件里还有没有这一张。有删掉的返回 true。
    @discardableResult
    public mutating func removeOrphans(widgets: Set<UUID>,
                                       sheetExists: (UUID, String) -> Bool = { _, _ in true }) -> Bool {
        let before = pins.count
        pins.removeAll { pin in
            guard widgets.contains(pin.widgetID) else { return true }
            if let sheet = pin.sheetID { return !sheetExists(pin.widgetID, sheet) }
            return false
        }
        return pins.count != before
    }

    /// 设置里「已钉 3 张」下面那行：「算（大）、快速待办（中）、时钟（小）」。
    public func summary(name: (DesktopPin) -> String) -> String {
        pins.map { "\(name($0))（\($0.size.title)）" }.joined(separator: tr("、"))
    }
}

/// 解不出来的那一张变成 nil，别的照常读。
private struct FailableDesktopPin: Decodable {
    var pin: DesktopPin?
    init(from decoder: Decoder) throws { pin = try? DesktopPin(from: decoder) }
}

// MARK: - 位置

/// 一块屏幕：displayID 和可用区域（去掉菜单栏和程序坞，AppKit 坐标，y 向上）。
public struct DesktopScreen: Equatable, Sendable {
    public var id: UInt32
    public var visible: CGRect

    public init(id: UInt32, visible: CGRect) {
        self.id = id
        self.visible = visible
    }
}

/// 网格吸附、相对坐标换算、找空位。坐标都是 AppKit 屏幕坐标（原点左下，y 向上），
/// 卡片的「位置」是窗口 frame 的 origin（左下角）。网格从可用区域左上角往里 20pt 起算。
public enum DesktopPinLayout {
    /// 网格步长，也是卡片离屏幕边和卡片之间的间距。
    public static let grid: Double = 20
    public static let margin: Double = 20
    public static let gap: Double = 20

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// 卡片左边能放的最左、最右（左下角 x）。可用区域放不下时两者相等。
    private static func xRange(_ size: CGSize, _ visible: CGRect) -> (lo: Double, hi: Double) {
        let lo = Double(visible.minX) + margin
        let room = Double(visible.width) - 2 * margin - Double(size.width)
        // 最右也落在网格上，夹完仍然对齐。
        return (lo, lo + max(0, (room / grid).rounded(.down) * grid))
    }

    /// 卡片顶边能放的最上、最下（顶边 y，从上往下数）。
    private static func topRange(_ size: CGSize, _ visible: CGRect) -> (hi: Double, lo: Double) {
        let hi = Double(visible.maxY) - margin
        let room = Double(visible.height) - 2 * margin - Double(size.height)
        return (hi, hi - max(0, (room / grid).rounded(.down) * grid))
    }

    /// 吸到最近的网格点，并夹在屏幕可用区域里（离边 20pt）。
    public static func snap(_ origin: CGPoint, size: CGSize, in visible: CGRect) -> CGPoint {
        let xs = xRange(size, visible)
        let tops = topRange(size, visible)
        let x = xs.lo + ((Double(origin.x) - xs.lo) / grid).rounded() * grid
        let top = tops.hi - ((tops.hi - (Double(origin.y) + Double(size.height))) / grid).rounded() * grid
        let clampedX = min(max(x, xs.lo), xs.hi)
        let clampedTop = min(max(top, tops.lo), tops.hi)
        return CGPoint(x: clampedX, y: clampedTop - Double(size.height))
    }

    /// 某个位置（已吸附）换成相对坐标。
    public static func relative(_ origin: CGPoint, size: CGSize, in visible: CGRect) -> (x: Double, y: Double) {
        let xs = xRange(size, visible)
        let tops = topRange(size, visible)
        let x = xs.hi > xs.lo ? (Double(origin.x) - xs.lo) / (xs.hi - xs.lo) : 0
        let top = Double(origin.y) + Double(size.height)
        let y = tops.hi > tops.lo ? (tops.hi - top) / (tops.hi - tops.lo) : 0
        return (unit(x), unit(y))
    }

    /// 相对坐标换回屏幕上的位置（吸附到网格）。
    public static func origin(x: Double, y: Double, size: CGSize, in visible: CGRect) -> CGPoint {
        let xs = xRange(size, visible)
        let tops = topRange(size, visible)
        let left = xs.lo + unit(x) * (xs.hi - xs.lo)
        let top = tops.hi - unit(y) * (tops.hi - tops.lo)
        return snap(CGPoint(x: left, y: top - Double(size.height)), size: size, in: visible)
    }

    /// 卡片放在哪块屏幕：存的那块在就用它，不在（断开了）就收回主屏（列表第一块）。
    /// 存着的 displayID 不改，接回那块屏幕时自动回到原处。
    public static func screen(for pin: DesktopPin, screens: [DesktopScreen]) -> DesktopScreen? {
        if let id = pin.displayID, let match = screens.first(where: { $0.id == id }) { return match }
        return screens.first
    }

    /// 卡片现在的 frame。`size` 给了就按它（没解锁时大号按中号画）。
    public static func frame(for pin: DesktopPin, size: DesktopPinSize? = nil,
                             screens: [DesktopScreen]) -> CGRect? {
        guard let screen = screen(for: pin, screens: screens) else { return nil }
        let cardSize = (size ?? pin.size).size
        return CGRect(origin: origin(x: pin.x, y: pin.y, size: cardSize, in: screen.visible), size: cardSize)
    }

    /// 屏幕上的某个点落在哪块屏幕（拖动松手时换屏用），都不在时取最近的一块。
    public static func screen(containing point: CGPoint, screens: [DesktopScreen]) -> DesktopScreen? {
        if let hit = screens.first(where: { $0.visible.contains(point) }) { return hit }
        return screens.min { distance(point, $0.visible) < distance(point, $1.visible) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(Double(rect.minX) - Double(point.x), 0, Double(point.x) - Double(rect.maxX))
        let dy = max(Double(rect.minY) - Double(point.y), 0, Double(point.y) - Double(rect.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 和别的卡片之间至少留 20pt。
    public static func isFree(_ rect: CGRect, occupied: [CGRect]) -> Bool {
        let reach = gap - 0.5
        return !occupied.contains { $0.insetBy(dx: -reach, dy: -reach).intersects(rect) }
    }

    /// 每个网格位置，从左上往右、再往下。
    private static func slots(size: CGSize, in visible: CGRect) -> [CGPoint] {
        let xs = xRange(size, visible)
        let tops = topRange(size, visible)
        var result: [CGPoint] = []
        var top = tops.hi
        while top >= tops.lo - 0.01 {
            var x = xs.lo
            while x <= xs.hi + 0.01 {
                result.append(CGPoint(x: x, y: top - Double(size.height)))
                x += grid
            }
            top -= grid
        }
        return result
    }

    /// 第一个空位（右键「钉在桌面」用）：从左上角起一行一行找。没有空位时放左上角。
    public static func firstFree(size: CGSize, occupied: [CGRect], in visible: CGRect) -> CGPoint {
        for slot in slots(size: size, in: visible)
        where isFree(CGRect(origin: slot, size: size), occupied: occupied) {
            return slot
        }
        return snap(CGPoint(x: visible.minX, y: visible.maxY), size: size, in: visible)
    }

    /// 离想放的位置最近的空位（拖动时的橙色虚线空位、改尺寸后让开别的卡片）。
    /// 想放的地方吸附后就是空的，直接用；整块屏幕都没空位时就放想放的地方。
    public static func nearestFree(to origin: CGPoint, size: CGSize, occupied: [CGRect],
                                   in visible: CGRect) -> CGPoint {
        let wanted = snap(origin, size: size, in: visible)
        if isFree(CGRect(origin: wanted, size: size), occupied: occupied) { return wanted }
        var best: CGPoint?
        var bestDistance = Double.infinity
        for slot in slots(size: size, in: visible)
        where isFree(CGRect(origin: slot, size: size), occupied: occupied) {
            let dx = Double(slot.x - wanted.x)
            let dy = Double(slot.y - wanted.y)
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = slot
            }
        }
        return best ?? wanted
    }
}

// MARK: - 免费 / Pro

/// 免费钉 1 张、只有小 / 中；码头 Pro 不限张数，多一档大号。
///
/// 没解锁（或试用结束）时不删卡片、不改存着的尺寸：只显示第一张，大号按中号画，
/// 解锁后原样回来。
public enum DesktopPinGate {
    public static let freeLimit = 1

    public enum Verdict: Equatable, Sendable {
        case allowed
        /// 第二张起要 Pro。
        case needsProForCount
        /// 大号要 Pro。
        case needsProForSize
    }

    /// 再钉一张行不行。`existing` 是已经钉着的张数（同一个小组件重钉不算新的一张，
    /// 调用方先判断）。
    public static func canPin(existing: Int, size: DesktopPinSize, unlocked: Bool) -> Verdict {
        guard !unlocked else { return .allowed }
        if existing >= freeLimit { return .needsProForCount }
        if size.isPro { return .needsProForSize }
        return .allowed
    }

    /// 已经钉着的卡片换尺寸行不行。
    public static func canResize(to size: DesktopPinSize, unlocked: Bool) -> Verdict {
        unlocked || !size.isPro ? .allowed : .needsProForSize
    }

    /// 现在该显示哪几张：解锁了全部；没解锁只显示第一张。
    public static func shown(_ pins: [DesktopPin], unlocked: Bool) -> [DesktopPin] {
        unlocked ? pins : Array(pins.prefix(freeLimit))
    }

    /// 画出来的尺寸：没解锁时大号按中号画，存着的不改。
    public static func effectiveSize(_ size: DesktopPinSize, unlocked: Bool) -> DesktopPinSize {
        size.isPro && !unlocked ? .medium : size
    }

    /// 能选的尺寸里没解锁的那几档（菜单里打 Pro 标）。
    public static func lockedSizes(unlocked: Bool) -> Set<DesktopPinSize> {
        unlocked ? [] : Set(DesktopPinSize.allCases.filter(\.isPro))
    }
}

// MARK: - 哪些小组件能钉

public enum DesktopPinSupport {
    public enum Mode: Equatable, Sendable {
        /// 第一批专门做过桌面版的：算、便签、快速待办、时钟、天气、专注 / 倒计时 / 秒表。
        case dedicated
        /// 通用展开：小 / 中是放大的扩展栏卡片，大号是面板内容（见 `DesktopPinFit`）。
        case generic
        /// 不提供「钉在桌面」。
        case none
    }

    public static let dedicatedKinds: Set<WidgetKind> = [
        .calculator, .notes, .todo, .clock, .weather, .timer, .countdown, .stopwatch,
    ]

    /// 面板离不开扩展栏的，不提供：AI 助手（刘海对话和应用选择器）。截图工具、音量、相册、
    /// 壁纸、摸鱼时钟有了桌面专属布局（`DesktopCardsFilesPlan`），不再排除。
    public static let excludedKinds: Set<WidgetKind> = [
        .aiAssistant,
    ]

    /// 面板比 340 宽的放进卡片会被挤窄，先不通用展开。
    public static let maxGenericPanelWidth: Double = 340

    public static func mode(_ kind: WidgetKind, hasDetail: Bool, panelWidth: Double) -> Mode {
        if dedicatedKinds.contains(kind) { return .dedicated }
        if DesktopCardsDataPlan.handles(kind) { return .dedicated }
        if DesktopCardsFilesPlan.handles(kind) { return .dedicated }
        if DesktopCardsGamesPlan.handles(kind) { return .dedicated }
        if DesktopCardsToothPlan.handles(kind) { return .dedicated }
        guard hasDetail, !excludedKinds.contains(kind), panelWidth <= maxGenericPanelWidth else { return .none }
        return .generic
    }

    /// 这种卡片有哪几档。小号和中号画放大的扩展栏卡片（`DesktopPinFit.tile`），大号画面板
    /// （`DesktopPinFit.panel`）。`smallFits` 是这张卡片在 160×160 里能不能不缩小地完整放下
    /// （横排或竖排任选一种）；放不下就不给小号。中号 340×160 宽一倍，横排卡片都放得下。
    public static func sizes(_ mode: Mode, smallFits: Bool = true) -> [DesktopPinSize] {
        switch mode {
        case .dedicated, .generic: smallFits ? DesktopPinSize.allCases : [.medium, .large]
        case .none: []
        }
    }

    /// 画出来的尺寸：没解锁时大号按中号画（`DesktopPinGate.effectiveSize`）；存着的那档这张
    /// 卡片现在不提供（比如改了样式后小号放不下了）时按中号画。存着的不改，能放下了原样回来。
    public static func drawnSize(_ stored: DesktopPinSize, unlocked: Bool,
                                 offered: [DesktopPinSize]) -> DesktopPinSize {
        let size = DesktopPinGate.effectiveSize(stored, unlocked: unlocked)
        guard !offered.isEmpty, !offered.contains(size) else { return size }
        return offered.contains(.medium) ? .medium : offered[0]
    }

    /// 拖出来或没指定尺寸时用的那档：中号（免费也能用）。
    public static func defaultSize(_ mode: Mode) -> DesktopPinSize { .medium }
}

// MARK: - 卡片里怎么摆

/// 桌面卡片必须完整显示：内容铺满整张卡片，放不下先等比缩小，还放不下才在卡片里竖着滚。
///
/// 缩小有下限：各小组件里最小的字就是 13pt（全仓的最小字号），按设计尺寸再缩字就小于
/// 13pt，所以最小缩放是 1（设计尺寸）。往大放有上限，免得字大得像海报。
///
/// - 小号、中号：扩展栏上那张卡片放大摆在中间（`tile`）。横排（扩展栏在下面时的样子，
///   58 高）和竖排（扩展栏在左右时的样子，76 宽）取放得更大的那种。卡片本身就是一眼看完的
///   设计，放进去总是完整的；面板放进 160 高的卡片里只能露出一截，所以中号不放面板。
/// - 大号：面板（`panel`）。先按卡片宽把面板放大铺满；高度放得下就是完整；放大后放不下但
///   设计尺寸放得下，就缩到正好放下；设计尺寸也放不下才滚动，滚动区域按缩放后的高度算，
///   能滚到底。
public enum DesktopPinFit {
    /// 不缩小到设计尺寸以下（最小 13pt 的字不变小）。
    public static let minScale: Double = 1
    /// 扩展栏卡片最多放大到 2.2 倍。
    public static let maxTileScale: Double = 2.2
    /// 面板最多放大到 1.2 倍。
    public static let maxPanelScale: Double = 1.2
    /// 扩展栏卡片离桌面卡片边至少 12pt。
    public static let tileInset: Double = 12
    /// 面板在扩展栏上弹出时，内容区比面板窄 2×16，面板卡片（DetailCard）又往外伸 2×10，
    /// 所以面板卡片的宽是面板宽减 12。桌面卡片里的面板按这个宽排版，里面每一行和原来一样宽。
    /// 少数面板（正在播放、复古卡带、时钟）不套面板卡片，直接画在面板上：桌面卡片给它们
    /// 补上 16 的内边距，排版宽就是面板宽（`hasCard` 为 false）。
    public static let panelTrim: Double = 12

    /// 扩展栏卡片的两种排法。
    public enum TileAxis: Equatable, Sendable {
        /// 扩展栏在下面时的横排。
        case horizontal
        /// 扩展栏在左右时的竖排。
        case vertical
    }

    public struct TileFit: Equatable, Sendable {
        public var axis: TileAxis
        public var scale: Double
        /// 不用缩小就能完整放下（字不小于 13pt）。
        public var readable: Bool { scale >= DesktopPinFit.minScale - 0.0001 }
    }

    /// 一种排法放进卡片能放多大（离边 `tileInset`，最多 `maxTileScale`）。尺寸不对时是 0。
    public static func tileScale(_ natural: CGSize, box: CGSize) -> Double {
        let w = Double(natural.width), h = Double(natural.height)
        guard w > 0, h > 0, w.isFinite, h.isFinite else { return 0 }
        let room = (Double(box.width) - 2 * tileInset, Double(box.height) - 2 * tileInset)
        guard room.0 > 0, room.1 > 0 else { return 0 }
        return min(room.0 / w, room.1 / h, maxTileScale)
    }

    /// 横排、竖排取放得更大的那种；一样大时用横排（和扩展栏在下面时一样）。
    public static func tile(horizontal: CGSize, vertical: CGSize, box: CGSize) -> TileFit {
        let across = tileScale(horizontal, box: box)
        let down = tileScale(vertical, box: box)
        return down > across + 0.0001 ? TileFit(axis: .vertical, scale: down) : TileFit(axis: .horizontal, scale: across)
    }

    /// 面板怎么放。
    public enum PanelMode: Equatable, Sendable {
        /// 放大到铺满卡片宽，高度也放得下。
        case fill
        /// 放大后放不下，缩到正好放下（不小于设计尺寸）。
        case shrink
        /// 设计尺寸也放不下：铺满卡片宽，卡片里竖着滚。
        case scroll
    }

    public struct PanelFit: Equatable, Sendable {
        public var mode: PanelMode
        public var scale: Double
        /// 面板按多宽排版（缩放前）。乘上铺满时的缩放正好是卡片宽。
        public var layoutWidth: Double
        /// 内容不够高时往下撑到多高（缩放前），底色铺满卡片。
        public var minHeight: Double
    }

    /// 面板卡片的设计宽（缩放前排版的最窄宽度）。
    public static func panelLayoutWidth(panelWidth: Double, hasCard: Bool = true) -> Double {
        max(1, panelWidth - (hasCard ? panelTrim : 0))
    }

    /// 铺满卡片宽的缩放（最多 `maxPanelScale`）。
    public static func panelWidthScale(panelWidth: Double, hasCard: Bool = true, box: CGSize) -> Double {
        let scale = Double(box.width) / panelLayoutWidth(panelWidth: panelWidth, hasCard: hasCard)
        guard scale.isFinite, scale > 0 else { return 1 }
        return min(scale, maxPanelScale)
    }

    /// `naturalHeight` 是面板按 `layoutWidth` 排版后的自然高度；还没量到时是 nil，先按滚动
    /// 摆（什么都能看到）。排版宽只和面板宽、卡片尺寸有关，不随量到的高度变，所以量一次就定，
    /// 不会来回跳。
    public static func panel(naturalHeight: Double?, panelWidth: Double, hasCard: Bool = true,
                             box: CGSize) -> PanelFit {
        let widthScale = panelWidthScale(panelWidth: panelWidth, hasCard: hasCard, box: box)
        let layoutWidth = Double(box.width) / widthScale
        let boxHeight = Double(box.height)
        func fit(_ mode: PanelMode, _ scale: Double) -> PanelFit {
            PanelFit(mode: mode, scale: scale, layoutWidth: layoutWidth, minHeight: boxHeight / scale)
        }
        guard let natural = naturalHeight, natural.isFinite, natural > 0 else { return fit(.scroll, widthScale) }
        if natural * widthScale <= boxHeight + 0.5 { return fit(.fill, widthScale) }
        let shrink = boxHeight / natural
        if shrink >= minScale, shrink < widthScale { return fit(.shrink, shrink) }
        return fit(.scroll, widthScale)
    }
}

// MARK: - 刷新节奏

/// 卡片静止时降低刷新：时钟按分钟走（设了秒针才每秒），专注计时开着才每秒，倒计时和
/// 秒表每秒（它们自己的运行状态在各自的面板里），其余每分钟。
public enum DesktopPinCadence {
    public static func interval(_ kind: WidgetKind, secondHand: Bool = false, running: Bool = false) -> TimeInterval {
        switch kind {
        case .clock, .world: secondHand ? 1 : 60
        case .timer: running ? 1 : 60
        case .countdown, .stopwatch: 1
        default: 60
        }
    }
}

// MARK: - 便签单页

/// 便签叠着的每一张都能单独钉出来，桌面上并排摊开。每张纸靠 `StickySheet.id` 认，
/// 翻页、撕掉别的、加新一张都不影响已经钉出来的那张。
public enum DesktopPinSheet {
    /// 右键菜单里列出每一张：「第 2 张 · 给妈妈回个电话」。首行太长截到 12 个字。
    public static func label(index: Int, text: String) -> String {
        let firstLine = StickyChecklist.lines(text).first { line in
            switch line {
            case .text(let words), .item(_, let words):
                !words.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        var line = ""
        switch firstLine {
        case .text(let words)?, .item(_, let words)?: line = words.trimmingCharacters(in: .whitespaces)
        case nil: break
        }
        let head = tr("第 \(index + 1) 张")
        guard !line.isEmpty else { return head + " · " + tr("空白") }
        let short = line.count > 12 ? String(line.prefix(12)) + "…" : line
        return head + " · " + short
    }
}
