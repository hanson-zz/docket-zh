import Foundation

// MARK: - 沿边对齐

/// 扩展栏在它贴的那条边上靠哪一头。
///
/// 横向（底部、顶部）从左往右数：靠前是靠左，靠后是靠右；竖向（左边、右边）
/// 从上往下数：靠前是靠上，靠后是靠下。默认居中，也就是加这项之前的样子。
public enum ShelfAlignment: String, Codable, Sendable, CaseIterable {
    case leading, center, trailing

    /// 设置里显示的名字。竖向扩展栏说“靠上/靠下”。
    public func label(vertical: Bool) -> String {
        switch self {
        case .leading: vertical ? tr("靠上") : tr("靠左")
        case .center: tr("居中")
        case .trailing: vertical ? tr("靠下") : tr("靠右")
        }
    }
}

extension ShelfAlignment: LenientChoice { public static var fallback: Self { .center } }

// MARK: - 固定的八个位置

/// 菜单栏 ▸ 位置 ▸ 固定 里的八个位置：一条边加上在边上靠哪一头。
///
/// 四个角都算在横边上（左上角是顶部靠左），所以角上的扩展栏是横着的一短条；
/// 左右两边只有居中。
public enum ShelfPin: String, Codable, Sendable, CaseIterable {
    case topLeft, topCenter, topRight
    case leftCenter, rightCenter
    case bottomLeft, bottomCenter, bottomRight

    public var edge: DockPosition {
        switch self {
        case .topLeft, .topCenter, .topRight: .top
        case .leftCenter: .left
        case .rightCenter: .right
        case .bottomLeft, .bottomCenter, .bottomRight: .bottom
        }
    }

    public var alignment: ShelfAlignment {
        switch self {
        case .topLeft, .bottomLeft: .leading
        case .topRight, .bottomRight: .trailing
        case .topCenter, .leftCenter, .rightCenter, .bottomCenter: .center
        }
    }

    /// 这条边加这个对齐对应哪个固定位置；左右两边靠上靠下不在八个里，是 nil。
    public init?(edge: DockPosition, alignment: ShelfAlignment) {
        guard let match = Self.allCases.first(where: { $0.edge == edge && $0.alignment == alignment })
        else { return nil }
        self = match
    }

    public var title: String {
        switch self {
        case .topLeft: tr("左上角")
        case .topCenter: tr("顶部居中")
        case .topRight: tr("右上角")
        case .leftCenter: tr("左侧居中")
        case .rightCenter: tr("右侧居中")
        case .bottomLeft: tr("左下角")
        case .bottomCenter: tr("底部居中")
        case .bottomRight: tr("右下角")
        }
    }
}

// MARK: - 浮动位置

/// 浮动扩展栏在一块屏幕上的位置：窗口左下角相对这块屏幕可见区左下角的偏移，
/// 单位是点。按偏移而不是绝对坐标存，屏幕排列变了（副屏挪到左边）也还在
/// 这块屏幕的同一处。
public struct FloatingSpot: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - 方式

/// 菜单栏 ▸ 位置 里打勾的那一项。由设置推出来，不单独存，所以设置页和菜单
/// 改的是同一份东西，两边自然同步。
public enum ShelfPlacementMode: Hashable, Sendable {
    /// 和程序坞并排：两者都在，扩展栏贴底部、左边或右边，居中。
    case beside
    /// 置顶显示：扩展栏在屏幕顶部，程序坞照旧。
    case top
    /// 替换系统程序坞。
    case replace
    /// 替换并自动隐藏。
    case replaceAutoHide
    /// 浮动：不贴边、不占保留区，拖到哪停在哪。
    case floating
    /// 固定在八个位置之一。
    case pinned(ShelfPin)

    /// 一级菜单右侧的灰字。
    public var summary: String {
        switch self {
        case .beside: tr("并排")
        case .top: tr("置顶")
        case .replace: tr("替换")
        case .replaceAutoHide: tr("替换并隐藏")
        case .floating: tr("浮动")
        case .pinned(let pin): pin.title
        }
    }
}

/// 扩展栏放在哪里：菜单栏 ▸ 位置 的读写，以及对齐和浮动的几何计算。
///
/// 全部是纯函数，AppKit 那边只负责把屏幕的可见区和窗口大小交进来。
public enum ShelfPlacement {

    // MARK: 读

    /// 当前是哪一种方式。只有系统程序坞、没有扩展栏时是 nil。
    ///
    /// 先看浮动，再看替换（替换里自动隐藏分两档），然后是固定，最后按边分置顶
    /// 和并排。固定标记只决定“底部居中”这类和并排长得一样的位置勾哪一项；
    /// 对齐不是居中时一定算固定。
    public static func mode(setup: DockSetup, settings: CustomDockSettings) -> ShelfPlacementMode? {
        switch setup {
        case .macOSDockOnly: return nil
        case .customReplacement:
            if settings.floating { return .floating }
            return replacementHides(settings) ? .replaceAutoHide : .replace
        case .both:
            if settings.floating { return .floating }
            // 跟随程序坞时边和位置都由程序坞定（扩展栏挑一条空着的边），
            // 存着的边和对齐不起作用，就是并排。
            if settings.followSystemDock { return .beside }
            let pin = ShelfPin(edge: settings.position, alignment: settings.alignment)
            if let pin, settings.pinned || settings.alignment != .center { return .pinned(pin) }
            return settings.position == .top ? .top : .beside
        }
    }

    // MARK: 写

    /// 选中一种方式后的设置。
    ///
    /// - Parameter currentScale: 扩展栏现在显示的大小。要关掉“与系统程序坞
    ///   保持一致”时记下它，免得关掉的一瞬间扩展栏变大变小（新手引导选边也是
    ///   这样做的）。
    ///
    /// 跟随程序坞时边由程序坞决定（扩展栏挑一条程序坞不在的边），所以置顶和
    /// 固定这类明确指定了边的方式要先关掉跟随，不然选了等于没选。并排和替换
    /// 不关：并排就是贴当前边，替换本来就用自己的边。“替换并自动隐藏”要关：
    /// 跟随时隐藏看系统程序坞，而替换会把程序坞的自动隐藏关掉。
    ///
    /// 替换模式没有顶部（系统程序坞去不了顶部），在顶部时选替换先回到底部。
    /// 离开“替换并自动隐藏”时自动隐藏一起关掉，它是那一档的一部分。
    public static func applying(_ mode: ShelfPlacementMode, setup: DockSetup,
                                settings: CustomDockSettings,
                                currentScale: Double) -> (setup: DockSetup, settings: CustomDockSettings) {
        var dock = settings
        var newSetup = setup
        let wasReplaceAutoHide = self.mode(setup: setup, settings: settings) == .replaceAutoHide

        func stopFollowing() {
            guard dock.followSystemDock else { return }
            dock.scale = currentScale
            dock.followSystemDock = false
        }

        dock.floating = false
        dock.pinned = false
        switch mode {
        case .beside:
            newSetup = .both
            dock.alignment = .center
            if dock.position == .top { dock.position = .bottom }
        case .top:
            newSetup = .both
            stopFollowing()
            dock.position = .top
            dock.alignment = .center
        case .replace:
            newSetup = .customReplacement
            dock.alignment = .center
            if !dock.position.isSystemDockEdge { dock.position = .bottom }
            dock.autoHide = false
        case .replaceAutoHide:
            newSetup = .customReplacement
            stopFollowing()
            dock.alignment = .center
            if !dock.position.isSystemDockEdge { dock.position = .bottom }
            dock.autoHide = true
        case .floating:
            newSetup = .both
            dock.floating = true
        case .pinned(let pin):
            newSetup = .both
            stopFollowing()
            dock.position = pin.edge
            dock.alignment = pin.alignment
            dock.pinned = true
        }
        if wasReplaceAutoHide, mode != .replaceAutoHide { dock.autoHide = false }
        return (newSetup, dock)
    }

    /// 菜单栏 ▸ 位置 ▸ 贴哪条边：换边，回到居中。在替换模式里仍是替换，
    /// 别的方式（置顶、固定、浮动）回到并排。顶部不在这里，它是“置顶显示”。
    public static func applyingEdge(_ edge: DockPosition, setup: DockSetup,
                                    settings: CustomDockSettings,
                                    currentScale: Double) -> (setup: DockSetup, settings: CustomDockSettings) {
        var dock = settings
        let newSetup: DockSetup = setup == .customReplacement ? .customReplacement : .both
        if newSetup == .both, dock.followSystemDock {
            dock.scale = currentScale
            dock.followSystemDock = false
        }
        dock.floating = false
        dock.pinned = false
        dock.alignment = .center
        dock.position = edge.isSystemDockEdge ? edge : .bottom
        return (newSetup, dock)
    }

    /// 重置位置：并排、底部、居中、不自动隐藏，记住的浮动位置全部清空。
    ///
    /// 跟随程序坞时边由程序坞决定，程序坞在底部就会把扩展栏放到左边，所以和
    /// 选边一样关掉跟随（大小记下来），保证回到底部。
    public static func reset(setup: DockSetup, settings: CustomDockSettings,
                             currentScale: Double) -> (setup: DockSetup, settings: CustomDockSettings) {
        var dock = settings
        if dock.followSystemDock {
            dock.scale = currentScale
            dock.followSystemDock = false
        }
        dock.position = .bottom
        dock.alignment = .center
        dock.pinned = false
        dock.floating = false
        dock.autoHide = false
        dock.floatingSpots = [:]
        dock.floatingDisplayID = nil
        return (.both, dock)
    }

    // MARK: 行为

    /// 扩展栏该不该自动隐藏。
    ///
    /// 浮动不隐藏：它不贴边，没有可以藏进去的边。其余照旧：跟随时看程序坞，
    /// 不跟随看自己的开关。
    public static func autoHides(setup: DockSetup, settings: CustomDockSettings,
                                 systemAutoHide: Bool) -> Bool {
        if settings.floating { return false }
        return settings.followSystemDock ? systemAutoHide : settings.autoHide
    }

    /// 替换模式里扩展栏是不是自己设了自动隐藏（“替换并自动隐藏”）。
    ///
    /// 只认自己的开关：跟随时隐藏看系统程序坞，而借保留区时 Docket 正是把
    /// 程序坞的自动隐藏关掉的那一个，跟着它读得不出“替换并隐藏”。
    public static func replacementHides(_ settings: CustomDockSettings) -> Bool {
        !settings.followSystemDock && settings.autoHide
    }

    /// 要不要借系统程序坞的保留区（沿用 DockSetup 的替换流程）。
    ///
    /// 只有替换且扩展栏不自己隐藏时要：自动隐藏的扩展栏不占屏幕空间，借了
    /// 保留区，扩展栏收起来时露出的就是垫在下面的系统程序坞。浮动不贴边，也
    /// 不借。
    public static func wantsStrut(setup: DockSetup, settings: CustomDockSettings) -> Bool {
        setup == .customReplacement && !settings.floating && !replacementHides(settings)
    }

    // MARK: 对齐

    /// 实际按哪种对齐摆。浮动没有边；跟随程序坞并排时位置由程序坞定，居中；
    /// 借了系统程序坞保留区时扩展栏盖在居中的程序坞上，也居中。
    public static func effectiveAlignment(setup: DockSetup, settings: CustomDockSettings,
                                          borrowingStrut: Bool) -> ShelfAlignment {
        if settings.floating || borrowingStrut { return .center }
        if setup != .customReplacement, settings.followSystemDock { return .center }
        return settings.alignment
    }

    /// 贴在 `edge` 上、沿边按 `alignment` 摆的扩展栏原点（AppKit 坐标，y 向上）。
    ///
    /// 靠前靠后时离两头也留 `inset`，和离边一样远，角上看起来是对称的。结果夹在
    /// `bounds` 里，比屏幕还大的扩展栏不会挂出去。
    public static func alignedOrigin(edge: DockPosition, alignment: ShelfAlignment,
                                     size: CGSize, bounds: CGRect, inset: CGFloat) -> CGPoint {
        let centered = Geometry.shelfOrigin(edge: edge, size: size, bounds: bounds, inset: inset)
        var origin = centered
        if edge.isHorizontal {
            switch alignment {
            case .leading: origin.x = bounds.minX + inset
            case .center: break
            case .trailing: origin.x = bounds.maxX - size.width - inset
            }
        } else {
            switch alignment {
            case .leading: origin.y = bounds.maxY - size.height - inset
            case .center: break
            case .trailing: origin.y = bounds.minY + inset
            }
        }
        return clamped(origin, size: size, in: bounds)
    }

    // MARK: 浮动

    /// 浮动扩展栏放在哪：记住的偏移加上可见区原点，夹在可见区里；没记住时在
    /// 可见区横向居中、离底部五分之一处，第一次打开就在眼前又不挡正中。
    public static func floatingOrigin(saved: FloatingSpot?, size: CGSize, visible: CGRect) -> CGPoint {
        let origin: CGPoint
        if let saved, saved.x.isFinite, saved.y.isFinite {
            origin = CGPoint(x: visible.minX + saved.x, y: visible.minY + saved.y)
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + visible.height / 5)
        }
        return clamped(origin, size: size, in: visible)
    }

    /// 拖完要记下的偏移：先夹进可见区，再减去可见区原点。
    public static func floatingSpot(origin: CGPoint, size: CGSize, visible: CGRect) -> FloatingSpot {
        let inside = clamped(origin, size: size, in: visible)
        return FloatingSpot(x: Double(inside.x - visible.minX), y: Double(inside.y - visible.minY))
    }

    /// 浮动扩展栏的弹出方向：中心在屏幕上半时朝下开（当作顶部扩展栏），
    /// 下半时朝上开（当作底部扩展栏）。正好在中线上算下半。
    public static func floatingFacesDown(origin: CGPoint, size: CGSize, visible: CGRect) -> Bool {
        origin.y + size.height / 2 > visible.midY
    }

    /// 浮动扩展栏在哪块屏幕：上次拖到的那块还接着就用它；拔掉了退回
    /// `fallback`（设置里选的显示器或指针所在的那块），再不行用第一块。
    public static func floatingDisplay(last: UInt32?, connected: [UInt32], fallback: UInt32?) -> UInt32? {
        if let last, connected.contains(last) { return last }
        if let fallback, connected.contains(fallback) { return fallback }
        return connected.first
    }

    /// 记住的浮动位置按显示器编号存，键是编号的十进制字符串（JSON 字典的键
    /// 只能是字符串）。
    public static func spotKey(_ display: UInt32) -> String { String(display) }

    // MARK: 工具

    /// 把一个 `size` 大的矩形的原点夹进 `bounds`；放不下时贴左下。
    public static func clamped(_ origin: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
    }
}
