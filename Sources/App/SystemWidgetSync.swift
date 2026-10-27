import AppKit
import WidgetKit

/// 系统小组件（桌面右键「编辑小组件」里的「码头」）的主 App 一端。
///
/// - 每 5 秒从各个布局里的卡片拼一份快照（`SystemWidgetBridge.snapshot`），内容变了才写进
///   ~/Library/Application Support/com.docket-zh.app/SystemWidgets/snapshot.json，并让对应的
///   小组件重画（同一种小组件有最短间隔，省系统给的刷新次数）。
/// - 盯着 actions/ 文件夹（外加扩展发的分布式通知）：小组件上打勾、加一杯各是一个动作文件，
///   照扩展栏卡片上点的一样写进卡片（`TodoLog.toggle`、`WaterLog.drink`），写好新快照
///   （记下合并过的动作 id）后再删动作文件，扩展那头不会算两次。
///
/// 和扩展栏原有的功能互不影响：只读卡片，写回也走卡片自己的那条路。
@MainActor
final class SystemWidgetSync {
    static let shared = SystemWidgetSync()

    /// 每个布局里的全部卡片（文件夹、分组里的也算）。
    var widgets: () -> [WidgetInstance] = { [] }

    private let store = SystemWidgetStore.standard()
    private var started = false
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var observer: NSObjectProtocol?

    private var handled: [String] = []
    private var lastData: Data?
    private var last: SystemWidgetSnapshot?
    /// 天气没变时沿用上次的时间，免得快照每 5 秒都不一样。
    private var weatherStamp: (key: String, at: Date)?

    private var lastReload: [String: Date] = [:]
    private var dirty: Set<String> = []

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let previous = store.loadSnapshot()
        handled = previous?.handled ?? []
        last = previous
        try? FileManager.default.createDirectory(at: store.actionsDirectory, withIntermediateDirectories: true)
        mergePending()
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in SystemWidgetSync.shared.tick() }
        }
        watch()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SystemWidgetStore.actionNotification), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SystemWidgetSync.shared.actionsArrived() }
        }
    }

    private func tick() {
        mergePending()
        publish()
        flushReloads()
    }

    private func actionsArrived() {
        mergePending()
        publish()
        flushReloads()
    }

    /// actions/ 里多了文件就合并。
    private func watch() {
        let fd = open(store.actionsDirectory.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler {
            Task { @MainActor in SystemWidgetSync.shared.actionsArrived() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: 合并点按

    private func mergePending() {
        for bad in store.unreadableActionFiles() { try? FileManager.default.removeItem(at: bad) }
        let pending = store.pendingActions()
        guard !pending.isEmpty else { return }
        var done: [String] = []
        for (_, action) in pending {
            if !handled.contains(action.id) {
                // 每一条都按此刻的卡片判断：前一条可能刚改过同一张卡片。
                switch SystemWidgetBridge.resolve(action, widgets: widgets()) {
                case .toggleTodo(let id, let item, let cheering):
                    if let instance = WidgetWriter.current(id) {
                        TodoLog.toggle(item, in: instance, cheering: cheering)
                    }
                case .addWater(let id, let amount):
                    if let instance = WidgetWriter.current(id) {
                        WaterLog.drink(.water, amount: amount, in: instance)
                    }
                case .skip:
                    break
                }
            }
            done.append(action.id)
        }
        handled = SystemWidgetSnapshot.remembering(done, in: handled)
        // 先写好带着 handled 的新快照，再删动作文件。
        publish()
        for (url, _) in pending { try? FileManager.default.removeItem(at: url) }
        for kind in ["todo", "water"] { markDirty(kind, force: true) }
    }

    // MARK: 快照

    private func publish() {
        let live = SystemWidgetBridge.Live(
            language: L10n.isEnglish ? "en" : "zh-Hans",
            weather: weather(),
            unlocked: ProAccess.isUnlocked,
            melted: PetMelt.now,
            missedWaterDays: UserDefaults.standard.integer(forKey: VirtualPet.missedDaysDefault),
            rates: CurrencyService.shared.rates,
            handled: handled)
        let snapshot = SystemWidgetBridge.snapshot(from: widgets(), live: live)
        guard let data = try? SystemWidgetStore.encoder().encode(snapshot), data != lastData else { return }
        guard (try? store.save(snapshot)) != nil else { return }
        lastData = data
        let old = last
        last = snapshot
        for kind in changedKinds(old, snapshot) { markDirty(kind) }
    }

    private func changedKinds(_ old: SystemWidgetSnapshot?, _ new: SystemWidgetSnapshot) -> [String] {
        guard let old, old.language == new.language else {
            return ["clock", "weather", "anniversary", "todo", "water", "battery", "pet", "note", "calc"]
        }
        var kinds: [String] = []
        if old.clocks != new.clocks { kinds.append("clock") }
        if old.weather != new.weather { kinds.append("weather") }
        if old.anniversaries != new.anniversaries { kinds.append("anniversary") }
        if old.todos != new.todos { kinds.append("todo") }
        if old.waters != new.waters { kinds.append("water") }
        if old.pets != new.pets { kinds.append("pet") }
        if old.notes != new.notes { kinds.append("note") }
        if old.calcs != new.calcs { kinds.append("calc") }
        return kinds
    }

    /// 码头天气卡片那个城市的实时天气。天气卡片的城市没填（按定位）时叫「当前位置」。
    private func weather() -> SystemWidgetSnapshot.Weather? {
        let service = WeatherService.shared
        guard let current = service.current else { return nil }
        let card = widgets().first { $0.kind == .weather }
        let typed = card?.config.string("city").trimmingCharacters(in: .whitespaces) ?? ""
        let city = typed.isEmpty ? tr("当前位置") : typed
        let now = Date.now
        let today = service.place.flatMap { ForecastService.shared.forecast(at: $0) }?.today(now: now)
        let hours = service.hourly.prefix(6).map {
            SystemWidgetSnapshot.WeatherHour(time: $0.date, temperatureC: $0.temperatureC, symbol: $0.symbolName)
        }
        let key = "\(city)|\(current.temperatureC)|\(current.symbolName)|\(hours.first?.time.timeIntervalSince1970 ?? 0)"
        if weatherStamp?.key != key { weatherStamp = (key, now) }
        return SystemWidgetSnapshot.Weather(
            city: city, temperatureC: current.temperatureC, symbol: current.symbolName,
            condition: current.condition, highC: today?.highC, lowC: today?.lowC,
            fahrenheit: card?.config.bool("fahrenheit") ?? false, hours: Array(hours),
            asOf: weatherStamp?.at ?? now)
    }

    // MARK: 让小组件重画

    /// 同一种小组件两次重画之间至少隔这么久（系统每天给的刷新次数有限）。宠物的数值
    /// 一直在慢慢变，隔得最久；小组件上点的待办、喝水不受限（系统自己也会重画）。
    private func minimumInterval(_ kind: String) -> TimeInterval {
        kind == "pet" ? 15 * 60 : 30
    }

    private func markDirty(_ kind: String, force: Bool = false) {
        if force { lastReload[kind] = nil }
        dirty.insert(kind)
        flushReloads()
    }

    private func flushReloads() {
        let now = Date.now
        for kind in dirty {
            if let at = lastReload[kind], now.timeIntervalSince(at) < minimumInterval(kind) { continue }
            WidgetCenter.shared.reloadTimelines(ofKind: SystemWidgetStore.kindPrefix + kind)
            lastReload[kind] = now
            dirty.remove(kind)
        }
    }
}
