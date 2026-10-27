import Foundation

/// 主 App 这头：从扩展栏上的卡片拼出系统小组件的快照，以及判断扩展里的一次点按
/// 该怎么合并回卡片。
///
/// 数据格式和读写在 SystemWidgetSnapshot.swift（扩展也编它）；这里用到 Core 里
/// 各个小组件自己的读法，所以只编进主 App 和测试包。真正写卡片的 `TodoLog.toggle`、
/// `WaterLog.drink` 在界面层，由 SystemWidgetSync 照这里的判断去调。
public enum SystemWidgetBridge {

    /// 拼快照时需要、但 Core 自己拿不到的现场数据。
    public struct Live: Sendable {
        /// "zh-Hans" 或 "en"。
        public var language: String
        public var weather: SystemWidgetSnapshot.Weather?
        /// 码头 Pro 已解锁：宠物角色、便签纸色、待办标签色按它显示。
        public var unlocked: Bool
        /// 宠物「热化了」（Mac 过热、CPU 很忙或外面太热）。
        public var melted: Bool
        /// 喝水连续没达标的天数，宠物「渴成骷髅」看它。
        public var missedWaterDays: Int
        public var rates: CurrencyRates?
        /// 上一份快照里记着的、已经合并过的动作。
        public var handled: [String]

        public init(language: String = "zh-Hans", weather: SystemWidgetSnapshot.Weather? = nil,
                    unlocked: Bool = false, melted: Bool = false, missedWaterDays: Int = 0,
                    rates: CurrencyRates? = nil, handled: [String] = []) {
            self.language = language
            self.weather = weather
            self.unlocked = unlocked
            self.melted = melted
            self.missedWaterDays = missedWaterDays
            self.rates = rates
            self.handled = handled
        }
    }

    /// 系统小组件用得上的卡片种类。
    public static let kinds: Set<WidgetKind> = [.world, .anniversary, .todo, .water, .pet, .notes, .calculator]

    /// 每张卡片最多带几条，免得快照随清单无限长。
    public static let maxTodoItems = 12
    public static let maxAnniversaryEvents = 6
    public static let maxNoteLength = 600

    /// 同一种卡片按出现顺序编号：只有一张时就叫「快速待办」，多张时「快速待办 2」。
    /// 去重：同一个 id 出现在几个布局里只算一张（第一次出现的那张）。
    public static func unique(_ widgets: [WidgetInstance]) -> [WidgetInstance] {
        var seen = Set<UUID>()
        return widgets.filter { seen.insert($0.id).inserted }
    }

    public static func numbered(_ base: String, index: Int, count: Int) -> String {
        count > 1 ? "\(base) \(index + 1)" : base
    }

    // MARK: 快照

    public static func snapshot(from widgets: [WidgetInstance], live: Live,
                                now: Date = .now) -> SystemWidgetSnapshot {
        let all = unique(widgets).filter { kinds.contains($0.kind) }
        func of(_ kind: WidgetKind) -> [WidgetInstance] { all.filter { $0.kind == kind } }

        let worlds = of(.world)
        let clocks = worlds.enumerated().map { index, w in
            clock(w, title: numbered(tr("世界时钟"), index: index, count: worlds.count))
        }
        let annivs = of(.anniversary)
        let anniversaries = annivs.enumerated().map { index, w in
            anniversary(w, title: numbered(tr("纪念日"), index: index, count: annivs.count), now: now)
        }
        let todoCards = of(.todo)
        let todos = todoCards.enumerated().map { index, w in
            todo(w, title: numbered(tr("快速待办"), index: index, count: todoCards.count),
                 unlocked: live.unlocked, now: now)
        }
        let waterCards = of(.water)
        let waters = waterCards.enumerated().map { index, w in
            water(w, title: numbered(tr("喝水"), index: index, count: waterCards.count), now: now)
        }
        let pets = of(.pet).map { pet($0, live: live, now: now) }
        let noteCards = of(.notes)
        let notes = noteCards.enumerated().map { index, w in
            note(w, title: numbered(tr("便签"), index: index, count: noteCards.count), unlocked: live.unlocked)
        }
        let calcCards = of(.calculator)
        let calcs = calcCards.enumerated().map { index, w in
            calc(w, title: numbered(tr("算"), index: index, count: calcCards.count), rates: live.rates)
        }
        return SystemWidgetSnapshot(language: live.language, clocks: clocks, weather: live.weather,
                                    anniversaries: anniversaries, todos: todos, waters: waters, pets: pets,
                                    notes: notes, calcs: calcs, handled: live.handled)
    }

    static func clock(_ w: WidgetInstance, title: String) -> SystemWidgetSnapshot.ClockCard {
        let cities = WorldClockList.cities(w.config).map { SystemWidgetSnapshot.City(name: $0.name, zone: $0.zone) }
        return .init(id: w.id.uuidString, title: title, cities: cities)
    }

    static func anniversary(_ w: WidgetInstance, title: String, now: Date) -> SystemWidgetSnapshot.AnniversaryCard {
        let readings = Anniversary.readings(Anniversary.events(w.config), today: now)
        let events = readings.prefix(maxAnniversaryEvents).map { reading in
            SystemWidgetSnapshot.AnniversaryEvent(
                id: reading.event.id, title: reading.event.title,
                target: target(of: reading, now: now),
                subtitle: Anniversary.subtitle(reading), color: reading.event.color?.hex)
        }
        var pinned = Anniversary.pinnedID(w.config)
        if let id = pinned, !events.contains(where: { $0.id == id }) { pinned = nil }
        return .init(id: w.id.uuidString, title: title, events: Array(events), pinned: pinned)
    }

    /// 扩展按「数到哪一天」和今天的先后决定说「还有」「就是今天」还是「已经」：
    /// 要到的数到那一天，今天的就是今天，过去的、正数的数到起始日。
    static func target(of reading: AnniversaryReading, now: Date) -> String {
        switch reading.phase {
        case .today:
            return SystemWidgetSnapshot.dayKey(now)
        case .upcoming:
            let day = reading.event.kind == .countdown ? (reading.next ?? reading.original) : reading.original
            return SystemWidgetSnapshot.dayKey(day)
        case .past:
            return SystemWidgetSnapshot.dayKey(reading.original)
        }
    }

    static func todo(_ w: WidgetInstance, title: String, unlocked: Bool, now: Date) -> SystemWidgetSnapshot.TodoCard {
        let today = TodoDay.key(now)
        let items = QuickTodo.items(w.config)
        let open = items.filter { !$0.done }
        // 今天勾掉的留着（能在桌面上再点回去），更早勾掉的不带。
        let doneToday = items.filter { $0.done && $0.doneDay == today }
        let shown = (open.filter(\.today) + open.filter { !$0.today } + doneToday).prefix(maxTodoItems)
        return .init(id: w.id.uuidString, title: title, items: shown.map { item in
            SystemWidgetSnapshot.TodoItem(id: item.id, text: item.text, done: item.done, today: item.today,
                                          color: TodoTag.shown(item.tag, unlocked: unlocked)?.hex)
        })
    }

    static func water(_ w: WidgetInstance, title: String, now: Date) -> SystemWidgetSnapshot.WaterCard {
        let day = WaterIntake.today(w.config, now: now)
        return .init(id: w.id.uuidString, title: title, day: SystemWidgetSnapshot.dayKey(now),
                     total: day.total, goal: day.goal, cup: WaterIntake.cupSize(w.config),
                     ounces: WaterIntake.usesOunces(w.config))
    }

    static func pet(_ w: WidgetInstance, live: Live, now: Date) -> SystemWidgetSnapshot.PetCard {
        let character = WaterCharacter.petShown(w.config, unlocked: live.unlocked)
        let state = VirtualPet.advanced(VirtualPet.state(w.config, now: now), to: now)
        let dried = VirtualPet.isDried(w.config, missedDays: live.missedWaterDays)
        let look = VirtualPet.look(state, now: now, dried: dried, melted: live.melted)
        return .init(id: w.id.uuidString,
                     name: VirtualPet.name(w.config, fallback: character.title),
                     image: VirtualPet.imageName(character, look),
                     status: VirtualPet.statusLine(state, now: now, dried: dried, melted: live.melted),
                     // 取整：数值一直在慢慢掉，带小数的话快照每次都不一样。
                     food: state.food.rounded(), mood: state.mood.rounded(),
                     energy: state.energy.rounded(), clean: state.clean.rounded())
    }

    static func note(_ w: WidgetInstance, title: String, unlocked: Bool) -> SystemWidgetSnapshot.NoteCard {
        let front = StickyStack.pile(w.config).front
        let text = String(StickyChecklist.display(front.text).prefix(maxNoteLength))
        let first = text.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let named = first.isEmpty ? title : "\(title) · \(first.prefix(12))"
        return .init(id: w.id.uuidString, title: named, text: text, paper: front.paper(unlocked: unlocked).hex)
    }

    static func calc(_ w: WidgetInstance, title: String, rates: CurrencyRates?) -> SystemWidgetSnapshot.CalcCard {
        let input = SmartCalc.shown(w.config)
        guard !input.isEmpty else { return .init(id: w.id.uuidString, title: title, input: "", result: "0") }
        switch SmartCalc.evaluate(input, rates: rates, preferences: SmartCalc.Preferences(w.config)) {
        case .success(let out):
            return .init(id: w.id.uuidString, title: title, input: CurrencyDesk.label(input),
                         result: out.text, unit: out.unit)
        case .failure:
            return .init(id: w.id.uuidString, title: title, input: CurrencyDesk.label(input), result: "-")
        }
    }

    // MARK: 合并点按

    /// 一次点按该怎么落到卡片上。
    public enum Merge: Equatable, Sendable {
        /// 切换这一条；`cheering` 为真时这一下把「今天」一组清空了（照卡片上勾掉一样庆祝）。
        case toggleTodo(widget: UUID, item: String, cheering: Bool)
        case addWater(widget: UUID, amount: Int)
        /// 卡片没了、那一条没了、已经是要的状态：不用动，动作文件照样删掉。
        case skip
    }

    public static func resolve(_ action: SystemWidgetAction, widgets: [WidgetInstance]) -> Merge {
        guard let id = UUID(uuidString: action.card),
              let widget = widgets.first(where: { $0.id == id }) else { return .skip }
        switch action.kind {
        case .toggleTodo:
            guard widget.kind == .todo, let itemID = action.item, let desired = action.done else { return .skip }
            let items = QuickTodo.items(widget.config)
            guard let item = items.first(where: { $0.id == itemID }), item.done != desired else { return .skip }
            let cheering = desired && QuickTodo.clearsToday(toggling: itemID, in: items)
            return .toggleTodo(widget: id, item: itemID, cheering: cheering)
        case .addWater:
            guard widget.kind == .water else { return .skip }
            let amount = action.amount ?? WaterIntake.cupSize(widget.config)
            let clamped = min(max(amount, WaterIntake.cupRange.lowerBound), WaterIntake.cupRange.upperBound)
            return .addWater(widget: id, amount: clamped)
        }
    }
}
