import Foundation

// MARK: - Shelf placement & look

/// A stored choice that survives a value it does not recognise.
///
/// Synthesized `Codable` throws on an unknown raw value, and one throw
/// anywhere rejects the whole state file, which `Store.load()` answers by
/// setting the file aside and starting from a first-run default. So a single
/// misspelled word, or a downgrade to a build that predates one option, cost
/// the user every profile, widget and pinned app.
///
/// Only for choices where falling back is honestly better than failing: an
/// edge, a material, a colour. Deliberately NOT adopted by `WidgetKind`, where
/// the nearest equivalent would silently turn somebody's widget into a clock.
/// An unknown widget is dropped instead, which `DockItem` handles.
public protocol LenientChoice: RawRepresentable, Codable where RawValue == String {
    /// What an unrecognised value reads as.
    static var fallback: Self { get }
}

public extension LenientChoice {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

public enum DockSetup: String, Codable, Sendable, CaseIterable {
    /// Apple's Dock only. No shelf, so no widgets.
    case macOSDockOnly = "native"
    /// Both surfaces visible. The sane default.
    case both
    /// Shelf replaces Apple's Dock, which gets auto-hidden.
    case customReplacement = "custom"
}

/// What Apple's Dock looked like before Docket borrowed its reserved strip.
///
/// Persisted rather than held in memory. Docket promises to put these back,
/// and a crash between changing them and quitting must not turn that into a
/// lie: whatever is recorded here is what gets restored, whenever the app next
/// gets the chance.
public struct DockPrefs: Codable, Hashable, Sendable {
    public var autoHide: Bool
    public var tileSize: Double
    public var orientation: String

    public init(autoHide: Bool, tileSize: Double, orientation: String) {
        self.autoHide = autoHide
        self.tileSize = tileSize
        self.orientation = orientation
    }
}

/// Which screen edge the shelf is docked to.
///
/// The cases are declared in the order Settings shows them. `.top` sits under
/// the menu bar rather than over it: placement measures from the top of
/// `visibleFrame`, so the menu bar keeps its edge. Apple's Dock has no top
/// edge, which is why `isSystemDockEdge` exists: anything that mirrors or
/// moves the system Dock only ever deals in the other three.
public enum DockPosition: String, Codable, Sendable, CaseIterable {
    case left, top, bottom, right

    /// A column on a side of the screen, rather than a row along the top or bottom.
    public var isVertical: Bool { self == .left || self == .right }
    /// A row, along either the top or the bottom.
    public var isHorizontal: Bool { !isVertical }
    /// Whether Apple's Dock can sit on this edge (`com.apple.dock orientation`).
    public var isSystemDockEdge: Bool { self != .top }
    /// Whether popups anchored to a tile (labels, groups, detail panels)
    /// open downwards, away from a shelf at the top.
    public var opensDownward: Bool { self == .top }
}

public enum ProfileKind: String, Codable, Sendable, CaseIterable {
    case macOSDock, customDock
}

public enum AppAppearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public enum DockMaterial: String, Codable, Sendable, CaseIterable {
    case liquidGlass, frosted
    /// An opaque plate that stays white, or black, whatever the appearance.
    case solidLight = "white", solidDark = "black"
    /// No plate at all. Every widget keeps its own card, and icons stand on
    /// the desktop the way they do on a transparent Dock.
    case plateless = "none"
}

public enum GlassStyle: String, Codable, Sendable, CaseIterable {
    case regular, clear
}

/// Which way Liquid Glass is leaned: left to sample the desktop, or tinted
/// toward light or dark so the shelf keeps one look over any wallpaper.
public enum GlassTint: String, Codable, Sendable, CaseIterable {
    case automatic, light, dark
}

/// Whether widgets keep their own colours or are drawn in greys only.
public enum WidgetColorMode: String, Codable, Sendable, CaseIterable {
    case original, monochrome
}

public enum MenuBarLabelMode: String, Codable, Sendable, CaseIterable {
    case none, native, custom, both
}

public enum SpacerSize: String, Codable, Sendable, CaseIterable {
    case small, regular
    /// Apple's Dock stores spacers as these tile types.
    public var dockTileType: String { self == .small ? "small-spacer-tile" : "spacer-tile" }
}

// MARK: - Palettes

public enum PaletteColor: String, Codable, Sendable, CaseIterable {
    case orange, yellow, pink, purple, blue, green, graphite, indigo, red, teal

    public var hex: String {
        switch self {
        case .orange: "#FF8D28"
        case .yellow: "#FFCC00"
        case .pink: "#FF2D55"
        case .purple: "#CB30E0"
        case .blue: "#0088FF"
        case .green: "#34C759"
        case .graphite: "#8E8E93"
        case .indigo: "#6155F5"
        case .red: "#FF383C"
        case .teal: "#00C3D0"
        }
    }

    /// The 8 swatches actually offered in pickers - `yellow` and `graphite`
    /// exist for stored values but are not user-selectable.
    public static let picker: [PaletteColor] = [.orange, .red, .pink, .purple, .indigo, .blue, .teal, .green]
}

public enum PaperColor: String, Codable, Sendable, CaseIterable {
    case yellow, orange, pink, purple, blue, green, graphite
    case cream, peach, coral, mint, teal, lavender, kraft, slate, night

    public var hex: String {
        switch self {
        case .yellow: "#F5D15C"
        case .orange: "#FFB36E"
        case .pink: "#F5A3BA"
        case .purple: "#C7ADEE"
        case .blue: "#96C7F5"
        case .green: "#ADD985"
        case .graphite: "#CFCCC2"
        case .cream: "#F6EFDF"
        case .peach: "#FFCFB0"
        case .coral: "#FF9A8B"
        case .mint: "#A8E6CF"
        case .teal: "#8FD8D8"
        case .lavender: "#DCD0F5"
        case .kraft: "#D9B98C"
        case .slate: "#5B6B7F"
        case .night: "#26262B"
        }
    }

    /// 纸是深色的，墨用浅色。按对比度算，不再写死哪几种纸，见 `PaperInk`。
    public var isDark: Bool { PaperInk.inkIsLight(on: hex) }

    /// 这张纸上的墨色，保证对比度不低于 4.5:1（WCAG 正文），见 `PaperInk`。
    public var inkHex: String { PaperInk.ink(on: hex) }

    public var title: String {
        switch self {
        case .yellow: tr("柠檬黄")
        case .orange: tr("橘子橙")
        case .pink: tr("樱花粉")
        case .purple: tr("葡萄紫")
        case .blue: tr("天空蓝")
        case .green: tr("青草绿")
        case .graphite: tr("石墨灰")
        case .cream: tr("奶油白")
        case .peach: tr("蜜桃")
        case .coral: tr("珊瑚红")
        case .mint: tr("薄荷绿")
        case .teal: tr("湖水青")
        case .lavender: tr("薰衣草")
        case .kraft: tr("牛皮纸")
        case .slate: tr("雾霾蓝")
        case .night: tr("夜黑")
        }
    }

    public static let picker: [PaperColor] = [
        .yellow, .cream, .kraft, .peach, .orange, .coral, .pink, .lavender,
        .purple, .blue, .teal, .mint, .green, .slate, .night,
    ]
}

public enum MetricColor {
    public static let cpu = "#CE32E3"
    public static let memory = "#078AFF"
    public static let storage = "#FF9F0A"
    public static let batteryPresent = "#34C759"
    public static let netDownload = "#078AFF"
    public static let netUpload = "#AF52DE"
}

// MARK: - Widget identity

public enum WidgetKind: String, Codable, Sendable, CaseIterable {
    // Registry order drives library order.
    // `hydration` (喝水提醒) was folded into `water`; a saved one is read
    // back as `water` by `WidgetInstance`, see `WaterIntake.legacyHydrationKind`.
    // `converter` (单位换算) and `currency` (汇率换算) were folded into
    // `calculator`, now 「算」; see `SmartCalc.legacyConverterKind`.
    case clock, world, stopwatch, timer, progress, countdown, alarm
    case calendar, reminders, notes, music, battery, system
    case network, aiUsage = "ai-usage", shortcut, airdrop, weather
    case stripe, paddle, stock, watchlist, shopify
    case photos, screenshots, downloads, fileShelf = "file-shelf"
    case clipboard, colorPicker = "color-picker"
    case capture, emoji, search, volume, toggles
    case github
    case calculator
    case mail
    case recorder
    case bookmarks
    case appSwitcher = "app-switcher"
    case wallpaper
    case microphone
    case gauges
    case posture
    case todo
    case ambient
    case lunar
    case trash
    case habit
    case week
    case crypto
    case appVolume = "app-volume"
    case radio
    case anniversary
    case water
    case translate
    case pet
    case podcast
    case perfectDay = "perfect-day"
    case slacker
    case aiAssistant = "ai-assistant"
}

/// What a widget opens when its card is clicked.
public enum WidgetTarget: Equatable, Sendable {
    case app(bundleID: String)
    /// A System Settings pane, by extension identifier.
    case settings(String)

    /// The URL scheme System Settings registers for deep links.
    public var settingsURL: URL? {
        guard case .settings(let pane) = self else { return nil }
        return URL(string: "x-apple.systempreferences:\(pane)")
    }
}

public enum WidgetCategory: String, Codable, Sendable, CaseIterable {
    /// 小组件库侧栏里和常用应用、文件夹放在一起的小组件（应用切换器、快捷指令）。
    case appsAndFolders = "Apps and Folders"
    case time = "Time"
    case todo = "Todo"
    case health = "Health"
    case ai = "AI"
    case tools = "Tools"
    case media = "Media"
    case files = "Files"
    case system = "System"
    case weather = "Weather"
    case stocks = "Stocks"

    /// Library sidebar order. 应用和文件夹 has a row of its own above the
    /// rest, drawn with the app and folder shortcuts, but is listed here so
    /// every category stays reachable.
    public static let ordered: [WidgetCategory] = [
        .appsAndFolders, .time, .todo, .health, .ai, .tools, .media, .files, .system, .weather, .stocks,
    ]

    /// 旧版本的原始值（Clocks、Reminders、Calendar、Sticky Notes、Business）
    /// 对应的新分类，以及新分类自己的原始值。认不出的返回 nil。
    public init?(legacy raw: String) {
        if let known = WidgetCategory(rawValue: raw) {
            self = known
            return
        }
        switch raw {
        case "Clocks", "Calendar": self = .time
        case "Reminders", "Sticky Notes": self = .todo
        case "Business": self = .stocks
        default: return nil
        }
    }

    /// 解码时兼容旧原始值；完全认不出的值退回“小工具”，不让旧配置读不出来。
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetCategory(legacy: raw) ?? .tools
    }
}

// MARK: - Widget configuration

/// Loosely-typed widget config, mirroring the catalog's "deep-copy the default
/// dictionary" model. A typed struct per kind would be 24 more Codable types
/// and a migration burden every time one gains an option; each widget instead
/// reads what it needs through typed accessors and tolerates missing keys.
public struct WidgetConfig: Codable, Hashable, Sendable {
    public enum Value: Codable, Hashable, Sendable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case list([Value])

        public init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else if let s = try? c.decode(String.self) { self = .string(s) }
            else if let l = try? c.decode([Value].self) { self = .list(l) }
            else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported config value")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try c.encode(b)
            case .number(let d): try c.encode(d)
            case .string(let s): try c.encode(s)
            case .list(let l): try c.encode(l)
            }
        }
    }

    public var values: [String: Value]

    public init(_ values: [String: Value] = [:]) { self.values = values }

    public subscript(key: String) -> Value? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func bool(_ key: String, default fallback: Bool = false) -> Bool {
        if case .bool(let b) = values[key] { return b }
        return fallback
    }

    public func double(_ key: String, default fallback: Double = 0) -> Double {
        if case .number(let d) = values[key] { return d }
        return fallback
    }

    public func int(_ key: String, default fallback: Int = 0) -> Int {
        if case .number(let d) = values[key] { return Int(d) }
        return fallback
    }

    public func string(_ key: String, default fallback: String = "") -> String {
        if case .string(let s) = values[key] { return s }
        return fallback
    }

    public func strings(_ key: String, default fallback: [String] = []) -> [String] {
        guard case .list(let l) = values[key] else { return fallback }
        return l.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    public mutating func set(_ key: String, _ value: Value?) { values[key] = value }

    /// Config carried by an instance, with any keys the catalog has since
    /// added filled in from the default. Keeps old saved widgets working when
    /// a widget gains an option.
    public func merging(defaults: WidgetConfig) -> WidgetConfig {
        WidgetConfig(defaults.values.merging(values) { _, mine in mine })
    }
}

public struct WidgetInstance: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    /// New widgets always start expanded; only kinds with a compact variant
    /// can ever be false.
    public var expanded: Bool
    public var config: WidgetConfig

    public init(id: UUID = UUID(), kind: WidgetKind, expanded: Bool = true, config: WidgetConfig) {
        self.id = id
        self.kind = kind
        self.expanded = expanded
        self.config = config
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, expanded, config
    }

    /// The synthesized decode, plus aliases: the old 单位换算 (`converter`)
    /// and 汇率换算 (`currency`) come back as 「算」 (`calculator`), see
    /// `SmartCalc`. And the old 喝水提醒 widget
    /// (`hydration`) comes back as 喝水 (`water`), its interval carried over
    /// by `WaterIntake.migratingHydration`. Same id, so the tile keeps its
    /// place, and the next save writes it as `water`, which makes the move
    /// one-time. Any other unknown kind still throws, which `DockItem`
    /// answers by dropping that one widget.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        expanded = try c.decode(Bool.self, forKey: .expanded)
        let raw = try c.decode(String.self, forKey: .kind)
        let stored = try c.decode(WidgetConfig.self, forKey: .config)
        if let known = WidgetKind(rawValue: raw) {
            kind = known
            switch known {
            // GitHub followed one `repo`; it now keeps a list under `repos`.
            case .github: config = GitHubWatch.migratingRepo(stored)
            // 时钟并掉的旧样式（大号数字、秒圈、折叠翻页、极简）读成新样式加选项。
            case .clock: config = ClockStyles.migrating(stored)
            // 日历的「日期 + 日程列表」换成了今日时间线。
            case .calendar: config = CalendarDay.migratingLayout(stored)
            // 计算器并成了「算」：算式照旧，补一条最近记录。
            case .calculator: config = SmartCalc.migratingCalculator(stored)
            // 天气七个样式并成四个：天气状况、风与日出日落读成“当前”加副标题，
            // 未来 7 天、10 天读成“多日预报”加天数。
            case .weather: config = WeatherStyle.migrating(stored)
            default: config = stored
            }
        } else if raw == WaterIntake.legacyHydrationKind {
            kind = .water
            config = WaterIntake.migratingHydration(stored)
        } else if raw == SmartCalc.legacyConverterKind {
            // 单位换算并进「算」：同一个 id，卡片位置不变，那一对单位留作默认。
            kind = .calculator
            config = SmartCalc.migratingConverter(stored)
        } else if raw == SmartCalc.legacyCurrencyKind {
            // 汇率换算并进「算」：币种对变成默认币种对。
            kind = .calculator
            config = SmartCalc.migratingCurrency(stored)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                                                   debugDescription: "Unknown widget kind \(raw)")
        }
    }
}

// MARK: - Shelf items

public struct FolderIcon: Codable, Hashable, Sendable {
    /// nil means "System color" - draw Finder's own icon.
    public var color: PaletteColor?
    /// Exactly one letter or digit, or nil.
    public var letter: String?

    public init(color: PaletteColor? = nil, letter: String? = nil) {
        self.color = color
        self.letter = letter
    }

    public var isEmpty: Bool { color == nil && letter == nil }
}

/// A file-system reference that survives the target being moved or renamed.
///
/// Docket is not sandboxed, so the bookmark is not about access rights - it is
/// purely so a pinned app still resolves after an update relocates it.
public struct FileRef: Codable, Hashable, Sendable {
    public var url: URL
    public var bookmark: Data?

    public init(url: URL, bookmark: Data? = nil) {
        self.url = url
        self.bookmark = bookmark
    }

    public static func capture(_ url: URL) -> FileRef {
        FileRef(url: url, bookmark: try? url.bookmarkData(options: [.minimalBookmark]))
    }

    /// Resolved location, preferring the bookmark. Returns nil when the target
    /// is genuinely gone - callers render that as a repairable dead item
    /// rather than silently dropping the user's entry.
    public func resolve() -> URL? {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) {
                return resolved
            }
        }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}

/// A tint a group's plate can carry, as on iOS.
///
/// A name rather than a colour so it survives Codable and so the light and
/// dark renderings can differ; the view layer owns the actual swatches.
public enum GroupTint: String, Codable, Hashable, Sendable, CaseIterable {
    case none, red, orange, yellow, green, teal, blue, purple, pink, graphite
}

/// A folder of dock items, shown as one tile with a grid of its contents.
public struct DockGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var tint: GroupTint
    public var items: [DockItem]

    public init(id: UUID = UUID(), name: String, tint: GroupTint = .none,
                items: [DockItem] = []) {
        self.id = id
        self.name = name
        self.tint = tint
        self.items = items
    }

    /// How many icons the closed tile shows: a 2×2 grid, as Dockset does.
    ///
    /// Not a preference - the tile is one dock slot wide, and a third column
    /// would put the icons below the size at which their artwork is legible.
    public static let previewCount = 4

    /// The icons drawn on the closed tile.
    public var preview: [DockItem] { Array(items.prefix(Self.previewCount)) }

    /// How many are not shown, for the overflow marker.
    public var hiddenCount: Int { max(0, items.count - Self.previewCount) }
}

public enum DockItem: Codable, Hashable, Identifiable, Sendable {
    case app(id: UUID, bundleID: String, ref: FileRef)
    case folder(id: UUID, ref: FileRef, icon: FolderIcon)
    case file(id: UUID, ref: FileRef)
    case link(id: UUID, url: URL, title: String)
    case spacer(id: UUID, size: SpacerSize)
    case widget(WidgetInstance)
    case group(DockGroup)

    public var id: UUID {
        switch self {
        case .app(let id, _, _), .folder(let id, _, _), .file(let id, _),
             .link(let id, _, _), .spacer(let id, _):
            return id
        case .widget(let w):
            return w.id
        case .group(let g):
            return g.id
        }
    }

    public var group: DockGroup? {
        if case .group(let g) = self { return g }
        return nil
    }

    public var widget: WidgetInstance? {
        if case .widget(let w) = self { return w }
        return nil
    }

    public var isWidget: Bool { widget != nil }

    /// Apple's Dock can only represent apps and spacers.
    public var isRepresentableInMacOSDock: Bool {
        switch self {
        case .app, .spacer: true
        case .folder, .file, .link, .widget, .group: false
        }
    }

    public var fileRef: FileRef? {
        switch self {
        case .app(_, _, let r), .folder(_, let r, _), .file(_, let r): r
        case .link, .spacer, .widget, .group: nil
        }
    }
}

// MARK: - Profiles

public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier mask. Must include Control, Option or Command, see
    /// `hasRequiredModifier`; Shift alone would claim ordinary typing.
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Swallows one element of any shape.
///
/// An unkeyed container only advances when something is decoded from it, so
/// skipping a bad element still needs a successful decode. This accepts
/// anything, which is the point.
private struct DiscardedItem: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}

public struct DockProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ProfileKind
    public var name: String
    public var color: PaletteColor
    public var items: [DockItem]
    /// Travels with a customDock profile; ignored for macOSDock profiles.
    public var scale: Double
    /// A global hotkey that switches to this profile, registered by
    /// `HotKeyService`. Both duplicate paths drop it, since two profiles must
    /// never claim one key combination.
    public var shortcut: KeyCombo?
    /// Still reserved, and read by nothing.
    ///
    /// The Focus filter that does exist keeps its choice of layout inside
    /// System Settings, as the filter's own parameter, so the profile has
    /// nothing to remember about it. Kept so a file that already carries the
    /// key decodes and saves unchanged.
    public var focusFilterID: String?

    /// Decodes item by item, dropping any it cannot read.
    ///
    /// An unknown widget kind, or a shape written by a newer build, used to
    /// throw out of the array, out of the profile, and out of the whole state
    /// file: one item nobody recognised and every profile was gone. Losing one
    /// tile is a far better failure than losing the shelf, and the rest of the
    /// profile is still exactly right.
    ///
    /// Deliberately not a lenient `WidgetKind`: falling back there would turn
    /// somebody's widget into a clock, silently, and leave it looking like
    /// their configuration rather than like a loss.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ProfileKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? tr("未命名")
        color = try c.decodeIfPresent(PaletteColor.self, forKey: .color) ?? .blue
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? Geometry.defaultScale
        shortcut = try c.decodeIfPresent(KeyCombo.self, forKey: .shortcut)
        focusFilterID = try c.decodeIfPresent(String.self, forKey: .focusFilterID)

        var unread = try c.nestedUnkeyedContainer(forKey: .items)
        var kept: [DockItem] = []
        while !unread.isAtEnd {
            // The decode has to advance the container even when it fails, or
            // one bad item is an infinite loop. Decoding into a throwaway
            // wrapper consumes the element either way.
            if let item = try? unread.decode(DockItem.self) {
                kept.append(item)
            } else {
                _ = try? unread.decode(DiscardedItem.self)
            }
        }
        items = kept
    }

    public init(id: UUID = UUID(), kind: ProfileKind, name: String,
                color: PaletteColor = .blue, items: [DockItem] = [],
                scale: Double = Geometry.defaultScale,
                shortcut: KeyCombo? = nil, focusFilterID: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.color = color
        self.items = items
        self.scale = scale
        self.shortcut = shortcut
        self.focusFilterID = focusFilterID
    }

    /// Items this profile can actually apply, given its kind.
    public var applicableItems: [DockItem] {
        kind == .macOSDock ? items.filter(\.isRepresentableInMacOSDock) : items
    }
}

// MARK: - Settings

/// What the shelf actually shows.
///
/// Pure, and here rather than inline in `AppState`, because the filter is a
/// trap: while mirroring, every app the profile holds is dropped and the real
/// Dock's are substituted. An app appended to the profile was therefore
/// filtered straight back out, and one removed from it came back on the next
/// render - both read as "the button does nothing". Editing must clear
/// `mirroring` first.
/// Whether a media reading describes something actually playing.
///
/// A page can report a title with no duration and no position, which rendered
/// as a track stuck at 0:00 under a name from nowhere - the numbers on screen
/// were a paused flag and an elapsed count that had landed in the title and
/// artist slots of a tile with nothing real behind it.
public enum MediaReading {
    public static func isMeaningful(title: String,
                                    duration: TimeInterval,
                                    elapsed: TimeInterval) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return duration > 0 || elapsed > 0
    }
}

/// Which of the shelf's settings the real Dock still governs.
public enum DockFollowing {
    /// The shelf's size.
    ///
    /// An explicit size overrides the Dock's, and nothing else: dragging the
    /// grip used to switch following off wholesale, which silently took the
    /// edge, magnification and auto-hide with it, so the shelf stopped hiding
    /// after a resize with nothing to connect the two.
    public static func scale(overridden: Bool, custom: Double,
                             system: Double, following: Bool) -> Double {
        if overridden { return custom }
        return following ? system : custom
    }
}

public enum ShelfItems {

    /// Drops one item onto another: into it if it is already a group, into a
    /// new group of the two otherwise.
    ///
    /// The target keeps its slot so the shelf does not reshuffle around the
    /// gesture - the two tiles become one where the target already was.
    public static func combining(_ itemID: UUID, into targetID: UUID,
                                 named name: String, in items: [DockItem]) -> [DockItem] {
        guard itemID != targetID,
              let slot = items.firstIndex(where: { $0.id == itemID }),
              let targetSlot = items.firstIndex(where: { $0.id == targetID })
        else { return items }

        var result = items
        let item = result[slot]
        if var group = result[targetSlot].group {
            group.items.append(item)
            result[targetSlot] = .group(group)
        } else {
            result[targetSlot] = .group(DockGroup(name: name,
                                                  items: [result[targetSlot], item]))
        }
        // Removed last so neither index shifts under the other.
        result.removeAll { $0.id == itemID }
        return result
    }

    /// Takes an item out of a group and puts it back on the shelf beside it,
    /// dissolving the group if that leaves it with fewer than two.
    /// - Parameter at: where the user dropped it, as a slot index. Beside the
    ///   group when unknown - a drop with no destination still has to land
    ///   somewhere predictable.
    public static func removingFromGroup(_ itemID: UUID, group groupID: UUID,
                                         in items: [DockItem],
                                         at destination: Int? = nil) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group,
              let inner = group.items.firstIndex(where: { $0.id == itemID })
        else { return items }

        var result = items
        let item = group.items.remove(at: inner)
        result[slot] = .group(group)
        let landing = min(max(0, destination ?? (slot + 1)), result.count)
        result.insert(item, at: landing)
        return dissolvingSmallGroups(in: result)
    }

    /// A group needs two things in it to be a group.
    ///
    /// Left holding one it is a worse version of the icon it contains - the
    /// same tile with the artwork shrunk into a quarter of it - so it gives
    /// way to that icon rather than waiting to be tidied up.
    public static func dissolvingSmallGroups(in items: [DockItem]) -> [DockItem] {
        items.flatMap { item -> [DockItem] in
            guard let group = item.group, group.items.count < 2 else { return [item] }
            return group.items
        }
    }

    public static func displayed(profile: [DockItem],
                                 mirrored: [DockItem],
                                 mirroring: Bool) -> [DockItem] {
        // Enforced here rather than only where items leave a group, so the
        // rule holds however the data got that way - a group of one written
        // by an older build, or restored from a backup, still gives way to
        // the icon it holds instead of rendering three empty cells.
        let profile = dissolvingSmallGroups(in: profile)
        guard mirroring else { return profile }
        // Widgets first: a mirrored Dock can be long enough to push them past
        // the screen edge, where only scrolling would reach them.
        let extras = profile.filter { if case .app = $0 { false } else { true } }
        return extras + mirrored
    }
}

public struct CustomDockSettings: Codable, Hashable, Sendable {
    /// nil renders nothing - an explicit "no shelf", not an error state.
    public var profileID: UUID?
    /// Mirror the real Dock's size, edge, magnification and hiding.
    ///
    /// On by default: the user has already told macOS how they like their
    /// Dock, and the shelf's whole job is to sit beside it convincingly.
    public var followSystemDock: Bool = true
    /// Mirror the real Dock's *app list* as well as its settings.
    ///
    /// Separate from `followSystemDock` because editing the shelf must not
    /// cost the user their mirrored size, edge and hiding: adding or removing
    /// an app takes ownership of the list alone, and everything else keeps
    /// following. Optional so state saved before this flag existed still
    /// decodes - absent means "yes", which is what those profiles were doing.
    public var mirrorSystemApps: Bool?
    /// Set once the user has sized the shelf themselves.
    ///
    /// Optional so state written before it existed still decodes. Separate
    /// from `followSystemDock` because dragging the grip is an override of
    /// the *size* - it used to switch following off wholesale, which silently
    /// took the Dock's edge, magnification and auto-hide with it, so the shelf
    /// simply stopped hiding after a resize.
    public var scaleOverridden: Bool?
    public var position: DockPosition = .bottom
    public var displayID: UInt32?
    /// Live value, mirroring the active profile's scale.
    public var scale: Double = Geometry.defaultScale
    /// Liquid Glass by default: Docket requires macOS 26 anyway, and the
    /// real material is what makes the shelf sit beside the Dock convincingly.
    public var material: DockMaterial = .liquidGlass
    public var glass: GlassStyle = .regular
    /// Only read while the material is Liquid Glass.
    public var glassTint: GlassTint = .automatic
    /// Widget colours on the shelf: their own, or greys only.
    public var widgetColor: WidgetColorMode = .original
    /// An opaque plate whatever the material, as macOS's own Reduce
    /// Transparency does. The system setting still applies on its own; this
    /// is for anyone who wants it on the shelf alone.
    public var reduceTransparency: Bool = false
    /// A supporter colour laid into the plate (`ShelfColor`), empty for none.
    public var shelfColor: String = ""
    /// What happens when the shelf is longer than the screen.
    public var overflow: ShelfOverflow = .scroll
    public var autoHide: Bool = false
    public var showHandleWhenHidden: Bool = true
    public var useAsDesktopWidget: Bool = false
    public var hideWhenMacOSDockAppears: Bool = false
    public var showRunningApps: Bool = true
    public var showTrash: Bool = false
    /// Flies on the shelf's own Trash icon, the same as the 废纸篓 widget's.
    /// On by default: they only arrive once the Trash passes the size below.
    public var showTrashFlies: Bool = true
    /// The size the shelf Trash icon's flies arrive at, one of
    /// `TrashFlies.thresholds`' values.
    public var trashFliesThreshold: String = TrashFlies.defaultThreshold
    /// Widgets and nothing else on the shelf.
    ///
    /// For the setup this app is usually run in: Apple's Dock keeps the apps
    /// on one edge and the shelf carries the widgets on another. Without this
    /// the shelf mirrors the Dock's apps as well, so the same icons are on
    /// screen twice and the widgets are pushed to the end of a row they are
    /// supposed to be the point of.
    ///
    /// A display filter, not an edit. Apps, folders and links stay in the
    /// profile untouched and come straight back when this is turned off, so
    /// it costs nothing to try.
    public var widgetsOnly: Bool = false
    /// On by default: a dock that does not magnify does not feel like
    /// the Dock, which is the entire reference point for this surface.
    public var magnification: Bool = true
    /// Command-scroll, or a sideways two-finger swipe, over the shelf moves
    /// to the next or previous shelf layout.
    ///
    /// On by default because neither gesture did anything on the shelf
    /// before: Command-scroll was ignored, and a sideways swipe only scrolls
    /// a shelf that overflows, which keeps doing exactly that.
    public var switchLayoutsByGesture: Bool = true
    /// Points between the shelf and the screen edge it sits on.
    ///
    /// Six was hard-coded, which is right beside Apple's Dock but reads as a
    /// stray gap to anyone who wants the shelf flush with the bezel.
    public var edgeGap: Double = 6
    /// Keep clear of Apple's Dock when both are on the same edge.
    ///
    /// On by default so the two never stack. Turning it off lets the shelf
    /// sit at the bezel and draw over the Dock, which is what people asking
    /// for "flush" usually mean when they keep Apple's Dock on that edge.
    public var reserveSystemDockSpace: Bool = true

    /// Decodes field by field, so an unknown or missing key is a default and
    /// not a thrown error.
    ///
    /// Synthesized `Codable` treats every non-optional property as required.
    /// That made adding one setting to this struct reject the user's whole
    /// state file, which `Store.load()` answers by putting the file aside and
    /// starting from a first-run default: one new key, and every profile,
    /// widget and pinned app silently gone. Decoding leniently is what makes
    /// adding a setting a safe thing to do.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        followSystemDock = try c.decodeIfPresent(Bool.self, forKey: .followSystemDock) ?? true
        mirrorSystemApps = try c.decodeIfPresent(Bool.self, forKey: .mirrorSystemApps)
        scaleOverridden = try c.decodeIfPresent(Bool.self, forKey: .scaleOverridden)
        position = try c.decodeIfPresent(DockPosition.self, forKey: .position) ?? .bottom
        displayID = try c.decodeIfPresent(UInt32.self, forKey: .displayID)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? Geometry.defaultScale
        material = try c.decodeIfPresent(DockMaterial.self, forKey: .material) ?? .liquidGlass
        glass = try c.decodeIfPresent(GlassStyle.self, forKey: .glass) ?? .regular
        glassTint = try c.decodeIfPresent(GlassTint.self, forKey: .glassTint) ?? .automatic
        widgetColor = try c.decodeIfPresent(WidgetColorMode.self, forKey: .widgetColor) ?? .original
        reduceTransparency = try c.decodeIfPresent(Bool.self, forKey: .reduceTransparency) ?? false
        shelfColor = try c.decodeIfPresent(String.self, forKey: .shelfColor) ?? ""
        overflow = try c.decodeIfPresent(ShelfOverflow.self, forKey: .overflow) ?? .scroll
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        showHandleWhenHidden = try c.decodeIfPresent(Bool.self, forKey: .showHandleWhenHidden) ?? true
        useAsDesktopWidget = try c.decodeIfPresent(Bool.self, forKey: .useAsDesktopWidget) ?? false
        hideWhenMacOSDockAppears = try c.decodeIfPresent(Bool.self, forKey: .hideWhenMacOSDockAppears) ?? false
        showRunningApps = try c.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? true
        showTrash = try c.decodeIfPresent(Bool.self, forKey: .showTrash) ?? false
        showTrashFlies = try c.decodeIfPresent(Bool.self, forKey: .showTrashFlies) ?? true
        trashFliesThreshold = try c.decodeIfPresent(String.self, forKey: .trashFliesThreshold)
            ?? TrashFlies.defaultThreshold
        widgetsOnly = try c.decodeIfPresent(Bool.self, forKey: .widgetsOnly) ?? false
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? true
        switchLayoutsByGesture = try c.decodeIfPresent(Bool.self, forKey: .switchLayoutsByGesture) ?? true
        edgeGap = try c.decodeIfPresent(Double.self, forKey: .edgeGap) ?? 6
        reserveSystemDockSpace = try c.decodeIfPresent(Bool.self, forKey: .reserveSystemDockSpace) ?? true
    }

    public init() {}
}

public struct MacOSDockSettings: Codable, Hashable, Sendable {
    /// nil means "No profile" - leave the live Dock completely alone.
    public var profileID: UUID?

    /// Decodes field by field, so an unknown or missing key is a default and
    /// not a thrown error.
    ///
    /// Synthesized `Codable` treats every non-optional property as required.
    /// That made adding one setting to this struct reject the user's whole
    /// state file, which `Store.load()` answers by putting the file aside and
    /// starting from a first-run default: one new key, and every profile,
    /// widget and pinned app silently gone. Decoding leniently is what makes
    /// adding a setting a safe thing to do.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
    }

    public init() {}
}

public struct MenuBarSettings: Codable, Hashable, Sendable {
    public var showIcon: Bool = true
    /// Icon only by default: the layout's name is already in the menu's
    /// submenu, and beside the icon it cost menu bar width all day.
    public var label: MenuBarLabelMode = .none
    /// Written by every save. A file without it predates the icon-only
    /// default, so its old automatic `.custom` is reset to `.none` once.
    public var labelReviewed: Bool = true

    /// Decodes field by field, so an unknown or missing key is a default and
    /// not a thrown error.
    ///
    /// Synthesized `Codable` treats every non-optional property as required.
    /// That made adding one setting to this struct reject the user's whole
    /// state file, which `Store.load()` answers by putting the file aside and
    /// starting from a first-run default: one new key, and every profile,
    /// widget and pinned app silently gone. Decoding leniently is what makes
    /// adding a setting a safe thing to do.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showIcon = try c.decodeIfPresent(Bool.self, forKey: .showIcon) ?? true
        let reviewed = try c.decodeIfPresent(Bool.self, forKey: .labelReviewed) ?? false
        let saved: MenuBarLabelMode = try c.decodeIfPresent(MenuBarLabelMode.self, forKey: .label) ?? MenuBarLabelMode.none
        label = reviewed ? saved : MenuBarLabelMode.none
        labelReviewed = true
    }

    public init() {}
}

// MARK: - Persisted root

public struct PersistedState: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int = PersistedState.currentVersion
    public var setup: DockSetup = .both
    public var appearance: AppAppearance = .system
    public var profiles: [DockProfile] = []
    public var customDock = CustomDockSettings()
    public var macOSDock = MacOSDockSettings()
    public var menuBar = MenuBarSettings()
    /// Shared across every Focus Timer widget - the product treats it as one timer.
    public var timer = TimerState()
    /// Snapshot of the user's live Dock taken before Docket ever wrote to it.
    public var originalMacOSDock: [MacOSDockTile]?
    /// Apple's Dock preferences from before the shelf borrowed its strip.
    /// Non-nil means they are currently changed and owe a restore.
    public var borrowedDockPrefs: DockPrefs?
    /// Whether to look for new releases.
    ///
    /// Three states on purpose. Nil means the question has not been asked, and
    /// it is asked once rather than assumed: this is the only thing the app
    /// does unprompted that talks to a server, and it necessarily tells GitHub
    /// that someone ran it. Everything else that leaves the machine, weather
    /// and stock quotes, is there because the user added that widget.
    public var checkForUpdates: Bool?
    /// Layouts to return to when the current Focus ends. Nil while no Focus
    /// filter has switched anything.
    public var focusRevert: FocusRevert?
    /// 灵动提示: the capsule under the notch. All off by default.
    public var island = IslandSettings()
    /// 添加和移除小组件时的音效. On by default.
    public var widgetSounds = WidgetSoundSettings()
    /// 提醒事项、喝水、待办到点时的提示音。音量和总开关跟着 `widgetSounds`。
    public var reminderSounds = ReminderSoundSettings()
    /// 提醒事项、喝水、待办到点时弹不弹卡片，三类各自开关。
    public var reminderPopups = ReminderPopupSettings()
    /// AI 助手的刘海对话：入口、快捷键、每个服务的打开方式和接口。密钥不在这里。
    public var aiNotch = AINotchSettings()
    /// 弹出快速待办小输入框的全局快捷键。默认不设。
    public var quickTodoHotKey: KeyCombo?

    /// Decodes field by field, so an unknown or missing key is a default and
    /// not a thrown error.
    ///
    /// Synthesized `Codable` treats every non-optional property as required.
    /// That made adding one setting to this struct reject the user's whole
    /// state file, which `Store.load()` answers by putting the file aside and
    /// starting from a first-run default: one new key, and every profile,
    /// widget and pinned app silently gone. Decoding leniently is what makes
    /// adding a setting a safe thing to do.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? PersistedState.currentVersion
        setup = try c.decodeIfPresent(DockSetup.self, forKey: .setup) ?? .both
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        profiles = try c.decodeIfPresent([DockProfile].self, forKey: .profiles) ?? []
        customDock = try c.decodeIfPresent(CustomDockSettings.self, forKey: .customDock) ?? CustomDockSettings()
        macOSDock = try c.decodeIfPresent(MacOSDockSettings.self, forKey: .macOSDock) ?? MacOSDockSettings()
        menuBar = try c.decodeIfPresent(MenuBarSettings.self, forKey: .menuBar) ?? MenuBarSettings()
        timer = try c.decodeIfPresent(TimerState.self, forKey: .timer) ?? TimerState()
        originalMacOSDock = try c.decodeIfPresent([MacOSDockTile].self, forKey: .originalMacOSDock)
        borrowedDockPrefs = try c.decodeIfPresent(DockPrefs.self, forKey: .borrowedDockPrefs)
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates)
        focusRevert = try c.decodeIfPresent(FocusRevert.self, forKey: .focusRevert)
        island = try c.decodeIfPresent(IslandSettings.self, forKey: .island) ?? IslandSettings()
        widgetSounds = try c.decodeIfPresent(WidgetSoundSettings.self, forKey: .widgetSounds) ?? WidgetSoundSettings()
        reminderSounds = (try? c.decodeIfPresent(ReminderSoundSettings.self, forKey: .reminderSounds)) ?? ReminderSoundSettings()
        reminderPopups = (try? c.decodeIfPresent(ReminderPopupSettings.self, forKey: .reminderPopups)) ?? ReminderPopupSettings()
        aiNotch = (try? c.decodeIfPresent(AINotchSettings.self, forKey: .aiNotch)) ?? AINotchSettings()
        quickTodoHotKey = try? c.decodeIfPresent(KeyCombo.self, forKey: .quickTodoHotKey)
    }

    public init() {}

    public func profile(_ id: UUID?) -> DockProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    public func profiles(of kind: ProfileKind) -> [DockProfile] {
        profiles.filter { $0.kind == kind }
    }

    public var activeCustomProfile: DockProfile? { profile(customDock.profileID) }
    public var activeMacOSProfile: DockProfile? { profile(macOSDock.profileID) }
}

// MARK: - Shared timer state

public enum TimerPhase: String, Codable, Sendable, CaseIterable {
    case focus, rest, long

    public var label: String {
        switch self {
        case .focus: tr("专注")
        case .rest: tr("休息")
        case .long: tr("长休息")
        }
    }
}

public struct TimerState: Codable, Hashable, Sendable {
    public var work: Int = 25          // 1...180
    public var rest: Int = 5           // 1...60
    public var longBreak: Int = 15     // 1...180
    public var sessions: Int = 4       // 1...12
    public var phase: TimerPhase = .focus
    public var completed: Int = 0
    public var color: PaletteColor = .indigo
    public var alerts: Bool = true
    public var deadline: Date?
    public var paused: TimeInterval?
    public var duration: TimeInterval?
    /// 休息时提醒起身：休息环节卡片变绿，写“站起来走走”，同时让久坐提醒让位。
    public var standUp: Bool = true
    /// 上一次休息环节结束的时刻，久坐提醒从这里重新算已坐多久。
    public var stoodUp: Date?

    /// Decodes field by field, so an unknown or missing key is a default and
    /// not a thrown error.
    ///
    /// Synthesized `Codable` treats every non-optional property as required.
    /// That made adding one setting to this struct reject the user's whole
    /// state file, which `Store.load()` answers by putting the file aside and
    /// starting from a first-run default: one new key, and every profile,
    /// widget and pinned app silently gone. Decoding leniently is what makes
    /// adding a setting a safe thing to do.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        work = try c.decodeIfPresent(Int.self, forKey: .work) ?? 25
        rest = try c.decodeIfPresent(Int.self, forKey: .rest) ?? 5
        longBreak = try c.decodeIfPresent(Int.self, forKey: .longBreak) ?? 15
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 4
        phase = try c.decodeIfPresent(TimerPhase.self, forKey: .phase) ?? .focus
        completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        color = try c.decodeIfPresent(PaletteColor.self, forKey: .color) ?? .indigo
        alerts = try c.decodeIfPresent(Bool.self, forKey: .alerts) ?? true
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        paused = try c.decodeIfPresent(TimeInterval.self, forKey: .paused)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        standUp = try c.decodeIfPresent(Bool.self, forKey: .standUp) ?? true
        stoodUp = try c.decodeIfPresent(Date.self, forKey: .stoodUp)
    }

    public init() {}

    public var minutes: Int {
        switch phase {
        case .focus: work
        case .rest: rest
        case .long: longBreak
        }
    }
}

public extension UUID {
    /// A UUID derived deterministically from a string.
    ///
    /// Transient shelf items (running-but-unpinned apps) need an identity that
    /// is stable across renders but is not persisted anywhere. Hashing the
    /// bundle identifier gives exactly that; generating a fresh UUID instead
    /// makes SwiftUI rebuild the view on every frame.
    static func stable(from string: String) -> UUID {
        var hash = SHA256Lite()
        hash.combine(string)
        return hash.uuid
    }
}

/// Small, dependency-free digest. Not cryptographic - it only needs to spread
/// bundle identifiers across the UUID space without colliding.
private struct SHA256Lite {
    private var a: UInt64 = 0x243F6A8885A308D3
    private var b: UInt64 = 0x13198A2E03707344

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            a = (a ^ UInt64(byte)) &* 0x100000001B3
            b = (b &+ UInt64(byte)) &* 0x9E3779B97F4A7C15
            b ^= b >> 29
        }
    }

    var uuid: UUID {
        var bytes = [UInt8]()
        withUnsafeBytes(of: a.bigEndian) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: b.bigEndian) { bytes.append(contentsOf: $0) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Applies a displayed ordering back onto a stored list.
public enum Reorder {

    /// Reorders `items` to match `displayed`, by identity.
    ///
    /// Index-based reordering is wrong here: while the shelf mirrors the
    /// macOS Dock it shows the profile's own items *plus* the Dock's apps, so
    /// a position on screen has no relationship to a position in the stored
    /// array. Ids that the shelf was not showing keep their place rather than
    /// being dropped - losing a user's pinned item to a drag would be far
    /// worse than an imperfect order.
    public static func apply(order displayed: [UUID], to items: [DockItem]) -> [DockItem] {
        var remaining = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DockItem] = []
        result.reserveCapacity(items.count)
        for id in displayed {
            if let item = remaining.removeValue(forKey: id) { result.append(item) }
        }
        result.append(contentsOf: items.filter { remaining[$0.id] != nil })
        return result
    }
}

// MARK: - Choices that tolerate a value they do not know

// Each fallback is the same value the property defaults to, so an unreadable
// setting behaves exactly as one that was never written.
extension DockSetup: LenientChoice { public static var fallback: Self { .both } }
extension DockPosition: LenientChoice { public static var fallback: Self { .bottom } }
extension AppAppearance: LenientChoice { public static var fallback: Self { .system } }
extension DockMaterial: LenientChoice { public static var fallback: Self { .liquidGlass } }
extension GlassStyle: LenientChoice { public static var fallback: Self { .regular } }
extension GlassTint: LenientChoice { public static var fallback: Self { .automatic } }
extension WidgetColorMode: LenientChoice { public static var fallback: Self { .original } }
extension MenuBarLabelMode: LenientChoice { public static var fallback: Self { .none } }
extension SpacerSize: LenientChoice { public static var fallback: Self { .regular } }
extension PaletteColor: LenientChoice { public static var fallback: Self { .blue } }
extension PaperColor: LenientChoice { public static var fallback: Self { .yellow } }
extension TimerPhase: LenientChoice { public static var fallback: Self { .focus } }

// ProfileKind is deliberately absent. A profile that decoded as the wrong kind
// would be applied to the wrong surface, writing a shelf layout into Apple's
// Dock. Losing the profile is the better failure, and it is one profile rather
// than the file.

// MARK: - 简体中文显示名称
//
// 中文本地化分支新增。原始值（rawValue）会被持久化或用作标识符，因此保持英文不变，
// 界面上显示的名称统一从这里取。

public extension DockPosition {
    /// 界面上显示的屏幕边缘名称。
    var displayName: String {
        switch self {
        case .left: tr("左侧")
        case .top: tr("顶部")
        case .bottom: tr("底部")
        case .right: tr("右侧")
        }
    }
}

public extension WidgetCategory {
    /// 小组件库侧边栏中显示的类别名称。
    var displayName: String {
        switch self {
        case .appsAndFolders: tr("应用和文件夹")
        case .time: tr("时间与日历")
        case .todo: tr("待办与笔记")
        case .health: tr("健康与习惯")
        case .ai: tr("AI 与效率")
        case .tools: tr("小工具")
        case .media: tr("媒体")
        case .files: tr("文件")
        case .system: tr("系统")
        case .weather: tr("天气")
        case .stocks: tr("行情")
        }
    }

    /// 侧边栏的 SF Symbols 图标。
    var symbol: String {
        switch self {
        case .appsAndFolders: "app.badge"
        case .time: "clock"
        case .todo: "checklist"
        case .health: "heart.text.square"
        case .ai: "sparkles"
        case .tools: "wrench.and.screwdriver"
        case .media: "play.rectangle"
        case .files: "folder"
        case .system: "cpu"
        case .weather: "cloud.sun"
        case .stocks: "chart.line.uptrend.xyaxis"
        }
    }
}

/// 颜色原始值（如 "red"、"graphite"）对应的中文名称；未知值按原样首字母大写。
public func docketColourName(_ raw: String) -> String {
    switch raw {
    case "red": tr("红色")
    case "orange": tr("橙色")
    case "yellow": tr("黄色")
    case "green": tr("绿色")
    case "teal": tr("青色")
    case "blue": tr("蓝色")
    case "indigo": tr("靛蓝色")
    case "purple": tr("紫色")
    case "pink": tr("粉色")
    case "graphite": tr("石墨色")
    default: raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
