import AppIntents
import Foundation
import WidgetKit

// 右键「编辑小组件」里的选项（选哪张卡片、哪个城市），以及小组件上能点的两个按钮
// （待办打勾、喝水加一杯）。
//
// 选项列出的是扩展栏上已有的卡片：主 App 写快照时给每张卡片起好名字（「快速待办」，
// 有几张时「快速待办 2」），实体的 id 就是卡片（WidgetInstance）的 id。

// MARK: - 卡片

/// 快照里某一种卡片的 id 和名字。
enum CardList {
    static func todos() -> [(String, String)] { (Shared.snapshot()?.todos ?? []).map { ($0.id, $0.title) } }
    static func waters() -> [(String, String)] { (Shared.snapshot()?.waters ?? []).map { ($0.id, $0.title) } }
    static func anniversaries() -> [(String, String)] {
        (Shared.snapshot()?.anniversaries ?? []).map { ($0.id, $0.title) }
    }
    static func notes() -> [(String, String)] { (Shared.snapshot()?.notes ?? []).map { ($0.id, $0.title) } }
    static func pets() -> [(String, String)] { (Shared.snapshot()?.pets ?? []).map { ($0.id, $0.name) } }
    static func calcs() -> [(String, String)] { (Shared.snapshot()?.calcs ?? []).map { ($0.id, $0.title) } }
    static func clocks() -> [(String, String)] { (Shared.snapshot()?.clocks ?? []).map { ($0.id, $0.title) } }
}

struct TodoCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "快速待办卡片") }
    static var defaultQuery: TodoCardQuery { TodoCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TodoCardQuery: EntityQuery {
    private func all() -> [TodoCardEntity] { CardList.todos().map { TodoCardEntity(id: $0.0, title: $0.1) } }
    func entities(for identifiers: [String]) async throws -> [TodoCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [TodoCardEntity] { all() }
    func defaultResult() async -> TodoCardEntity? { all().first }
}

struct WaterCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "喝水卡片") }
    static var defaultQuery: WaterCardQuery { WaterCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WaterCardQuery: EntityQuery {
    private func all() -> [WaterCardEntity] { CardList.waters().map { WaterCardEntity(id: $0.0, title: $0.1) } }
    func entities(for identifiers: [String]) async throws -> [WaterCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WaterCardEntity] { all() }
    func defaultResult() async -> WaterCardEntity? { all().first }
}

struct AnniversaryCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "纪念日卡片") }
    static var defaultQuery: AnniversaryCardQuery { AnniversaryCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct AnniversaryCardQuery: EntityQuery {
    private func all() -> [AnniversaryCardEntity] {
        CardList.anniversaries().map { AnniversaryCardEntity(id: $0.0, title: $0.1) }
    }
    func entities(for identifiers: [String]) async throws -> [AnniversaryCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [AnniversaryCardEntity] { all() }
    func defaultResult() async -> AnniversaryCardEntity? { all().first }
}

struct NoteCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "便签卡片") }
    static var defaultQuery: NoteCardQuery { NoteCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct NoteCardQuery: EntityQuery {
    private func all() -> [NoteCardEntity] { CardList.notes().map { NoteCardEntity(id: $0.0, title: $0.1) } }
    func entities(for identifiers: [String]) async throws -> [NoteCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [NoteCardEntity] { all() }
    func defaultResult() async -> NoteCardEntity? { all().first }
}

struct PetCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "电子宠物卡片") }
    static var defaultQuery: PetCardQuery { PetCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct PetCardQuery: EntityQuery {
    private func all() -> [PetCardEntity] { CardList.pets().map { PetCardEntity(id: $0.0, title: $0.1) } }
    func entities(for identifiers: [String]) async throws -> [PetCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [PetCardEntity] { all() }
    func defaultResult() async -> PetCardEntity? { all().first }
}

struct CalcCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "「算」卡片") }
    static var defaultQuery: CalcCardQuery { CalcCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct CalcCardQuery: EntityQuery {
    private func all() -> [CalcCardEntity] { CardList.calcs().map { CalcCardEntity(id: $0.0, title: $0.1) } }
    func entities(for identifiers: [String]) async throws -> [CalcCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [CalcCardEntity] { all() }
    func defaultResult() async -> CalcCardEntity? { all().first }
}

struct WorldClockCardEntity: AppEntity {
    let id: String
    let title: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "世界时钟卡片") }
    static var defaultQuery: WorldClockCardQuery { WorldClockCardQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WorldClockCardQuery: EntityQuery {
    private func all() -> [WorldClockCardEntity] {
        CardList.clocks().map { WorldClockCardEntity(id: $0.0, title: $0.1) }
    }
    func entities(for identifiers: [String]) async throws -> [WorldClockCardEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WorldClockCardEntity] { all() }
    func defaultResult() async -> WorldClockCardEntity? { all().first }
}

// MARK: - 城市

/// 时钟的主城市：世界时钟卡片里加过的城市在前，再接一组常用城市。id 是「时区|名字」。
struct ClockCityEntity: AppEntity {
    let id: String
    let name: String
    let zone: String

    init(name: String, zone: String) {
        self.id = "\(zone)|\(name)"
        self.name = name
        self.zone = zone
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "城市") }
    static var defaultQuery: ClockCityQuery { ClockCityQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    /// 常用城市：中文名（也是查英文的键）和时区。
    static let common: [(String, String)] = [
        ("北京", "Asia/Shanghai"), ("上海", "Asia/Shanghai"), ("香港", "Asia/Hong_Kong"),
        ("东京", "Asia/Tokyo"), ("首尔", "Asia/Seoul"), ("新加坡", "Asia/Singapore"),
        ("迪拜", "Asia/Dubai"), ("伦敦", "Europe/London"), ("巴黎", "Europe/Paris"),
        ("柏林", "Europe/Berlin"), ("纽约", "America/New_York"), ("旧金山", "America/Los_Angeles"),
        ("洛杉矶", "America/Los_Angeles"), ("悉尼", "Australia/Sydney"),
    ]

    static func all() -> [ClockCityEntity] {
        let snapshot = Shared.snapshot()
        let words = Words(lang: Shared.language(snapshot))
        var seen = Set<String>()
        var out: [ClockCityEntity] = []
        for city in (snapshot?.clocks ?? []).flatMap(\.cities) {
            let entity = ClockCityEntity(name: city.name, zone: city.zone)
            if seen.insert(entity.id).inserted { out.append(entity) }
        }
        for (name, zone) in common {
            let entity = ClockCityEntity(name: words(name), zone: zone)
            if seen.insert(entity.id).inserted { out.append(entity) }
        }
        return out
    }
}

struct ClockCityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ClockCityEntity] {
        // 存下来的 id 自带时区和名字，列表里找不到（城市从卡片里删了）也照样能用。
        identifiers.compactMap { id in
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, TimeZone(identifier: parts[0]) != nil else { return nil }
            return ClockCityEntity(name: parts[1], zone: parts[0])
        }
    }
    func entities(matching string: String) async throws -> [ClockCityEntity] {
        ClockCityEntity.all().filter { $0.name.localizedCaseInsensitiveContains(string) || $0.zone.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [ClockCityEntity] { ClockCityEntity.all() }
}

// MARK: - 编辑小组件里的选项

struct ClockConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "时钟" }
    static var description: IntentDescription { IntentDescription("选主城市，以及中号小组件下面列哪张世界时钟卡片的城市") }

    @Parameter(title: "主城市（不选为本机时间）")
    var city: ClockCityEntity?

    @Parameter(title: "世界时钟卡片")
    var card: WorldClockCardEntity?
}

struct TodoConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "快速待办" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪张快速待办卡片") }

    @Parameter(title: "卡片")
    var card: TodoCardEntity?
}

struct WaterConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "喝水" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪张喝水卡片") }

    @Parameter(title: "卡片")
    var card: WaterCardEntity?
}

struct AnniversaryConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "纪念日" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪张纪念日卡片") }

    @Parameter(title: "卡片")
    var card: AnniversaryCardEntity?
}

struct NoteConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "便签" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪张便签") }

    @Parameter(title: "卡片")
    var card: NoteCardEntity?
}

struct PetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "电子宠物" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪只宠物") }

    @Parameter(title: "卡片")
    var card: PetCardEntity?
}

struct CalcConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "算" }
    static var description: IntentDescription { IntentDescription("显示扩展栏上的哪张「算」卡片") }

    @Parameter(title: "卡片")
    var card: CalcCardEntity?
}

// MARK: - 小组件上的按钮

/// 待办圆圈：记一个动作文件，主 App 合并进卡片。小组件随后自己刷新，叠上这一下马上显示打勾。
struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource { "勾选待办" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "卡片")
    var card: String

    @Parameter(title: "待办")
    var item: String

    @Parameter(title: "完成")
    var done: Bool

    init() {}

    init(card: String, item: String, done: Bool) {
        self.card = card
        self.item = item
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        try Shared.store.record(.toggleTodo(card: card, item: item, done: done))
        Shared.notifyApp()
        return .result()
    }
}

/// 喝水：加一杯（卡片设的杯量）。
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "喝一杯水" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "卡片")
    var card: String

    init() {}

    init(card: String) {
        self.card = card
    }

    func perform() async throws -> some IntentResult {
        try Shared.store.record(.addWater(card: card, amount: nil))
        Shared.notifyApp()
        return .result()
    }
}
