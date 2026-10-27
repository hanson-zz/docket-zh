import Foundation

// 系统小组件（桌面右键「编辑小组件」里的「码头」）和主 App 之间交换的数据。
//
// 这个文件只用 Foundation，同时编进主 App、测试包和小组件扩展（DocklingWidgets），
// 所以不能引用 Core 里别的类型。主 App 那头怎么从扩展栏卡片拼出快照、怎么把
// 扩展里的点按合并回真实数据，在 SystemWidgetBridge.swift。
//
// 为什么不用 App Group：码头是 ad-hoc 签名（配了证书也只是自签名，没有 Team ID），
// macOS 15 起 containermanagerd 只认带 Team ID 前缀的组容器，ad-hoc 的扩展拿不到
// 容器，主 App 去碰还会弹「想要访问其他 App 的数据」。所以换成：主 App（不沙盒）把
// 快照写进自己 Application Support 下的 SystemWidgets 文件夹，沙盒里的扩展用
// temporary-exception 的 home-relative-path 读写这一个文件夹。
//
// 扩展只写「动作」：每次点按一个小文件放进 actions/，主 App 看到后合并进卡片、
// 重写快照、删掉动作文件。快照里记着合并过的动作 id（handled），扩展画的时候把
// 还没合并的动作叠在快照上（applying），点下去马上就有反应，合并前后不会算两次。

/// 主 App 写、扩展读的一整份快照。
public struct SystemWidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// 主 App 的界面语言："zh-Hans" 或 "en"。扩展按它查表，和 App 里选的语言一致。
    public var language: String
    public var clocks: [ClockCard]
    public var weather: Weather?
    public var anniversaries: [AnniversaryCard]
    public var todos: [TodoCard]
    public var waters: [WaterCard]
    public var pets: [PetCard]
    public var notes: [NoteCard]
    public var calcs: [CalcCard]
    /// 已经合并进真实数据的动作 id，最近的在后面，最多 `handledLimit` 条。
    public var handled: [String]

    public static let handledLimit = 200

    public init(language: String = "zh-Hans", clocks: [ClockCard] = [], weather: Weather? = nil,
                anniversaries: [AnniversaryCard] = [], todos: [TodoCard] = [], waters: [WaterCard] = [],
                pets: [PetCard] = [], notes: [NoteCard] = [], calcs: [CalcCard] = [],
                handled: [String] = []) {
        self.version = Self.currentVersion
        self.language = language
        self.clocks = clocks
        self.weather = weather
        self.anniversaries = anniversaries
        self.todos = todos
        self.waters = waters
        self.pets = pets
        self.notes = notes
        self.calcs = calcs
        self.handled = handled
    }

    // MARK: 卡片

    public struct City: Codable, Equatable, Hashable, Sendable {
        public var name: String
        /// IANA 时区。
        public var zone: String
        public init(name: String, zone: String) {
            self.name = name
            self.zone = zone
        }
    }

    /// 一张世界时钟卡片里的城市。
    public struct ClockCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var cities: [City]
        public init(id: String, title: String, cities: [City]) {
            self.id = id
            self.title = title
            self.cities = cities
        }
    }

    public struct WeatherHour: Codable, Equatable, Sendable {
        public var time: Date
        public var temperatureC: Double
        public var symbol: String
        public init(time: Date, temperatureC: Double, symbol: String) {
            self.time = time
            self.temperatureC = temperatureC
            self.symbol = symbol
        }
    }

    /// 主天气卡片的城市（码头只有一个实时天气地点）。
    public struct Weather: Codable, Equatable, Sendable {
        public var city: String
        public var temperatureC: Double
        /// SF Symbols 名。
        public var symbol: String
        public var condition: String
        public var highC: Double?
        public var lowC: Double?
        public var fahrenheit: Bool
        public var hours: [WeatherHour]
        public var asOf: Date
        public init(city: String, temperatureC: Double, symbol: String, condition: String,
                    highC: Double? = nil, lowC: Double? = nil, fahrenheit: Bool = false,
                    hours: [WeatherHour] = [], asOf: Date) {
            self.city = city
            self.temperatureC = temperatureC
            self.symbol = symbol
            self.condition = condition
            self.highC = highC
            self.lowC = lowC
            self.fahrenheit = fahrenheit
            self.hours = hours
            self.asOf = asOf
        }
    }

    public struct AnniversaryEvent: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// 数到哪一天（"2026-12-25"）：倒数是下一次，正数是起始日。在今天之后读「还有 N 天」，
        /// 就是今天读「就是今天」，在今天之前读「已经 N 天」。
        public var target: String
        /// 卡片上的小字：公历或农历日期。
        public var subtitle: String
        /// "#RRGGBB"，没选颜色时为 nil。
        public var color: String?
        public init(id: String, title: String, target: String, subtitle: String, color: String? = nil) {
            self.id = id
            self.title = title
            self.target = target
            self.subtitle = subtitle
            self.color = color
        }
    }

    public struct AnniversaryCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// 卡片上的顺序：今天的、最近要到的在前（主 App 排好）。
        public var events: [AnniversaryEvent]
        /// 卡片里固定显示的那一条。
        public var pinned: String?
        public init(id: String, title: String, events: [AnniversaryEvent], pinned: String? = nil) {
            self.id = id
            self.title = title
            self.events = events
            self.pinned = pinned
        }
    }

    public struct TodoItem: Codable, Equatable, Sendable {
        public var id: String
        public var text: String
        public var done: Bool
        /// 在「今天」一组（否则是「稍后」）。
        public var today: Bool
        /// 标签色 "#RRGGBB"。
        public var color: String?
        public init(id: String, text: String, done: Bool = false, today: Bool = true, color: String? = nil) {
            self.id = id
            self.text = text
            self.done = done
            self.today = today
            self.color = color
        }
    }

    public struct TodoCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var items: [TodoItem]
        public init(id: String, title: String, items: [TodoItem]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    public struct WaterCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// `SystemWidgetSnapshot.dayKey` 写的那一天；过了这天读成 0。
        public var day: String
        /// 毫升（已经按饮品折算）。
        public var total: Int
        public var goal: Int
        /// 点一下加多少毫升。
        public var cup: Int
        public var ounces: Bool
        public init(id: String, title: String, day: String, total: Int, goal: Int, cup: Int,
                    ounces: Bool = false) {
            self.id = id
            self.title = title
            self.day = day
            self.total = total
            self.goal = goal
            self.cup = cup
            self.ounces = ounces
        }
    }

    public struct PetCard: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// 扩展里的图片名（不带 .png），见 `VirtualPet.imageName`。
        public var image: String
        public var status: String
        public var food: Double
        public var mood: Double
        public var energy: Double
        public var clean: Double
        public init(id: String, name: String, image: String, status: String,
                    food: Double, mood: Double, energy: Double, clean: Double) {
            self.id = id
            self.name = name
            self.image = image
            self.status = status
            self.food = food
            self.mood = mood
            self.energy = energy
            self.clean = clean
        }
    }

    public struct NoteCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var text: String
        /// 纸色 "#RRGGBB"。
        public var paper: String
        public init(id: String, title: String, text: String, paper: String) {
            self.id = id
            self.title = title
            self.text = text
            self.paper = paper
        }
    }

    public struct CalcCard: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// 上面一小行：输入的算式。
        public var input: String
        public var result: String
        public var unit: String
        public init(id: String, title: String, input: String, result: String, unit: String = "") {
            self.id = id
            self.title = title
            self.input = input
            self.result = result
            self.unit = unit
        }
    }

    // MARK: 日子

    /// 喝水按这一天归零："2026-10-27"，公历、本机时区。主 App 和扩展都用它。
    public static func dayKey(_ date: Date, calendar: Calendar = SystemWidgetSnapshot.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// 从 `today` 到 "2026-12-25" 隔几天：在今天之后为正，今天为 0，之前为负。读不出来时 nil。
    public static func days(to key: String, from today: Date,
                            calendar: Calendar = SystemWidgetSnapshot.calendar) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let target = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let start = calendar.startOfDay(for: today)
        return calendar.dateComponents([.day], from: start, to: target).day
    }

    // MARK: 叠上还没合并的点按

    /// 把还没合并的动作叠在快照上，扩展画的就是这份。
    ///
    /// 已经在 `handled` 里的跳过（主 App 写好了新快照、还没来得及删动作文件的那一下）；
    /// 打勾是「设成完成 / 没完成」，叠几次都一样；加一杯按动作数，过了快照那一天
    /// 从 0 起。
    public func applying(_ actions: [SystemWidgetAction], now: Date = .now) -> SystemWidgetSnapshot {
        var out = self
        let done = Set(handled)
        let today = Self.dayKey(now)
        for action in actions.sorted(by: { $0.at < $1.at }) where !done.contains(action.id) {
            switch action.kind {
            case .toggleTodo:
                guard let item = action.item, let desired = action.done,
                      let c = out.todos.firstIndex(where: { $0.id == action.card }),
                      let i = out.todos[c].items.firstIndex(where: { $0.id == item }) else { continue }
                out.todos[c].items[i].done = desired
            case .addWater:
                guard let c = out.waters.firstIndex(where: { $0.id == action.card }) else { continue }
                let amount = max(0, action.amount ?? out.waters[c].cup)
                if out.waters[c].day != today {
                    out.waters[c].day = today
                    out.waters[c].total = 0
                }
                out.waters[c].total += amount
            }
        }
        return out
    }

    /// 喝水今天的量：快照不是今天写的就是 0。
    public func waterTotal(_ card: WaterCard, now: Date = .now) -> Int {
        card.day == Self.dayKey(now) ? card.total : 0
    }

    /// 记下合并过的动作，只留最近 `handledLimit` 条。
    public static func remembering(_ ids: [String], in handled: [String],
                                   limit: Int = SystemWidgetSnapshot.handledLimit) -> [String] {
        let fresh = ids.filter { !handled.contains($0) }
        return Array((handled + fresh).suffix(limit))
    }

    /// 待办卡片上画哪几条：没做的「今天」在前、「稍后」在后，再接今天刚勾掉的
    /// （叠上动作后还留在原处，能再点回去），最多 `limit` 条。
    public static func shownTodos(_ items: [TodoItem], limit: Int) -> [TodoItem] {
        let open = items.filter { !$0.done }
        let ordered = open.filter(\.today) + open.filter { !$0.today } + items.filter(\.done)
        return Array(ordered.prefix(max(0, limit)))
    }

    /// 没做完的有几条（今天一组）。
    public static func openToday(_ items: [TodoItem]) -> Int {
        items.filter { !$0.done && $0.today }.count
    }
}

/// 扩展里的一次点按，存成 actions/ 下的一个文件。
public struct SystemWidgetAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 待办圆圈：把 `item` 设成 `done`。
        case toggleTodo
        /// 喝水：加 `amount` 毫升（nil 时用卡片的一杯）。
        case addWater
    }

    public var id: String
    public var kind: Kind
    /// 扩展栏卡片（WidgetInstance）的 id。
    public var card: String
    public var item: String?
    public var done: Bool?
    public var amount: Int?
    public var at: Date

    public init(id: String = UUID().uuidString, kind: Kind, card: String, item: String? = nil,
                done: Bool? = nil, amount: Int? = nil, at: Date = .now) {
        self.id = id
        self.kind = kind
        self.card = card
        self.item = item
        self.done = done
        self.amount = amount
        self.at = at
    }

    public static func toggleTodo(card: String, item: String, done: Bool, at: Date = .now) -> SystemWidgetAction {
        SystemWidgetAction(kind: .toggleTodo, card: card, item: item, done: done, at: at)
    }

    public static func addWater(card: String, amount: Int?, at: Date = .now) -> SystemWidgetAction {
        SystemWidgetAction(kind: .addWater, card: card, amount: amount, at: at)
    }
}

/// 快照和动作文件放在哪、怎么读写。主 App 和扩展共用。
public struct SystemWidgetStore: Sendable {
    /// 相对用户主目录。扩展的 entitlements 里同一条路径（结尾带 /）。
    public static let relativePath = "Library/Application Support/com.docket-zh.app/SystemWidgets"
    /// 扩展收到点按后发的分布式通知，主 App 听到马上去合并（不带 userInfo，沙盒会去掉）。
    public static let actionNotification = "com.docket-zh.app.systemwidgets.action"
    /// 系统小组件的 kind 前缀，和扩展里每个 Widget 的 kind 一致。
    public static let kindPrefix = "com.docket-zh.app.widget."

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 真正的用户主目录下的那个文件夹。沙盒里 `NSHomeDirectory()` 指向扩展自己的容器，
    /// 所以从账户信息里取主目录。
    public static func standard() -> SystemWidgetStore {
        SystemWidgetStore(directory: realHome().appending(path: relativePath, directoryHint: .isDirectory))
    }

    public static func realHome() -> URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public var snapshotURL: URL { directory.appending(path: "snapshot.json") }
    public var actionsDirectory: URL { directory.appending(path: "actions", directoryHint: .isDirectory) }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 没有文件、读不出来或版本比自己新时 nil（扩展显示「打开码头」的提示）。
    public func loadSnapshot() -> SystemWidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? Self.decoder().decode(SystemWidgetSnapshot.self, from: data),
              snapshot.version <= SystemWidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// 写快照。内容和磁盘上的一样时不写，返回 false（主 App 据此决定要不要刷新小组件）。
    @discardableResult
    public func save(_ snapshot: SystemWidgetSnapshot) throws -> Bool {
        let data = try Self.encoder().encode(snapshot)
        if let old = try? Data(contentsOf: snapshotURL), old == data { return false }
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try data.write(to: snapshotURL, options: .atomic)
        return true
    }

    /// 还没合并的动作，按时间先后。读不出来的文件跳过（下一轮由主 App 清掉）。
    public func pendingActions() -> [(url: URL, action: SystemWidgetAction)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: actionsDirectory,
                                                                   includingPropertiesForKeys: nil)) ?? []
        let decoder = Self.decoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let action = try? decoder.decode(SystemWidgetAction.self, from: data) else { return nil }
            return (url, action)
        }.sorted { $0.action.at < $1.action.at }
    }

    /// 读不出来的动作文件（写到一半、格式坏了），主 App 合并时顺手删掉。
    public func unreadableActionFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: actionsDirectory,
                                                                   includingPropertiesForKeys: nil)) ?? []
        let decoder = Self.decoder()
        return files.filter { url in
            guard url.pathExtension == "json" else { return false }
            guard let data = try? Data(contentsOf: url) else { return true }
            return (try? decoder.decode(SystemWidgetAction.self, from: data)) == nil
        }
    }

    /// 扩展记一次点按：一个动作一个文件，主 App 和扩展不会同时写同一个文件。
    public func record(_ action: SystemWidgetAction) throws {
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(action)
        try data.write(to: actionsDirectory.appending(path: "\(action.id).json"), options: .atomic)
    }

    /// 扩展画的那份：快照叠上还没合并的动作。
    public func current(now: Date = .now) -> SystemWidgetSnapshot? {
        loadSnapshot()?.applying(pendingActions().map(\.action), now: now)
    }
}
