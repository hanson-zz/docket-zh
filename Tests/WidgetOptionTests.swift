import Foundation
import XCTest

/// The controls the Widgets tab builds for a widget's options.
///
/// Every defect these cover had the same shape: the control rendered, it
/// accepted input, and the value went nowhere useful. A setting that looks
/// like it worked is worse than one that is missing.
final class WidgetOptionTests: XCTestCase {

    // MARK: Reading with the catalog's default

    /// A widget saved before a key existed carries no value for it, and the
    /// control used to read it with Swift's zero rather than the catalog's
    /// default. So the toggle showed off while the tile ran on, until it was
    /// touched once and the disagreement wrote itself into the file.
    func testAMissingKeyReadsAsTheCatalogDefault() {
        for kind in WidgetKind.allCases {
            guard let entry = WidgetCatalog.entry(kind) else { continue }
            let empty = WidgetConfig()
            for key in WidgetCatalog.configurableKeys(kind) {
                switch entry.defaults.values[key] {
                case .bool(let fallback):
                    XCTAssertEqual(empty.bool(key, default: fallback), fallback,
                                   "\(kind.rawValue).\(key)")
                case .string(let fallback):
                    XCTAssertEqual(empty.string(key, default: fallback), fallback,
                                   "\(kind.rawValue).\(key)")
                default:
                    continue
                }
            }
        }
    }

    /// And a stored value still wins, or the control could not change anything.
    func testAStoredValueBeatsTheDefault() {
        var config = WidgetConfig()
        config.set("chart", .bool(true))
        XCTAssertTrue(config.bool("chart", default: false))
    }

    // MARK: Every option has some control

    /// The Widgets tab builds a control per configurable key. A key whose
    /// shape has no branch renders nothing, so the option exists, is stored,
    /// and cannot be reached: `symbols` was exactly that.
    func testEveryConfigurableKeyHasAShapeThatCanBeRendered() {
        for kind in WidgetKind.allCases {
            guard let entry = WidgetCatalog.entry(kind) else { continue }
            for key in WidgetCatalog.configurableKeys(kind) {
                let value = entry.defaults.values[key]
                XCTAssertNotNil(value, "\(kind.rawValue).\(key) is listed but has no default")
                switch value {
                case .bool, .number, .string, .list: break
                case .none: XCTFail("\(kind.rawValue).\(key) has no value to render")
                }
            }
        }
    }

    // MARK: Nothing offered that nothing reads

    /// Every configurable key becomes a control in the Widgets tab, so a key
    /// the widget never reads is a switch that persists and changes nothing.
    /// Eleven of them shipped that way across four widgets.
    ///
    /// Pinned as a list rather than inferred, because the reader lives in a
    /// view the test target cannot see. The list is the promise: adding a key
    /// here means committing to read it, and the failure message says so.
    func testNoWidgetOffersAnOptionItDoesNotRead() {
        let expected: [WidgetKind: Set<String>] = [
            .world: ["city", "zone"],
            .progress: ["period", "liquidMotion"],
            .timer: ["look"],
            .countdown: ["duration", "name", "presets", "look", "sound"],
            .alarm: ["time", "name", "sound"],
            .calendar: ["allDay", "calendars"],
            .reminders: ["list"],
            .notes: ["text", "color", "font", "fontSize"],
            .music: ["mini", "previous", "next", "backward", "forward",
                     "skip", "spotify", "apple", "netease", "xiaoyuzhou", "browsers",
                     "qqmusic", "autoSwitch", "pinned"],
            .battery: ["devices", "bluetooth", "look"],
            .system: ["chart", "metrics"],
            .network: ["display", "chart", "unit"],
            .shortcut: [],
            .stock: ["symbol", "symbols", "chart", "alerts", "rotate", "colors", "metalUnit"],
            .watchlist: ["symbols", "groups", "holdings", "sort", "colors", "metalUnit"],
            .weather: ["city", "cities", "fahrenheit", "caption", "days", "moreCities", "showIndices", "showRain"],
            .photos: ["folder", "interval", "shuffle", "memoriesFirst"],
            .emoji: ["emoji"],
            .search: ["engine"],
            .github: ["repos", "notify", "interval"],
            .calculator: ["currencyFrom", "currencyTo", "decimals", "grouping"],
            .colorPicker: ["copyFormat", "hexStyle", "showPalette"],
            .recorder: ["folder"],
            .mail: ["limit", "markReadOnOpen", "summary"],
            .bookmarks: ["links"],
            .wallpaper: ["folder", "allScreens"],
            .gauges: ["rings", "storageAlert", "batteryAlert", "cpuAlert", "memoryAlert"],
            .microphone: ["muteKey", "notifyCamera", "notifyMic", "redWhenMuted"],
            .posture: ["duration", "start", "end", "notify", "goal", "away", "awayAfter"],
            .aiUsage: ["show", "notify", "alertAt", "notifyDone", "extras", "look",
                       "soundWaiting", "soundDone", "soundQuota", "tone"],
            .todo: ["showDone"],
            .ambient: ["sounds", "volume"],
            .lunar: ["showAlmanac", "showTerm", "workAlert", "workAlertLead"],
            .trash: ["flies", "threshold"],
            .capture: ["after", "buttons", "delay", "format"],
            .habit: ["showStreak"],
            .week: ["allDay", "calendars"],
            .crypto: ["coins", "currency", "colors", "chart"],
            .radio: ["skin", "volume"],
            .anniversary: ["showRing"],
            .water: ["cupSize", "remindEvery", "start", "end", "unit", "character", "dryUp"],
            .clipboard: ["pasteOnClick"],
            .fileShelf: ["expire"],
            .translate: ["clickAction", "autoDirection"],
            .pet: ["character"],
            .perfectDay: ["look"],
            .podcast: ["notify"],
            .toggles: ["actions", "keepAwakeFor", "showNames"],
            .appSwitcher: ["sort"],
            // 时钟的子选项来自样式注册表，各由 ClockStyles.face 读（见 ClockStyleTests）。
            .clock: Set(["seconds"] + ClockStyles.optionKeys),
            .aiAssistant: [],
            .slacker: ["workdays", "start", "end", "holidays", "payday", "income", "more", "font", "tint", "look"],
        ]

        for kind in WidgetKind.allCases {
            guard WidgetCatalog.entry(kind) != nil else { continue }
            let offered = Set(WidgetCatalog.configurableKeys(kind))
            let promised = expected[kind] ?? []
            XCTAssertEqual(offered, promised, """
                \(kind.rawValue) offers \(offered.sorted()) but this test \
                expects \(promised.sorted()). If you added an option, read it \
                somewhere and add it here. If you removed one, drop it here \
                too. An option nothing reads is a control that persists and \
                does nothing.
                """)
        }
    }

    // MARK: Readers agreeing on a default

    /// A widget saved before an option existed carries no value for it, so
    /// every reader has to fall back to the same thing. `naturalSize` read
    /// System Activity's metrics with no default while the tile and the panel
    /// both defaulted to two, so the tile measured as one column and drew two.
    func testAnUnconfiguredWidgetIsMeasuredForWhatItDraws() {
        let bare = WidgetInstance(kind: .system, config: WidgetConfig())
        var explicit = bare
        explicit.config.set("metrics", .list([.string("cpu"), .string("memory")]))

        XCTAssertEqual(WidgetCatalog.naturalSize(bare),
                       WidgetCatalog.naturalSize(explicit),
                       "no stored metrics has to measure the same as the default it draws")
    }

    /// And the sizes really do differ by count, or the test above would pass
    /// for the wrong reason.
    func testTheSizeDependsOnHowManyMetricsThereAre() {
        var one = WidgetInstance(kind: .system, config: WidgetConfig())
        one.config.set("metrics", .list([.string("cpu")]))
        var three = one
        three.config.set("metrics", .list([.string("cpu"), .string("memory"), .string("disk")]))

        XCTAssertNotEqual(WidgetCatalog.naturalSize(one).width,
                          WidgetCatalog.naturalSize(three).width)
    }

    // MARK: Free-form lists

    /// The watchlist editor is a comma separated field, so the parse is the
    /// whole feature. Whitespace, trailing separators and empty entries all
    /// arrive while someone is still typing.
    func testCommaSeparatedEntriesAreParsedForgivingly() {
        XCTAssertEqual(parse("AAPL, MSFT,NVDA"), ["AAPL", "MSFT", "NVDA"])
        XCTAssertEqual(parse("  AAPL  ,   MSFT  "), ["AAPL", "MSFT"])
        XCTAssertEqual(parse("AAPL,,MSFT"), ["AAPL", "MSFT"], "a double comma is a typo, not a gap")
        XCTAssertEqual(parse("AAPL,"), ["AAPL"], "mid-edit, having just typed the separator")
    }

    /// An empty field is a half-finished edit rather than a request for a
    /// widget with nothing in it, so it must not be written.
    func testAnEmptyListIsNotWritten() {
        XCTAssertTrue(parse("").isEmpty)
        XCTAssertTrue(parse("   ,  , ").isEmpty)
    }

    private func parse(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Round trip

    /// What the field shows has to be what a save would produce, or an edit
    /// that changes nothing still rewrites the value.
    func testTheListSurvivesADisplayAndReparse() {
        let original = ["AAPL", "MSFT", "NVDA"]
        XCTAssertEqual(parse(original.joined(separator: ", ")), original)
    }
}

/// Whether an option means anything given the rest of the configuration.
///
/// An option that applies to one layout and not another is the same defect as
/// one nothing reads: the control accepts a change and produces none.
final class OptionApplicabilityTests: XCTestCase {

    private func system(layout: String) -> WidgetConfig {
        var config = WidgetConfig()
        config.set("layout", .string(layout))
        return config
    }

    func testTheChartAppliesToNumbersOnly() {
        XCTAssertTrue(WidgetCatalog.applies("chart", to: system(layout: "numbers"), kind: .system))
        XCTAssertFalse(WidgetCatalog.applies("chart", to: system(layout: "rings"), kind: .system))
        XCTAssertFalse(WidgetCatalog.applies("chart", to: system(layout: "bars"), kind: .system))
    }

    /// The default layout is numbers, so an unconfigured widget offers it.
    func testAnUnconfiguredWidgetStillOffersTheChart() {
        XCTAssertTrue(WidgetCatalog.applies("chart", to: WidgetConfig(), kind: .system))
    }

    /// Only System Activity's chart is conditional. Network has charted and
    /// uncharted variants with no layout key, so its own switch always means
    /// something.
    func testNetworksChartIsNotConditional() {
        XCTAssertTrue(WidgetCatalog.applies("chart", to: WidgetConfig(), kind: .network))
    }

    private func music(mini: Bool) -> WidgetConfig {
        var config = WidgetConfig()
        config.set("mini", .bool(mini))
        return config
    }

    /// Mini Now Playing is a 64pt chip: artwork and one glyph, which is play
    /// and pause. The wide layout is the only one that draws skipping and
    /// seeking, so in mini those five controls accepted a change and drew
    /// nothing.
    func testTheTransportOptionsApplyToTheWideLayoutOnly() {
        for key in ["previous", "next", "backward", "forward", "skip"] {
            XCTAssertTrue(WidgetCatalog.applies(key, to: music(mini: false), kind: .music),
                          "\(key) is drawn by the wide layout")
            XCTAssertFalse(WidgetCatalog.applies(key, to: music(mini: true), kind: .music),
                           "\(key) draws nothing in mini, so it must not be offered")
        }
    }

    /// Which players to watch still means something in mini: the chip shows
    /// whichever source is playing, so narrowing the sources narrows what it
    /// can show.
    func testTheSourceOptionsApplyInMiniToo() {
        for key in ["spotify", "apple", "netease", "qqmusic", "xiaoyuzhou", "browsers", "autoSwitch"] {
            XCTAssertTrue(WidgetCatalog.applies(key, to: music(mini: true), kind: .music), key)
        }
    }

    /// Every option that is conditional at all, so adding a rule means
    /// coming here and saying so.
    ///
    /// The loop below uses a default config, which is the honest limit of
    /// this test: a rule that only hides a control once some non-default
    /// value is set would pass it. Both rules that exist today flip on a
    /// value away from its default, which is why each is also pinned by a
    /// test of its own above.
    private static let conditional: Set<String> = [
        "system.chart",
        "music.previous", "music.next", "music.backward", "music.forward", "music.skip",
        // 固定的来源在面板的来源列表里选，设置页不列。
        "music.pinned",
        "search.engine",
        "weather.city", "weather.cities",
        // 副标题只有“当前”有，天数只有“多日预报”有（WeatherStyle）。
        "weather.caption", "weather.days",
        // 面板的城市列表和显示开关，多城市样式的面板不读。
        "weather.moreCities", "weather.showIndices", "weather.showRain",
        // 水面动效只有液态外观有。
        "progress.liquidMotion",
        // 时钟的子选项只在所属样式下列出（ClockStyles.applies）。
        "clock.clockSize", "clock.clockWeight", "clock.clockDial", "clock.clockCard", "clock.clockFlip",
        // 调休提醒关掉时，提醒提前几天没有意义。
        "lunar.workAlertLead",
        // 黄金白银单位只在列表里有贵金属时有用；只有一只股票时没有可轮播的；
        // 自选股有了分组就不再读原来那串代码。
        "stock.metalUnit", "stock.rotate", "watchlist.metalUnit", "watchlist.symbols",
        // 四格没有周期可选；旧的单个闹钟才有时间和名称；倒计时的预设在面板里改。
        "progress.period", "alarm.time", "alarm.name", "countdown.presets",
        // 世界时钟的城市名跟着城市列表走，设置里只改列表。
        "world.city",
        // 收音机的皮肤在“样式”里选，设置里不单列。
        "radio.skin",
        // 麦克风的静音快捷键在面板里录，设置里不给文字框。
        "microphone.muteKey",
        // 圆环仪表的警戒线只列卡片上有的圆环（默认存储和电池，CPU 和内存没勾时不列）。
        "gauges.cpuAlert", "gauges.memoryAlert", "gauges.storageAlert", "gauges.batteryAlert",
        // Codex 用量的声音四项在设置里自己一组「声音」（CodexSoundSettings），不在通用列表里。
        "ai-usage.soundWaiting", "ai-usage.soundDone", "ai-usage.soundQuota", "ai-usage.tone",
    ]

    func testStockOptionsFollowTheList() {
        let metal = WidgetConfig(["symbols": .list([.string("AAPL"), .string("GC=F")])])
        XCTAssertTrue(WidgetCatalog.applies("metalUnit", to: metal, kind: .stock))
        XCTAssertTrue(WidgetCatalog.applies("rotate", to: metal, kind: .stock))
        XCTAssertFalse(WidgetCatalog.applies("metalUnit", to: WidgetConfig(), kind: .stock))
        XCTAssertFalse(WidgetCatalog.applies("rotate", to: WidgetConfig(), kind: .stock))
        let grouped = WidgetConfig(["groups": .list([.string("避险=GC=F SI=F")])])
        XCTAssertFalse(WidgetCatalog.applies("symbols", to: grouped, kind: .watchlist))
        XCTAssertTrue(WidgetCatalog.applies("metalUnit", to: grouped, kind: .watchlist))
        XCTAssertTrue(WidgetCatalog.applies("symbols", to: WidgetConfig(), kind: .watchlist))
    }

    /// Everything else is unconditional, and a rule added carelessly would
    /// silently hide a working control.
    func testNothingElseIsHiddenByAccident() {
        for kind in WidgetKind.allCases {
            for key in WidgetCatalog.configurableKeys(kind)
            where !Self.conditional.contains("\(kind.rawValue).\(key)") {
                XCTAssertTrue(WidgetCatalog.applies(key, to: WidgetConfig(), kind: kind),
                              "\(kind.rawValue).\(key) should not be conditional")
            }
        }
    }

    /// The catalog's own variant list has always implied this: it offers
    /// Numbers and Numbers + graph, and no charted ring or bar.
    func testTheVariantsNeverChartARingOrABar() {
        guard let entry = WidgetCatalog.entry(.system) else { return XCTFail("no entry") }
        for variant in entry.variants {
            let layout = variant.overrides["layout"]
            let charted = variant.overrides["chart"] == .bool(true)
            if charted {
                XCTAssertEqual(layout, .string("numbers"),
                               "\(variant.title) charts a layout that cannot draw one")
            }
        }
    }
}
