import Foundation

/// The widget registry. Order drives the order of the library.
///
/// Sizes are natural, unscaled native points, matching the shipped app's
/// catalog. The shelf applies `Geometry.contentScale` on top; the cross-axis
/// extent is always fixed by the shelf (62pt tall on a bottom shelf, 76pt wide
/// on a side one), so in practice only the long axis here varies.
public enum WidgetCatalog {

    public struct Entry: Sendable {
        public var kind: WidgetKind
        public var name: String
        public var category: WidgetCategory
        public var defaults: WidgetConfig
        /// Library cards beyond the default one: (title, config overrides).
        public var variants: [(title: String, overrides: [String: WidgetConfig.Value])]
        /// Whether this kind can collapse to a narrow tile.
        public var supportsCompact: Bool
        /// Whether the library offers this kind.
        ///
        /// It was described as "no permissions, no network", and has never
        /// meant that: Weather needs the network and a location, Stocks needs
        /// the network, Now Playing needs Automation consent, and all three
        /// are listed. What it actually gates is whether a kind has a tile
        /// that renders something honest, so the only kinds excluded are the
        /// ones that would draw the "still to come" placeholder.
        public var selfContained: Bool
    }

    /// 赞助者专属表盘, unlocked from the sponsor window like the shelf colours.
    public static let supporterClockLayouts: Set<String> = ["neon", "nixie", "lcd", "minimal"]

    /// 赞助者专属角色 for 喝水: every character but the red panda.
    public static let supporterWaterCharacters: Set<String> =
        Set(WaterCharacter.allCases.filter(\.isSupporterOnly).map(\.rawValue))

    /// Whether a variant's overrides (or one option's value) pick a
    /// supporter-only clock face or 喝水 character.
    public static func isSupporterOnly(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        if case .string(let layout) = overrides["layout"], supporterClockLayouts.contains(layout) { return true }
        if case .string(let character) = overrides["character"], supporterWaterCharacters.contains(character) { return true }
        if case .string(let layout) = overrides["layout"], WifiRingStyle.from(layout: layout)?.isSupporterOnly == true { return true }
        return false
    }

    /// 网络活动's four Wi-Fi rings, one variant each.
    private static let wifiVariants: [(title: String, overrides: [String: WidgetConfig.Value])] =
        WifiRingStyle.allCases.map { (title: "Wi-Fi \($0.title)", overrides: ["layout": .string($0.rawValue)]) }

    private static func c(_ pairs: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(pairs) }

    public static let entries: [Entry] = [
        Entry(kind: .clock, name: "时钟", category: .clocks,
              defaults: c(["layout": .string("standard"), "seconds": .bool(true)]),
              variants: [("标准", ["layout": .string("standard")]),
                         ("模拟表盘", ["layout": .string("analog")]),
                         ("翻页", ["layout": .string("flip")]),
                         ("像素", ["layout": .string("pixel")]),
                         ("大号数字", ["layout": .string("digital")]),
                         ("秒圈", ["layout": .string("ring")]),
                         ("中文", ["layout": .string("words")]),
                         ("霓虹", ["layout": .string("neon")]),
                         ("实景", ["layout": .string("nixie")]),
                         ("简约", ["layout": .string("lcd")]),
                         ("极简", ["layout": .string("minimal")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .world, name: "世界时钟", category: .clocks,
              defaults: c(["city": .string("伦敦"), "zone": .string("Europe/London")]),
              variants: [], supportsCompact: true, selfContained: true),

        Entry(kind: .stopwatch, name: "秒表", category: .clocks, defaults: c([:]),
              variants: [], supportsCompact: true, selfContained: true),

        Entry(kind: .timer, name: "专注计时", category: .clocks, defaults: c([:]),
              variants: [], supportsCompact: true, selfContained: true),

        Entry(kind: .progress, name: "时间进度", category: .clocks,
              defaults: c(["layout": .string("bars"), "period": .string("year")]),
              variants: [("进度条", ["layout": .string("bars")]),
                         ("圆环", ["layout": .string("ring")]),
                         ("百分比", ["layout": .string("percentage")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .countdown, name: "倒计时", category: .clocks,
              defaults: c(["duration": .number(300), "name": .string(""), "presets": .list([])]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .alarm, name: "闹钟", category: .clocks,
              defaults: c(["time": .string("14:30"), "name": .string("给小王回电话")]),
              variants: [], supportsCompact: false, selfContained: true),

        // No `showCallButton`: read by nothing. A join-call affordance needs
        // the event's conference URL and a row to put it in, neither of which
        // exists, so the switch promised something that was never built.
        Entry(kind: .calendar, name: "日历", category: .calendar,
              defaults: c(["layout": .string("nextEvent"), "allDay": .bool(true),
                           "calendars": .list([])]),
              variants: [("下一个日程", ["layout": .string("nextEvent")]),
                         ("日期 + 下一个日程", ["layout": .string("dateAndEvent")]),
                         ("日期 + 日程列表", ["layout": .string("agenda")]),
                         ("日期", ["layout": .string("date")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .reminders, name: "提醒事项", category: .reminders,
              defaults: c(["layout": .string("list"), "list": .string("")]),
              variants: [("列表", ["layout": .string("list")]),
                         ("下一个提醒", ["layout": .string("next")]),
                         ("数量", ["layout": .string("count")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .notes, name: "便签", category: .notes,
              defaults: c(["text": .string(""), "color": .string("yellow")]),
              variants: PaperColor.picker.map { ($0.title, ["color": .string($0.rawValue)]) },
              supportsCompact: false, selfContained: true),

        Entry(kind: .music, name: "正在播放", category: .media,
              defaults: c(["mini": .bool(false), "previous": .bool(true), "next": .bool(true),
                           "backward": .bool(false), "forward": .bool(false), "skip": .number(15),
                           "spotify": .bool(true), "apple": .bool(true), "netease": .bool(true), "xiaoyuzhou": .bool(true),
                           // Falls back to video playing in a scriptable
                           // browser tab when no native player has anything.
                           "browsers": .bool(true)]),
              variants: [("完整", ["mini": .bool(false)]), ("迷你", ["mini": .bool(true)])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .battery, name: "电池", category: .system,
              defaults: c(["layout": .string("status"),
                           "devices": .list([.string("mac")])]),
              variants: [("状态", ["layout": .string("status")]),
                         ("百分比圆环", ["layout": .string("gauge")]),
                         ("仅图标", ["layout": .string("icon")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .system, name: "系统活动", category: .system,
              // No chart by default: the shipped design is clean numbers with
              // a coloured dot, and a sparkline behind them crowds a 62pt
              // strip. Offered as its own variant instead.
              defaults: c(["layout": .string("numbers"), "chart": .bool(false),
                           "metrics": .list([.string("cpu"), .string("memory")])]),
              variants: [("数字", ["layout": .string("numbers"), "chart": .bool(false)]),
                         ("数字 + 图表", ["layout": .string("numbers"), "chart": .bool(true)]),
                         ("圆环", ["layout": .string("rings")]),
                         ("条形", ["layout": .string("bars")])],
              supportsCompact: true, selfContained: true),

        // No `popupChart`: it was read by nothing, and the detail panel it
        // presumably meant now exists and always draws its history.
        // The Wi-Fi rings share the card: same shelf slot, a different
        // reading of the same link. 经典 is free, the other three are
        // 赞助者专属 appearances.
        Entry(kind: .network, name: "网络活动", category: .system,
              defaults: c(["layout": .string("speed"), "display": .string("both"), "chart": .bool(false)]),
              variants: [("仅数字", ["layout": .string("speed"), "chart": .bool(false)]),
                         ("带图表", ["layout": .string("speed"), "chart": .bool(true)])]
                + wifiVariants,
              supportsCompact: true, selfContained: true),

        Entry(kind: .shortcut, name: "快捷指令", category: .system,
              defaults: c(["name": .string("")]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .airdrop, name: "隔空投送", category: .system, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // `period`, `metric`, `reference` and `style` were offered here and
        // read by nothing: the service fetches a fixed intraday range,
        // DitherChart has no reference line and no styles, and no reader ever
        // asked for a metric. Every one of them persisted and changed nothing.
        // They come back with the code that honours them, not before.
        Entry(kind: .stock, name: "股票", category: .stocks,
              defaults: c(["symbol": .string("AAPL"),
                           "symbols": .list([.string("AAPL")]),
                           "chart": .bool(true)]),
              variants: [], supportsCompact: true, selfContained: true),

        // Prices from CoinGecko's free API, at most every five minutes, the
        // last good table cached; see CryptoMarket and CryptoService.
        Entry(kind: .crypto, name: "加密货币行情", category: .stocks,
              defaults: c(["coins": .list(CryptoMarket.defaultCoins.map { .string($0) }),
                           "currency": .string("cny"), "colors": .string(ChangeColors.redUp.rawValue),
                           "chart": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // No `chart` here, unlike Stock: this tile is a list of rows and has
        // never drawn one, so the switch had nothing to switch.
        Entry(kind: .watchlist, name: "自选股", category: .stocks,
              defaults: c(["symbols": .list([.string("AAPL"), .string("MSFT"), .string("NVDA")])]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .weather, name: "天气", category: .weather,
              // Empty city: use wherever the user actually is. "Oslo" is the
              // city in the reference screenshots, not a sane default.
              // `cities` is only read by the multi-city layout, which shows
              // those places (at most three) and ignores `city`; see
              // WeatherLayout.cities.
              defaults: c(["layout": .string("current"), "fahrenheit": .bool(false),
                           "city": .string(""),
                           "cities": .list(WeatherLayout.defaultCities.map { .string($0) })]),
              variants: [("当前", ["layout": .string("current")]),
                         ("天气状况", ["layout": .string("conditions")]),
                         ("逐小时预报", ["layout": .string("hourly")]),
                         ("风与日出日落", ["layout": .string("sky")]),
                         ("未来 7 天", ["layout": .string("week")]),
                         ("未来 10 天", ["layout": .string("tenDays")]),
                         ("多城市", ["layout": .string("cities")])],
              supportsCompact: true, selfContained: true),

        // Empty folder: ~/Pictures. Chosen in the panel with an open panel;
        // the Settings field is there for anyone who would rather paste.
        Entry(kind: .photos, name: "相册", category: .media,
              defaults: c(["layout": .string("standard"), "folder": .string(""),
                           "interval": .number(30), "shuffle": .bool(false)]),
              variants: [("标准", ["layout": .string("standard")]),
                         ("宽幅", ["layout": .string("wide")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .screenshots, name: "最近截图", category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .downloads, name: "下载", category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // The held paths live under `files`, which is deliberately not a
        // default: it is the shelf's contents, not a setting.
        Entry(kind: .fileShelf, name: "文件暂存", category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Starred texts live under `pins`, contents rather than a setting.
        Entry(kind: .clipboard, name: "剪贴板", category: .tools, defaults: c(["pasteOnClick": .bool(false)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Recent colours live under `recent`, not a default, for the same
        // reason as the file shelf's paths.
        Entry(kind: .colorPicker, name: "取色器", category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Category, units and value are edited in the panel, where the unit
        // menus can follow the category; see ConverterState.
        Entry(kind: .converter, name: "单位换算", category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .capture, name: "截图工具", category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .emoji, name: "表情符号", category: .tools,
              defaults: c(["emoji": .list(["😂", "✨", "✅", "🔥", "🥹", "🙏", "💡", "🚀", "❤️"]
                                            .map { .string($0) })]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .search, name: "搜索", category: .tools,
              defaults: c(["layout": .string("web"), "engine": .string("bing")]),
              variants: [("网页搜索", ["layout": .string("web")]),
                         ("查找文件", ["layout": .string("files")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .volume, name: "音量", category: .media, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Which switches, in order; see QuickToggle.
        Entry(kind: .toggles, name: "快速开关", category: .system,
              defaults: c([QuickToggle.key: .list(QuickToggle.defaults.map { .string($0.rawValue) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // Empty folder: ~/Pictures, like the photo frame. Chosen in the panel.
        Entry(kind: .wallpaper, name: "壁纸切换", category: .media,
              defaults: c(["folder": .string(""), "allScreens": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // What Command-Tab lists: the regular apps that are open.
        Entry(kind: .appSwitcher, name: "应用切换器", category: .system, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Each link is "标题 网址" or just the address; see Bookmark.
        Entry(kind: .bookmarks, name: "书签", category: .tools,
              defaults: c(["links": .list(["GitHub https://github.com/hanson-zz/docket-zh",
                                              "必应 https://cn.bing.com",
                                              "哔哩哔哩 https://www.bilibili.com",
                                              "知乎 https://www.zhihu.com"].map { .string($0) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // Empty folder: ~/Downloads. Chosen in the panel.
        Entry(kind: .recorder, name: "录音", category: .media,
              defaults: c(["folder": .string("")]),
              variants: [], supportsCompact: false, selfContained: true),

        // Read from Mail over AppleScript, and only while Mail is open.
        Entry(kind: .mail, name: "邮件", category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // The last sum is kept under `expression`, written by the panel.
        Entry(kind: .calculator, name: "计算器", category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Apple's on-device Translation: free, no key, nothing leaves the Mac.
        // The languages and the last translations (`source`, `target`,
        // `history`) are kept by the panel; see Translate.
        Entry(kind: .translate, name: "翻译", category: .tools,
              defaults: c(["clickAction": .string("panel"), "autoDirection": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Rates from open.er-api.com, cached for offline use; see
        // CurrencyService. The amount is typed in the panel.
        Entry(kind: .currency, name: "汇率换算", category: .tools,
              defaults: c(["from": .string("USD"), "to": .string("CNY"), "amount": .number(100)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Public numbers need no token; one in the keychain adds notifications
        // and a higher request limit. Up to eight repositories under `repos`
        // (an old `repo` is moved there on load, see GitHubWatch); what was
        // last seen of each is kept by GitHubService, not in the config.
        Entry(kind: .github, name: "GitHub", category: .tools,
              defaults: c(["repos": .list([.string(GitHubWatch.defaultRepo)]),
                           "notify": .bool(false),
                           "interval": .string("\(GitHubWatch.defaultInterval)")]),
              variants: [], supportsCompact: false, selfContained: true),

        // Whether any app is using the default input device, from Core Audio.
        // Reading the state needs no microphone permission.
        Entry(kind: .microphone, name: "麦克风", category: .system, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Storage from URLResourceValues, battery from the power-source API.
        // CPU temperature is left out: macOS has no public API for it.
        Entry(kind: .gauges, name: "圆环仪表", category: .system,
              defaults: c(["rings": .list([.string("storage"), .string("battery")])]),
              variants: [], supportsCompact: false, selfContained: true),

        // A ring that fills between breaks, with active hours, a
        // notification and a count of today's breaks.
        Entry(kind: .posture, name: "久坐提醒", category: .reminders,
              defaults: c(["duration": .number(1800), "start": .string("09:00"),
                           "end": .string("18:00"), "notify": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // A list of its own under `items`, never the system's Reminders.
        Entry(kind: .todo, name: "快速待办", category: .reminders,
              defaults: c(["showDone": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Habits of its own under `habits`, with each day they were done;
        // see HabitTracker.
        Entry(kind: .habit, name: "习惯打卡", category: .reminders,
              defaults: c(["showStreak": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Dates of its own under `events`, counted down or up, by the solar
        // or the lunar calendar; the single card's event is `pinned`, chosen
        // in the panel. See Anniversary.
        Entry(kind: .anniversary, name: "纪念日", category: .reminders,
              defaults: c(["layout": .string("single"), "showRing": .bool(true)]),
              variants: [("单个", ["layout": .string("single")]),
                         ("多个", ["layout": .string("multi")])],
              supportsCompact: false, selfContained: true),

        // Today's glasses under `days`, with the chosen `character` (the red
        // panda by default) filling up toward the goal; reminders between
        // `start` and `end`. See WaterIntake.
        Entry(kind: .water, name: "喝水", category: .reminders,
              defaults: c(["layout": .string("character"), "goal": .number(2000),
                           "cupSize": .number(250), "remindEvery": .string("60"),
                           "start": .string("09:00"), "end": .string("21:00"),
                           "unit": .string("ml"), "character": .string("panda")]),
              // The red panda's card names its character, so a 柴犬 config is
              // not also matched by it; the other five are 赞助者专属.
              variants: [("小熊猫", ["layout": .string("character"), "character": .string("panda")]),
                         ("柴犬", ["layout": .string("character"), "character": .string("shiba")]),
                         ("橘猫", ["layout": .string("character"), "character": .string("cat")]),
                         ("企鹅", ["layout": .string("character"), "character": .string("penguin")]),
                         ("水獭", ["layout": .string("character"), "character": .string("otter")]),
                         ("章鱼", ["layout": .string("character"), "character": .string("octopus")]),
                         ("圆环", ["layout": .string("ring")])],
              supportsCompact: false, selfContained: true),

        // A pet of its own: four needs kept with the time they were true, so
        // they run down without anything running (see VirtualPet), and the
        // same six characters as 喝水 under `character`, the red panda free
        // and the other five 赞助者专属.
        Entry(kind: .pet, name: "电子宠物", category: .reminders,
              defaults: c(["character": .string("panda")]),
              variants: [("小熊猫", ["character": .string("panda")]),
                         ("柴犬", ["character": .string("shiba")]),
                         ("橘猫", ["character": .string("cat")]),
                         ("企鹅", ["character": .string("penguin")]),
                         ("水獭", ["character": .string("otter")]),
                         ("章鱼", ["character": .string("octopus")])],
              supportsCompact: false, selfContained: true),

        // This week from EventKit, Monday first; see WeekAgenda. Same
        // options as the Calendar widget, which reads the same store.
        Entry(kind: .week, name: "一周日程", category: .calendar,
              defaults: c(["allDay": .bool(true), "calendars": .list([])]),
              variants: [], supportsCompact: false, selfContained: true),

        // Lunar date, solar terms and the official holidays; see ChineseCalendar.
        Entry(kind: .lunar, name: "农历与假期", category: .calendar,
              defaults: c(["showTerm": .bool(true), "workAlert": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // The Trash's size, a drop target, and flies; see TrashFlies.
        Entry(kind: .trash, name: "废纸篓", category: .files,
              defaults: c(["flies": .bool(true), "threshold": .string(TrashFlies.defaultThreshold)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Synthesised noise, mixed live; see AmbientSynth and AmbientPlayer.
        Entry(kind: .ambient, name: "环境音", category: .media,
              defaults: c(["sounds": .list([.string("rain")]), "volume": .number(50)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Internet radio through one shared AVPlayer; favourites live under
        // `stations` like the to-do list's items, see RadioDial and RadioPlayer.
        Entry(kind: .radio, name: "收音机", category: .media,
              defaults: c(["volume": .number(60)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Each playing app's own volume, through Core Audio process taps; see
        // AppVolume and AppVolumeService. Per-app choices are kept by the
        // service, by bundle identifier, not in the widget's config.
        Entry(kind: .appVolume, name: "应用音量", category: .media, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Codex's own rate limits, read with the sign-in Codex keeps in
        // ~/.codex, and what Codex is doing from its newest session log.
        Entry(kind: .aiUsage, name: "Codex 用量", category: .system,
              defaults: c(["show": .string("used"), "notify": .bool(true), "alertAt": .number(80),
                           "notifyDone": .bool(true), "extras": .bool(false)]),
              variants: [], supportsCompact: false, selfContained: true),
    ]

    private static let byKind: [WidgetKind: Entry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.kind, $0) }
    )

    public static func entry(_ kind: WidgetKind) -> Entry? { byKind[kind] }

    /// The colour a widget's detail panel is tinted with.
    ///
    /// The reference shelf tints an open panel toward whatever the widget is
    /// *about* - Stripe teal, a sticky note its own paper, activity the
    /// magenta of its CPU ring - while readouts with no colour of their own
    /// stay neutral. A tint on everything would be noise; a tint on nothing
    /// makes eight identical panels.
    public static func accentHex(_ kind: WidgetKind) -> String? {
        switch kind {
        case .stripe: PaletteColor.teal.hex
        case .paddle, .shopify: PaletteColor.yellow.hex
        case .notes: PaletteColor.yellow.hex
        case .calendar, .reminders: PaletteColor.orange.hex
        case .system: MetricColor.cpu
        case .network: MetricColor.netUpload
        case .stock, .watchlist: PaletteColor.green.hex
        case .aiUsage: PaletteColor.indigo.hex
        case .posture: PaletteColor.green.hex
        case .todo: PaletteColor.orange.hex
        case .ambient: PaletteColor.teal.hex
        case .lunar: PaletteColor.red.hex
        case .trash: PaletteColor.green.hex
        case .habit: PaletteColor.green.hex
        case .week: PaletteColor.orange.hex
        case .crypto: PaletteColor.yellow.hex
        case .appVolume: PaletteColor.indigo.hex
        case .radio: PaletteColor.orange.hex
        case .anniversary: PaletteColor.pink.hex
        case .water: PaletteColor.blue.hex
        case .pet: ShelfColor.redPanda.hex
        // Neutral: a clock, a battery or a player is not "about" a colour.
        case .clock, .world, .stopwatch, .timer, .progress, .countdown,
             .alarm, .music, .battery, .shortcut, .airdrop, .weather:
            nil
        // A photo or a file is its own colour; a tint behind it competes.
        case .photos, .screenshots, .downloads, .fileShelf, .clipboard,
             .wallpaper,
             .appSwitcher,
             .bookmarks,
             .recorder,
             .mail,
             .calculator,
             .translate,
             .currency,
             .github,
             .microphone, .gauges,
             .colorPicker, .converter, .capture, .emoji, .search, .volume, .toggles:
            nil
        }
    }

    /// The keys a widget's settings UI should offer.
    ///
    /// `layout` is excluded: the style picker owns it, and listing it as a
    /// plain text field alongside that picker let the two disagree.
    public static func configurableKeys(_ kind: WidgetKind) -> [String] {
        guard let entry = entry(kind) else { return [] }
        return entry.defaults.values.keys.filter { $0 != "layout" }.sorted()
    }

    /// Whether an option means anything given the rest of the configuration.
    ///
    /// Some options only apply to one layout. System Activity's chart is
    /// drawn behind its numbers and there is nowhere for it to go behind
    /// rings or bars, so the switch sat there accepting changes and doing
    /// nothing in two of the four layouts, and switching to one of them did
    /// not clear it either: a widget could be left storing chart true while
    /// showing bars, and going back to numbers brought a graph nobody asked
    /// for.
    ///
    /// The catalog already knew this. Its variants offer "Numbers" and
    /// "Numbers + graph" and no charted ring or bar, so this states what the
    /// variant list has always implied.
    public static func applies(_ key: String, to config: WidgetConfig,
                               kind: WidgetKind) -> Bool {
        switch (kind, key) {
        case (.system, "chart"):
            config.string("layout", default: "numbers") == "numbers"
        // Mini is a 64pt chip: artwork and one glyph, which is play and
        // pause. Skipping, seeking and the seek distance are drawn by the
        // wide layout only, so in mini these were five controls that
        // accepted a change and produced none. Offering an option that does
        // nothing is the same defect as offering one nothing reads.
        case (.music, "previous"), (.music, "next"), (.music, "backward"),
             (.music, "forward"), (.music, "skip"):
            !config.bool("mini")
        // Finding files asks Spotlight, not a search engine.
        case (.search, "engine"):
            config.string("layout", default: "web") == "web"
        // The multi-city card shows its own list of places and no other;
        // every other layout reads the one city and never the list.
        case (.weather, "cities"):
            config.string("layout", default: "current") == "cities"
        case (.weather, "city"):
            config.string("layout", default: "current") != "cities"
        // The ring sits beside the one big number; three columns have no
        // room for it and never draw one.
        case (.anniversary, "showRing"):
            config.string("layout", default: "single") == "single"
        // The Wi-Fi rings read the signal, not throughput, so the direction
        // and the chart mean nothing there.
        case (.network, "display"), (.network, "chart"):
            WifiRingStyle.from(layout: config.string("layout", default: "speed")) == nil
        default:
            true
        }
    }

    /// "showRunningApps" -> "Show Running Apps".
    public static func optionLabel(_ key: String) -> String {
        var words = ""
        for character in key {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Which variant a config currently matches, by title.
    ///
    /// Every override must match, not just `layout`: "Numbers" and
    /// "Numbers + graph" share a layout and differ only by `chart`, so
    /// matching on layout alone made them indistinguishable - the style
    /// picker could neither tell them apart nor show the right one.
    public static func variantTitle(matching config: WidgetConfig,
                                    kind: WidgetKind) -> String? {
        guard let entry = entry(kind) else { return nil }
        return entry.variants.first { variant in
            variant.overrides.allSatisfy { config.values[$0.key] == $0.value }
        }?.title
    }

    /// Where a widget sends you when its card is clicked.
    ///
    /// Every tile in the Dock opens something; a widget that reports a number
    /// and does nothing when you click it reads as broken. A tile's own
    /// controls may only take the click where they actually sit - a gesture
    /// spread over the whole card beats this one everywhere and leaves the
    /// card dead, which is exactly how every widget panel came to be
    /// unreachable.
    public static func openTarget(_ kind: WidgetKind) -> WidgetTarget? {
        switch kind {
        case .clock, .world, .alarm, .timer, .stopwatch, .countdown:
            .app(bundleID: "com.apple.clock")
        case .calendar, .week:
            .app(bundleID: "com.apple.iCal")
        case .reminders:
            .app(bundleID: "com.apple.reminders")
        case .notes:
            .app(bundleID: "com.apple.Notes")
        case .weather:
            .app(bundleID: "com.apple.weather")
        case .stock, .watchlist:
            .app(bundleID: "com.apple.stocks")
        // CPU, memory and network all report what Activity Monitor owns.
        case .system, .network:
            .app(bundleID: "com.apple.ActivityMonitor")
        case .battery:
            .settings("com.apple.Battery-Settings.extension")
        case .airdrop:
            .app(bundleID: "com.apple.finder")
        case .shortcut:
            .app(bundleID: "com.apple.shortcuts")
        // Each has a panel, so these are only the fallback: the files are
        // Finder's, and a colour off the screen is Digital Color Meter's.
        case .photos, .screenshots, .downloads, .fileShelf:
            .app(bundleID: "com.apple.finder")
        case .colorPicker:
            .app(bundleID: "com.apple.DigitalColorMeter")
        // The card around the three buttons opens the system's own
        // Screenshot app, where recording and the timer are.
        case .capture:
            .app(bundleID: "com.apple.screenshot.launcher")
        case .volume:
            .settings("com.apple.Sound-Settings.extension")
        case .toggles:
            .settings("com.apple.ControlCenter-Settings.extension")
        case .mail:
            .app(bundleID: "com.apple.mail")
        // Both have panels; these are where the card goes without one.
        case .wallpaper:
            .settings("com.apple.Wallpaper-Settings.extension")
        case .recorder:
            .app(bundleID: "com.apple.VoiceMemos")
        // Where the input device is chosen.
        case .microphone:
            .settings("com.apple.Sound-Settings.extension")
        case .gauges:
            .settings("com.apple.settings.Storage")
        // No honest destination: `music` would have to guess between Music and
        // Spotify while its own transport already owns the card, `progress`
        // and `water` are self-contained, and the business tiles are for
        // dashboards we cannot address.
        case .music, .progress, .stripe, .paddle, .shopify,
             .clipboard, .converter, .emoji, .appSwitcher, .bookmarks, .calculator, .currency, .github, .search, .posture,
             .aiUsage, .todo, .ambient, .lunar, .trash, .habit, .crypto, .appVolume, .radio,
             .anniversary, .water, .translate, .pet:
            nil
        }
    }

    public static var shippable: [Entry] { entries.filter(\.selfContained) }

    /// Fresh instance with a deep copy of the catalog defaults, so array
    /// defaults are never shared between two widgets of the same kind.
    public static func make(_ kind: WidgetKind, overrides: [String: WidgetConfig.Value] = [:]) -> WidgetInstance? {
        guard let entry = byKind[kind] else { return nil }
        var config = entry.defaults
        for (k, v) in overrides { config.set(k, v) }
        return WidgetInstance(kind: kind, expanded: true, config: config)
    }

    // MARK: Sizing

    /// Natural size before the shelf's scale is applied.
    ///
    /// `expanded == false` collapses to the compact width, which only kinds
    /// with `supportsCompact` can request.
    public static func naturalSize(_ instance: WidgetInstance) -> CGSize {
        let cfg = instance.config
        let entry = byKind[instance.kind]
        let expanded = instance.expanded || !(entry?.supportsCompact ?? false)
        guard expanded else { return CGSize(width: compactWidth(instance.kind), height: 62) }

        switch instance.kind {
        case .clock, .world: return CGSize(width: 168, height: 132)
        case .stopwatch: return CGSize(width: 168, height: 80)
        case .timer: return CGSize(width: 168, height: 124)
        case .progress:
            switch cfg.string("layout", default: "bars") {
            case "ring": return CGSize(width: 148, height: 76)
            case "percentage": return CGSize(width: 112, height: 62)
            default: return CGSize(width: 176, height: 78)
            }
        case .countdown: return CGSize(width: 140, height: 72)
        case .alarm: return CGSize(width: 168, height: 124)
        case .calendar:
            switch cfg.string("layout", default: "nextEvent") {
            case "date": return CGSize(width: 88, height: 76)
            case "dateAndEvent": return CGSize(width: 244, height: 132)
            case "agenda": return CGSize(width: 300, height: 132)
            default: return CGSize(width: 168, height: 132)
            }
        case .reminders:
            switch cfg.string("layout", default: "list") {
            case "next": return CGSize(width: 180, height: 132)
            case "count": return CGSize(width: 88, height: 76)
            default: return CGSize(width: 220, height: 132)
            }
        case .notes: return CGSize(width: 160, height: 100)
        case .music:
            return cfg.bool("mini") ? CGSize(width: 64, height: 62) : CGSize(width: 264, height: 132)
        case .battery:
            let devices = max(1, cfg.strings("devices", default: ["mac"]).count)
            if devices == 1, cfg.string("layout", default: "status") == "status" {
                return CGSize(width: 168, height: 132)
            }
            return CGSize(width: Double(devices * 44 + (devices - 1) * 8 + 20),
                          height: devices > 2 ? 116 : 62)
        case .system:
            // With the catalog's default, like every other reader of this key.
            // Without it a widget carrying no stored `metrics` measured as one
            // column and drew two, so the tile was sized too narrow for its
            // own contents.
            let metrics = max(1, cfg.strings("metrics", default: ["cpu", "memory"]).count)
            let layout = cfg.string("layout", default: "numbers")
            if layout == "bars" { return CGSize(width: 168, height: 62) }
            let rings = layout == "rings"
            // The per-metric widths are content widths; the tile also has to
            // pay for WidgetSurface's horizontal inset, or a two-metric tile
            // truncates "Memory" to "Memo…". 168pt for two metrics matches the
            // shipped render exactly.
            // 20pt for WidgetSurface's horizontal inset plus 8pt of breathing
            // room. Hardcoded rather than read from WidgetStyle so the catalog
            // stays free of SwiftUI and keeps compiling into the test target.
            let inset = 28.0
            return CGSize(width: Double(metrics * (rings ? 66 : 70)) + inset,
                          height: Double(metrics * (rings ? 60 : 46) + 16))
        case .network:
            if WifiRingStyle.from(layout: cfg.string("layout", default: "speed")) != nil {
                return CGSize(width: 124, height: 62)
            }
            return cfg.bool("chart") ? CGSize(width: 160, height: 84) : CGSize(width: 100, height: 62)
        case .aiUsage: return CGSize(width: 244, height: 62)
        case .shortcut: return CGSize(width: 140, height: 76)
        case .airdrop: return CGSize(width: 100, height: 76)
        case .weather:
            switch cfg.string("layout", default: "current") {
            case "hourly": return CGSize(width: 216, height: 132)
            // Wind and the next sun time are a longer caption than a city.
            case "sky": return CGSize(width: 196, height: 132)
            // A row of day columns, each as wide as "24° 16°".
            case "week", "tenDays":
                return CGSize(width: WeatherLayout.forecastWidth(layout: cfg.string("layout")), height: 132)
            case "cities":
                let count = WeatherLayout.cities(cfg.strings("cities", default: WeatherLayout.defaultCities)).count
                return CGSize(width: WeatherLayout.citiesWidth(count: count), height: 132)
            default: return CGSize(width: 148, height: 132)
            }
        case .stripe, .paddle:
            return cfg.bool("chart", default: true)
                ? CGSize(width: 200, height: 144) : CGSize(width: 148, height: 108)
        case .shopify: return CGSize(width: 200, height: 132)
        case .stock: return CGSize(width: 192, height: 132)
        case .watchlist: return CGSize(width: 276, height: 176)
        case .photos:
            return cfg.string("layout", default: "standard") == "wide"
                ? CGSize(width: 176, height: 62) : CGSize(width: 112, height: 62)
        case .screenshots: return CGSize(width: 132, height: 62)
        case .downloads: return CGSize(width: 176, height: 62)
        case .fileShelf: return CGSize(width: 148, height: 62)
        case .clipboard: return CGSize(width: 196, height: 62)
        case .colorPicker: return CGSize(width: 136, height: 62)
        case .converter: return CGSize(width: 188, height: 62)
        case .capture: return CGSize(width: 136, height: 62)
        case .emoji: return CGSize(width: 160, height: 62)
        case .search: return CGSize(width: 220, height: 62)
        case .volume: return CGSize(width: 200, height: 62)
        case .toggles: return CGSize(width: QuickToggle.length(count: QuickToggle.chosen(cfg).count), height: 62)
        case .github: return CGSize(width: 196, height: 62)
        case .currency: return CGSize(width: 196, height: 62)
        case .calculator: return CGSize(width: 168, height: 62)
        case .translate: return CGSize(width: 196, height: 62)
        case .mail: return CGSize(width: 160, height: 62)
        case .recorder: return CGSize(width: 168, height: 62)
        case .bookmarks: return CGSize(width: Bookmark.tileWidth(count: cfg.strings("links").count), height: 62)
        case .appSwitcher: return CGSize(width: 220, height: 62)
        case .wallpaper: return CGSize(width: 176, height: 62)
        case .microphone: return CGSize(width: 184, height: 62)
        case .gauges:
            return CGSize(width: GaugeReading.tileWidth(rings: GaugeReading.rings(cfg).count), height: 62)
        case .posture: return CGSize(width: 168, height: 124)
        case .todo: return CGSize(width: 204, height: 62)
        case .ambient: return CGSize(width: 188, height: 62)
        case .lunar: return CGSize(width: 196, height: 62)
        case .trash: return CGSize(width: 176, height: 62)
        case .habit: return CGSize(width: 196, height: 62)
        case .week: return CGSize(width: 216, height: 62)
        case .crypto:
            return CGSize(width: CryptoMarket.tileWidth(count: CryptoMarket.coinIDs(cfg).count), height: 62)
        case .appVolume: return CGSize(width: 196, height: 62)
        case .radio: return CGSize(width: 212, height: 62)
        case .anniversary:
            return CGSize(width: Anniversary.tileWidth(layout: cfg.string("layout", default: "single"),
                                                       count: Anniversary.events(cfg).count), height: 62)
        case .water:
            return CGSize(width: WaterIntake.tileWidth(layout: cfg.string("layout", default: "character")), height: 62)
        case .pet: return CGSize(width: 196, height: 62)
        }
    }

    private static func compactWidth(_ kind: WidgetKind) -> Double {
        switch kind {
        case .stopwatch: 120
        case .network: 110
        default: 88
        }
    }

    /// Width of a side shelf's column. Matches the icon column, so a left or
    /// right shelf stays a narrow strip rather than a 168pt slab.
    public static let columnWidth: Double = 76

    /// The size a widget's content is authored at, before the shelf scales it.
    ///
    /// Orientation changes the shape of a widget, not just its scale. A bottom
    /// shelf gives a widget a wide 62pt strip; a side shelf gives it a narrow
    /// 76pt column, and each widget draws a genuinely different, stacked
    /// layout for it. Reusing the wide layout in a column either crops it into
    /// nonsense or forces the whole shelf absurdly wide.
    public static func contentSize(_ instance: WidgetInstance, position: DockPosition) -> CGSize {
        if position.isVertical {
            return CGSize(width: columnWidth, height: verticalHeight(instance))
        }
        let canCompact = byKind[instance.kind]?.supportsCompact ?? false
        let width = (canCompact && !instance.expanded)
            ? compactWidth(instance.kind)
            : naturalSize(instance).width
        // Shorter than the 62pt icon tile on purpose: the cards read as
        // oversized when they match the row exactly. The plate is pinned by
        // the icons (Geometry.iconGeometry), so this only shrinks the cards.
        return CGSize(width: width, height: 58)
    }

    /// Long-axis extent of a widget's stacked, column layout.
    public static func verticalHeight(_ instance: WidgetInstance) -> Double {
        let cfg = instance.config
        switch instance.kind {
        case .clock, .world: return 76
        case .stopwatch, .countdown: return 62
        case .timer: return 92
        case .alarm: return 76
        case .posture: return 88
        case .microphone: return 88
        case .gauges: return Double(GaugeReading.rings(cfg).count * 66)
        case .aiUsage: return 132
        case .notes: return 96
        case .airdrop: return 76
        case .progress:
            return cfg.string("layout", default: "bars") == "percentage" ? 58 : 80
        case .battery:
            let devices = max(1, cfg.strings("devices", default: ["mac"]).count)
            return Double(devices * 62)
        case .system:
            let metrics = max(1, cfg.strings("metrics", default: ["cpu", "memory"]).count)
            // Each metric gets a row: sparkline, value, label.
            return Double(metrics * 54 + 8)
        case .network:
            if WifiRingStyle.from(layout: cfg.string("layout", default: "speed")) != nil { return 76 }
            return cfg.string("display", default: "both") == "both" ? 76 : 46
        case .photos:
            return cfg.string("layout", default: "standard") == "wide" ? 112 : 76
        case .colorPicker, .converter:
            return 84
        case .capture:
            return 112
        case .toggles:
            return Double(QuickToggle.chosen(cfg).count * 30 + 8)
        case .currency:
            return 84
        // The badge, the pair and two lines of the last result.
        case .translate:
            return 96
        case .bookmarks:
            return Bookmark.columnHeight(count: cfg.strings("links").count)
        case .appSwitcher:
            return 112
        case .wallpaper:
            return 112
        case .emoji:
            return 132
        case .todo, .ambient, .lunar, .trash, .appVolume, .radio:
            return 112
        case .weather:
            let layout = cfg.string("layout", default: "current")
            switch layout {
            case "week", "tenDays": return WeatherLayout.forecastColumnHeight(layout: layout)
            case "cities":
                let count = WeatherLayout.cities(cfg.strings("cities", default: WeatherLayout.defaultCities)).count
                return WeatherLayout.citiesColumnHeight(count: count)
            default: return 76
            }
        case .week:
            return 112
        case .crypto:
            return CryptoMarket.columnHeight(count: CryptoMarket.coinIDs(cfg).count,
                                             chart: cfg.bool("chart", default: true))
        case .habit:
            return HabitTracker.columnHeight(count: HabitTracker.habits(cfg).count)
        case .anniversary:
            return Anniversary.columnHeight(layout: cfg.string("layout", default: "single"),
                                            count: Anniversary.events(cfg).count)
        case .water:
            return WaterIntake.columnHeight(layout: cfg.string("layout", default: "character"))
        // The character, a line, the bar and the bowl.
        case .pet:
            return 118
        default:
            return 76
        }
    }

    /// Size the shelf actually lays out.
    public static func tileSize(_ instance: WidgetInstance, position: DockPosition, scale: Double) -> CGSize {
        let f = Geometry.contentScale(scale)
        let content = contentSize(instance, position: position)
        return CGSize(width: content.width * f, height: content.height * f)
    }

}
