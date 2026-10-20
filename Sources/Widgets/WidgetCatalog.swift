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

    /// 近期新增的小组件，在添加面板的卡片上标“新”。名单和推荐列表在
    /// `WidgetLibraryGroups` 里，这里只是目录上的入口。
    public static func isNew(_ kind: WidgetKind) -> Bool { WidgetLibraryGroups.isNew(kind) }

    /// Pro 专属表盘（原来的赞助者表盘），仍从“支持码头”窗口解锁，清单在 `ProFeatures`。
    public static let supporterClockLayouts: Set<String> = ProFeatures.proClockLayouts

    /// Pro 专属角色 for 喝水: the penguin, the otter and the octopus. The
    /// shiba and the cat are earned by meeting the goal instead.
    public static let supporterWaterCharacters: Set<String> =
        Set(WaterCharacter.allCases.filter(\.isSupporterOnly).map(\.rawValue))

    /// Whether a variant's overrides (or one option's value) pick a
    /// supporter-unlocked clock face, 喝水 character, Wi-Fi ring or battery
    /// look. These fall back to a free look when locked; the wider Pro list
    /// (whole kinds, 液态, kind-only styles) is in `ProFeatures`.
    public static func isSupporterOnly(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        ProFeatures.isSupporterStyle(overrides)
    }

    /// `isSupporterOnly` 的新名字，意思一样。
    public static func isProLocked(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        isSupporterOnly(overrides)
    }

    /// 网络活动's four Wi-Fi rings, one variant each.
    private static let wifiVariants: [(title: String, overrides: [String: WidgetConfig.Value])] =
        WifiRingStyle.allCases.map { (title: "Wi-Fi \($0.title)", overrides: ["layout": .string($0.rawValue)]) }

    private static func c(_ pairs: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(pairs) }

    public static let entries: [Entry] = [
        // 时钟的样式和子选项都从注册表 `ClockStyles` 来（Core/ClockStyle.swift），
        // 新增样式只改那里和绘制视图，这里不用动。
        Entry(kind: .clock, name: tr("时钟"), category: .time,
              defaults: c(ClockStyles.defaultOptionValues.merging(
                  ["layout": .string(ClockStyles.defaultStyleID), "seconds": .bool(true)]) { _, new in new }),
              variants: ClockStyles.all.map { (title: $0.title, overrides: ["layout": .string($0.id)]) },
              supportsCompact: true, selfContained: true),

        Entry(kind: .world, name: tr("世界时钟"), category: .time,
              defaults: c(["city": .string(tr("伦敦")), "zone": .string("Europe/London")]),
              variants: [], supportsCompact: true, selfContained: true),

        Entry(kind: .stopwatch, name: tr("秒表"), category: .time, defaults: c([:]),
              variants: [], supportsCompact: true, selfContained: true),

        // 专注计时没有样式选择，外观（圆环或液态）用 look 键，默认圆环。
        Entry(kind: .timer, name: tr("专注计时"), category: .health,
              defaults: c([LiquidMotion.timerLookKey: .string(LiquidMotion.TimerLook.ring.rawValue)]),
              variants: [], supportsCompact: true, selfContained: true),

        // 默认值里的 layout 仍是进度条：没存 layout 的旧卡片补默认值时保持
        // 原样。新放上去的卡片在 `make` 里换成圆环（推荐默认），所以圆环排第一。
        Entry(kind: .progress, name: tr("时间进度"), category: .time,
              defaults: c([TimeProgress.layoutKey: .string(TimeProgress.legacyLayout),
                           TimeProgress.periodKey: .string("year"),
                           TimeProgress.motionKey: .bool(true)]),
              variants: [(tr("圆环"), ["layout": .string("ring")]),
                         (tr("百分比"), ["layout": .string("percentage")]),
                         (tr("液态"), ["layout": .string(LiquidMotion.layout)]),
                         (tr("进度条"), ["layout": .string("bars")]),
                         // 四格：年、月、周、今天一起看。
                         (tr("四格"), ["layout": .string(TimeProgress.quadLayout)])],
              supportsCompact: true, selfContained: true),

        // 倒计时没有样式选择，数字的外观（普通或折叠翻页）用 look 键，默认普通。
        // 卡片上的三个预设（presets）在面板里改，没设时是 3、5、10 分钟（CountdownRun）。
        Entry(kind: .countdown, name: tr("倒计时"), category: .time,
              defaults: c(["duration": .number(300), "name": .string(""), "presets": .list([]),
                           FoldFlip.countdownLookKey: .string(FoldFlip.CountdownLook.plain.rawValue),
                           CountdownRun.soundKey: .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // 摸鱼时钟：工作日倒数下班，周末祝周末快乐，四个小格是发薪、周五、
        // 下一个节日和今天赚的钱，全部由 SlackerClock 算。背景色、背景图和
        // 字体颜色只在面板里改（background、backgroundImage、textColor），
        // 所以不在这里的默认值里，读的时候用 SlackerClock 的默认。
        Entry(kind: .slacker, name: tr("摸鱼时钟"), category: .time,
              defaults: c([SlackerClock.workdaysKey: .list(SlackerClock.weekdays.map { .string(String($0)) }),
                           SlackerClock.startKey: .string("09:00"),
                           SlackerClock.endKey: .string("18:00"),
                           SlackerClock.holidaysKey: .bool(true),
                           SlackerClock.paydayKey: .number(Double(SlackerClock.defaultPayday)),
                           SlackerClock.incomeKey: .number(SlackerClock.defaultIncome),
                           SlackerClock.itemsKey: .list(SlackerClock.Item.allCases.map { .string($0.rawValue) }),
                           SlackerClock.fontKey: .string(SlackerClock.FontChoice.system.rawValue),
                           SlackerClock.tintKey: .bool(true),
                           SlackerClock.lookKey: .string(SlackerClock.Look.illustrated.rawValue)]),
              variants: [], supportsCompact: false, selfContained: true),

        // 一张卡片多个闹钟，存在 alarms 里（AlarmBook）。time 和 name 是旧的单个
        // 闹钟，没有 alarms 的旧卡片按它们读成一个，新卡片也从它们开始。
        Entry(kind: .alarm, name: tr("闹钟"), category: .time,
              defaults: c(["time": .string("14:30"), "name": .string(tr("给小王回电话")),
                           AlarmBook.soundKey: .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // 日历只管今天和下一个会。「加入」按钮不是开关：日程带会议链接
        // （URL 字段，或地点、备注里的腾讯会议、Zoom、Teams、飞书、Meet）就显示，
        // 没有就不显示，见 MeetingLink。原来的「日期 + 日程列表」换成今日时间线，
        // 放好的卡片读配置时 agenda 自动换成 timeline，见 CalendarDay.migratingLayout。
        Entry(kind: .calendar, name: tr("日历"), category: .time,
              defaults: c(["layout": .string("nextEvent"), "allDay": .bool(true),
                           "calendars": .list([])]),
              variants: [(tr("下一个日程"), ["layout": .string("nextEvent")]),
                         (tr("今日时间线"), ["layout": .string(CalendarDay.timelineLayout)]),
                         (tr("日期"), ["layout": .string("date")]),
                         (tr("日期 + 下一个日程"), ["layout": .string("dateAndEvent")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .reminders, name: tr("提醒事项"), category: .todo,
              defaults: c(["layout": .string("list"), "list": .string("")]),
              variants: [(tr("列表"), ["layout": .string("list")]),
                         (tr("下一个提醒"), ["layout": .string("next")]),
                         // 原来叫“数量”，layout 值不变，已经放好的卡片照旧。
                         (tr("今日概览"), ["layout": .string("count")])],
              supportsCompact: true, selfContained: true),

        Entry(kind: .notes, name: tr("便签"), category: .todo,
              defaults: c(["text": .string(""), "color": .string("yellow")]),
              // 纸色不再当样式列出来：添加面板只放一张便签，颜色在面板和设置里选
              // （免费五种，其余 Pro）。原来按颜色放好的那张本来就把 color 写进了
              // 配置，读出来就是这张纸的颜色，样子不变。
              variants: [],
              supportsCompact: false, selfContained: true),

        Entry(kind: .music, name: tr("正在播放"), category: .media,
              defaults: c(["mini": .bool(false), "previous": .bool(true), "next": .bool(true),
                           "backward": .bool(false), "forward": .bool(false), "skip": .number(15),
                           "spotify": .bool(true), "apple": .bool(true), "netease": .bool(true), "xiaoyuzhou": .bool(true),
                           // QQ 音乐和网易云走同一路：系统「正在播放」加媒体键。
                           "qqmusic": .bool(true),
                           // 谁开始播放就切到谁；关掉后停在面板里选的来源（pinned，设置页不列）。
                           MusicSourceSwitch.autoKey: .bool(true), MusicSourceSwitch.pinnedKey: .string(""),
                           // Falls back to video playing in a scriptable
                           // browser tab when no native player has anything.
                           "browsers": .bool(true)]),
              variants: [(tr("完整"), ["mini": .bool(false)]), (tr("迷你"), ["mini": .bool(true)])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .battery, name: tr("电池"), category: .system,
              defaults: c(["layout": .string("status"),
                           "devices": .list([.string("mac")]),
                           // Connected Bluetooth accessories in the spare
                           // slots and the panel. A widget saved before this
                           // existed reads the same default, so it is on.
                           BatteryShelf.bluetoothKey: .bool(true),
                           // 外观. The catalog default is what a widget saved
                           // before looks existed reads, so it stays 经典;
                           // `make` gives a new widget 液态.
                           BatteryLook.key: .string(BatteryLook.legacyDefault.rawValue)]),
              variants: [// 原来叫“状态”，用户看不懂，改叫“电量”；存的值仍是 status。
                         (tr("电量"), ["layout": .string("status")]),
                         // 原来的“百分比圆环”，画成电池形状后改名；存的值仍是 gauge，Pro 照旧。
                         (tr("电池格"), ["layout": .string("gauge")]),
                         (tr("仅图标"), ["layout": .string("icon")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .system, name: tr("系统活动"), category: .system,
              // No chart by default: the shipped design is clean numbers with
              // a coloured dot, and a sparkline behind them crowds a 62pt
              // strip. 原来单独列成“数字 + 图表”样式，只差一条线，现在并进
              // “数字”，用“显示图表”开关（`chart`，旧卡片本来就存着它）。
              defaults: c(["layout": .string("numbers"), "chart": .bool(false),
                           "metrics": .list([.string("cpu"), .string("memory")])]),
              variants: [(tr("数字"), ["layout": .string("numbers")]),
                         // 原来的“圆环”，改成一格一格的竖条；存的值仍是 rings。
                         (tr("竖条"), ["layout": .string(ShapeMeters.systemSegmentsLayout)]),
                         (tr("条形"), ["layout": .string("bars")]),
                         (tr("液态"), ["layout": .string(LiquidMotion.layout)])],
              supportsCompact: true, selfContained: true),

        // No `popupChart`: it was read by nothing, and the detail panel it
        // presumably meant now exists and always draws its history.
        // The Wi-Fi rings share the card: same shelf slot, a different
        // reading of the same link. 经典 is free, the other three are
        // Pro 专属 appearances.
        Entry(kind: .network, name: tr("网络活动"), category: .system,
              defaults: c(["layout": .string("speed"), "display": .string("both"), "chart": .bool(false)]),
              // “仅数字”和“带图表”并成“网速”，图表用“显示图表”开关（`chart`）。
              variants: [(tr("网速"), ["layout": .string("speed")])]
                + wifiVariants,
              supportsCompact: true, selfContained: true),

        // 一张卡放多个快捷指令（`items`，见 `ShortcutDeck`），在面板里勾选、
        // 排序、改外观，不进设置页，所以不放默认值。旧卡片的单个 `name`
        // 读成列表第一项，面板第一次写列表时删掉。
        Entry(kind: .shortcut, name: tr("快捷指令"), category: .appsAndFolders,
              defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .airdrop, name: tr("隔空投送"), category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // `period`, `metric`, `reference` and `style` were offered here and
        // read by nothing: the service fetches a fixed intraday range,
        // DitherChart has no reference line and no styles, and no reader ever
        // asked for a metric. Every one of them persisted and changed nothing.
        // They come back with the code that honours them, not before.
        // 股票盯一只：分时、昨收、量、到价提醒（`alerts`，`AAPL>237`），
        // 多只时自动轮播（`rotate`）。涨跌颜色和加密货币行情同一个键，默认红涨绿跌；
        // 黄金白银默认按元/克显示（`metalUnit`）。见 StockBoard、PreciousMetal。
        Entry(kind: .stock, name: tr("股票"), category: .stocks,
              defaults: c(["symbol": .string("AAPL"),
                           "symbols": .list([.string("AAPL")]),
                           "chart": .bool(true),
                           "alerts": .list([]),
                           "rotate": .bool(true),
                           "colors": .string(RegionalDefaults.current.colors.rawValue),
                           "metalUnit": .string(RegionalDefaults.current.metalUnit.rawValue)]),
              variants: [], supportsCompact: true, selfContained: true),

        // Prices from CoinGecko's free API, at most every five minutes, the
        // last good table cached; see CryptoMarket and CryptoService.
        Entry(kind: .crypto, name: tr("加密货币行情"), category: .stocks,
              defaults: c(["coins": .list(CryptoMarket.defaultCoins.map { .string($0) }),
                           // 英文界面按地区：美元计价、绿涨红跌，见 RegionalDefaults。
                           "currency": .string(RegionalDefaults.current.cryptoCurrency),
                           "colors": .string(RegionalDefaults.current.colors.rawValue),
                           "chart": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // 自选股管一组：按涨跌幅排序（`sort`）、分组（`groups`，`科技=NVDA TSLA`，
        // 卡片上正在看的分组记在 `group`，不在设置里列）、持仓（`holdings`，填了才算
        // 今日盈亏）。没有 `chart` 开关：每行的迷你走势就是这张卡片本身。
        Entry(kind: .watchlist, name: tr("自选股"), category: .stocks,
              defaults: c(["symbols": .list(StockBoard.defaultWatchlist.map { .string($0) }),
                           "groups": .list([]),
                           "holdings": .list([]),
                           "sort": .string(StockBoard.Order.change.rawValue),
                           "colors": .string(RegionalDefaults.current.colors.rawValue),
                           "metalUnit": .string(RegionalDefaults.current.metalUnit.rawValue)]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .weather, name: tr("天气"), category: .weather,
              // Empty city: use wherever the user actually is. "Oslo" is the
              // city in the reference screenshots, not a sane default.
              // `cities` is only read by the multi-city layout, which shows
              // those places (at most three) and ignores `city`; see
              // WeatherLayout.cities.
              // 七个样式并成四个（见 WeatherStyle）：原来的天气状况、风与日出日落
              // 是“当前”的副标题（caption），未来 7 天、10 天是“多日预报”的天数
              // （days）。放好的旧卡片读配置时自动迁过来，见 WeatherStyle.migrating。
              defaults: c(["layout": .string(WeatherStyle.currentLayout), "fahrenheit": .bool(false),
                           "city": .string(""),
                           "cities": .list(WeatherLayout.defaultCities.map { .string($0) }),
                           WeatherStyle.captionKey: .string(WeatherStyle.Caption.city.rawValue),
                           WeatherStyle.daysKey: .string(String(WeatherStyle.defaultDays)),
                           // 面板改版：城市管理加的第 2 个起（Pro），面板显示的降水提示和生活指数。
                           WeatherPanel.moreCitiesKey: .list([]),
                           WeatherPanel.showIndicesKey: .bool(true),
                           WeatherPanel.showRainKey: .bool(true)]),
              variants: [(tr("当前"), ["layout": .string(WeatherStyle.currentLayout)]),
                         (tr("多日预报"), ["layout": .string(WeatherStyle.forecastLayout)]),
                         (tr("逐小时预报"), ["layout": .string(WeatherStyle.hourlyLayout)]),
                         (tr("多城市"), ["layout": .string(WeatherStyle.citiesLayout)])],
              supportsCompact: true, selfContained: true),

        // Empty folder: ~/Pictures. Chosen in the panel with an open panel;
        // the Settings field is there for anyone who would rather paste.
        Entry(kind: .photos, name: tr("相册"), category: .media,
              defaults: c(["layout": .string("standard"), "folder": .string(""),
                           "interval": .number(30), "shuffle": .bool(false)]),
              // 卡片名突出是相册，和时钟的“标准”分得开；layout 值不变，
              // 已经放好的卡片不受影响。
              variants: [(tr("相册标准"), ["layout": .string("standard")]),
                         (tr("相册宽幅"), ["layout": .string("wide")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .screenshots, name: tr("最近截图"), category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .downloads, name: tr("下载"), category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // The held paths live under `files`, which is deliberately not a
        // default: it is the shelf's contents, not a setting.
        Entry(kind: .fileShelf, name: tr("文件暂存"), category: .files, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Starred texts live under `pins`, contents rather than a setting.
        Entry(kind: .clipboard, name: tr("剪贴板"), category: .ai, defaults: c(["pasteOnClick": .bool(false)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Recent colours live under `recent`, not a default, for the same
        // reason as the file shelf's paths.
        Entry(kind: .colorPicker, name: tr("取色器"), category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .capture, name: tr("截图工具"), category: .tools, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        Entry(kind: .emoji, name: tr("表情符号"), category: .tools,
              defaults: c(["emoji": .list(["😂", "✨", "✅", "🔥", "🥹", "🙏", "💡", "🚀", "❤️"]
                                            .map { .string($0) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // AI 助手：小熊猫是提问入口，后面是勾选的 AI 服务字牌，末尾“＋”添加。
        // 显示哪些、顺序、默认服务和自定义服务（services、customServices、
        // defaultService）在卡片和面板里改，不在这里的默认值里，读的时候
        // 用 AIServices 的默认；所以设置页里没有它们。
        Entry(kind: .aiAssistant, name: tr("AI 助手"), category: .ai,
              defaults: c(["layout": .string(AIServices.wideLayout)]),
              // 卡片名说清是什么：横排是一排 AI 字牌，方块是小熊猫。layout 值不变。
              variants: [(tr("AI 任意门（横版）"), ["layout": .string(AIServices.wideLayout)]),
                         (tr("AI 任意门（竖版）"), ["layout": .string(AIServices.squareLayout)])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .search, name: tr("搜索"), category: .ai,
              defaults: c(["layout": .string("web"), "engine": .string("bing")]),
              variants: [(tr("网页搜索"), ["layout": .string("web")]),
                         (tr("查找文件"), ["layout": .string("files")])],
              supportsCompact: false, selfContained: true),

        Entry(kind: .volume, name: tr("音量"), category: .media, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Which switches, in order; see QuickToggle.
        Entry(kind: .toggles, name: tr("快速开关"), category: .tools,
              defaults: c([QuickToggle.key: .list(QuickToggle.defaults.map { .string($0.rawValue) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // Empty folder: ~/Pictures, like the photo frame. Chosen in the panel.
        Entry(kind: .wallpaper, name: tr("壁纸切换"), category: .system,
              defaults: c(["folder": .string(""), "allScreens": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // What Command-Tab lists: the regular apps that are open.
        Entry(kind: .appSwitcher, name: tr("应用切换器"), category: .appsAndFolders, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Each link is "标题 网址" or just the address; see Bookmark.
        Entry(kind: .bookmarks, name: tr("书签"), category: .ai,
              defaults: c(["links": .list(["GitHub https://github.com/hanson-zz/docket-zh",
                                              tr("必应 https://cn.bing.com"),
                                              tr("哔哩哔哩 https://www.bilibili.com"),
                                              tr("知乎 https://www.zhihu.com")].map { .string($0) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // Empty folder: ~/Downloads. Chosen in the panel.
        Entry(kind: .recorder, name: tr("录音"), category: .media,
              defaults: c(["folder": .string("")]),
              variants: [], supportsCompact: false, selfContained: true),

        // Read from Mail over AppleScript, and only while Mail is open.
        // 面板列最近未读（MailInbox）：每次显示几封、摘要、点开后是否标已读是设置；
        // 关掉的账户 `hiddenAccounts` 和顶部筛选 `filter`（Pro）由面板写，不进设置页。
        Entry(kind: .mail, name: tr("邮件"), category: .ai,
              defaults: c([MailInbox.limitKey: .string("\(MailInbox.defaultLimit)"),
                           MailInbox.markReadKey: .bool(false),
                           MailInbox.summaryKey: .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // 「算」：计算器、单位换算和汇率换算合成一张，输入什么自动认（SmartCalc）。
        // 最后一次输入在 `expression`，最近记录在 `history`，固定到卡片的在
        // `pinned`，旧单位换算留下的一对单位在 `unitFrom`、`unitTo`，都由面板写，
        // 不进设置页。币种对是设置：只写了一种币种时换成哪种。汇率来自
        // open.er-api.com，离线时用缓存，见 CurrencyService。旧的单位换算和
        // 汇率换算读配置时自动变成它，见 SmartCalc.migratingConverter / migratingCurrency。
        Entry(kind: .calculator, name: tr("算"), category: .tools,
              defaults: c([SmartCalc.currencyFromKey: .string(SmartCalc.defaultCurrencyFrom),
                           SmartCalc.currencyToKey: .string(SmartCalc.defaultCurrencyTo)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Apple's on-device Translation: free, no key, nothing leaves the Mac.
        // The languages and the last translations (`source`, `target`,
        // `history`) are kept by the panel; see Translate.
        Entry(kind: .translate, name: tr("翻译"), category: .ai,
              defaults: c(["clickAction": .string("panel"), "autoDirection": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Public numbers need no token; one in the keychain adds notifications
        // and a higher request limit. Up to eight repositories under `repos`
        // (an old `repo` is moved there on load, see GitHubWatch); what was
        // last seen of each is kept by GitHubService, not in the config.
        Entry(kind: .github, name: "GitHub", category: .ai,
              defaults: c(["repos": .list([.string(GitHubWatch.defaultRepo)]),
                           "notify": .bool(false),
                           "interval": .string("\(GitHubWatch.defaultInterval)")]),
              variants: [], supportsCompact: false, selfContained: true),

        // Whether any app is using the default input device, from Core Audio.
        // Reading the state needs no microphone permission.
        Entry(kind: .microphone, name: tr("麦克风"), category: .system, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Storage from URLResourceValues, battery from the power-source API,
        // CPU and memory from the System Activity sampler. 圆只留给它：任意
        // 拼装多个指标。CPU temperature is left out: macOS has no public API for it.
        Entry(kind: .gauges, name: tr("圆环仪表"), category: .system,
              defaults: c(["rings": .list(GaugeReading.defaultRings.map { .string($0) })]),
              variants: [], supportsCompact: false, selfContained: true),

        // 小熊猫陪坐，到点叫你起身；提醒时段、通知、每天起身目标（`goal`，
        // 见 PostureTrack），面板里画今天的时间轴和近 7 天。离开电脑满
        // `awayAfter` 分钟自动算一次休息（`away`，默认开，见 PostureAway）。
        Entry(kind: .posture, name: tr("久坐提醒"), category: .health,
              defaults: c(["duration": .number(1800), "start": .string("09:00"),
                           "end": .string("18:00"), "notify": .bool(true),
                           "goal": .number(Double(PostureTrack.defaultGoal)),
                           PostureAway.enabledKey: .bool(true),
                           PostureAway.afterKey: .string("\(PostureAway.defaultMinutes)")]),
              variants: [], supportsCompact: false, selfContained: true),

        // A list of its own under `items`, never the system's Reminders.
        Entry(kind: .todo, name: tr("快速待办"), category: .todo,
              defaults: c(["showDone": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Habits of its own under `habits`, with each day they were done;
        // see HabitTracker.
        Entry(kind: .habit, name: tr("习惯打卡"), category: .health,
              defaults: c(["showStreak": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Dates of its own under `events`, counted down or up, by the solar
        // or the lunar calendar; the single card's event is `pinned`, chosen
        // in the panel. See Anniversary.
        Entry(kind: .anniversary, name: tr("纪念日"), category: .todo,
              defaults: c(["layout": .string("single"), "showRing": .bool(true)]),
              variants: [(tr("单个"), ["layout": .string("single")]),
                         (tr("多个"), ["layout": .string("multi")])],
              supportsCompact: false, selfContained: true),

        // Today's glasses under `days`, with the chosen `character` (the red
        // panda by default) filling up toward the goal; reminders between
        // `start` and `end`. See WaterIntake. No `goal` here: the goal is the
        // personal recommendation unless one is set by hand in the panel,
        // and a default would read as a hand-set 2000 (see WaterGoal).
        Entry(kind: .water, name: tr("喝水"), category: .health,
              defaults: c([WaterLayout.key: .string(WaterLayout.legacyDefault.rawValue),
                           "cupSize": .number(250), "remindEvery": .string("60"),
                           "start": .string("09:00"), "end": .string("21:00"),
                           "unit": .string("ml"), "character": .string("panda"),
                           WaterParched.key: .bool(true)]),
              // 添加面板只列长相不同的三张：圆环（免费，新放的默认）、角色和
              // 液态（Pro，见 WaterLayout）。六只角色在面板或设置里选
              // （`character`），柴犬、橘猫累计达标 3 天、7 天解锁，企鹅、水獭、
              // 章鱼是 Pro 专属；原来的六张角色卡片本来就存成 layout = character
              // 加角色，读出来就是“角色”样式，样子不变（见 WaterPetCards）。
              // defaults 里的 layout 仍是 character：没存 layout 的老卡片照旧是
              // 角色，新放的由 make() 写成圆环。
              variants: [(tr("圆环"), [WaterLayout.key: .string(WaterLayout.ring.rawValue)]),
                         (tr("角色"), [WaterLayout.key: .string(WaterLayout.character.rawValue)]),
                         (tr("液态"), [WaterLayout.key: .string(WaterLayout.liquid.rawValue)])],
              supportsCompact: false, selfContained: true),

        // A pet of its own: four needs kept with the time they were true, so
        // they run down without anything running (see VirtualPet), and the
        // same six characters as 喝水 under `character`, the red panda free
        // and the other five Pro 专属. 角色不再作为样式列在添加面板里，只有
        // 一张卡片，角色在面板或设置里选；已放好的卡片的角色照旧存在
        // `character` 里，样子不变（见 WaterPetCards）。
        Entry(kind: .pet, name: tr("电子宠物"), category: .health,
              defaults: c(["character": .string("panda")]),
              variants: [],
              supportsCompact: false, selfContained: true),

        // 喝水、习惯打卡、专注计时 summed up as a bamboo leaf a day for the
        // red panda, with its own history, month basket and badges kept by
        // PerfectDayCenter (see PerfectDay). No options: the focus goal is
        // the 专注计时 panel's. The kind stays perfect-day so widgets already
        // placed keep working.
        // 唯一的选项是外观：竹叶（默认）或液态，见 LiquidLooks。
        Entry(kind: .perfectDay, name: tr("小熊猫的竹篮"), category: .health,
              defaults: c([LiquidLooks.key: .string(LiquidLooks.BasketLook.leaf.rawValue)]),
              variants: [], supportsCompact: false, selfContained: true),

        // This week from EventKit, Monday first; see WeekAgenda. Same
        // options as the Calendar widget, which reads the same store.
        Entry(kind: .week, name: tr("一周日程"), category: .time,
              defaults: c(["allDay": .bool(true), "calendars": .list([])]),
              variants: [], supportsCompact: false, selfContained: true),

        // Lunar date, solar terms and the official holidays; see ChineseCalendar.
        // 同一张卡按优先级只说一件事：调休上班 > 节气节日当天 > 下一个假期，见 LunarCard。
        Entry(kind: .lunar, name: tr("农历与假期"), category: .time,
              defaults: c(["showTerm": .bool(true), "workAlert": .bool(true),
                           LunarCard.leadKey: .string("\(LunarCard.defaultLead)")]),
              variants: [], supportsCompact: false, selfContained: true),

        // The Trash's size, a drop target, and flies; see TrashFlies.
        Entry(kind: .trash, name: tr("废纸篓"), category: .files,
              defaults: c(["flies": .bool(true), "threshold": .string(TrashFlies.defaultThreshold)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Synthesised noise, mixed live; see AmbientSynth and AmbientPlayer.
        Entry(kind: .ambient, name: tr("环境音"), category: .media,
              defaults: c(["sounds": .list([.string("rain")]), "volume": .number(50)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Internet radio through one shared AVPlayer; favourites live under
        // `stations` like the to-do list's items, see RadioDial and RadioPlayer.
        // 整种免费；皮肤存在 `skin` 下：经典（半圆表盘，免费，默认）、三款复古
        // 皮肤和五款新外观（都是 Pro，见 RadioSkin）。没存 skin 的旧卡片按经典读。
        Entry(kind: .radio, name: tr("收音机"), category: .media,
              defaults: c(["volume": .number(60), RadioSkin.key: .string(RadioSkin.fallback.rawValue)]),
              variants: RadioSkin.allCases.map { (title: $0.title, overrides: [RadioSkin.key: WidgetConfig.Value.string($0.rawValue)]) },
              supportsCompact: false, selfContained: true),

        // 小宇宙 shows by their public pages, played in 码头; the subscriptions
        // are shared by every 播客 widget and kept by PodcastService, which
        // checks hourly while one is placed. `notify` announces new episodes.
        Entry(kind: .podcast, name: tr("播客"), category: .media,
              defaults: c(["notify": .bool(true)]),
              variants: [], supportsCompact: false, selfContained: true),

        // Each playing app's own volume, through Core Audio process taps; see
        // AppVolume and AppVolumeService. Per-app choices are kept by the
        // service, by bundle identifier, not in the widget's config.
        Entry(kind: .appVolume, name: tr("应用音量"), category: .media, defaults: c([:]),
              variants: [], supportsCompact: false, selfContained: true),

        // Codex's own rate limits, read with the sign-in Codex keeps in
        // ~/.codex, and what Codex is doing from its newest session log.
        Entry(kind: .aiUsage, name: tr("Codex 用量"), category: .ai,
              defaults: c(["show": .string("used"), "notify": .bool(true), "alertAt": .number(80),
                           "notifyDone": .bool(true), "extras": .bool(false),
                           // 外观：圆环（默认）或液态小圆杯，见 LiquidLooks。
                           LiquidLooks.key: .string(LiquidLooks.CodexLook.ring.rawValue)]),
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
        case .podcast: "#25B4E1"
        case .perfectDay: PerfectDay.bambooHex
        case .slacker: SlackerClock.workHex
        case .aiAssistant: ShelfColor.redPanda.hex
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
             .github,
             .microphone, .gauges,
             .colorPicker, .capture, .emoji, .search, .volume, .toggles:
            nil
        }
    }

    /// The keys a widget's settings UI should offer.
    ///
    /// `layout` is excluded: the style picker owns it, and listing it as a
    /// plain text field alongside that picker let the two disagree.
    public static func configurableKeys(_ kind: WidgetKind) -> [String] {
        guard let entry = entry(kind) else { return [] }
        // 按字母排；时钟的子选项恰好是大小在粗细前、卡片在翻法前。
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
        // 时钟的子选项只在它所属的样式下列出（见 `ClockStyles.applies`）。
        case (.clock, _):
            ClockStyles.applies(key, to: config)
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
        // 固定的来源在面板的来源列表里点选，设置页不给文字框。
        case (.music, MusicSourceSwitch.pinnedKey):
            false
        // Finding files asks Spotlight, not a search engine.
        case (.search, "engine"):
            config.string("layout", default: "web") == "web"
        // 搜索站的一排和自定义站在面板里点图标、点“添加”来改，设置里不列。
        case (.search, "sites"), (.search, "customSites"):
            false
        // 有了分组就按分组看，原来那串代码不再读；黄金白银的单位只在列表里有贵金属时才有用；
        // 只有一只股票时没有可轮播的。
        case (.watchlist, "symbols"):
            config.strings("groups", default: []).compactMap(StockBoard.Group.parse).isEmpty
        case (.watchlist, "metalUnit"):
            StockBoard.groups(config).contains { $0.symbols.contains { PreciousMetal(symbol: $0) != nil } }
        case (.stock, "metalUnit"):
            StockBoard.rotation(config).contains { PreciousMetal(symbol: $0) != nil }
        case (.stock, "rotate"):
            StockBoard.rotation(config).count > 1
        // 世界时钟的城市名跟着城市列表走（设置里“城市与时区”那一项改列表，
        // 第一项同步回 city），不再单独给一个文字框。
        case (.world, "city"):
            false
        // 离开多久算休息：离开检测关着时没用。
        case (.posture, PostureAway.afterKey):
            PostureAway.isEnabled(config)
        // The multi-city card shows its own list of places and no other;
        // every other layout reads the one city and never the list.
        case (.weather, "cities"):
            WeatherStyle.layout(config) == WeatherStyle.citiesLayout
        case (.weather, "city"), (.weather, WeatherPanel.moreCitiesKey),
             (.weather, WeatherPanel.showRainKey), (.weather, WeatherPanel.showIndicesKey):
            WeatherStyle.layout(config) != WeatherStyle.citiesLayout
        // 副标题只有“当前”有，天数只有“多日预报”有。
        case (.weather, WeatherStyle.captionKey):
            WeatherStyle.layout(config) == WeatherStyle.currentLayout
        case (.weather, WeatherStyle.daysKey):
            WeatherStyle.layout(config) == WeatherStyle.forecastLayout
        // 旧键名 showRing，现在管单个卡片左边那页撕页；多个是时间轴，没有撕页。
        case (.anniversary, "showRing"):
            config.string("layout", default: "single") == "single"
        // The Wi-Fi rings read the signal, not throughput, so the direction
        // and the chart mean nothing there.
        case (.network, "display"), (.network, "chart"):
            WifiRingStyle.from(layout: config.string("layout", default: "speed")) == nil
        // 仅图标 draws bare glyphs; there is no gauge for a look to change.
        case (.battery, BatteryLook.key):
            config.string("layout", default: "status") != "icon"
        // 提醒提前几天只管调休上班提醒，提醒关了它就没有意义。
        case (.lunar, LunarCard.leadKey):
            config.bool("workAlert", default: true)
        // 水面动效只有液态外观有。
        case (.progress, TimeProgress.motionKey):
            TimeProgress.layout(config) == LiquidMotion.layout
        // 四格四个周期一起看，没有“周期”可选。
        case (.progress, TimeProgress.periodKey):
            TimeProgress.layout(config) != TimeProgress.quadLayout
        // 旧的单个闹钟的时间和名字；换成多个闹钟后在面板里改。
        case (.alarm, "time"), (.alarm, "name"):
            AlarmBook.isLegacy(config)
        // 三个预设在面板里改。
        case (.countdown, CountdownRun.presetsKey):
            false
        // 收音机的皮肤在“样式”里选，不再单列一项。
        case (.radio, RadioSkin.key):
            false
        // 渴成骷髅只画在角色上；圆环和液态没有角色。
        case (.water, WaterParched.key):
            WaterLayout.stored(config) == .character
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
        // The card around the four buttons opens the system's own
        // Screenshot app, where the timer and region recording are.
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
             .clipboard, .emoji, .appSwitcher, .bookmarks, .calculator, .github, .search, .posture,
             .aiUsage, .todo, .ambient, .lunar, .trash, .habit, .crypto, .appVolume, .radio,
             .anniversary, .water, .translate, .pet, .podcast, .perfectDay, .slacker, .aiAssistant:
            nil
        }
    }

    public static var shippable: [Entry] { entries.filter(\.selfContained) }

    /// Fresh instance with a deep copy of the catalog defaults, so array
    /// defaults are never shared between two widgets of the same kind.
    public static func make(_ kind: WidgetKind, overrides: [String: WidgetConfig.Value] = [:]) -> WidgetInstance? {
        guard let entry = byKind[kind] else { return nil }
        var config = entry.defaults
        if kind == .battery { config.set(BatteryLook.key, .string(BatteryLook.newWidgetDefault.rawValue)) }
        if kind == .progress { config.set(TimeProgress.layoutKey, .string(TimeProgress.newWidgetLayout)) }
        // 新放的喝水默认圆环（免费）；defaults 里的角色只给没存 layout 的老卡片。
        if kind == .water { config.set(WaterLayout.key, .string(WaterLayout.newWidget.rawValue)) }
        // 摸鱼时钟的货币符号跟地区走，只写给新放的；不放进 defaults，免得设置页多一栏。
        if kind == .slacker {
            config.set(SlackerClock.currencyKey, .string(RegionalDefaults.current.currencySymbol))
        }
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
            // 圆环、百分比、液态一样宽（方案的 176pt），留白一致。
            case "ring", "percentage", LiquidMotion.layout: return CGSize(width: 176, height: 76)
            default: return CGSize(width: 176, height: 78)
            }
        // 168：名字、三个预设放得下。
        case .countdown: return CGSize(width: 168, height: 72)
        // 220：下一个闹钟的时间和名字一行，后面的闹钟一行小字。
        case .alarm: return CGSize(width: 220, height: 124)
        case .calendar:
            switch cfg.string("layout", default: "nextEvent") {
            case "date": return CGSize(width: 88, height: 76)
            case "dateAndEvent": return CGSize(width: 244, height: 132)
            // 今日时间线一行高，旧的 agenda 也按它算。
            case CalendarDay.timelineLayout, CalendarDay.legacyAgendaLayout: return CGSize(width: 300, height: 62)
            default: return CGSize(width: 168, height: 132)
            }
        case .reminders:
            switch cfg.string("layout", default: "list") {
            case "next": return CGSize(width: 180, height: 132)
            // 今日概览：两个大数字并排，88 放不下。
            case "count": return CGSize(width: 132, height: 76)
            default: return CGSize(width: 220, height: 132)
            }
        case .notes: return CGSize(width: 160, height: 100)
        case .music:
            return cfg.bool("mini") ? CGSize(width: 64, height: 62) : CGSize(width: 264, height: 132)
        case .battery:
            // The single-device 电量 card keeps its size: connected
            // accessories turn it into three gauges, which fit the same 168.
            if BatteryShelf.isStatusCard(cfg) {
                return CGSize(width: 168, height: 132)
            }
            // A slot per configured device, plus the spare slots kept for
            // Bluetooth accessories when 显示蓝牙设备 is on. The height still
            // follows the configured devices, as it always did.
            let devices = BatteryShelf.configuredCount(cfg)
            let slots = BatteryShelf.slotCount(cfg)
            // 仅图标每台设备是电量环加大号百分比，一格要 84 宽（见 `BatteryHourglass`）。
            if cfg.string("layout", default: "status") == "icon" {
                return CGSize(width: BatteryHourglass.iconCardWidth(slots: slots), height: devices > 2 ? 116 : 62)
            }
            return CGSize(width: Double(slots * 44 + (slots - 1) * 8 + 20),
                          height: devices > 2 ? 116 : 62)
        case .system:
            // With the catalog's default, like every other reader of this key.
            // Without it a widget carrying no stored `metrics` measured as one
            // column and drew two, so the tile was sized too narrow for its
            // own contents.
            let metrics = max(1, cfg.strings("metrics", default: ["cpu", "memory"]).count)
            let layout = cfg.string("layout", default: "numbers")
            if layout == "bars" { return CGSize(width: 168, height: 62) }
            // 竖条（存的值 rings）和液态一样宽：竖条加大数字，每个读数 66。
            let rings = layout == ShapeMeters.systemSegmentsLayout || layout == LiquidMotion.layout
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
        // 一排圆角图标，按卡片上的个数算宽（最多 4 个）。
        case .shortcut:
            return CGSize(width: ShortcutDeck.tileWidth(count: ShortcutDeck.tileItems(cfg).count), height: 62)
        // 横排：左边图标，右边“隔空投送”和一行说明。
        case .airdrop: return CGSize(width: 176, height: 76)
        case .weather:
            switch WeatherStyle.layout(cfg) {
            case WeatherStyle.hourlyLayout: return CGSize(width: 216, height: 132)
            // A row of day columns, each as wide as "24° 16°".
            case WeatherStyle.forecastLayout:
                return CGSize(width: WeatherLayout.forecastWidth(cfg), height: 132)
            case WeatherStyle.citiesLayout:
                let count = WeatherLayout.cities(cfg.strings("cities", default: WeatherLayout.defaultCities)).count
                return CGSize(width: WeatherLayout.citiesWidth(count: count), height: 132)
            // Wind and the next sun time are a longer caption than a city or
            // a condition, so those captions keep the old 风与日出日落 width.
            default:
                let caption = WeatherStyle.caption(cfg)
                return CGSize(width: caption.showsWind || caption.showsSun ? 196 : 148, height: 132)
            }
        case .stripe, .paddle:
            return cfg.bool("chart", default: true)
                ? CGSize(width: 200, height: 144) : CGSize(width: 148, height: 108)
        case .shopify: return CGSize(width: 200, height: 132)
        case .stock: return CGSize(width: StockBoard.stockTileWidth(chart: cfg.bool("chart", default: true)), height: 132)
        case .watchlist: return CGSize(width: StockBoard.watchlistTileWidth, height: 176)
        case .photos:
            return cfg.string("layout", default: "standard") == "wide"
                ? CGSize(width: 176, height: 62) : CGSize(width: 112, height: 62)
        // 最新一张大图加 2×2 四格缩略图。
        case .screenshots: return CGSize(width: 184, height: 62)
        case .downloads: return CGSize(width: 176, height: 62)
        case .fileShelf: return CGSize(width: 148, height: 62)
        case .clipboard: return CGSize(width: 196, height: 62)
        // 一排六个最近颜色，下面 HEX 和吸管。
        case .colorPicker: return CGSize(width: 160, height: 62)
        // 截区域、截窗口、识字、录屏四个按钮，各带两个字。
        case .capture: return CGSize(width: 184, height: 62)
        case .emoji: return CGSize(width: 160, height: 62)
        case .search: return CGSize(width: 220, height: 62)
        case .volume: return CGSize(width: 200, height: 62)
        case .toggles: return CGSize(width: QuickToggle.length(count: QuickToggle.chosen(cfg).count), height: 62)
        case .github: return CGSize(width: 196, height: 62)
        // 「算」：字牌、输入和结果、右上角的类别小标签。
        case .calculator: return CGSize(width: 184, height: 62)
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
            return CGSize(width: WaterIntake.tileWidth(layout: WaterLayout.raw(cfg)), height: 62)
        case .pet: return CGSize(width: 196, height: 62)
        case .podcast: return CGSize(width: 220, height: 62)
        case .perfectDay: return CGSize(width: 196, height: 62)
        case .slacker:
            return CGSize(width: SlackerClock.tileWidth(count: SlackerClock.Settings(config: cfg).items.count), height: 62)
        case .aiAssistant:
            return CGSize(width: AIServices.tileWidth(count: AIServices.enabled(in: cfg).count,
                                                      square: AIServices.isSquare(cfg)), height: 62)
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
        case .clock: return 76
        // 世界时钟多个城市时上下排，最多三个，每个一行。
        case .world: return WorldClockList.verticalHeight(cfg)
        case .stopwatch, .countdown: return 62
        case .timer: return 92
        case .alarm: return 76
        case .posture: return 88
        case .microphone: return 88
        case .gauges: return Double(GaugeReading.rings(cfg).count * 66)
        case .aiUsage: return 132
        case .notes: return 96
        case .airdrop: return 76
        case .shortcut: return ShortcutDeck.columnHeight(count: ShortcutDeck.tileItems(cfg).count)
        case .progress:
            return cfg.string("layout", default: "bars") == "percentage" ? 58 : 80
        case .battery:
            return Double(BatteryShelf.slotCount(cfg) * 62)
        case .system:
            let metrics = max(1, cfg.strings("metrics", default: ["cpu", "memory"]).count)
            // Each metric gets a row: sparkline, value, label.
            return Double(metrics * 54 + 8)
        case .network:
            if WifiRingStyle.from(layout: cfg.string("layout", default: "speed")) != nil { return 76 }
            return cfg.string("display", default: "both") == "both" ? 76 : 46
        case .photos:
            return cfg.string("layout", default: "standard") == "wide" ? 112 : 76
        case .colorPicker, .calculator:
            return 84
        case .capture:
            return 112
        case .toggles:
            return Double(QuickToggle.chosen(cfg).count * 30 + 8)
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
        case .todo, .ambient, .lunar, .trash, .appVolume, .radio, .podcast:
            return 112
        case .weather:
            switch WeatherStyle.layout(cfg) {
            case WeatherStyle.forecastLayout: return WeatherLayout.forecastColumnHeight(cfg)
            case WeatherStyle.citiesLayout:
                let count = WeatherLayout.cities(cfg.strings("cities", default: WeatherLayout.defaultCities)).count
                return WeatherLayout.citiesColumnHeight(count: count)
            default: return 76
            }
        case .week:
            return 112
        // 代码、价格、涨跌，下面一段分时和轮播圆点。
        case .stock:
            return 100
        case .watchlist:
            return StockBoard.watchlistColumnHeight(count: StockBoard.currentGroup(cfg).symbols.count)
        case .crypto:
            return CryptoMarket.columnHeight(count: CryptoMarket.coinIDs(cfg).count,
                                             chart: cfg.bool("chart", default: true))
        case .habit:
            return HabitTracker.columnHeight(count: HabitTracker.habits(cfg).count)
        case .anniversary:
            return Anniversary.columnHeight(layout: cfg.string("layout", default: "single"),
                                            count: Anniversary.events(cfg).count)
        case .water:
            return WaterIntake.columnHeight(layout: WaterLayout.raw(cfg))
        // The character, a line, the bar and the bowl.
        case .pet:
            return 118
        // The leaf, its name and the three dots.
        case .perfectDay:
            return 112
        // Two lines of title, the panda, and the cells two to a row.
        case .slacker:
            return SlackerClock.columnHeight(count: SlackerClock.Settings(config: cfg).items.count)
        // The panda on top, the letter tiles two to a row, then the plus.
        case .aiAssistant:
            return AIServices.columnHeight(count: AIServices.enabled(in: cfg).count,
                                           square: AIServices.isSquare(cfg))
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
